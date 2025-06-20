defmodule RubberDuck.Commands.CommandHandlerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Commands.CommandHandler
  alias RubberDuck.Commands.CommandBehaviour
  alias RubberDuck.Commands.CommandMetadata
  
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
      # Simulate some work
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
  
  defmodule AsyncCommand do
    @behaviour CommandBehaviour
    
    @impl true
    def metadata do
      %CommandMetadata{
        name: "async_command",
        description: "An async command",
        category: :testing,
        async: true
      }
    end
    
    @impl true
    def validate(_params), do: :ok
    
    @impl true
    def execute(params, _context) do
      duration = Map.get(params, :duration, 50)
      Process.sleep(duration)
      {:ok, "Async completed after #{duration}ms"}
    end
  end
  
  setup do
    # Ensure clean state for each test
    :ok
  end
  
  describe "start_link/1" do
    test "starts a command handler with valid configuration" do
      config = %{
        command_module: TestCommand,
        command_id: "test_123",
        context: %{user_id: "user_1", session_id: "session_1"}
      }
      
      assert {:ok, pid} = CommandHandler.start_link(config)
      assert is_pid(pid)
      assert Process.alive?(pid)
      
      # Cleanup
      Process.exit(pid, :normal)
    end
    
    test "requires command_module in configuration" do
      config = %{
        command_id: "test_123",
        context: %{}
      }
      
      assert {:error, {:invalid_config, "command_module is required"}} = 
        CommandHandler.start_link(config)
    end
  end
  
  describe "execute/2" do
    setup do
      config = %{
        command_module: TestCommand,
        command_id: "test_123",
        context: %{user_id: "user_1"}
      }
      
      {:ok, pid} = CommandHandler.start_link(config)
      
      on_exit(fn ->
        if Process.alive?(pid), do: Process.exit(pid, :normal)
      end)
      
      {:ok, handler: pid}
    end
    
    test "executes command successfully with valid parameters", %{handler: handler} do
      params = %{message: "Hello, World!"}
      
      assert {:ok, result} = CommandHandler.execute(handler, params)
      assert result =~ "Processed: Hello, World!"
      assert result =~ "user_1"
    end
    
    test "returns validation error for invalid parameters", %{handler: handler} do
      params = %{invalid: "param"}
      
      assert {:error, {:validation_failed, errors}} = CommandHandler.execute(handler, params)
      assert [{:message, _}] = errors
    end
    
    test "tracks execution state during command processing", %{handler: handler} do
      params = %{message: "Test"}
      
      # Execute synchronously
      assert {:ok, result} = CommandHandler.execute(handler, params)
      
      # Check final state after execution
      state = CommandHandler.get_state(handler)
      assert state.status == :completed
      assert state.start_time != nil
      assert state.end_time != nil
      assert state.result == :success
      assert result =~ "Processed: Test"
    end
  end
  
  describe "execute_async/2" do
    setup do
      config = %{
        command_module: AsyncCommand,
        command_id: "async_123",
        context: %{user_id: "user_1"}
      }
      
      {:ok, pid} = CommandHandler.start_link(config)
      
      on_exit(fn ->
        if Process.alive?(pid), do: Process.exit(pid, :normal)
      end)
      
      {:ok, handler: pid}
    end
    
    test "executes command asynchronously", %{handler: handler} do
      params = %{duration: 20}
      
      assert {:ok, :executing} = CommandHandler.execute_async(handler, params)
      
      # Should still be executing
      state = CommandHandler.get_state(handler)
      assert state.status == :executing
      
      # Wait for completion
      Process.sleep(30)
      
      state = CommandHandler.get_state(handler)
      assert state.status == :completed
      assert state.result == :success
    end
    
    test "allows checking async execution status", %{handler: handler} do
      params = %{duration: 100}
      
      assert {:ok, :executing} = CommandHandler.execute_async(handler, params)
      
      # Check status while running
      assert {:ok, :executing} = CommandHandler.check_status(handler)
      
      # Wait for completion
      Process.sleep(150)
      
      assert {:ok, :completed} = CommandHandler.check_status(handler)
    end
  end
  
  describe "cancel/1" do
    setup do
      config = %{
        command_module: AsyncCommand,
        command_id: "async_123",
        context: %{user_id: "user_1"}
      }
      
      {:ok, pid} = CommandHandler.start_link(config)
      
      on_exit(fn ->
        if Process.alive?(pid), do: Process.exit(pid, :normal)
      end)
      
      {:ok, handler: pid}
    end
    
    test "cancels executing command", %{handler: handler} do
      params = %{duration: 1000}
      
      assert {:ok, :executing} = CommandHandler.execute_async(handler, params)
      assert {:ok, :cancelled} = CommandHandler.cancel(handler)
      
      state = CommandHandler.get_state(handler)
      assert state.status == :cancelled
      assert state.cancelled_at != nil
    end
    
    test "cannot cancel already completed command", %{handler: handler} do
      params = %{duration: 10}
      
      assert {:ok, :executing} = CommandHandler.execute_async(handler, params)
      Process.sleep(20)
      
      assert {:error, :not_cancellable} = CommandHandler.cancel(handler)
    end
  end
  
  describe "get_state/1" do
    setup do
      config = %{
        command_module: TestCommand,
        command_id: "test_123",
        context: %{user_id: "user_1"},
        metadata: %{priority: :high}
      }
      
      {:ok, pid} = CommandHandler.start_link(config)
      
      on_exit(fn ->
        if Process.alive?(pid), do: Process.exit(pid, :normal)
      end)
      
      {:ok, handler: pid}
    end
    
    test "returns current handler state", %{handler: handler} do
      state = CommandHandler.get_state(handler)
      
      assert state.command_id == "test_123"
      assert state.command_module == TestCommand
      assert state.status == :ready
      assert state.context.user_id == "user_1"
      assert state.metadata.priority == :high
      assert state.created_at != nil
    end
  end
  
  describe "handoff_state/1" do
    setup do
      config = %{
        command_module: TestCommand,
        command_id: "test_123",
        context: %{user_id: "user_1"},
        parameters: %{message: "Test"},
        execution_state: %{progress: 50}
      }
      
      {:ok, pid} = CommandHandler.start_link(config)
      
      on_exit(fn ->
        if Process.alive?(pid), do: Process.exit(pid, :normal)
      end)
      
      {:ok, handler: pid}
    end
    
    test "returns state for handoff to another node", %{handler: handler} do
      assert {:ok, handoff_data} = CommandHandler.handoff_state(handler)
      
      assert handoff_data.command_id == "test_123"
      assert handoff_data.command_module == TestCommand
      assert handoff_data.context.user_id == "user_1"
      assert handoff_data.parameters.message == "Test"
      assert handoff_data.execution_state.progress == 50
    end
    
    test "can restore from handoff state" do
      # Get handoff state from first handler
      config = %{
        command_module: TestCommand,
        command_id: "test_123",
        context: %{user_id: "user_1"},
        parameters: %{message: "Test"}
      }
      
      {:ok, handler1} = CommandHandler.start_link(config)
      {:ok, handoff_data} = CommandHandler.handoff_state(handler1)
      Process.exit(handler1, :normal)
      
      # Restore in new handler
      {:ok, handler2} = CommandHandler.start_link(handoff_data)
      state = CommandHandler.get_state(handler2)
      
      assert state.command_id == "test_123"
      assert state.parameters.message == "Test"
      
      # Cleanup
      Process.exit(handler2, :normal)
    end
  end
  
  describe "error handling" do
    test "handles command execution errors gracefully" do
      config = %{
        command_module: ErrorCommand,
        command_id: "error_123",
        context: %{}
      }
      
      {:ok, handler} = CommandHandler.start_link(config)
      
      assert {:error, "Command failed"} = CommandHandler.execute(handler, %{})
      
      state = CommandHandler.get_state(handler)
      assert state.status == :failed
      assert state.error == "Command failed"
      
      # Cleanup
      Process.exit(handler, :normal)
    end
    
    test "handles command module crashes" do
      defmodule CrashCommand do
        @behaviour CommandBehaviour
        
        @impl true
        def metadata do
          %CommandMetadata{name: "crash", description: "Crashes", category: :testing}
        end
        
        @impl true
        def validate(_), do: :ok
        
        @impl true
        def execute(_, _) do
          raise "Intentional crash"
        end
      end
      
      config = %{
        command_module: CrashCommand,
        command_id: "crash_123",
        context: %{}
      }
      
      {:ok, handler} = CommandHandler.start_link(config)
      
      assert {:error, {:execution_failed, _}} = CommandHandler.execute(handler, %{})
      
      state = CommandHandler.get_state(handler)
      assert state.status == :failed
      assert state.error != nil
      
      # Cleanup
      Process.exit(handler, :normal)
    end
  end
  
  describe "timeout handling" do
    test "enforces execution timeout" do
      defmodule TimeoutCommand do
        @behaviour CommandBehaviour
        
        @impl true
        def metadata do
          %CommandMetadata{name: "timeout", description: "Times out", category: :testing}
        end
        
        @impl true
        def validate(_), do: :ok
        
        @impl true
        def execute(_, _) do
          Process.sleep(1000)
          {:ok, "Should not reach here"}
        end
      end
      
      config = %{
        command_module: TimeoutCommand,
        command_id: "timeout_123",
        context: %{},
        timeout: 50  # 50ms timeout
      }
      
      {:ok, handler} = CommandHandler.start_link(config)
      
      assert {:error, :timeout} = CommandHandler.execute(handler, %{})
      
      state = CommandHandler.get_state(handler)
      assert state.status == :failed
      assert state.error == :timeout
      
      # Cleanup
      Process.exit(handler, :normal)
    end
  end
end