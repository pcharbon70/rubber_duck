defmodule RubberDuck.Tool.ExecutorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.Executor
  
  # Test user contexts - admin user not currently used but kept for future tests
  @admin_user %{
    id: "admin-123",
    roles: [:admin],
    permissions: [:all]
  }
  
  # Suppress unused warning
  _ = @admin_user
  
  @regular_user %{
    id: "user-456",
    roles: [:user],
    permissions: [:read, :execute, :file_read]
  }
  
  defmodule SimpleTool do
    use RubberDuck.Tool
    
    tool do
      name :simple_tool
      description "A simple test tool"
      category :testing
      
      parameter :input do
        type :string
        required true
      end
      
      execution do
        handler &SimpleTool.execute/2
        timeout 5_000
        async false
      end
    end
    
    def execute(params, _context) do
      {:ok, "Processed: #{params.input}"}
    end
  end
  
  defmodule AsyncTool do
    use RubberDuck.Tool
    
    tool do
      name :async_tool
      description "An async test tool"
      category :testing
      
      parameter :delay do
        type :integer
        default 100
      end
      
      execution do
        handler &AsyncTool.execute/2
        timeout 10_000
        async true
      end
    end
    
    def execute(params, _context) do
      Process.sleep(params[:delay] || 100)
      {:ok, "Async result"}
    end
  end
  
  defmodule TimeoutTool do
    use RubberDuck.Tool
    
    tool do
      name :timeout_tool
      description "A tool that times out"
      category :testing
      
      execution do
        handler &TimeoutTool.execute/2
        timeout 100
      end
    end
    
    def execute(_params, _context) do
      Process.sleep(200)
      {:ok, "Should timeout"}
    end
  end
  
  defmodule ErrorTool do
    use RubberDuck.Tool
    
    tool do
      name :error_tool
      description "A tool that raises errors"
      category :testing
      
      execution do
        handler &ErrorTool.execute/2
        timeout 5_000
        retries 2
      end
    end
    
    def execute(_params, _context) do
      raise "Test error"
    end
  end
  
  defmodule RetryTool do
    use RubberDuck.Tool
    
    tool do
      name :retry_tool
      description "A tool that succeeds after retries"
      category :testing
      
      execution do
        handler &RetryTool.execute/2
        timeout 5_000
        retries 2
      end
    end
    
    def execute(_params, context) do
      attempt = context[:attempt] || 1
      
      if attempt < 3 do
        {:error, "Retry #{attempt}"}
      else
        {:ok, "Success on attempt #{attempt}"}
      end
    end
  end
  
  setup do
    # Ensure clean state for each test
    :ok
  end
  
  describe "basic execution" do
    test "executes simple tool successfully" do
      params = %{input: "test"}
      
      assert {:ok, result} = Executor.execute(SimpleTool, params, @regular_user)
      assert result.output == "Processed: test"
      assert result.status == :success
      assert is_number(result.execution_time)
    end
    
    test "validates parameters before execution" do
      # Missing required parameter
      params = %{}
      
      assert {:error, :validation_failed, errors} = Executor.execute(SimpleTool, params, @regular_user)
      assert is_list(errors)
    end
    
    test "checks authorization before execution" do
      # User without proper permissions
      unauthorized_user = %{
        id: "guest-000",
        roles: [:guest],
        permissions: []
      }
      
      defmodule RestrictedTool do
        use RubberDuck.Tool
        
        tool do
          name :restricted_tool
          description "A restricted tool"
          
          execution do
            handler &RestrictedTool.execute/2
          end
          
          security do
            capabilities [:admin_access]
          end
        end
        
        def execute(_params, _context) do
          {:ok, "restricted result"}
        end
      end
      
      assert {:error, :authorization_failed, reason} = Executor.execute(RestrictedTool, %{}, unauthorized_user)
      assert reason == :insufficient_role
    end
  end
  
  describe "async execution" do
    test "executes async tool" do
      params = %{delay: 50}
      
      assert {:ok, execution_ref} = Executor.execute_async(AsyncTool, params, @regular_user)
      assert is_reference(execution_ref)
      
      # Wait for result
      assert_receive {^execution_ref, {:ok, result}}, 1000
      assert result.output == "Async result"
      assert result.status == :success
    end
    
    test "can cancel async execution" do
      params = %{delay: 1000}
      
      assert {:ok, execution_ref} = Executor.execute_async(AsyncTool, params, @regular_user)
      
      # Cancel execution
      assert :ok = Executor.cancel_execution(execution_ref)
      
      # Should receive cancellation message
      assert_receive {^execution_ref, {:error, :cancelled}}, 1000
    end
    
    test "monitors async execution status" do
      params = %{delay: 100}
      
      assert {:ok, execution_ref} = Executor.execute_async(AsyncTool, params, @regular_user)
      
      # Check status while running
      assert {:ok, status} = Executor.get_execution_status(execution_ref)
      assert status.status == :running
      assert is_number(status.started_at)
      
      # Wait for completion
      assert_receive {^execution_ref, {:ok, _result}}, 1000
      
      # Check final status
      assert {:ok, status} = Executor.get_execution_status(execution_ref)
      assert status.status == :completed
      assert is_number(status.completed_at)
    end
  end
  
  describe "timeout handling" do
    test "handles execution timeout" do
      assert {:error, :timeout} = Executor.execute(TimeoutTool, %{}, @regular_user)
    end
    
    test "handles async timeout" do
      assert {:ok, execution_ref} = Executor.execute_async(TimeoutTool, %{}, @regular_user)
      
      # Should receive timeout message
      assert_receive {^execution_ref, {:error, :timeout}}, 1000
    end
  end
  
  describe "error handling and retries" do
    test "handles tool errors" do
      assert {:error, :execution_failed, reason} = Executor.execute(ErrorTool, %{}, @regular_user)
      assert reason =~ "Test error"
    end
    
    test "retries on failure" do
      # The retry tool will succeed on the 3rd attempt
      # So we expect 2 retries (first attempt + 2 retries = 3 total attempts)
      assert {:ok, result} = Executor.execute(RetryTool, %{}, @regular_user)
      assert result.output == "Success on attempt 3"
      assert result.retry_count == 2
    end
  end
  
  describe "resource limits" do
    test "enforces memory limits" do
      defmodule MemoryHogTool do
        use RubberDuck.Tool
        
        tool do
          name :memory_hog
          description "A tool that uses lots of memory"
          
          execution do
            handler &MemoryHogTool.execute/2
            timeout 5_000
          end
        end
        
        def execute(_params, _context) do
          # Simulate memory usage
          big_list = Enum.to_list(1..1_000_000)
          {:ok, "Memory used: #{length(big_list)}"}
        end
      end
      
      # Set memory limit
      limits = %{memory_mb: 10}
      
      assert {:error, :resource_limit_exceeded, :memory} = 
        Executor.execute(MemoryHogTool, %{}, @regular_user, %{limits: limits})
    end
    
    test "enforces CPU limits" do
      defmodule CpuHogTool do
        use RubberDuck.Tool
        
        tool do
          name :cpu_hog
          description "A tool that uses lots of CPU"
          
          execution do
            handler &CpuHogTool.execute/2
            timeout 5_000
          end
        end
        
        def execute(_params, _context) do
          # Simulate CPU usage
          Enum.reduce(1..1_000_000, 0, fn i, acc -> acc + i end)
          {:ok, "CPU intensive task completed"}
        end
      end
      
      # Set CPU limit
      limits = %{cpu_seconds: 1}
      
      assert {:error, :resource_limit_exceeded, :cpu} = 
        Executor.execute(CpuHogTool, %{}, @regular_user, %{limits: limits})
    end
  end
  
  describe "execution context" do
    test "provides execution context to tools" do
      defmodule ContextTool do
        use RubberDuck.Tool
        
        tool do
          name :context_tool
          description "A tool that checks execution context"
          
          execution do
            handler &ContextTool.execute/2
          end
        end
        
        def execute(_params, context) do
          {:ok, "User: #{context.user.id}, Execution ID: #{context.execution_id}"}
        end
      end
      
      assert {:ok, result} = Executor.execute(ContextTool, %{}, @regular_user)
      assert result.output =~ "User: user-456"
      assert result.output =~ "Execution ID:"
    end
    
    test "tracks execution metadata" do
      assert {:ok, result} = Executor.execute(SimpleTool, %{input: "test"}, @regular_user)
      
      assert result.metadata.tool_name == :simple_tool
      assert result.metadata.user_id == "user-456"
      assert is_binary(result.metadata.execution_id)
      assert is_number(result.metadata.started_at)
      assert is_number(result.metadata.completed_at)
    end
  end
  
  describe "concurrent execution" do
    test "handles multiple concurrent executions" do
      params = %{delay: 100}
      
      # Start multiple async executions
      refs = Enum.map(1..5, fn _ ->
        {:ok, ref} = Executor.execute_async(AsyncTool, params, @regular_user)
        ref
      end)
      
      # Wait for all to complete
      results = Enum.map(refs, fn ref ->
        assert_receive {^ref, {:ok, result}}, 1000
        result
      end)
      
      # All should succeed
      assert length(results) == 5
      assert Enum.all?(results, & &1.status == :success)
    end
    
    test "respects concurrency limits" do
      # Set concurrency limit
      limits = %{max_concurrent: 2}
      
      # Try to start 5 executions
      refs = Enum.map(1..5, fn _ ->
        Executor.execute_async(AsyncTool, %{delay: 100}, @regular_user, %{limits: limits})
      end)
      
      # First 2 should succeed, rest should be queued or rejected
      successful_refs = Enum.filter(refs, fn
        {:ok, _ref} -> true
        _ -> false
      end)
      
      assert length(successful_refs) <= 2
    end
  end
  
  describe "execution events" do
    test "emits execution events" do
      # Subscribe to execution events
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "tool_executions")
      
      assert {:ok, result} = Executor.execute(SimpleTool, %{input: "test"}, @regular_user)
      
      # Should receive events
      assert_receive {:tool_execution_started, %{tool: :simple_tool, user: @regular_user}}
      assert_receive {:tool_execution_completed, %{tool: :simple_tool, result: ^result}}
    end
    
    test "emits error events" do
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "tool_executions")
      
      assert {:error, :execution_failed, _reason} = Executor.execute(ErrorTool, %{}, @regular_user)
      
      # Should receive error event
      assert_receive {:tool_execution_failed, %{tool: :error_tool, error: _}}
    end
  end
  
  describe "execution history" do
    test "records execution history" do
      assert {:ok, _result} = Executor.execute(SimpleTool, %{input: "test"}, @regular_user)
      
      # Should be able to retrieve execution history
      history = Executor.get_execution_history(@regular_user, limit: 10)
      
      assert length(history) >= 1
      assert List.first(history).tool_name == :simple_tool
    end
    
    test "limits execution history" do
      # Execute tool multiple times
      Enum.each(1..15, fn i ->
        Executor.execute(SimpleTool, %{input: "test#{i}"}, @regular_user)
      end)
      
      # History should be limited
      history = Executor.get_execution_history(@regular_user, limit: 10)
      assert length(history) == 10
    end
  end
end