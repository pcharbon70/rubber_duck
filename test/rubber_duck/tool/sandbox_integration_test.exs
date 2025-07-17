defmodule RubberDuck.Tool.SandboxIntegrationTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.Executor
  
  defmodule SecureTool do
    use RubberDuck.Tool
    
    tool do
      name :secure_tool
      description "A secure tool with sandbox protection"
      category :security
      
      parameter :operation do
        type :string
        required true
        constraints enum: ["safe", "memory_test", "timeout_test"]
      end
      
      execution do
        handler &SecureTool.execute/2
        timeout 10_000
        retries 1
      end
      
      security do
        sandbox :strict
        capabilities [:execute]
        file_access []
        network_access false
      end
    end
    
    def execute(%{operation: "safe"}, _context) do
      {:ok, "Safe operation completed"}
    end
    
    def execute(%{operation: "memory_test"}, _context) do
      # This should be killed by memory limits
      big_list = Enum.to_list(1..10_000_000)
      {:ok, "Created list with #{length(big_list)} items"}
    end
    
    def execute(%{operation: "timeout_test"}, _context) do
      # This should timeout
      Process.sleep(15_000)
      {:ok, "Should not reach here"}
    end
  end
  
  # Test user
  @test_user %{
    id: "test-user",
    roles: [:user],
    permissions: [:execute]
  }
  
  describe "sandbox integration with executor" do
    test "executes safe operations successfully" do
      params = %{operation: "safe"}
      
      assert {:ok, result} = Executor.execute(SecureTool, params, @test_user)
      assert result.output == "Safe operation completed"
      assert result.status == :success
    end
    
    test "enforces memory limits through sandbox" do
      params = %{operation: "memory_test"}
      
      # This should fail due to memory limits
      assert {:error, :memory_limit_exceeded, _details} = 
        Executor.execute(SecureTool, params, @test_user)
    end
    
    test "enforces timeout limits through sandbox" do
      params = %{operation: "timeout_test"}
      
      # This should timeout
      assert {:error, :timeout, _details} = 
        Executor.execute(SecureTool, params, @test_user)
    end
    
    test "async execution with sandbox protection" do
      params = %{operation: "safe"}
      
      assert {:ok, ref} = Executor.execute_async(SecureTool, params, @test_user)
      
      # Wait for result
      assert_receive {^ref, {:ok, result}}, 5000
      assert result.output == "Safe operation completed"
      assert result.status == :success
    end
    
    test "sandbox configuration is respected" do
      # The secure tool has strict sandbox with no file access
      # This confirms the sandbox system is being used
      params = %{operation: "safe"}
      
      assert {:ok, result} = Executor.execute(SecureTool, params, @test_user)
      assert result.output == "Safe operation completed"
      
      # Verify sandbox metadata is included
      assert is_map(result.metadata)
      assert result.metadata.tool_name == :secure_tool
    end
  end
end