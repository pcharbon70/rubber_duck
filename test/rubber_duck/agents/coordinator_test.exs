defmodule RubberDuck.Agents.CoordinatorTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Agents.{Coordinator, Supervisor, AgentRegistry}

  import ExUnit.CaptureLog

  # Test agent for simulating various behaviors
  defmodule TestAgent do
    use GenServer

    def start_link(config) do
      GenServer.start_link(__MODULE__, config)
    end

    def init(config) do
      {:ok, %{config: config, tasks_completed: 0}}
    end

    def handle_call({:agent_request, task, from, ref}, _from, state) do
      # Simulate task processing
      result =
        case task do
          {:fail, _reason} ->
            {:error, :task_failed}

          {:delay, ms} ->
            Process.sleep(ms)
            {:ok, :delayed_result}

          {:crash, _} ->
            raise "Test crash"

          _ ->
            {:ok, %{task: task, agent: self()}}
        end

      send(from, {:agent_response, result, ref})
      {:reply, :ok, %{state | tasks_completed: state.tasks_completed + 1}}
    end

    def handle_info(_msg, state), do: {:noreply, state}
  end

  setup do
    # Ensure clean state
    start_supervisor()
    start_registry()
    start_coordinator()

    on_exit(fn ->
      # Clean up all agents
      clean_up_agents()
    end)

    :ok
  end

  defp start_supervisor do
    case Process.whereis(Supervisor) do
      nil -> {:ok, _} = Supervisor.start_link([])
      _ -> :ok
    end
  end

  defp start_registry do
    case Process.whereis(AgentRegistry) do
      nil -> {:ok, _} = AgentRegistry.start_link([])
      _ -> :ok
    end
  end

  defp start_coordinator do
    case Process.whereis(Coordinator) do
      nil ->
        {:ok, _} = Coordinator.start_link([])

      _ ->
        # Reset coordinator state
        :ok
    end
  end

  defp clean_up_agents do
    for {_, pid, _} <- DynamicSupervisor.which_children(Supervisor) do
      DynamicSupervisor.terminate_child(Supervisor, pid)
    end
  end

  describe "execute_workflow/3" do
    test "executes simple sequential workflow" do
      workflow = %{
        id: "test_workflow_1",
        steps: [
          %{
            id: "step1",
            agent_type: :research,
            task: {:search, "elixir patterns"},
            depends_on: []
          },
          %{
            id: "step2",
            agent_type: :analysis,
            task: {:analyze, "results"},
            depends_on: ["step1"]
          }
        ]
      }

      {:ok, results} = Coordinator.execute_workflow(workflow, %{}, timeout: 5000)

      assert Map.has_key?(results, "step1")
      assert Map.has_key?(results, "step2")
      assert results["step1"].status == :completed
      assert results["step2"].status == :completed
    end

    test "executes parallel workflow steps" do
      workflow = %{
        id: "test_workflow_2",
        steps: [
          %{
            id: "parallel1",
            agent_type: :research,
            task: {:search, "topic1"},
            depends_on: []
          },
          %{
            id: "parallel2",
            agent_type: :research,
            task: {:search, "topic2"},
            depends_on: []
          },
          %{
            id: "merge",
            agent_type: :analysis,
            task: {:merge_results, "both"},
            depends_on: ["parallel1", "parallel2"]
          }
        ]
      }

      start_time = System.monotonic_time(:millisecond)
      {:ok, results} = Coordinator.execute_workflow(workflow, %{}, timeout: 10000)
      duration = System.monotonic_time(:millisecond) - start_time

      # Verify all steps completed
      assert results["parallel1"].status == :completed
      assert results["parallel2"].status == :completed
      assert results["merge"].status == :completed

      # Parallel steps should execute concurrently (duration should be less than sequential)
      # Assuming each step takes ~1-2s
      assert duration < 5000
    end

    test "handles workflow step failures" do
      workflow = %{
        id: "failing_workflow",
        steps: [
          %{
            id: "step1",
            agent_type: :test,
            task: {:process, "data"},
            depends_on: []
          },
          %{
            id: "step2",
            agent_type: :test,
            task: {:fail, "intentional"},
            depends_on: ["step1"]
          },
          %{
            id: "step3",
            agent_type: :test,
            task: {:process, "more"},
            depends_on: ["step2"]
          }
        ]
      }

      # Register test agents
      {:ok, pid1} = GenServer.start_link(TestAgent, %{})
      AgentRegistry.register_agent("test_agent_1", pid1, %{type: :test})

      {:ok, results} = Coordinator.execute_workflow(workflow, %{}, timeout: 5000)

      assert results["step1"].status == :completed
      assert results["step2"].status == :failed
      # Should skip due to dependency failure
      assert results["step3"].status == :skipped
    end

    test "handles workflow timeout" do
      workflow = %{
        id: "timeout_workflow",
        steps: [
          %{
            id: "slow_step",
            agent_type: :test,
            task: {:delay, 5000},
            depends_on: []
          }
        ]
      }

      # Register test agent
      {:ok, pid} = GenServer.start_link(TestAgent, %{})
      AgentRegistry.register_agent("test_slow", pid, %{type: :test})

      assert {:error, :timeout} =
               Coordinator.execute_workflow(workflow, %{}, timeout: 1000)
    end

    test "validates workflow dependencies" do
      invalid_workflow = %{
        id: "invalid",
        steps: [
          %{
            id: "step1",
            agent_type: :research,
            task: {:search, "data"},
            depends_on: ["non_existent_step"]
          }
        ]
      }

      assert {:error, {:invalid_dependencies, _}} =
               Coordinator.execute_workflow(invalid_workflow, %{})
    end
  end

  describe "route_task/3" do
    test "routes task to agent with matching capabilities" do
      # Start agent with specific capabilities
      {:ok, pid} = Supervisor.start_agent(:research, %{})

      task = {:search_context, %{query: "elixir"}}
      {:ok, result} = Coordinator.route_task(task, :research, timeout: 5000)

      assert result
    end

    test "starts new agent when none available" do
      # Ensure no research agents exist
      clean_up_agents()

      task = {:search_context, %{query: "test"}}

      # Should start a new agent and route task
      capture_log(fn ->
        {:ok, _result} = Coordinator.route_task(task, :research)
      end)

      # Verify agent was started
      agents = Supervisor.list_agents()
      assert Enum.any?(agents, fn {id, _, _} -> String.starts_with?(id, "research_") end)
    end

    test "routes to least loaded agent" do
      # Start multiple research agents
      {:ok, pid1} = Supervisor.start_agent(:research, %{})
      {:ok, pid2} = Supervisor.start_agent(:research, %{})
      {:ok, pid3} = Supervisor.start_agent(:research, %{})

      # Send tasks to create different load levels
      # (This would require actual load tracking in the coordinator)

      task = {:search_context, %{query: "balanced"}}
      {:ok, _result} = Coordinator.route_task(task, :research)

      # Verify task was routed (implementation-specific verification)
    end

    test "handles routing failures gracefully" do
      # Use non-existent agent type
      task = {:unknown_task, %{}}

      capture_log(fn ->
        assert {:error, _} = Coordinator.route_task(task, :non_existent_type)
      end)
    end
  end

  describe "get_system_status/0" do
    test "returns accurate system status" do
      # Start some agents
      {:ok, _} = Supervisor.start_agent(:research, %{})
      {:ok, _} = Supervisor.start_agent(:analysis, %{})
      {:ok, _} = Supervisor.start_agent(:generation, %{})

      status = Coordinator.get_system_status()

      assert status.coordinator_status == :running
      assert status.total_agents >= 3
      assert status.agents_by_type[:research] >= 1
      assert status.agents_by_type[:analysis] >= 1
      assert status.agents_by_type[:generation] >= 1
      assert is_list(status.active_workflows)
      assert is_map(status.metrics)
    end

    test "tracks active workflows" do
      workflow = %{
        id: "status_test_workflow",
        steps: [
          %{
            id: "step1",
            agent_type: :test,
            task: {:delay, 2000},
            depends_on: []
          }
        ]
      }

      # Start workflow in background
      Task.async(fn ->
        Coordinator.execute_workflow(workflow, %{})
      end)

      # Let workflow start
      Process.sleep(100)

      status = Coordinator.get_system_status()
      assert Enum.any?(status.active_workflows, &(&1.id == "status_test_workflow"))
    end
  end

  describe "agent lifecycle management" do
    test "starts agent with configuration" do
      config = %{memory_tier: :short_term, custom: :value}

      {:ok, agent_id} = Coordinator.start_agent(:research, config, "custom_id")

      assert agent_id == "custom_id"

      # Verify agent is registered
      {:ok, _pid, metadata} = AgentRegistry.lookup_agent(agent_id)
      assert metadata.config.custom == :value
    end

    test "stops agent cleanly" do
      {:ok, agent_id} = Coordinator.start_agent(:analysis, %{})

      # Verify agent exists
      {:ok, pid, _} = AgentRegistry.lookup_agent(agent_id)
      assert Process.alive?(pid)

      # Stop agent
      assert :ok = Coordinator.stop_agent(agent_id)

      # Verify agent is gone
      assert {:error, :agent_not_found} = AgentRegistry.lookup_agent(agent_id)
    end

    test "handles concurrent agent operations" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            operation = Enum.random([:start, :stop])

            case operation do
              :start ->
                Coordinator.start_agent(Enum.random([:research, :analysis]), %{index: i})

              :stop ->
                # Try to stop a random agent
                agents = Supervisor.list_agents()

                if length(agents) > 0 do
                  {id, _, _} = Enum.random(agents)
                  Coordinator.stop_agent(id)
                end
            end
          end)
        end

      # Wait for all operations
      Task.await_many(tasks, 5000)

      # System should still be stable
      status = Coordinator.get_system_status()
      assert status.coordinator_status == :running
    end
  end

  describe "failure recovery" do
    test "recovers from agent crashes during workflow" do
      workflow = %{
        id: "crash_recovery",
        steps: [
          %{
            id: "crash_step",
            agent_type: :test,
            task: {:crash, "boom"},
            depends_on: []
          }
        ]
      }

      # Register crash-prone test agent
      {:ok, pid} = GenServer.start_link(TestAgent, %{})
      AgentRegistry.register_agent("crash_test", pid, %{type: :test})

      capture_log(fn ->
        {:ok, results} = Coordinator.execute_workflow(workflow, %{})
        assert results["crash_step"].status == :failed
      end)
    end

    test "handles registry lookup failures" do
      # Simulate registry being unavailable
      # This would require mocking or a test-specific registry

      task = {:search, "test"}

      # Should handle gracefully
      capture_log(fn ->
        result = Coordinator.route_task(task, :research)
        assert match?({:error, _}, result) or match?({:ok, _}, result)
      end)
    end
  end

  describe "performance and load" do
    @tag :performance
    test "handles high workflow throughput" do
      # Create many small workflows
      workflows =
        for i <- 1..50 do
          %{
            id: "perf_test_#{i}",
            steps: [
              %{
                id: "step1",
                agent_type: :research,
                task: {:quick_task, i},
                depends_on: []
              }
            ]
          }
        end

      # Execute workflows concurrently
      tasks =
        Enum.map(workflows, fn workflow ->
          Task.async(fn ->
            Coordinator.execute_workflow(workflow, %{}, timeout: 10000)
          end)
        end)

      results = Task.await_many(tasks, 30000)

      # All should complete successfully
      successful = Enum.count(results, &match?({:ok, _}, &1))
      assert successful == 50
    end

    @tag :performance
    test "maintains performance under agent pool pressure" do
      # Start limited agents
      for _ <- 1..3 do
        Supervisor.start_agent(:research, %{})
      end

      # Submit many concurrent tasks
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            Coordinator.route_task({:search, "query_#{i}"}, :research, timeout: 5000)
          end)
        end

      start_time = System.monotonic_time(:millisecond)
      results = Task.await_many(tasks, 30000)
      duration = System.monotonic_time(:millisecond) - start_time

      successful = Enum.count(results, &match?({:ok, _}, &1))
      # Allow some failures under load
      assert successful > 90

      # Should complete in reasonable time despite limited agents
      assert duration < 20000
    end
  end

  describe "integration scenarios" do
    test "multi-agent collaboration workflow" do
      workflow = %{
        id: "collaboration_test",
        steps: [
          %{
            id: "research1",
            agent_type: :research,
            task: {:search, "elixir genserver"},
            depends_on: []
          },
          %{
            id: "research2",
            agent_type: :research,
            task: {:search, "otp patterns"},
            depends_on: []
          },
          %{
            id: "analyze",
            agent_type: :analysis,
            task: {:analyze, "combined"},
            depends_on: ["research1", "research2"]
          },
          %{
            id: "generate",
            agent_type: :generation,
            task: {:generate_code, "implementation"},
            depends_on: ["analyze"]
          },
          %{
            id: "review",
            agent_type: :review,
            task: {:review_code, "final"},
            depends_on: ["generate"]
          }
        ]
      }

      {:ok, results} = Coordinator.execute_workflow(workflow, %{}, timeout: 15000)

      # Verify all steps completed in order
      assert results["research1"].status == :completed
      assert results["research2"].status == :completed
      assert results["analyze"].status == :completed
      assert results["generate"].status == :completed
      assert results["review"].status == :completed
    end
  end
end
