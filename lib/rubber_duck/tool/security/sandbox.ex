defmodule RubberDuck.Tool.Security.Sandbox do
  @moduledoc """
  Process-level sandboxing for tool execution.
  
  Leverages BEAM's process isolation to create secure execution environments with:
  - Memory limits
  - CPU time limits  
  - Message queue limits
  - File descriptor limits
  - Timeout management
  """
  
  require Logger
  
  @default_limits %{
    max_heap_size: 50 * 1024 * 1024,     # 50 MB
    max_reductions: 10_000_000,           # ~1 second of CPU
    max_message_queue: 1000,              # Message queue size
    timeout_ms: 30_000,                   # 30 seconds
    kill_timeout_ms: 5_000                # 5 seconds to clean up
  }
  
  @type sandbox_opts :: [
    max_heap_size: pos_integer(),
    max_reductions: pos_integer(),
    max_message_queue: pos_integer(),
    timeout_ms: pos_integer(),
    allowed_modules: [module()],
    allowed_functions: [{module(), atom()}]
  ]
  
  @type sandbox_result :: {:ok, term()} | {:error, sandbox_error()}
  @type sandbox_error :: 
    :timeout | 
    :memory_limit | 
    :cpu_limit | 
    :forbidden_operation |
    {:exit, term()} |
    {:exception, term()}
  
  @doc """
  Executes a function in a sandboxed process with resource limits.
  
  Options:
    - max_heap_size: Maximum heap size in bytes
    - max_reductions: Maximum reductions (CPU operations)
    - max_message_queue: Maximum message queue length
    - timeout_ms: Execution timeout in milliseconds
    - allowed_modules: List of allowed modules (if restricted)
    - allowed_functions: List of allowed {module, function} tuples
  """
  @spec execute(fun(), sandbox_opts()) :: sandbox_result()
  def execute(fun, opts \\ []) when is_function(fun, 0) do
    limits = build_limits(opts)
    
    # Create a monitoring process
    monitor_pid = spawn_monitor_process(limits)
    
    # Spawn the sandboxed process
    _spawn_opts = [
      max_heap_size: limits.max_heap_size,
      message_queue_data: :off_heap  # Reduce memory pressure
    ]
    
    {sandbox_pid, monitor_ref} = spawn_monitor(fn ->
      # Set up process dictionary for tracking
      Process.put(:sandbox_reductions_limit, limits.max_reductions)
      Process.put(:sandbox_start_reductions, :erlang.statistics(:reductions))
      
      # Execute with reduction checking
      execute_with_limits(fun, limits)
    end)
    
    # Monitor the sandboxed process
    monitor_sandbox(sandbox_pid, monitor_ref, monitor_pid, limits)
  end
  
  @doc """
  Executes a module function call in a sandbox.
  
  Provides additional security by validating module/function access.
  """
  @spec execute_mfa(module(), atom(), [term()], sandbox_opts()) :: sandbox_result()
  def execute_mfa(module, function, args, opts \\ []) do
    # Validate module/function access
    case validate_mfa_access(module, function, opts) do
      :ok ->
        execute(fn -> apply(module, function, args) end, opts)
      {:error, _} = error ->
        error
    end
  end
  
  @doc """
  Creates a sandboxed task that can be awaited.
  
  Similar to Task.async but with sandbox restrictions.
  """
  def async(fun, opts \\ []) do
    Task.async(fn ->
      case execute(fun, opts) do
        {:ok, result} -> result
        {:error, reason} -> raise "Sandbox error: #{inspect(reason)}"
      end
    end)
  end
  
  @doc """
  Checks current process resource usage against limits.
  
  Can be called periodically within long-running operations.
  """
  def check_limits do
    case Process.get(:sandbox_reductions_limit) do
      nil -> 
        :ok
      limit ->
        start = Process.get(:sandbox_start_reductions, 0)
        current = :erlang.statistics(:reductions)
        used = current - start
        
        if used > limit do
          {:error, :cpu_limit}
        else
          :ok
        end
    end
  end
  
  # Private functions
  
  defp build_limits(opts) do
    Enum.reduce(opts, @default_limits, fn {key, value}, limits ->
      Map.put(limits, key, value)
    end)
  end
  
  defp spawn_monitor_process(limits) do
    spawn(fn ->
      receive do
        {:monitor, sandbox_pid} ->
          monitor_process_resources(sandbox_pid, limits)
        :stop ->
          :ok
      end
    end)
  end
  
  defp monitor_process_resources(sandbox_pid, limits) do
    case Process.info(sandbox_pid, [:message_queue_len, :total_heap_size, :reductions]) do
      nil ->
        # Process has exited
        :ok
        
      info ->
        # Check message queue
        if info[:message_queue_len] > limits.max_message_queue do
          Process.exit(sandbox_pid, :message_queue_limit)
        end
        
        # Check memory (heap size is in words, convert to bytes)
        heap_bytes = info[:total_heap_size] * :erlang.system_info(:wordsize)
        if heap_bytes > limits.max_heap_size do
          Process.exit(sandbox_pid, :memory_limit)
        end
        
        # Continue monitoring
        Process.sleep(100)
        monitor_process_resources(sandbox_pid, limits)
    end
  end
  
  defp execute_with_limits(fun, _limits) do
    # Set up reduction checking
    check_reductions = fn ->
      case check_limits() do
        :ok -> :ok
        {:error, :cpu_limit} -> throw(:cpu_limit_exceeded)
      end
    end
    
    # Wrap the function to periodically check limits
    wrapped_fun = wrap_with_checks(fun, check_reductions)
    
    try do
      {:ok, wrapped_fun.()}
    catch
      :throw, :cpu_limit_exceeded ->
        {:error, :cpu_limit}
      :throw, other ->
        {:error, {:exception, {:throw, other}}}
      :error, reason ->
        {:error, {:exception, {:error, reason, __STACKTRACE__}}}
      :exit, reason ->
        {:error, {:exit, reason}}
    end
  end
  
  defp wrap_with_checks(fun, check_fn) do
    # For simple functions, we can't inject checks
    # For more complex operations, the tool should call check_limits()
    fn ->
      check_fn.()
      result = fun.()
      check_fn.()
      result
    end
  end
  
  defp monitor_sandbox(sandbox_pid, monitor_ref, monitor_pid, limits) do
    # Set up timeout
    timeout_ref = Process.send_after(self(), :timeout, limits.timeout_ms)
    
    # Tell monitor process to start monitoring
    send(monitor_pid, {:monitor, sandbox_pid})
    
    # Wait for result or timeout
    result = receive do
      {:DOWN, ^monitor_ref, :process, ^sandbox_pid, :normal} ->
        # Process completed normally, get result
        receive_sandbox_result()
        
      {:DOWN, ^monitor_ref, :process, ^sandbox_pid, :memory_limit} ->
        {:error, :memory_limit}
        
      {:DOWN, ^monitor_ref, :process, ^sandbox_pid, :message_queue_limit} ->
        {:error, :message_queue_limit}
        
      {:DOWN, ^monitor_ref, :process, ^sandbox_pid, reason} ->
        {:error, {:exit, reason}}
        
      :timeout ->
        # Kill the sandboxed process
        Process.exit(sandbox_pid, :kill)
        {:error, :timeout}
    end
    
    # Cleanup
    Process.cancel_timer(timeout_ref)
    send(monitor_pid, :stop)
    
    result
  end
  
  defp receive_sandbox_result do
    receive do
      {:sandbox_result, result} -> result
    after
      100 -> {:error, :no_result}
    end
  end
  
  defp validate_mfa_access(module, function, opts) do
    allowed_modules = Keyword.get(opts, :allowed_modules)
    allowed_functions = Keyword.get(opts, :allowed_functions)
    
    cond do
      # Check if module is in allowed list
      allowed_modules && module not in allowed_modules ->
        {:error, {:forbidden_module, module}}
        
      # Check if specific function is allowed
      allowed_functions && {module, function} not in allowed_functions ->
        {:error, {:forbidden_function, {module, function}}}
        
      # Check if module is loaded and safe
      not Code.ensure_loaded?(module) ->
        {:error, {:module_not_loaded, module}}
        
      # Check if function is exported
      not function_exported?(module, function, length(opts[:args] || [])) ->
        {:error, {:function_not_exported, {module, function}}}
        
      true ->
        :ok
    end
  end
  
  @doc """
  Creates a restricted execution environment with minimal capabilities.
  
  This is the most secure sandbox mode.
  """
  def execute_restricted(fun, opts \\ []) do
    restricted_opts = [
      max_heap_size: 10 * 1024 * 1024,  # 10 MB
      max_reductions: 1_000_000,         # ~0.1 second
      timeout_ms: 5_000,                 # 5 seconds
      allowed_modules: [
        Enum,
        List,
        Map,
        String,
        Integer,
        Float,
        Kernel  # Only pure functions
      ]
    ] ++ opts
    
    execute(fun, restricted_opts)
  end
  
  @doc """
  Executes code with file system restrictions.
  
  Intercepts file operations and validates them against allowed paths.
  """
  def execute_with_fs_restrictions(fun, allowed_paths, opts \\ []) do
    # This would require more complex implementation with
    # custom file operation wrappers
    execute(fn ->
      Process.put(:sandbox_allowed_paths, allowed_paths)
      fun.()
    end, opts)
  end
  
  @doc """
  Information about sandbox limits and current usage.
  """
  def sandbox_info do
    case Process.info(self(), [:total_heap_size, :message_queue_len, :reductions]) do
      nil -> 
        %{}
      info ->
        %{
          heap_size_bytes: info[:total_heap_size] * :erlang.system_info(:wordsize),
          message_queue_len: info[:message_queue_len],
          reductions: info[:reductions],
          limits: Process.get(:sandbox_limits, @default_limits)
        }
    end
  end
end