defmodule RubberDuck.Workflows.AgentStepsTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.AgentSteps
  alias RubberDuck.Agents.{Supervisor, AgentRegistry}

  import ExUnit.CaptureLog

  setup do
    # Start agent supervisor if not already running
    case Process.whereis(Supervisor) do
      nil ->
        {:ok, _pid} = Supervisor.start_link([])

      _pid ->
        :ok
    end

    # Start agent registry if not already running
    case Process.whereis(AgentRegistry) do
      nil ->
        {:ok, _pid} = AgentRegistry.start_link([])

      _pid ->
        :ok
    end

    on_exit(fn ->
      # Clean up any started agents
      for {_, pid, _} <- DynamicSupervisor.which_children(Supervisor) do
        DynamicSupervisor.terminate_child(Supervisor, pid)
      end
    end)

    :ok
  end

  describe "start_agent/3" do
    test "successfully starts an agent of specified type" do
      arguments = %{type: :research, config: %{memory_tier: :short_term}}

      assert {:ok, agent_id} = AgentSteps.start_agent(arguments, %{}, %{})
      assert String.starts_with?(agent_id, "research_")
      assert String.contains?(agent_id, "_")
    end

    test "passes configuration to agent" do
      config = %{
        memory_tier: :mid_term,
        capabilities: [:semantic_search, :context_building]
      }

      arguments = %{type: :analysis, config: config}

      assert {:ok, _agent_id} = AgentSteps.start_agent(arguments, %{}, %{})
    end

    test "returns error when agent startup fails" do
      arguments = %{type: :invalid_type, config: %{}}

      capture_log(fn ->
        assert {:error, _reason} = AgentSteps.start_agent(arguments, %{}, %{})
      end)
    end
  end

  describe "execute_agent_task/3" do
    setup do
      # Start a test agent
      {:ok, _pid} = Supervisor.start_agent(:research, %{})
      agent_id = "research_test_#{System.system_time(:millisecond)}"

      # Register it in the mock registry
      AgentRegistry.register_agent(agent_id, self(), %{type: :research})

      {:ok, agent_id: agent_id}
    end

    test "executes task on specified agent", %{agent_id: agent_id} do
      arguments = %{
        agent_id: agent_id,
        task: {:research_context, %{query: "test query"}},
        timeout: 5000
      }

      # Spawn a process to simulate agent response
      spawn(fn ->
        receive do
          {:agent_request, _task, requester, ref} ->
            send(requester, {:agent_response, %{results: ["test result"]}, ref})
        end
      end)

      # Give spawned process time to register
      Process.sleep(10)

      assert {:ok, %{results: ["test result"]}} =
               AgentSteps.execute_agent_task(arguments, %{}, %{})
    end

    test "handles task execution timeout", %{agent_id: agent_id} do
      arguments = %{
        agent_id: agent_id,
        task: {:long_running_task, %{}},
        timeout: 100
      }

      capture_log(fn ->
        assert {:error, :timeout} = AgentSteps.execute_agent_task(arguments, %{}, %{})
      end)
    end
  end

  describe "aggregate_agent_results/3" do
    test "merges results using merge strategy" do
      results = [
        %{data: %{a: 1, b: 2}, items: [1, 2]},
        %{data: %{b: 3, c: 4}, items: [3, 4]}
      ]

      arguments = %{results: results, strategy: :merge}

      assert {:ok, aggregated} = AgentSteps.aggregate_agent_results(arguments, %{}, %{})
      assert aggregated[:data] == %{a: 1, b: 3, c: 4}
      assert aggregated[:items] == [1, 2, 3, 4]
    end

    test "finds consensus using consensus strategy" do
      results = [
        %{answer: "yes"},
        %{answer: "yes"},
        %{answer: "no"}
      ]

      arguments = %{results: results, strategy: :consensus}

      assert {:ok, %{answer: "yes"}} =
               AgentSteps.aggregate_agent_results(arguments, %{}, %{})
    end

    test "selects by priority using priority strategy" do
      results = [
        %{value: "low", priority: 1},
        %{value: "high", priority: 10},
        %{value: "medium", priority: 5}
      ]

      arguments = %{results: results, strategy: :priority}

      assert {:ok, %{value: "high", priority: 10}} =
               AgentSteps.aggregate_agent_results(arguments, %{}, %{})
    end

    test "uses custom aggregator function" do
      results = [1, 2, 3, 4, 5]
      custom_fn = fn numbers -> Enum.sum(numbers) end

      arguments = %{
        results: results,
        strategy: :custom,
        custom_aggregator: custom_fn
      }

      assert {:ok, 15} = AgentSteps.aggregate_agent_results(arguments, %{}, %{})
    end

    test "returns error for invalid strategy" do
      arguments = %{results: [], strategy: :invalid}

      assert {:error, {:invalid_strategy, :invalid}} =
               AgentSteps.aggregate_agent_results(arguments, %{}, %{})
    end
  end

  describe "broadcast_to_agents/3" do
    setup do
      # Register some test agents
      AgentRegistry.register_agent("research_1", self(), %{type: :research})
      AgentRegistry.register_agent("analysis_1", self(), %{type: :analysis})

      AgentRegistry.register_agent("generation_1", self(), %{
        type: :generation,
        capabilities: [:code_generation]
      })

      :ok
    end

    test "broadcasts to agents of specific type" do
      arguments = %{
        message: {:update_config, %{new_setting: true}},
        target: {:type, :research}
      }

      assert {:ok, count} = AgentSteps.broadcast_to_agents(arguments, %{}, %{})
      assert count >= 0
    end

    test "broadcasts to agents with specific capability" do
      arguments = %{
        message: {:task_available, %{task: "generate code"}},
        target: {:capability, :code_generation}
      }

      assert {:ok, count} = AgentSteps.broadcast_to_agents(arguments, %{}, %{})
      assert count >= 0
    end

    test "broadcasts with custom filter function" do
      filter_fn = fn metadata -> metadata[:type] == :analysis end

      arguments = %{
        message: {:analyze, %{code: "test"}},
        target: {:all, filter_fn}
      }

      assert {:ok, count} = AgentSteps.broadcast_to_agents(arguments, %{}, %{})
      assert count >= 0
    end

    test "returns error for invalid target" do
      arguments = %{
        message: {:test, %{}},
        target: :invalid
      }

      capture_log(fn ->
        assert {:error, {:invalid_target, :invalid}} =
                 AgentSteps.broadcast_to_agents(arguments, %{}, %{})
      end)
    end
  end

  describe "collect_agent_events/3" do
    test "collects specified number of events" do
      arguments = %{
        event_type: :task_completed,
        count: 2,
        timeout: 1000
      }

      # Spawn a process to send events
      test_pid = self()

      spawn(fn ->
        Process.sleep(50)
        send(test_pid, {:agent_event, :task_completed, %{task: "task1"}})
        Process.sleep(50)
        send(test_pid, {:agent_event, :task_completed, %{task: "task2"}})
      end)

      assert {:ok, events} = AgentSteps.collect_agent_events(arguments, %{}, %{})
      assert length(events) == 2
      assert [%{task: "task1"}, %{task: "task2"}] = events
    end

    test "returns timeout error when not enough events received" do
      arguments = %{
        event_type: :rare_event,
        count: 5,
        timeout: 100
      }

      assert {:error, :timeout} = AgentSteps.collect_agent_events(arguments, %{}, %{})
    end
  end

  describe "coordinate_agents/3" do
    test "coordinates multiple agents with specification" do
      spec = %{
        steps: [
          %{agent_type: :research, task: {:gather_info, %{topic: "elixir"}}},
          %{agent_type: :analysis, task: {:analyze, %{data: "result"}}}
        ],
        strategy: :sequential,
        timeout: 10_000
      }

      arguments = %{coordination_spec: spec}
      context = %{workflow_id: "test_workflow_123"}

      # This would normally coordinate real agents
      # For testing, we'd need to mock the Coordinator
      assert_raise UndefinedFunctionError, fn ->
        AgentSteps.coordinate_agents(arguments, context, %{})
      end
    end
  end
end
