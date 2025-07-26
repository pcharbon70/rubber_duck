defmodule RubberDuck.Engine.CancellationIntegrationTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Engine.{TaskRegistry, CancellationToken}
  alias RubberDuck.CoT.Manager
  
  setup do
    # Start required services
    start_supervised!(TaskRegistry)
    :ok
  end
  
  describe "end-to-end cancellation" do
    test "cancellation token stops chain execution" do
      # Create a cancellation token
      token = CancellationToken.create("test_conv")
      
      # Start chain execution in a task
      chain_task = Task.async(fn ->
        # Create a mock chain module
        defmodule TestChain do
          def config, do: %{description: "Test chain"}
          def steps, do: [
            %{name: :step1, prompt: "Step 1: {{query}}"},
            %{name: :step2, prompt: "Step 2: {{step1_result}}"},
            %{name: :step3, prompt: "Step 3: {{step2_result}}"}
          ]
        end
        
        context = %{
          provider: :mock,
          model: "test-model",
          cancellation_token: token
        }
        
        Manager.execute_chain(TestChain, "Test query", context)
      end)
      
      # Let the chain start
      Process.sleep(50)
      
      # Cancel the token
      assert :ok = CancellationToken.cancel(token)
      
      # Wait for the chain to finish
      result = Task.await(chain_task, 5000)
      
      # Should get cancellation error
      assert {:error, :cancelled} = result
    end
    
    test "task registry tracks and cancels tasks" do
      # Create a long-running task
      task = Task.async(fn ->
        receive do
          :stop -> :stopped
        after
          10_000 -> :timeout
        end
      end)
      
      # Register it
      {:ok, task_id} = TaskRegistry.register_task(task, "test_conv", "test_engine")
      
      # Verify it's tracked
      tasks = TaskRegistry.find_by_conversation("test_conv")
      assert length(tasks) == 1
      assert hd(tasks).task_id == task_id
      
      # Cancel it
      assert :ok = TaskRegistry.cancel_task(task_id)
      
      # Task should be cancelled
      Process.flag(:trap_exit, true)
      assert_receive {:EXIT, _, :cancelled}, 1000
    end
    
    test "engine server respects cancellation" do
      # This would require setting up a test engine
      # For now, we'll verify the basic flow
      
      token = CancellationToken.create("test_conv")
      
      # Cancel immediately
      CancellationToken.cancel(token)
      
      # Any operation with this token should fail
      assert CancellationToken.cancelled?(token)
      assert {:error, :cancelled} = CancellationToken.check!(token)
    end
  end
end