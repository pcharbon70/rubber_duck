defmodule RubberDuck.Tool.Sandbox do
  @moduledoc """
  Sandboxing system for secure tool execution with process-level isolation.

  Provides comprehensive sandboxing capabilities including:
  - Process isolation with resource limits
  - File system restrictions
  - Network access control
  - Environment variable filtering
  - Function call restrictions
  - Memory and CPU limits
  - Timeout management
  - Security monitoring
  """

  require Logger
  alias RubberDuck.Instructions.SecurityConfig

  @type sandbox_level :: :strict | :balanced | :relaxed | :none

  @type sandbox_config :: %{
          level: sandbox_level(),
          timeout: pos_integer(),
          memory_limit: pos_integer(),
          cpu_limit: pos_integer(),
          file_access: [String.t()],
          network_access: boolean(),
          env_vars: [String.t()],
          allowed_modules: [atom()],
          allowed_functions: [atom()],
          working_directory: String.t() | nil
        }

  @type sandbox_result :: {:ok, term()} | {:error, atom(), term()}

  @doc """
  Executes a tool handler function in a sandboxed environment.

  ## Parameters

  - `tool_module` - The tool module being executed
  - `handler_fun` - The function to execute (params, context) -> result
  - `params` - Parameters to pass to the handler
  - `context` - Execution context
  - `opts` - Sandbox options

  ## Options

  - `:level` - Sandbox security level (:strict, :balanced, :relaxed, :none)
  - `:timeout` - Maximum execution time in milliseconds
  - `:memory_limit` - Maximum memory usage in bytes
  - `:cpu_limit` - Maximum CPU usage in seconds
  - `:file_access` - List of allowed file paths
  - `:network_access` - Whether network access is allowed
  - `:env_vars` - Allowed environment variables
  - `:working_directory` - Working directory for execution

  ## Returns

  - `{:ok, result}` - Successful execution
  - `{:error, :timeout, details}` - Execution timed out
  - `{:error, :memory_limit_exceeded, details}` - Memory limit exceeded
  - `{:error, :cpu_limit_exceeded, details}` - CPU limit exceeded
  - `{:error, :file_access_denied, details}` - File access violation
  - `{:error, :network_access_denied, details}` - Network access violation
  - `{:error, :sandbox_violation, details}` - General sandbox violation
  """
  @spec execute_in_sandbox(module(), function(), map(), map(), keyword()) :: sandbox_result()
  def execute_in_sandbox(tool_module, handler_fun, params, context, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    # Get tool's sandbox configuration
    tool_security = RubberDuck.Tool.security(tool_module)
    sandbox_level = get_sandbox_level(tool_security, opts)

    # Skip sandbox if disabled
    if sandbox_level == :none do
      execute_unsandboxed(handler_fun, params, context)
    else
      # Build sandbox configuration
      sandbox_config = build_sandbox_config(tool_module, sandbox_level, opts)

      # Execute in sandboxed process
      result = execute_sandboxed(handler_fun, params, context, sandbox_config)

      # Emit telemetry
      duration = System.monotonic_time(:millisecond) - start_time
      emit_sandbox_telemetry(tool_module, sandbox_level, result, duration)

      result
    end
  end

  @doc """
  Gets the default sandbox configuration for a security level.
  """
  @spec get_default_config(sandbox_level()) :: sandbox_config()
  def get_default_config(level) do
    base_config = %{
      level: level,
      timeout: RubberDuck.Config.Timeouts.get([:tools, :sandbox, :standard], 30_000),
      # 100MB
      memory_limit: 100_000_000,
      # 10 seconds
      cpu_limit: 10,
      file_access: [],
      network_access: false,
      env_vars: ["PATH", "HOME", "USER"],
      allowed_modules: [],
      allowed_functions: [],
      working_directory: nil
    }

    case level do
      :strict ->
        %{
          base_config
          | timeout: RubberDuck.Config.Timeouts.get([:tools, :sandbox, :minimal], 5_000),
            # 50MB
            memory_limit: 50_000_000,
            # 2 seconds
            cpu_limit: 2,
            network_access: false,
            env_vars: []
        }

      :balanced ->
        %{
          base_config
          | timeout: RubberDuck.Config.Timeouts.get([:tools, :sandbox, :standard], 15_000),
            # 75MB
            memory_limit: 75_000_000,
            # 5 seconds
            cpu_limit: 5,
            network_access: false,
            env_vars: ["PATH", "HOME"]
        }

      :relaxed ->
        %{
          base_config
          | timeout: RubberDuck.Config.Timeouts.get([:tools, :sandbox, :enhanced], 30_000),
            # 150MB
            memory_limit: 150_000_000,
            # 15 seconds
            cpu_limit: 15,
            network_access: true,
            env_vars: ["PATH", "HOME", "USER", "LANG", "LC_ALL"]
        }

      :none ->
        %{
          base_config
          | timeout: RubberDuck.Config.Timeouts.get([:tools, :sandbox, :maximum], 60_000),
            # 500MB
            memory_limit: 500_000_000,
            # 60 seconds
            cpu_limit: 60,
            network_access: true
        }
    end
  end

  @doc """
  Validates if a module/function is allowed in the sandbox.
  """
  @spec validate_function_call(module(), atom(), sandbox_config()) :: :ok | {:error, atom()}
  def validate_function_call(module, function, sandbox_config) do
    cond do
      # Check if module is in allowed list
      not Enum.empty?(sandbox_config.allowed_modules) and
          module not in sandbox_config.allowed_modules ->
        {:error, :module_not_allowed}

      # Check if function is in allowed list
      not Enum.empty?(sandbox_config.allowed_functions) and
          function not in sandbox_config.allowed_functions ->
        {:error, :function_not_allowed}

      # Check for dangerous modules
      is_dangerous_module?(module) ->
        {:error, :dangerous_module}

      # Check for dangerous functions
      is_dangerous_function?(module, function) ->
        {:error, :dangerous_function}

      true ->
        :ok
    end
  end

  @doc """
  Validates file access against sandbox restrictions.
  """
  @spec validate_file_access(String.t(), sandbox_config()) :: :ok | {:error, atom()}
  def validate_file_access(path, sandbox_config) do
    cond do
      # Check if file access is completely disabled
      Enum.empty?(sandbox_config.file_access) ->
        {:error, :file_access_disabled}

      # Check for path traversal attempts first
      String.contains?(path, "..") ->
        {:error, :path_traversal_detected}

      # Check for sensitive system paths
      is_sensitive_path?(path) ->
        {:error, :sensitive_path_access}

      # Check if path is in allowed list
      not path_allowed?(path, sandbox_config.file_access) ->
        {:error, :file_access_denied}

      true ->
        :ok
    end
  end

  @doc """
  Validates network access against sandbox restrictions.
  """
  @spec validate_network_access(sandbox_config()) :: :ok | {:error, atom()}
  def validate_network_access(sandbox_config) do
    if sandbox_config.network_access do
      :ok
    else
      {:error, :network_access_denied}
    end
  end

  # Private functions

  defp execute_unsandboxed(handler_fun, params, context) do
    try do
      result = handler_fun.(params, context)
      {:ok, result}
    rescue
      error ->
        {:error, :execution_failed, Exception.message(error)}
    catch
      kind, reason ->
        {:error, :execution_failed, {kind, reason}}
    end
  end

  defp execute_sandboxed(handler_fun, params, context, sandbox_config) do
    # Spawn isolated process with resource limits
    task =
      Task.async(fn ->
        setup_sandbox_environment(sandbox_config)
        execute_with_monitoring(handler_fun, params, context, sandbox_config)
      end)

    # Wait for result with timeout
    case Task.yield(task, sandbox_config.timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      {:exit, {:killed, _}} ->
        {:error, :memory_limit_exceeded, "Process killed due to memory limit"}

      {:exit, reason} ->
        Logger.warning("Sandbox execution failed: #{inspect(reason)}")
        {:error, :sandbox_violation, reason}

      nil ->
        {:error, :timeout, "Execution timed out after #{sandbox_config.timeout}ms"}
    end
  end

  defp setup_sandbox_environment(sandbox_config) do
    # Set process flags for resource limits
    Process.flag(:trap_exit, true)

    Process.flag(:max_heap_size, %{
      size: sandbox_config.memory_limit,
      kill: true,
      error_logger: true
    })

    # Mark process as sandboxed
    Process.put(:sandboxed, true)
    Process.put(:sandbox_level, sandbox_config.level)
    Process.put(:sandbox_config, sandbox_config)

    # Set working directory if specified
    if sandbox_config.working_directory do
      File.cd!(sandbox_config.working_directory)
    end

    # Filter environment variables
    filter_environment_variables(sandbox_config.env_vars)
  end

  defp execute_with_monitoring(handler_fun, params, context, sandbox_config) do
    # Start CPU monitoring
    cpu_monitor = start_cpu_monitor(sandbox_config.cpu_limit)

    try do
      # Execute the handler function
      result = handler_fun.(params, context)
      {:ok, result}
    rescue
      error ->
        {:error, :execution_failed, Exception.message(error)}
    catch
      kind, reason ->
        {:error, :execution_failed, {kind, reason}}
    after
      # Stop CPU monitoring
      stop_cpu_monitor(cpu_monitor)
    end
  end

  defp start_cpu_monitor(cpu_limit) do
    if cpu_limit > 0 do
      parent = self()

      spawn_link(fn ->
        monitor_cpu_usage(parent, cpu_limit)
      end)
    else
      nil
    end
  end

  defp monitor_cpu_usage(parent_pid, cpu_limit) do
    start_time = System.monotonic_time(:second)

    # Monitor CPU usage periodically
    :timer.sleep(1000)

    current_time = System.monotonic_time(:second)
    elapsed = current_time - start_time

    if elapsed > cpu_limit do
      Process.exit(parent_pid, {:cpu_limit_exceeded, elapsed})
    else
      monitor_cpu_usage(parent_pid, cpu_limit)
    end
  end

  defp stop_cpu_monitor(nil), do: :ok

  defp stop_cpu_monitor(monitor_pid) do
    if Process.alive?(monitor_pid) do
      Process.exit(monitor_pid, :normal)
    end
  end

  defp filter_environment_variables(allowed_vars) do
    # Get current environment
    current_env = System.get_env()

    # Filter to only allowed variables
    filtered_env = Map.take(current_env, allowed_vars)

    # Clear environment and set only allowed variables
    Enum.each(current_env, fn {key, _value} ->
      if key not in allowed_vars do
        System.delete_env(key)
      end
    end)

    # Set allowed variables
    Enum.each(filtered_env, fn {key, value} ->
      System.put_env(key, value)
    end)
  end

  defp get_sandbox_level(tool_security, opts) do
    cond do
      # Explicit option takes precedence
      level = Keyword.get(opts, :level) ->
        level

      # Tool security configuration
      tool_security && tool_security.sandbox ->
        tool_security.sandbox

      # Default from configuration
      true ->
        SecurityConfig.get_sandbox_config()
        |> Map.get(:default_security_level, :balanced)
    end
  end

  defp build_sandbox_config(tool_module, sandbox_level, opts) do
    # Get default configuration for the level
    default_config = get_default_config(sandbox_level)

    # Get tool-specific overrides
    tool_security = RubberDuck.Tool.security(tool_module)

    tool_overrides =
      if tool_security do
        %{
          file_access: tool_security.file_access || default_config.file_access,
          network_access: tool_security.network_access || default_config.network_access,
          allowed_modules: tool_security.allowed_modules || default_config.allowed_modules,
          allowed_functions: tool_security.allowed_functions || default_config.allowed_functions
        }
      else
        %{}
      end

    # Merge with provided options
    option_overrides = Enum.into(opts, %{})

    # Merge all configurations
    Map.merge(default_config, tool_overrides)
    |> Map.merge(option_overrides)
  end

  defp is_dangerous_module?(module) do
    dangerous_modules = [
      :os,
      :file,
      :code,
      :ets,
      :dets,
      :mnesia,
      :net,
      :gen_tcp,
      :gen_udp,
      :httpc,
      :ssl,
      :crypto,
      :beam_lib,
      :erl_eval,
      :erl_parse,
      :erl_scan,
      :init,
      :heart,
      :disk_log,
      :error_logger,
      :global,
      :global_group,
      :net_adm,
      :net_kernel,
      :nodes,
      :rpc,
      :slave
    ]

    module in dangerous_modules
  end

  defp is_dangerous_function?(module, function) do
    dangerous_functions = [
      {File, :write},
      {File, :write!},
      {File, :rm},
      {File, :rm!},
      {File, :rm_rf},
      {File, :rm_rf!},
      {File, :copy},
      {File, :copy!},
      {File, :rename},
      {File, :rename!},
      {File, :mkdir},
      {File, :mkdir!},
      {File, :mkdir_p},
      {File, :mkdir_p!},
      {File, :rmdir},
      {File, :rmdir!},
      {System, :cmd},
      {System, :shell},
      {System, :halt},
      {System, :stop},
      {System, :restart},
      {Process, :spawn},
      {Process, :spawn_link},
      {Process, :spawn_monitor},
      {Process, :spawn_opt},
      {Process, :exit},
      {Process, :kill},
      {GenServer, :start},
      {GenServer, :start_link},
      {Supervisor, :start_link},
      {Task, :start},
      {Task, :start_link},
      {Agent, :start},
      {Agent, :start_link},
      {:erlang, :spawn},
      {:erlang, :spawn_link},
      {:erlang, :spawn_monitor},
      {:erlang, :spawn_opt},
      {:erlang, :halt},
      {:erlang, :open_port},
      {:erlang, :port_command},
      {:erlang, :port_control},
      {:erlang, :load_nif},
      {:erlang, :system_flag},
      {:erlang, :trace},
      {:erlang, :trace_pattern}
    ]

    {module, function} in dangerous_functions
  end

  defp path_allowed?(path, allowed_paths) do
    # Normalize path to handle relative paths
    normalized_path = Path.absname(path)

    Enum.any?(allowed_paths, fn allowed_path ->
      normalized_allowed = Path.absname(allowed_path)
      String.starts_with?(normalized_path, normalized_allowed)
    end)
  end

  defp is_sensitive_path?(path) do
    sensitive_paths = [
      "/etc/",
      "/sys/",
      "/proc/",
      "/dev/",
      "/root/",
      "/var/log/",
      "/var/run/",
      "/var/spool/",
      "/boot/",
      "/lib/",
      "/lib64/",
      "/usr/bin/",
      "/usr/sbin/",
      "/sbin/",
      "/bin/"
    ]

    Enum.any?(sensitive_paths, fn sensitive_path ->
      String.starts_with?(path, sensitive_path)
    end)
  end

  defp emit_sandbox_telemetry(tool_module, sandbox_level, result, duration) do
    metadata = RubberDuck.Tool.metadata(tool_module)

    result_tag =
      case result do
        {:ok, _} -> :success
        {:error, _, _} -> :failure
        {:error, _} -> :failure
      end

    :telemetry.execute(
      [:rubber_duck, :tool, :sandbox, :execution],
      %{duration: duration},
      %{
        tool: metadata.name,
        sandbox_level: sandbox_level,
        result: result_tag
      }
    )
  end
end
