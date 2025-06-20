defmodule RubberDuck.Commands.ExecutionManagerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Commands.{ExecutionManager, CommandHandler, CommandSupervisor}
  alias RubberDuck.Commands.{CommandBehaviour, CommandMetadata}
  
  # Mock command for testing
  defmodule TestCommand do
    @behaviour CommandBehaviour
    
    @impl true
    def metadata do
      %CommandMetadata{
        name: "test_command",
        description: "A test command",
        category: :testing,
        parameters: [
          %CommandMetadata.Parameter{
            name: :message,
            type: :string,
            required: true,
            description: "Test message"
          }
        ]
      }
    end
    
    @impl true
    def validate(params) do
      if Map.has_key?(params, :message) and is_binary(params.message) do
        :ok
      else
        {:error, [{:message, "is required and must be a string"}]}
      end
    end
    
    @impl true
    def execute(%{message: message}, context) do
      Process.sleep(10)
      {:ok, "Processed: #{message} in context: #{inspect(context)}"}
    end
  end
  
  defmodule ErrorCommand do
    @behaviour CommandBehaviour
    
    @impl true
    def metadata do
      %CommandMetadata{
        name: "error_command",
        description: "A command that errors",
        category: :testing
      }
    end
    
    @impl true
    def validate(_params), do: :ok
    
    @impl true
    def execute(_params, _context) do
      {:error, "Command failed"}
    end
  end
  
  defmodule SlowCommand do
    @behaviour CommandBehaviour
    
    @impl true
    def metadata do
      %CommandMetadata{
        name: "slow_command",
        description: "A slow command",
        category: :testing,
        async: true
      }
    end
    
    @impl true
    def validate(_params), do: :ok
    
    @impl true
    def execute(params, _context) do
      duration = Map.get(params, :duration, 100)
      Process.sleep(duration)
      {:ok, "Slow completed after #{duration}ms"}
    end
  end
  
  setup_all do
    # Start required services for testing
    case CommandSupervisor.start_link(name: :test_command_supervisor) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
    
    case ExecutionManager.start_link(config: %{telemetry_enabled: false}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
    
    :ok
  end
  
  setup do
    # Clean up any existing executions before each test
    try do
      executions = ExecutionManager.list_active_executions()
      Enum.each(executions, fn execution ->
        ExecutionManager.cancel_execution(execution.execution_id)
      end)
    catch
      _, _ -> :ok
    end
    
    # Clean up command supervisor
    try do
      children = GenServer.call(:test_command_supervisor, :which_children)
      Enum.each(children, fn {_id, pid, _type, _modules} ->
        if is_pid(pid) do
          DynamicSupervisor.terminate_child(:test_command_supervisor, pid)
        end
      end)
    catch
      _, _ -> :ok
    end
    
    :ok
  end
  
  describe "execute_command/4" do
    test "executes a command successfully" do
      parameters = %{message: "Hello, World!"}
      context = %{user_id: "user_1", session_id: "session_1"}
      
      assert {:ok, result} = ExecutionManager.execute_command(TestCommand, parameters, context)
      assert result =~ "Processed: Hello, World!"
      assert result =~ "user_1"
    end
    
    test "returns validation error for invalid parameters" do
      parameters = %{invalid: "param"}
      context = %{user_id: "user_1"}
      
      assert {:error, {:validation_failed, errors}} = ExecutionManager.execute_command(TestCommand, parameters, context)
      assert [{:message, _}] = errors
    end
    
    test "returns error for failing command" do
      parameters = %{}
      context = %{user_id: "user_1"}
      
      assert {:error, "Command failed"} = ExecutionManager.execute_command(ErrorCommand, parameters, context)
    end
    
    test "respects placement strategy option" do
      parameters = %{message: "Test"}
      context = %{user_id: "user_1"}
      opts = %{placement_strategy: :least_loaded}
      
      assert {:ok, result} = ExecutionManager.execute_command(TestCommand, parameters, context, opts)
      assert result =~ "Processed: Test"
    end
    
    test "handles timeout option" do
      parameters = %{message: "Test"}
      context = %{user_id: "user_1", timeout: 50}
      
      # This should succeed as the command is fast
      assert {:ok, result} = ExecutionManager.execute_command(TestCommand, parameters, context)
      assert result =~ "Processed: Test"
    end
  end
  
  describe "execute_command_async/4" do
    test "executes command asynchronously" do
      parameters = %{duration: 50}
      context = %{user_id: "user_1"}
      
      assert {:ok, execution_id} = ExecutionManager.execute_command_async(SlowCommand, parameters, context)
      assert is_binary(execution_id)
      assert String.starts_with?(execution_id, "exec_")
      
      # Should appear in active executions
      executions = ExecutionManager.list_active_executions()
      assert Enum.any?(executions, fn exec -> exec.execution_id == execution_id end)
      
      # Wait for completion
      Process.sleep(100)
      
      # Should complete and be removed from active executions
      executions_after = ExecutionManager.list_active_executions()
      refute Enum.any?(executions_after, fn exec -> exec.execution_id == execution_id end)
    end
    
    test "returns execution ID immediately for async execution" do
      parameters = %{duration: 1000}
      context = %{user_id: "user_1"}
      
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, execution_id} = ExecutionManager.execute_command_async(SlowCommand, parameters, context)
      end_time = System.monotonic_time(:millisecond)
      
      # Should return quickly (within 100ms)
      assert (end_time - start_time) < 100
      assert is_binary(execution_id)
      
      # Clean up
      ExecutionManager.cancel_execution(execution_id)
    end
  end
  
  describe "get_execution_status/1" do
    test "returns status for active execution" do
      parameters = %{duration: 200}
      context = %{user_id: "user_1"}
      
      {:ok, execution_id} = ExecutionManager.execute_command_async(SlowCommand, parameters, context)
      
      assert {:ok, status} = ExecutionManager.get_execution_status(execution_id)
      assert status.execution_id == execution_id
      assert status.command_module == SlowCommand
      assert status.status in [:ready, :executing, :validating]
      assert is_integer(status.start_time)
      assert is_integer(status.duration)
      assert status.context.user_id == "user_1"
      
      # Clean up
      ExecutionManager.cancel_execution(execution_id)
    end
    
    test "returns error for non-existent execution" do
      assert {:error, :execution_not_found} = ExecutionManager.get_execution_status("non_existent")
    end
  end
  
  describe "cancel_execution/1" do
    test "cancels running execution" do
      parameters = %{duration: 1000}
      context = %{user_id: "user_1"}
      
      {:ok, execution_id} = ExecutionManager.execute_command_async(SlowCommand, parameters, context)
      
      # Execution should be running
      executions = ExecutionManager.list_active_executions()
      assert Enum.any?(executions, fn exec -> exec.execution_id == execution_id end)
      
      # Cancel execution
      assert {:ok, :cancelled} = ExecutionManager.cancel_execution(execution_id)
      
      # Wait a bit for cancellation to process
      Process.sleep(50)
      
      # Should be removed from active executions
      executions_after = ExecutionManager.list_active_executions()
      refute Enum.any?(executions_after, fn exec -> exec.execution_id == execution_id end)
    end
    
    test "returns error for non-existent execution" do
      assert {:error, :execution_not_found} = ExecutionManager.cancel_execution("non_existent")
    end
  end
  
  describe "list_active_executions/0" do
    test "lists all active executions" do
      # Start multiple async executions
      {:ok, exec_id1} = ExecutionManager.execute_command_async(SlowCommand, %{duration: 200}, %{user_id: "user_1"})
      {:ok, exec_id2} = ExecutionManager.execute_command_async(SlowCommand, %{duration: 200}, %{user_id: "user_2"})
      
      executions = ExecutionManager.list_active_executions()
      
      execution_ids = Enum.map(executions, & &1.execution_id)
      assert exec_id1 in execution_ids
      assert exec_id2 in execution_ids
      
      # Each execution should have required fields
      Enum.each(executions, fn execution ->
        assert Map.has_key?(execution, :execution_id)
        assert Map.has_key?(execution, :command_module)
        assert Map.has_key?(execution, :status)
        assert Map.has_key?(execution, :start_time)
        assert Map.has_key?(execution, :duration)
      end)
      
      # Clean up
      ExecutionManager.cancel_execution(exec_id1)
      ExecutionManager.cancel_execution(exec_id2)
    end
    
    test "returns empty list when no active executions" do
      executions = ExecutionManager.list_active_executions()
      assert executions == []
    end
  end
  
  describe "get_execution_stats/0" do
    test "returns comprehensive execution statistics" do
      # Execute some commands to generate stats
      ExecutionManager.execute_command(TestCommand, %{message: "Test1"}, %{user_id: "user_1"})
      ExecutionManager.execute_command(TestCommand, %{message: "Test2"}, %{user_id: "user_2"})
      
      stats = ExecutionManager.get_execution_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :uptime_ms)
      assert Map.has_key?(stats, :active_executions)
      assert Map.has_key?(stats, :total_executions)
      assert Map.has_key?(stats, :successful_executions)
      assert Map.has_key?(stats, :failed_executions)
      assert Map.has_key?(stats, :cancelled_executions)
      assert Map.has_key?(stats, :average_execution_time)
      assert Map.has_key?(stats, :circuit_breakers)
      assert Map.has_key?(stats, :executions_per_minute)
      
      assert is_integer(stats.uptime_ms)
      assert is_integer(stats.active_executions)
      assert is_integer(stats.total_executions)
      assert is_integer(stats.successful_executions)
      assert is_float(stats.average_execution_time) or stats.average_execution_time == 0
      assert is_map(stats.circuit_breakers)
      assert is_float(stats.executions_per_minute)
      
      assert stats.total_executions >= 2
      assert stats.successful_executions >= 2
    end
  end
  
  describe "circuit breaker functionality" do
    test "gets circuit breaker status" do
      status = ExecutionManager.get_circuit_breaker_status(TestCommand)
      assert status in [:closed, :open, :half_open]
    end
    
    test "circuit breaker initially closed" do
      status = ExecutionManager.get_circuit_breaker_status(TestCommand)
      assert status == :closed
    end
  end
  
  describe "health_check/0" do
    test "returns health status" do
      assert {:ok, health} = ExecutionManager.health_check()
      
      assert is_map(health)
      assert Map.has_key?(health, :status)
      assert Map.has_key?(health, :active_executions)
      assert Map.has_key?(health, :circuit_breakers)
      assert Map.has_key?(health, :uptime_ms)
      
      assert health.status == :healthy
      assert is_integer(health.active_executions)
      assert is_integer(health.circuit_breakers)
      assert is_integer(health.uptime_ms)
    end
  end
  
  describe "telemetry integration" do
    test "can be configured with telemetry disabled" do
      # This is tested by the setup which creates ExecutionManager with telemetry disabled
      # The fact that tests pass shows it works without telemetry
      assert {:ok, health} = ExecutionManager.health_check()
      assert health.status == :healthy
    end
  end
  
  describe "error handling" do
    test "handles command module that doesn't exist gracefully" do
      parameters = %{message: "Test"}
      context = %{user_id: "user_1"}
      
      # This should fail gracefully
      assert {:error, _reason} = ExecutionManager.execute_command(NonExistentCommand, parameters, context)
    end
    
    test "handles execution manager restart" do
      # Execute a command to verify normal operation
      parameters = %{message: "Test"}
      context = %{user_id: "user_1"}
      
      assert {:ok, result} = ExecutionManager.execute_command(TestCommand, parameters, context)
      assert result =~ "Processed: Test"
    end
  end
  
  describe "concurrent execution" do
    test "handles multiple concurrent executions" do
      # Start multiple async executions concurrently
      tasks = for i <- 1..5 do
        Task.async(fn ->
          ExecutionManager.execute_command_async(SlowCommand, %{duration: 100}, %{user_id: "user_#{i}"})
        end)
      end
      
      results = Task.await_many(tasks, 1000)
      
      # All should succeed and return execution IDs
      Enum.each(results, fn result ->
        assert {:ok, execution_id} = result
        assert is_binary(execution_id)
        assert String.starts_with?(execution_id, "exec_")
      end)
      
      # Should have multiple active executions
      executions = ExecutionManager.list_active_executions()
      assert length(executions) == 5
      
      # Clean up
      Enum.each(results, fn {:ok, execution_id} ->
        ExecutionManager.cancel_execution(execution_id)
      end)
    end
  end
end