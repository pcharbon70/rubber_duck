defmodule RubberDuck.Jido.Workflows.SimplePipelineTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Jido.Workflows.SimplePipeline
  alias RubberDuck.Jido.Agents.{Supervisor, Registry}
  
  # Mock actions for testing
  defmodule RubberDuck.Actions.ValidateAction do
    use Jido.Action,
      name: "validate",
      description: "Validates input data",
      schema: [
        items: [type: {:list, :integer}, required: false]
      ]
    
    def run(params, _context) do
      if is_map(params) and Map.has_key?(params, :items) do
        {:ok, %{validated: true, data: params}}
      else
        {:error, :invalid_input}
      end
    end
  end
  
  defmodule RubberDuck.Actions.TransformAction do
    use Jido.Action,
      name: "transform",
      description: "Transforms validated data",
      schema: []
    
    def run(%{validated: true, data: data}, _context) do
      transformed = Map.update(data, :items, [], &Enum.map(&1, fn x -> x * 2 end))
      {:ok, %{transformed: true, data: transformed}}
    end
    
    def run(_params, _context) do
      {:error, :not_validated}
    end
  end
  
  defmodule RubberDuck.Actions.StoreAction do
    use Jido.Action,
      name: "store",
      description: "Stores transformed data",
      schema: []
    
    def run(%{transformed: true, data: data}, _context) do
      # Simulate storage
      id = :erlang.unique_integer([:positive])
      {:ok, %{stored: true, id: id, data: data}}
    end
    
    def run(_params, _context) do
      {:error, :not_transformed}
    end
  end
  
  # Test agent that supports all capabilities
  defmodule TestPipelineAgent do
    use RubberDuck.Jido.BaseAgent,
      name: "test_pipeline_agent",
      description: "Agent for pipeline testing"
    
    @impl true
    def init(initial_state) do
      state = Map.merge(initial_state, %{
        capabilities: [:validation, :transformation, :storage],
        load: 0
      })
      {:ok, state}
    end
  end
  
  setup do
    # Start the supervisor
    {:ok, _} = start_supervised(Supervisor)
    
    # Start agents with different capabilities
    {:ok, validator_pid} = Supervisor.start_agent(
      TestPipelineAgent,
      %{},
      id: "validator_#{System.unique_integer()}",
      tags: [:validator],
      capabilities: [:validation]
    )
    
    {:ok, transformer_pid} = Supervisor.start_agent(
      TestPipelineAgent,
      %{},
      id: "transformer_#{System.unique_integer()}",
      tags: [:transformer],
      capabilities: [:transformation]
    )
    
    {:ok, storage_pid} = Supervisor.start_agent(
      TestPipelineAgent,
      %{},
      id: "storage_#{System.unique_integer()}",
      tags: [:storage],
      capabilities: [:storage]
    )
    
    # Give agents time to register
    Process.sleep(50)
    
    {:ok, 
      validator_pid: validator_pid,
      transformer_pid: transformer_pid,
      storage_pid: storage_pid
    }
  end
  
  describe "SimplePipeline workflow" do
    @tag :skip  # Skip until we have WorkflowCoordinator
    test "processes data through pipeline successfully" do
      inputs = %{
        data: %{items: [1, 2, 3]},
        pipeline_config: %{
          steps: [:validate, :transform, :store]
        }
      }
      
      assert {:ok, result} = Reactor.run(SimplePipeline, inputs, %{})
      assert result.stored == true
      assert result.data.items == [2, 4, 6]
      assert is_integer(result.id)
    end
    
    @tag :skip
    test "fails when validation fails" do
      inputs = %{
        data: %{invalid: "data"},  # Missing items
        pipeline_config: %{
          steps: [:validate, :transform, :store]
        }
      }
      
      assert {:error, _reason} = Reactor.run(SimplePipeline, inputs, %{})
    end
    
    @tag :skip
    test "selects least loaded agents" do
      # This would require setting up agents with different loads
      # and verifying the selection strategy works correctly
    end
  end
  
  describe "SimplePipeline step definitions" do
    test "workflow has correct structure" do
      # Verify the workflow module exists and has expected structure
      assert function_exported?(SimplePipeline, :__reactor__, 0)
      
      reactor = SimplePipeline.__reactor__()
      assert is_map(reactor)
      
      # Check inputs are defined
      assert {:ok, _} = Reactor.Info.to_struct(reactor)
    end
  end
end