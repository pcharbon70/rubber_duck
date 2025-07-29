defmodule RubberDuck.Jido.Workflows.Library.PipelineTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Jido.Workflows.Library.Pipeline
  alias RubberDuck.Jido.Agents.{Supervisor, Registry}

  # Test actions for pipeline stages
  defmodule ValidateAction do
    use Jido.Action,
      name: "validate",
      description: "Validates input data",
      schema: [
        value: [type: :integer, required: true]
      ]

    def run(%{value: value}, _context) when is_integer(value) and value > 0 do
      {:ok, %{validated: true, value: value}}
    end

    def run(_params, _context) do
      {:error, :invalid_input}
    end
  end

  defmodule TransformAction do
    use Jido.Action,
      name: "transform",
      description: "Transforms validated data",
      schema: []

    def run(%{validated: true, value: value}, _context) do
      {:ok, %{transformed: true, value: value * 2}}
    end

    def run(_params, _context) do
      {:error, :not_validated}
    end
  end

  defmodule FormatAction do
    use Jido.Action,
      name: "format",
      description: "Formats transformed data",
      schema: []

    def run(%{transformed: true, value: value}, _context) do
      {:ok, %{formatted: true, result: "Value: #{value}"}}
    end

    def run(_params, _context) do
      {:error, :not_transformed}
    end
  end

  # Test agent for pipeline operations
  defmodule PipelineAgent do
    use RubberDuck.Jido.BaseAgent,
      name: "pipeline_agent",
      description: "Agent for pipeline operations"

    @impl true
    def init(initial_state) do
      state = Map.merge(initial_state, %{
        capabilities: [:validation, :transformation, :formatting],
        load: 0
      })
      {:ok, state}
    end
  end

  setup do
    # Start the supervisor
    {:ok, _} = start_supervised(Supervisor)
    
    # Start multiple agents for pipeline stages
    for i <- 1..3 do
      {:ok, _pid} = Supervisor.start_agent(
        PipelineAgent,
        %{},
        id: "pipeline_agent_#{i}_#{System.unique_integer()}",
        tags: [:pipeline_worker],
        capabilities: [:validation, :transformation, :formatting]
      )
    end
    
    # Give agents time to register
    Process.sleep(100)
    
    :ok
  end

  describe "Pipeline workflow" do
    test "processes data through sequential stages successfully" do
      inputs = %{
        data: %{value: 5},
        stages: [
          %{action: ValidateAction, capability: :validation},
          %{action: TransformAction, capability: :transformation},
          %{action: FormatAction, capability: :formatting}
        ]
      }
      
      assert {:ok, result} = Reactor.run(Pipeline, inputs, %{})
      
      assert result.formatted == true
      assert result.result == "Value: 10"  # 5 * 2 = 10
    end

    test "handles single stage pipeline" do
      inputs = %{
        data: %{value: 3},
        stages: [
          %{action: ValidateAction, capability: :validation}
        ]
      }
      
      assert {:ok, result} = Reactor.run(Pipeline, inputs, %{})
      
      assert result.validated == true
      assert result.value == 3
    end

    test "passes context between stages" do
      inputs = %{
        data: %{value: 7},
        stages: [
          %{action: ValidateAction, capability: :validation},
          %{action: TransformAction, capability: :transformation}
        ]
      }
      
      assert {:ok, result} = Reactor.run(Pipeline, inputs, %{})
      
      assert result.transformed == true
      assert result.value == 14  # 7 * 2 = 14
    end

    test "handles empty stages list" do
      inputs = %{
        data: %{value: 5},
        stages: []
      }
      
      assert {:ok, result} = Reactor.run(Pipeline, inputs, %{})
      assert result.value == 5  # Data should pass through unchanged
    end
  end

  describe "Pipeline error handling" do
    test "fails early when validation fails" do
      inputs = %{
        data: %{value: -1},  # Invalid value
        stages: [
          %{action: ValidateAction, capability: :validation},
          %{action: TransformAction, capability: :transformation},
          %{action: FormatAction, capability: :formatting}
        ]
      }
      
      assert {:error, _errors} = Reactor.run(Pipeline, inputs, %{})
    end

    test "fails when intermediate stage fails" do
      defmodule FailingAction do
        use Jido.Action,
          name: "failing",
          description: "Action that always fails"

        def run(_params, _context) do
          {:error, :stage_failed}
        end
      end

      inputs = %{
        data: %{value: 5},
        stages: [
          %{action: ValidateAction, capability: :validation},
          %{action: FailingAction, capability: :validation},  # This will fail
          %{action: FormatAction, capability: :formatting}
        ]
      }
      
      assert {:error, _errors} = Reactor.run(Pipeline, inputs, %{})
    end

    test "handles agent selection failures" do
      inputs = %{
        data: %{value: 5},
        stages: [
          %{action: ValidateAction, capability: :nonexistent_capability}
        ]
      }
      
      assert {:error, _errors} = Reactor.run(Pipeline, inputs, %{})
    end

    test "handles no available agents" do
      # Stop all agents
      Registry.list_agents()
      |> Enum.each(fn agent ->
        Supervisor.stop_agent(agent.id)
      end)
      
      # Give time for cleanup
      Process.sleep(50)

      inputs = %{
        data: %{value: 5},
        stages: [
          %{action: ValidateAction, capability: :validation}
        ]
      }
      
      assert {:error, _errors} = Reactor.run(Pipeline, inputs, %{})
    end
  end

  describe "Pipeline configuration options" do
    test "respects parallel execution option" do
      inputs = %{
        data: %{value: 5},
        stages: [
          %{action: ValidateAction, capability: :validation}
        ],
        parallel: false  # Force sequential execution
      }
      
      assert {:ok, result} = Reactor.run(Pipeline, inputs, %{})
      assert result.validated == true
    end

    test "handles timeout configuration" do
      defmodule SlowAction do
        use Jido.Action,
          name: "slow",
          description: "Slow action for timeout test"

        def run(params, _context) do
          Process.sleep(200)
          {:ok, params}
        end
      end

      inputs = %{
        data: %{value: 5},
        stages: [
          %{action: SlowAction, capability: :validation}
        ],
        timeout: 100  # Short timeout
      }
      
      # Should timeout
      assert {:error, _errors} = Reactor.run(Pipeline, inputs, %{})
    end
  end

  describe "Pipeline workflow structure" do
    test "has correct reactor structure" do
      assert function_exported?(Pipeline, :__reactor__, 0)
      
      reactor = Pipeline.__reactor__()
      assert is_map(reactor)
      
      # Should be able to create info struct
      assert {:ok, _info} = Reactor.Info.to_struct(reactor)
    end

    test "defines required inputs" do
      expected_inputs = [:data, :stages]
      actual_inputs = Pipeline.required_inputs()
      
      assert Enum.all?(expected_inputs, &(&1 in actual_inputs))
    end

    test "defines available options" do
      options = Pipeline.available_options()
      assert is_list(options)
      assert Keyword.has_key?(options, :parallel)
      assert Keyword.has_key?(options, :timeout)
    end
  end
end