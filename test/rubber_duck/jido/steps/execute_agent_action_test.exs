defmodule RubberDuck.Jido.Steps.ExecuteAgentActionTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido.Steps.ExecuteAgentAction
  alias RubberDuck.Jido.Agents.{Supervisor, Registry}
  
  # Test action module
  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      description: "Test action for unit tests",
      schema: [
        value: [type: :integer, required: true]
      ]
    
    def run(%{value: value}, _context) do
      {:ok, %{result: value * 2}}
    end
    
    def undo(%{undo: true, original_result: result}, _context) do
      {:ok, %{undone: true, original: result}}
    end
  end
  
  setup do
    {:ok, _} = start_supervised(Supervisor)
    
    # Start a test agent
    {:ok, pid} = Supervisor.start_agent(
      RubberDuck.Jido.Agents.ExampleAgent,
      %{},
      id: "test_agent_#{System.unique_integer()}"
    )
    
    # Get the agent info
    [agent | _] = Registry.list_agents()
    
    {:ok, agent: agent}
  end
  
  describe "run/3" do
    test "executes action on agent successfully", %{agent: agent} do
      arguments = %{
        agent_id: agent.id,
        action: TestAction,
        params: %{value: 5}
      }
      
      assert {:ok, result} = ExecuteAgentAction.run(arguments, %{}, [])
      assert result.result == 10
    end
    
    test "returns error when agent not found" do
      arguments = %{
        agent_id: "non_existent_agent",
        action: TestAction,
        params: %{value: 5}
      }
      
      assert {:error, "Agent non_existent_agent not found"} = 
        ExecuteAgentAction.run(arguments, %{}, [])
    end
    
    test "respects custom timeout", %{agent: agent} do
      # Create a slow action
      defmodule SlowAction do
        use Jido.Action,
          name: "slow_action",
          description: "Slow action for timeout test"
        
        def run(_params, _context) do
          Process.sleep(200)
          {:ok, %{result: :done}}
        end
      end
      
      arguments = %{
        agent_id: agent.id,
        action: SlowAction,
        params: %{}
      }
      
      # Should timeout with 100ms timeout
      assert {:error, _} = ExecuteAgentAction.run(arguments, %{}, timeout: 100)
      
      # Should succeed with 300ms timeout
      assert {:ok, _} = ExecuteAgentAction.run(arguments, %{}, timeout: 300)
    end
  end
  
  describe "compensate/4" do
    test "retries on timeout errors" do
      error = {:error, :timeout}
      assert :retry = ExecuteAgentAction.compensate(error, %{}, %{}, [])
      
      error = {:error, {:timeout, "details"}}
      assert :retry = ExecuteAgentAction.compensate(error, %{}, %{}, [])
    end
    
    test "retries on process errors" do
      error = {:error, :noproc}
      assert :retry = ExecuteAgentAction.compensate(error, %{}, %{}, [])
    end
    
    test "does not retry on permanent errors" do
      error = {:error, :invalid_action}
      assert :ok = ExecuteAgentAction.compensate(error, %{}, %{}, [])
      
      error = {:error, "Some other error"}
      assert :ok = ExecuteAgentAction.compensate(error, %{}, %{}, [])
    end
  end
  
  describe "undo/4" do
    test "executes undo when action supports it", %{agent: agent} do
      original_result = %{result: 10}
      arguments = %{
        agent_id: agent.id,
        action: TestAction,
        params: %{}
      }
      
      assert :ok = ExecuteAgentAction.undo(original_result, arguments, %{}, [])
    end
    
    test "returns ok when action does not support undo", %{agent: agent} do
      defmodule NoUndoAction do
        use Jido.Action,
          name: "no_undo_action",
          description: "Action without undo"
        
        def run(_params, _context) do
          {:ok, %{result: :done}}
        end
      end
      
      arguments = %{
        agent_id: agent.id,
        action: NoUndoAction,
        params: %{}
      }
      
      assert :ok = ExecuteAgentAction.undo(%{}, arguments, %{}, [])
    end
    
    test "returns ok even if undo fails", %{agent: agent} do
      defmodule FailingUndoAction do
        use Jido.Action,
          name: "failing_undo_action",
          description: "Action with failing undo"
        
        def run(_params, _context) do
          {:ok, %{result: :done}}
        end
        
        def undo(_params, _context) do
          {:error, :undo_failed}
        end
      end
      
      arguments = %{
        agent_id: agent.id,
        action: FailingUndoAction,
        params: %{}
      }
      
      # Should not raise, just return :ok
      assert :ok = ExecuteAgentAction.undo(%{}, arguments, %{}, [])
    end
  end
end