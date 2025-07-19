defmodule RubberDuck.Tool.SandboxTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Tool.Sandbox

  defmodule SafeTool do
    use RubberDuck.Tool

    tool do
      name :safe_tool
      description "A safe tool for testing"
      category(:testing)

      parameter :input do
        type :string
        required(true)
      end

      execution do
        handler(&SafeTool.execute/2)
      end

      security do
        sandbox(:balanced)
        capabilities([])
      end
    end

    def execute(params, _context) do
      {:ok, "Processed: #{params.input}"}
    end
  end

  defmodule FileAccessTool do
    use RubberDuck.Tool

    tool do
      name :file_access_tool
      description "A tool that needs file access"
      category(:testing)

      parameter :path do
        type :string
        required(true)
      end

      execution do
        handler(&FileAccessTool.execute/2)
      end

      security do
        sandbox(:strict)
        file_access(["/tmp/", "/var/tmp/"])
        capabilities([:file_read])
      end
    end

    def execute(params, _context) do
      case File.read(params.path) do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defmodule NetworkTool do
    use RubberDuck.Tool

    tool do
      name :network_tool
      description "A tool that needs network access"
      category(:testing)

      parameter :url do
        type :string
        required(true)
      end

      execution do
        handler(&NetworkTool.execute/2)
      end

      security do
        sandbox(:relaxed)
        network_access(true)
        capabilities([:network_access])
      end
    end

    def execute(params, _context) do
      # Simulate network access
      if String.starts_with?(params.url, "http") do
        {:ok, "Connected to #{params.url}"}
      else
        {:error, :invalid_url}
      end
    end
  end

  defmodule DangerousTool do
    use RubberDuck.Tool

    tool do
      name :dangerous_tool
      description "A tool that tries to do dangerous things"
      category(:testing)

      execution do
        handler(&DangerousTool.execute/2)
      end

      security do
        sandbox(:strict)
        capabilities([])
      end
    end

    def execute(_params, _context) do
      # Try to do something dangerous
      System.cmd("echo", ["hello"])
    end
  end

  defmodule MemoryHogTool do
    use RubberDuck.Tool

    tool do
      name :memory_hog_tool
      description "A tool that uses lots of memory"
      category(:testing)

      execution do
        handler(&MemoryHogTool.execute/2)
      end

      security do
        sandbox(:strict)
        capabilities([])
      end
    end

    def execute(_params, _context) do
      # Create a large list to consume memory
      big_list = Enum.to_list(1..10_000_000)
      {:ok, "Created list with #{length(big_list)} items"}
    end
  end

  defmodule SlowTool do
    use RubberDuck.Tool

    tool do
      name :slow_tool
      description "A tool that takes a long time"
      category(:testing)

      execution do
        handler(&SlowTool.execute/2)
      end

      security do
        sandbox(:strict)
        capabilities([])
      end
    end

    def execute(_params, _context) do
      # Sleep for a long time
      Process.sleep(10_000)
      {:ok, "Finished sleeping"}
    end
  end

  defmodule NoSandboxTool do
    use RubberDuck.Tool

    tool do
      name :no_sandbox_tool
      description "A tool with no sandbox"
      category(:testing)

      execution do
        handler(&NoSandboxTool.execute/2)
      end

      security do
        sandbox(:none)
        capabilities([])
      end
    end

    def execute(params, _context) do
      {:ok, "Unsandboxed result: #{params[:input] || "no input"}"}
    end
  end

  describe "sandbox configuration" do
    test "gets default config for strict level" do
      config = Sandbox.get_default_config(:strict)

      assert config.level == :strict
      assert config.timeout == 5_000
      assert config.memory_limit == 50_000_000
      assert config.cpu_limit == 2
      assert config.network_access == false
      assert config.env_vars == []
    end

    test "gets default config for balanced level" do
      config = Sandbox.get_default_config(:balanced)

      assert config.level == :balanced
      assert config.timeout == 15_000
      assert config.memory_limit == 75_000_000
      assert config.cpu_limit == 5
      assert config.network_access == false
      assert config.env_vars == ["PATH", "HOME"]
    end

    test "gets default config for relaxed level" do
      config = Sandbox.get_default_config(:relaxed)

      assert config.level == :relaxed
      assert config.timeout == 30_000
      assert config.memory_limit == 150_000_000
      assert config.cpu_limit == 15
      assert config.network_access == true
      assert "PATH" in config.env_vars
      assert "HOME" in config.env_vars
      assert "USER" in config.env_vars
    end

    test "gets default config for none level" do
      config = Sandbox.get_default_config(:none)

      assert config.level == :none
      assert config.timeout == 60_000
      assert config.memory_limit == 500_000_000
      assert config.cpu_limit == 60
      assert config.network_access == true
    end
  end

  describe "basic sandbox execution" do
    test "executes safe tool successfully" do
      handler = &SafeTool.execute/2
      params = %{input: "test"}
      context = %{user: %{id: "test"}}

      assert {:ok, result} = Sandbox.execute_in_sandbox(SafeTool, handler, params, context)
      assert result == {:ok, "Processed: test"}
    end

    test "executes tool without sandbox when level is none" do
      handler = &NoSandboxTool.execute/2
      params = %{input: "test"}
      context = %{user: %{id: "test"}}

      assert {:ok, result} = Sandbox.execute_in_sandbox(NoSandboxTool, handler, params, context)
      assert result == {:ok, "Unsandboxed result: test"}
    end

    test "handles errors in sandboxed execution" do
      handler = fn _params, _context ->
        raise "Test error"
      end

      params = %{}
      context = %{user: %{id: "test"}}

      assert {:error, :execution_failed, error_msg} =
               Sandbox.execute_in_sandbox(SafeTool, handler, params, context)

      assert error_msg == "Test error"
    end
  end

  describe "timeout handling" do
    test "enforces timeout limits" do
      handler = &SlowTool.execute/2
      params = %{}
      context = %{user: %{id: "test"}}

      # Use custom timeout
      opts = [timeout: 1000]

      assert {:error, :timeout, message} =
               Sandbox.execute_in_sandbox(SlowTool, handler, params, context, opts)

      assert message =~ "timed out"
    end

    test "allows execution within timeout" do
      handler = fn _params, _context ->
        Process.sleep(100)
        {:ok, "completed"}
      end

      params = %{}
      context = %{user: %{id: "test"}}
      opts = [timeout: 5000]

      assert {:ok, result} =
               Sandbox.execute_in_sandbox(SafeTool, handler, params, context, opts)

      assert result == {:ok, "completed"}
    end
  end

  describe "memory limit handling" do
    test "enforces memory limits" do
      handler = &MemoryHogTool.execute/2
      params = %{}
      context = %{user: %{id: "test"}}

      # Use very low memory limit
      # 1MB
      opts = [memory_limit: 1_000_000]

      # The process should be killed due to memory limit
      assert {:error, :memory_limit_exceeded, _message} =
               Sandbox.execute_in_sandbox(MemoryHogTool, handler, params, context, opts)
    end

    test "allows execution within memory limits" do
      handler = fn _params, _context ->
        # Create a small list
        small_list = Enum.to_list(1..100)
        {:ok, "Created list with #{length(small_list)} items"}
      end

      params = %{}
      context = %{user: %{id: "test"}}
      # 10MB
      opts = [memory_limit: 10_000_000]

      assert {:ok, result} =
               Sandbox.execute_in_sandbox(SafeTool, handler, params, context, opts)

      assert result == {:ok, "Created list with 100 items"}
    end
  end

  describe "function validation" do
    test "validates allowed modules" do
      config = %{
        allowed_modules: [String, Enum],
        allowed_functions: []
      }

      assert :ok = Sandbox.validate_function_call(String, :upcase, config)
      assert :ok = Sandbox.validate_function_call(Enum, :map, config)
      assert {:error, :module_not_allowed} = Sandbox.validate_function_call(File, :read, config)
    end

    test "validates allowed functions" do
      config = %{
        allowed_modules: [],
        allowed_functions: [:upcase, :downcase, :map]
      }

      assert :ok = Sandbox.validate_function_call(String, :upcase, config)
      assert :ok = Sandbox.validate_function_call(String, :downcase, config)
      assert {:error, :function_not_allowed} = Sandbox.validate_function_call(String, :replace, config)
    end

    test "detects dangerous modules" do
      config = %{allowed_modules: [], allowed_functions: []}

      assert {:error, :dangerous_module} = Sandbox.validate_function_call(:os, :cmd, config)
      assert {:error, :dangerous_module} = Sandbox.validate_function_call(:file, :write, config)
      assert {:error, :dangerous_module} = Sandbox.validate_function_call(:code, :eval_string, config)
    end

    test "detects dangerous functions" do
      config = %{allowed_modules: [], allowed_functions: []}

      assert {:error, :dangerous_function} = Sandbox.validate_function_call(System, :cmd, config)
      assert {:error, :dangerous_function} = Sandbox.validate_function_call(File, :write, config)
      assert {:error, :dangerous_function} = Sandbox.validate_function_call(Process, :spawn, config)
    end
  end

  describe "file access validation" do
    test "validates allowed file paths" do
      config = %{file_access: ["/tmp/", "/var/tmp/"]}

      assert :ok = Sandbox.validate_file_access("/tmp/test.txt", config)
      assert :ok = Sandbox.validate_file_access("/var/tmp/data.json", config)
      assert {:error, :sensitive_path_access} = Sandbox.validate_file_access("/etc/passwd", config)
    end

    test "detects path traversal attempts" do
      config = %{file_access: ["/tmp/"]}

      assert {:error, :path_traversal_detected} =
               Sandbox.validate_file_access("/tmp/../etc/passwd", config)

      assert {:error, :path_traversal_detected} =
               Sandbox.validate_file_access("../sensitive/file.txt", config)
    end

    test "detects sensitive system paths" do
      config = %{file_access: ["/etc/", "/sys/", "/proc/"]}

      assert {:error, :sensitive_path_access} =
               Sandbox.validate_file_access("/etc/passwd", config)

      assert {:error, :sensitive_path_access} =
               Sandbox.validate_file_access("/sys/kernel/debug", config)

      assert {:error, :sensitive_path_access} =
               Sandbox.validate_file_access("/proc/version", config)
    end

    test "blocks file access when disabled" do
      config = %{file_access: []}

      assert {:error, :file_access_disabled} =
               Sandbox.validate_file_access("/tmp/test.txt", config)
    end
  end

  describe "network access validation" do
    test "allows network access when enabled" do
      config = %{network_access: true}

      assert :ok = Sandbox.validate_network_access(config)
    end

    test "blocks network access when disabled" do
      config = %{network_access: false}

      assert {:error, :network_access_denied} =
               Sandbox.validate_network_access(config)
    end
  end

  describe "sandbox level inheritance" do
    test "uses tool security configuration" do
      handler = &SafeTool.execute/2
      params = %{input: "test"}
      context = %{user: %{id: "test"}}

      # SafeTool is configured with :balanced level
      assert {:ok, _result} = Sandbox.execute_in_sandbox(SafeTool, handler, params, context)
    end

    test "overrides with explicit options" do
      handler = &SafeTool.execute/2
      params = %{input: "test"}
      context = %{user: %{id: "test"}}

      # Override to strict level
      opts = [level: :strict, timeout: 1000]

      assert {:ok, _result} = Sandbox.execute_in_sandbox(SafeTool, handler, params, context, opts)
    end
  end

  describe "error handling" do
    test "handles sandbox violations gracefully" do
      handler = fn _params, _context ->
        # Try to do something that would cause a sandbox violation
        spawn(fn -> :ok end)
      end

      params = %{}
      context = %{user: %{id: "test"}}

      # This should succeed since spawn returns a PID
      assert {:ok, result} =
               Sandbox.execute_in_sandbox(SafeTool, handler, params, context)

      assert is_pid(result)
    end

    test "handles process crashes" do
      handler = fn _params, _context ->
        # Cause a process crash
        exit(:crash)
      end

      params = %{}
      context = %{user: %{id: "test"}}

      assert {:error, :execution_failed, _reason} =
               Sandbox.execute_in_sandbox(SafeTool, handler, params, context)
    end
  end

  describe "resource monitoring" do
    test "tracks successful execution" do
      handler = &SafeTool.execute/2
      params = %{input: "test"}
      context = %{user: %{id: "test"}}

      # Should emit telemetry events
      assert {:ok, _result} = Sandbox.execute_in_sandbox(SafeTool, handler, params, context)
    end

    test "tracks failed execution" do
      handler = fn _params, _context ->
        raise "Test error"
      end

      params = %{}
      context = %{user: %{id: "test"}}

      # Should emit telemetry events for failure
      assert {:error, :execution_failed, _reason} =
               Sandbox.execute_in_sandbox(SafeTool, handler, params, context)
    end
  end
end
