defmodule RubberDuck.Jido.Workflows.Library.MapReduceTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Jido.Workflows.Library.MapReduce
  alias RubberDuck.Jido.Agents.{Supervisor, Registry}

  # Test actions for map/reduce operations
  defmodule SquareAction do
    use Jido.Action,
      name: "square",
      description: "Squares a number",
      schema: [
        value: [type: :integer, required: true]
      ]

    def run(%{value: value}, _context) do
      {:ok, %{result: value * value}}
    end
  end

  defmodule SumAction do
    use Jido.Action,
      name: "sum",
      description: "Sums a list of numbers",
      schema: [
        values: [type: {:list, :integer}, required: true]
      ]

    def run(%{values: values}, _context) do
      result = Enum.sum(values)
      {:ok, %{result: result}}
    end
  end

  # Test agent that can handle map/reduce operations
  defmodule MapReduceAgent do
    use RubberDuck.Jido.BaseAgent,
      name: "map_reduce_agent",
      description: "Agent for map/reduce operations"

    @impl true
    def init(initial_state) do
      state = Map.merge(initial_state, %{
        capabilities: [:computation, :aggregation],
        load: 0
      })
      {:ok, state}
    end
  end

  setup do
    # Start the supervisor
    {:ok, _} = start_supervised(Supervisor)
    
    # Start multiple agents for parallel processing
    agents = for i <- 1..3 do
      {:ok, pid} = Supervisor.start_agent(
        MapReduceAgent,
        %{},
        id: "map_reduce_agent_#{i}_#{System.unique_integer()}",
        tags: [:mapper, :reducer],
        capabilities: [:computation, :aggregation]
      )
      pid
    end
    
    # Give agents time to register
    Process.sleep(100)
    
    {:ok, agents: agents}
  end

  describe "MapReduce workflow" do
    test "processes data through map-reduce successfully" do
      inputs = %{
        data: [1, 2, 3, 4, 5],
        map_action: SquareAction,
        reduce_action: SumAction,
        chunk_size: 2
      }
      
      # Execute the map-reduce workflow
      assert {:ok, result} = Reactor.run(MapReduce, inputs, %{})
      
      # Should compute sum of squares: 1² + 2² + 3² + 4² + 5² = 1 + 4 + 9 + 16 + 25 = 55
      assert result.result == 55
    end

    test "handles single chunk processing" do
      inputs = %{
        data: [2, 3],
        map_action: SquareAction,  
        reduce_action: SumAction,
        chunk_size: 5  # Larger than data size
      }
      
      assert {:ok, result} = Reactor.run(MapReduce, inputs, %{})
      
      # Should compute: 2² + 3² = 4 + 9 = 13
      assert result.result == 13
    end

    test "handles empty data" do
      inputs = %{
        data: [],
        map_action: SquareAction,
        reduce_action: SumAction,
        chunk_size: 2
      }
      
      assert {:ok, result} = Reactor.run(MapReduce, inputs, %{})
      assert result.result == 0
    end

    test "uses custom chunk size" do
      inputs = %{
        data: [1, 2, 3, 4, 5, 6],
        map_action: SquareAction,
        reduce_action: SumAction,
        chunk_size: 3  # Should create 2 chunks
      }
      
      assert {:ok, result} = Reactor.run(MapReduce, inputs, %{})
      
      # Should compute sum of squares: 1² + 2² + 3² + 4² + 5² + 6² = 91
      assert result.result == 91
    end

    @tag :skip  # Skip until we have more sophisticated agent selection
    test "distributes work across available mappers" do
      # This test would verify that work is distributed
      # across multiple mapper agents effectively
    end
  end

  describe "MapReduce error handling" do
    test "handles map action failures gracefully" do
      defmodule FailingMapAction do
        use Jido.Action,
          name: "failing_map",
          description: "Action that fails"

        def run(_params, _context) do
          {:error, :map_failed}
        end
      end

      inputs = %{
        data: [1, 2, 3],
        map_action: FailingMapAction,
        reduce_action: SumAction,
        chunk_size: 2
      }
      
      assert {:error, _errors} = Reactor.run(MapReduce, inputs, %{})
    end

    test "handles reduce action failures gracefully" do
      defmodule FailingReduceAction do
        use Jido.Action,
          name: "failing_reduce",
          description: "Action that fails during reduction"

        def run(_params, _context) do
          {:error, :reduce_failed}
        end
      end

      inputs = %{
        data: [1, 2, 3],
        map_action: SquareAction,
        reduce_action: FailingReduceAction,
        chunk_size: 2
      }
      
      assert {:error, _errors} = Reactor.run(MapReduce, inputs, %{})
    end

    test "handles agent selection failures" do
      # Stop all agents
      Registry.list_agents()
      |> Enum.each(fn agent ->
        Supervisor.stop_agent(agent.id)
      end)
      
      # Give time for cleanup
      Process.sleep(50)

      inputs = %{
        data: [1, 2, 3],
        map_action: SquareAction,
        reduce_action: SumAction,
        chunk_size: 2
      }
      
      assert {:error, _errors} = Reactor.run(MapReduce, inputs, %{})
    end
  end

  describe "MapReduce workflow structure" do
    test "has correct reactor structure" do
      assert function_exported?(MapReduce, :__reactor__, 0)
      
      reactor = MapReduce.__reactor__()
      assert is_map(reactor)
      
      # Should be able to create info struct
      assert {:ok, _info} = Reactor.Info.to_struct(reactor)
    end

    test "defines required inputs" do
      expected_inputs = [:data, :map_action, :reduce_action]
      actual_inputs = MapReduce.required_inputs()
      
      assert Enum.all?(expected_inputs, &(&1 in actual_inputs))
    end

    test "defines available options" do
      options = MapReduce.available_options()
      assert is_list(options)
      assert Keyword.has_key?(options, :chunk_size)
    end
  end
end