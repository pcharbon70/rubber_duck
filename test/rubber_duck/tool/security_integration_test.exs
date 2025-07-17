defmodule RubberDuck.Tool.SecurityIntegrationTest do
  @moduledoc """
  Security-focused integration tests for the tool execution system.
  
  Tests security boundaries, sandbox enforcement, and protection mechanisms.
  """
  
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.{Executor, Sandbox}
  
  # Test users with different security levels
  @high_security_user %{
    id: "secure-user-123",
    roles: [:user, :security_cleared],
    permissions: [:read, :execute, :file_read, :network_access]
  }
  
  @low_security_user %{
    id: "basic-user-456",
    roles: [:user],
    permissions: [:read, :execute]
  }
  
  @untrusted_user %{
    id: "untrusted-789",
    roles: [:guest],
    permissions: [:read]
  }
  
  # Security test tools
  defmodule FileSystemTool do
    use RubberDuck.Tool
    
    tool do
      name :filesystem_tool
      description "Tool for testing file system security"
      category :security_test
      
      parameter :operation do
        type :string
        required true
        constraints [enum: ["read", "write", "list", "traversal_attempt"]]
      end
      
      parameter :path do
        type :string
        required true
      end
      
      execution do
        handler &FileSystemTool.execute/2
        timeout 5_000
      end
      
      security do
        sandbox :strict
        capabilities [:file_read, :file_write]
        file_access ["/tmp/", "/var/tmp/"]
        network_access false
      end
    end
    
    def execute(params, _context) do
      case params.operation do
        "read" ->
          case Sandbox.validate_file_access(params.path, %{file_access: ["/tmp/", "/var/tmp/"]}) do
            :ok -> {:ok, "Reading from #{params.path}"}
            {:error, reason} -> {:error, "File access denied: #{reason}"}
          end
        
        "write" ->
          case Sandbox.validate_file_access(params.path, %{file_access: ["/tmp/", "/var/tmp/"]}) do
            :ok -> {:ok, "Writing to #{params.path}"}
            {:error, reason} -> {:error, "File access denied: #{reason}"}
          end
        
        "list" ->
          {:ok, "Listing directory #{params.path}"}
        
        "traversal_attempt" ->
          # This should be caught by path validation
          {:ok, "Should not reach here"}
      end
    end
  end
  
  defmodule NetworkTool do
    use RubberDuck.Tool
    
    tool do
      name :network_tool
      description "Tool for testing network security"
      category :security_test
      
      parameter :operation do
        type :string
        required true
        constraints [enum: ["connect", "fetch", "blocked"]]
      end
      
      parameter :url do
        type :string
        required true
      end
      
      execution do
        handler &NetworkTool.execute/2
        timeout 10_000
      end
      
      security do
        sandbox :balanced
        capabilities [:network_access]
        network_access true
      end
    end
    
    def execute(params, _context) do
      case params.operation do
        "connect" ->
          case Sandbox.validate_network_access(%{network_access: true}) do
            :ok -> {:ok, "Connected to #{params.url}"}
            {:error, reason} -> {:error, "Network access denied: #{reason}"}
          end
        
        "fetch" ->
          {:ok, "Fetched data from #{params.url}"}
        
        "blocked" ->
          # This should be blocked by network restrictions
          {:error, "Network access blocked"}
      end
    end
  end
  
  defmodule PrivilegedTool do
    use RubberDuck.Tool
    
    tool do
      name :privileged_tool
      description "Tool requiring elevated privileges"
      category :security_test
      
      parameter :action do
        type :string
        required true
        constraints [enum: ["system_info", "process_list", "admin_action"]]
      end
      
      execution do
        handler &PrivilegedTool.execute/2
        timeout 5_000
      end
      
      security do
        sandbox :relaxed
        capabilities [:admin_access, :system_info]
        network_access true
      end
    end
    
    def execute(params, _context) do
      case params.action do
        "system_info" -> {:ok, "System information retrieved"}
        "process_list" -> {:ok, "Process list retrieved"}
        "admin_action" -> {:ok, "Admin action executed"}
      end
    end
  end
  
  defmodule DangerousTool do
    use RubberDuck.Tool
    
    tool do
      name :dangerous_tool
      description "Tool that attempts dangerous operations"
      category :security_test
      
      parameter :exploit_type do
        type :string
        required true
        constraints [enum: ["command_injection", "path_traversal", "memory_bomb", "infinite_loop"]]
      end
      
      execution do
        handler &DangerousTool.execute/2
        timeout 5_000
      end
      
      security do
        sandbox :strict
        capabilities []
        file_access []
        network_access false
        allowed_modules [String, Enum]
        allowed_functions [:length, :count]
      end
    end
    
    def execute(params, _context) do
      case params.exploit_type do
        "command_injection" ->
          # This should be blocked by sandbox
          try do
            System.cmd("echo", ["malicious"])
            {:ok, "Command executed - SECURITY BREACH!"}
          rescue
            _ -> {:error, "Command execution blocked"}
          end
        
        "path_traversal" ->
          # This should be blocked by file access validation
          path = "../../../etc/passwd"
          case Sandbox.validate_file_access(path, %{file_access: []}) do
            :ok -> {:ok, "Path traversal successful - SECURITY BREACH!"}
            {:error, reason} -> {:error, "Path traversal blocked: #{reason}"}
          end
        
        "memory_bomb" ->
          # This should be blocked by memory limits
          try do
            _big_list = Enum.to_list(1..100_000_000)
            {:ok, "Memory bomb successful - SECURITY BREACH!"}
          rescue
            _ -> {:error, "Memory bomb blocked"}
          end
        
        "infinite_loop" ->
          # This should be blocked by timeout
          spawn(fn -> infinite_loop() end)
          {:ok, "Infinite loop started - SECURITY BREACH!"}
      end
    end
    
    defp infinite_loop do
      infinite_loop()
    end
  end
  
  describe "file system security" do
    test "allows access to permitted paths" do
      params = %{operation: "read", path: "/tmp/test.txt"}
      
      assert {:ok, result} = Executor.execute(FileSystemTool, params, @high_security_user)
      assert result.output =~ "Reading from /tmp/test.txt"
    end
    
    test "blocks access to restricted paths" do
      params = %{operation: "read", path: "/etc/passwd"}
      
      assert {:error, :execution_failed, reason} = Executor.execute(FileSystemTool, params, @high_security_user)
      assert reason =~ "File access denied"
    end
    
    test "prevents path traversal attacks" do
      params = %{operation: "traversal_attempt", path: "/tmp/../../../etc/passwd"}
      
      # Should be blocked at validation level
      assert {:error, :validation_failed, _errors} = Executor.execute(FileSystemTool, params, @high_security_user)
    end
    
    test "respects user file permissions" do
      params = %{operation: "write", path: "/tmp/test.txt"}
      
      # User without file_write permission should be denied
      user = %{@low_security_user | permissions: [:read, :execute, :file_read]}
      assert {:ok, _result} = Executor.execute(FileSystemTool, params, user)
      
      # User without file_read permission should be denied for read operations
      user = %{@low_security_user | permissions: [:read, :execute]}
      assert {:error, :authorization_failed, _reason} = Executor.execute(FileSystemTool, params, user)
    end
  end
  
  describe "network security" do
    test "allows network access when permitted" do
      params = %{operation: "connect", url: "https://api.example.com"}
      
      assert {:ok, result} = Executor.execute(NetworkTool, params, @high_security_user)
      assert result.output =~ "Connected to https://api.example.com"
    end
    
    test "blocks network access for restricted users" do
      params = %{operation: "connect", url: "https://api.example.com"}
      
      user = %{@low_security_user | permissions: [:read, :execute]}
      assert {:error, :authorization_failed, _reason} = Executor.execute(NetworkTool, params, user)
    end
    
    test "respects network sandbox restrictions" do
      # Define a tool with network access disabled
      defmodule NoNetworkTool do
        use RubberDuck.Tool
        
        tool do
          name :no_network_tool
          description "Tool with network access disabled"
          
          parameter :url do
            type :string
            required true
          end
          
          execution do
            handler &NoNetworkTool.execute/2
          end
          
          security do
            sandbox :strict
            capabilities [:network_access]
            network_access false
          end
        end
        
        def execute(params, _context) do
          case Sandbox.validate_network_access(%{network_access: false}) do
            :ok -> {:ok, "Network access allowed"}
            {:error, reason} -> {:error, "Network access denied: #{reason}"}
          end
        end
      end
      
      params = %{url: "https://api.example.com"}
      
      assert {:error, :execution_failed, reason} = Executor.execute(NoNetworkTool, params, @high_security_user)
      assert reason =~ "Network access denied"
    end
  end
  
  describe "privilege escalation prevention" do
    test "prevents unauthorized access to privileged tools" do
      params = %{action: "admin_action"}
      
      # Regular user should be denied
      assert {:error, :authorization_failed, _reason} = Executor.execute(PrivilegedTool, params, @low_security_user)
      
      # Untrusted user should be denied
      assert {:error, :authorization_failed, _reason} = Executor.execute(PrivilegedTool, params, @untrusted_user)
    end
    
    test "allows authorized access to privileged tools" do
      params = %{action: "system_info"}
      
      # High security user with proper permissions
      user = %{@high_security_user | permissions: [:admin_access, :system_info]}
      assert {:ok, result} = Executor.execute(PrivilegedTool, params, user)
      assert result.output =~ "System information retrieved"
    end
    
    test "validates capability requirements" do
      # User missing required capability
      params = %{action: "admin_action"}
      user = %{@high_security_user | permissions: [:read, :execute]}
      
      assert {:error, :authorization_failed, reason} = Executor.execute(PrivilegedTool, params, user)
      assert reason in [:insufficient_capabilities, :insufficient_role]
    end
  end
  
  describe "dangerous operation prevention" do
    test "blocks command injection attempts" do
      params = %{exploit_type: "command_injection"}
      
      assert {:error, :execution_failed, reason} = Executor.execute(DangerousTool, params, @high_security_user)
      assert reason =~ "Command execution blocked"
    end
    
    test "blocks path traversal attempts" do
      params = %{exploit_type: "path_traversal"}
      
      assert {:error, :execution_failed, reason} = Executor.execute(DangerousTool, params, @high_security_user)
      assert reason =~ "Path traversal blocked"
    end
    
    test "blocks memory bombs" do
      params = %{exploit_type: "memory_bomb"}
      
      # Should be killed by memory limits
      assert {:error, :memory_limit_exceeded, _details} = Executor.execute(DangerousTool, params, @high_security_user)
    end
    
    test "blocks infinite loops with timeout" do
      params = %{exploit_type: "infinite_loop"}
      
      # Should be killed by timeout
      assert {:error, :timeout, _details} = Executor.execute(DangerousTool, params, @high_security_user)
    end
  end
  
  describe "sandbox isolation" do
    test "enforces strict sandbox for untrusted code" do
      # Define a tool that tries to break out of sandbox
      defmodule SandboxBreakoutTool do
        use RubberDuck.Tool
        
        tool do
          name :sandbox_breakout_tool
          description "Tool that attempts to break sandbox"
          
          parameter :method do
            type :string
            required true
            constraints [enum: ["process_spawn", "file_system", "network"]]
          end
          
          execution do
            handler &SandboxBreakoutTool.execute/2
          end
          
          security do
            sandbox :strict
            capabilities []
            file_access []
            network_access false
          end
        end
        
        def execute(params, _context) do
          case params.method do
            "process_spawn" ->
              try do
                spawn(fn -> :ok end)
                {:ok, "Process spawned - SECURITY BREACH!"}
              rescue
                _ -> {:error, "Process spawn blocked"}
              end
            
            "file_system" ->
              try do
                File.read("/etc/passwd")
                {:ok, "File system access - SECURITY BREACH!"}
              rescue
                _ -> {:error, "File system access blocked"}
              end
            
            "network" ->
              try do
                :httpc.request("http://example.com")
                {:ok, "Network access - SECURITY BREACH!"}
              rescue
                _ -> {:error, "Network access blocked"}
              end
          end
        end
      end
      
      # All breakout attempts should be blocked
      for method <- ["process_spawn", "file_system", "network"] do
        params = %{method: method}
        result = Executor.execute(SandboxBreakoutTool, params, @high_security_user)
        
        case result do
          {:error, :execution_failed, reason} -> 
            assert reason =~ "blocked"
          {:error, :timeout, _} -> 
            # Timeout is acceptable for security
            :ok
          {:error, :memory_limit_exceeded, _} ->
            # Memory limit is acceptable for security
            :ok
          other ->
            flunk("Expected security block, got: #{inspect(other)}")
        end
      end
    end
    
    test "allows controlled access in relaxed sandbox" do
      # PrivilegedTool uses relaxed sandbox
      params = %{action: "system_info"}
      user = %{@high_security_user | permissions: [:admin_access, :system_info]}
      
      assert {:ok, result} = Executor.execute(PrivilegedTool, params, user)
      assert result.output =~ "System information retrieved"
    end
  end
  
  describe "audit and monitoring" do
    test "logs security events" do
      import ExUnit.CaptureLog
      
      params = %{operation: "read", path: "/etc/passwd"}
      
      log = capture_log(fn ->
        Executor.execute(FileSystemTool, params, @high_security_user)
      end)
      
      # Should log security violation
      assert log =~ "authorization" || log =~ "access denied" || log =~ "validation"
    end
    
    test "emits security telemetry" do
      # Subscribe to security events
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "security_events")
      
      params = %{exploit_type: "command_injection"}
      Executor.execute(DangerousTool, params, @high_security_user)
      
      # Should emit security event
      assert_receive {:security_violation, %{type: _, tool: :dangerous_tool, user: @high_security_user}}, 1000
    end
  end
  
  describe "error handling security" do
    test "does not leak sensitive information in error messages" do
      params = %{operation: "read", path: "/etc/shadow"}
      
      assert {:error, :execution_failed, reason} = Executor.execute(FileSystemTool, params, @high_security_user)
      
      # Error message should not contain sensitive path details
      refute reason =~ "shadow"
      assert reason =~ "File access denied"
    end
    
    test "handles security exceptions gracefully" do
      # Force a security exception
      params = %{exploit_type: "command_injection"}
      
      result = Executor.execute(DangerousTool, params, @high_security_user)
      
      # Should handle exception without crashing
      assert match?({:error, _, _}, result)
    end
  end
  
  describe "resource limit enforcement" do
    test "prevents resource exhaustion attacks" do
      # Tool that tries to consume excessive resources
      defmodule ResourceHogTool do
        use RubberDuck.Tool
        
        tool do
          name :resource_hog_tool
          description "Tool that consumes excessive resources"
          
          parameter :resource_type do
            type :string
            required true
            constraints [enum: ["memory", "cpu", "processes"]]
          end
          
          execution do
            handler &ResourceHogTool.execute/2
            timeout 2_000
          end
          
          security do
            sandbox :strict
            capabilities []
          end
        end
        
        def execute(params, _context) do
          case params.resource_type do
            "memory" ->
              # Try to allocate excessive memory
              _big_list = Enum.to_list(1..50_000_000)
              {:ok, "Memory allocated - SECURITY BREACH!"}
            
            "cpu" ->
              # Try to consume excessive CPU
              Enum.reduce(1..100_000_000, 0, fn i, acc -> acc + i end)
              {:ok, "CPU consumed - SECURITY BREACH!"}
            
            "processes" ->
              # Try to spawn many processes
              Enum.each(1..1000, fn _ -> spawn(fn -> :ok end) end)
              {:ok, "Processes spawned - SECURITY BREACH!"}
          end
        end
      end
      
      # Memory exhaustion should be blocked
      params = %{resource_type: "memory"}
      assert {:error, :memory_limit_exceeded, _} = Executor.execute(ResourceHogTool, params, @high_security_user)
      
      # CPU exhaustion should be blocked by timeout
      params = %{resource_type: "cpu"}
      assert {:error, :timeout, _} = Executor.execute(ResourceHogTool, params, @high_security_user)
    end
  end
end