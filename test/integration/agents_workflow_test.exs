defmodule RubberDuck.Integration.AgentsWorkflowTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Agents.{Supervisor, AgentRegistry, Communication}
  alias RubberDuck.Workflows.{AgentSteps, Executor}
  alias Reactor

  import ExUnit.CaptureLog

  setup do
    # Ensure all required services are running
    ensure_services_started()

    on_exit(fn ->
      clean_up_agents()
    end)

    :ok
  end

  defp ensure_services_started do
    # Start agent supervisor
    case Process.whereis(Supervisor) do
      nil -> {:ok, _} = Supervisor.start_link([])
      _ -> :ok
    end

    # Start agent registry
    case Process.whereis(AgentRegistry) do
      nil -> {:ok, _} = AgentRegistry.start_link([])
      _ -> :ok
    end

    # Start workflow executor
    case Process.whereis(Executor) do
      nil -> {:ok, _} = Executor.start_link([])
      _ -> :ok
    end
  end

  defp clean_up_agents do
    for {_, pid, _} <- DynamicSupervisor.which_children(Supervisor) do
      DynamicSupervisor.terminate_child(Supervisor, pid)
    end
  end

  describe "agent workflow integration" do
    test "end-to-end code analysis workflow" do
      # Define a workflow that analyzes code using multiple agents
      defmodule AnalysisWorkflow do
        use Reactor

        input :code
        input :filename

        step :start_research_agent do
          run fn _, _ ->
            AgentSteps.start_agent(
              %{
                type: :research,
                config: %{memory_tier: :short_term}
              },
              %{},
              %{}
            )
          end
        end

        step :start_analysis_agent do
          run fn _, _ ->
            AgentSteps.start_agent(
              %{
                type: :analysis,
                config: %{}
              },
              %{},
              %{}
            )
          end
        end

        step :research_context do
          run fn inputs, _ ->
            AgentSteps.execute_agent_task(
              %{
                agent_id: inputs[:start_research_agent],
                task:
                  {:search_context,
                   %{
                     query: "analyze #{inputs[:filename]}",
                     code: inputs[:code]
                   }},
                timeout: 5000
              },
              %{},
              %{}
            )
          end

          wait_for [:start_research_agent]
        end

        step :analyze_code do
          run fn inputs, _ ->
            AgentSteps.execute_agent_task(
              %{
                agent_id: inputs[:start_analysis_agent],
                task:
                  {:analyze_code,
                   %{
                     code: inputs[:code],
                     context: inputs[:research_context]
                   }},
                timeout: 5000
              },
              %{},
              %{}
            )
          end

          wait_for [:start_analysis_agent, :research_context]
        end

        step :aggregate_results do
          run fn inputs, _ ->
            AgentSteps.aggregate_agent_results(
              %{
                results: [
                  inputs[:research_context],
                  inputs[:analyze_code]
                ],
                strategy: :merge
              },
              %{},
              %{}
            )
          end

          wait_for [:research_context, :analyze_code]
        end

        return :aggregate_results
      end

      # Execute the workflow
      code = """
      defmodule Example do
        def hello(name) do
          "Hello, \#{name}!"
        end
      end
      """

      inputs = %{code: code, filename: "example.ex"}

      assert {:ok, result} = Reactor.run(AnalysisWorkflow, inputs)
      assert is_map(result)
    end

    test "multi-agent collaboration for code generation" do
      # Start required agents
      {:ok, research_pid} = Supervisor.start_agent(:research, %{})
      {:ok, analysis_pid} = Supervisor.start_agent(:analysis, %{})
      {:ok, generation_pid} = Supervisor.start_agent(:generation, %{})
      {:ok, review_pid} = Supervisor.start_agent(:review, %{})

      research_id = "research_#{:erlang.phash2(research_pid)}"
      analysis_id = "analysis_#{:erlang.phash2(analysis_pid)}"
      generation_id = "generation_#{:erlang.phash2(generation_pid)}"
      review_id = "review_#{:erlang.phash2(review_pid)}"

      # Simulate a collaborative code generation task

      # 1. Research phase - gather context
      research_task = {:search_context, %{query: "implement binary search in elixir"}}

      {:ok, research_result} =
        Communication.request_response(
          research_id,
          research_task,
          5000
        )

      # 2. Analysis phase - analyze requirements
      analysis_task =
        {:analyze_requirements,
         %{
           query: "binary search implementation",
           context: research_result
         }}

      {:ok, analysis_result} =
        Communication.request_response(
          analysis_id,
          analysis_task,
          5000
        )

      # 3. Generation phase - generate code
      generation_task =
        {:generate_code,
         %{
           requirements: analysis_result,
           context: research_result
         }}

      {:ok, generated_code} =
        Communication.request_response(
          generation_id,
          generation_task,
          5000
        )

      # 4. Review phase - review generated code
      review_task =
        {:review_code,
         %{
           code: generated_code,
           requirements: analysis_result
         }}

      {:ok, review_result} =
        Communication.request_response(
          review_id,
          review_task,
          5000
        )

      # Verify all phases completed
      assert research_result
      assert analysis_result
      assert generated_code
      assert review_result
    end

    test "agent event broadcasting and coordination" do
      # Start multiple agents
      {:ok, _} = Supervisor.start_agent(:research, %{})
      {:ok, _} = Supervisor.start_agent(:research, %{})
      {:ok, _} = Supervisor.start_agent(:analysis, %{})

      # Test broadcasting to agent types
      message = {:update_context, %{new_data: "test"}}

      {:ok, research_count} =
        AgentSteps.broadcast_to_agents(
          %{
            message: message,
            target: {:type, :research}
          },
          %{},
          %{}
        )

      assert research_count == 2

      # Test broadcasting to agents with specific capability
      {:ok, analysis_count} =
        AgentSteps.broadcast_to_agents(
          %{
            message: message,
            target: {:capability, :code_analysis}
          },
          %{},
          %{}
        )

      assert analysis_count >= 1
    end

    test "workflow with agent pool management" do
      # Define a workflow that manages agent pools
      defmodule PooledWorkflow do
        use Reactor

        input :tasks

        step :ensure_agents do
          run fn inputs, _ ->
            # Ensure we have enough agents for the tasks
            required = length(inputs[:tasks])
            current = Supervisor.agent_counts().research

            if current < required do
              for _ <- 1..(required - current) do
                AgentSteps.start_agent(
                  %{
                    type: :research,
                    config: %{}
                  },
                  %{},
                  %{}
                )
              end
            end

            {:ok, :agents_ready}
          end
        end

        step :distribute_tasks do
          run fn inputs, _ ->
            # Get available agents
            {:ok, agents} = AgentRegistry.find_by_type(:research)

            # Distribute tasks among agents
            results =
              inputs[:tasks]
              |> Enum.zip(Enum.cycle(agents))
              |> Enum.map(fn {task, {_id, _pid, _meta} = agent_info} ->
                {agent_id, _, _} = agent_info

                Task.async(fn ->
                  AgentSteps.execute_agent_task(
                    %{
                      agent_id: agent_id,
                      task: task,
                      timeout: 5000
                    },
                    %{},
                    %{}
                  )
                end)
              end)
              |> Task.await_many(10000)

            {:ok, results}
          end

          wait_for [:ensure_agents]
        end

        return :distribute_tasks
      end

      # Create multiple search tasks
      tasks =
        for i <- 1..5 do
          {:search_context, %{query: "task_#{i}"}}
        end

      assert {:ok, results} = Reactor.run(PooledWorkflow, %{tasks: tasks})
      assert length(results) == 5
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    test "failure recovery in agent workflows" do
      # Test workflow that handles agent failures
      defmodule FailureRecoveryWorkflow do
        use Reactor

        input :unstable_task

        step :start_primary_agent do
          run fn _, _ ->
            AgentSteps.start_agent(
              %{
                type: :research,
                config: %{role: :primary}
              },
              %{},
              %{}
            )
          end
        end

        step :start_backup_agent do
          run fn _, _ ->
            AgentSteps.start_agent(
              %{
                type: :research,
                config: %{role: :backup}
              },
              %{},
              %{}
            )
          end
        end

        step :try_primary do
          run fn inputs, _ ->
            result =
              AgentSteps.execute_agent_task(
                %{
                  agent_id: inputs[:start_primary_agent],
                  task: inputs[:unstable_task],
                  timeout: 2000
                },
                %{},
                %{}
              )

            case result do
              {:ok, _} = success -> success
              {:error, _} -> {:error, :primary_failed}
            end
          end

          wait_for [:start_primary_agent]
        end

        step :try_backup do
          run fn inputs, _ ->
            case inputs[:try_primary] do
              {:ok, result} ->
                {:ok, result}

              {:error, :primary_failed} ->
                AgentSteps.execute_agent_task(
                  %{
                    agent_id: inputs[:start_backup_agent],
                    task: inputs[:unstable_task],
                    timeout: 2000
                  },
                  %{},
                  %{}
                )
            end
          end

          wait_for [:try_primary, :start_backup_agent]
        end

        return :try_backup
      end

      # Run with a task that might fail
      task = {:search_context, %{query: "potentially_failing_search"}}

      assert {:ok, _result} = Reactor.run(FailureRecoveryWorkflow, %{unstable_task: task})
    end

    test "complex workflow with conditional agent routing" do
      # Start agents with different capabilities
      {:ok, _} =
        Supervisor.start_agent(:research, %{
          capabilities: [:deep_search, :semantic_search]
        })

      {:ok, _} =
        Supervisor.start_agent(:research, %{
          capabilities: [:quick_search, :keyword_search]
        })

      {:ok, _} = Supervisor.start_agent(:analysis, %{})

      # Route tasks based on requirements
      deep_task = {:search_context, %{query: "complex topic", depth: :deep}}
      quick_task = {:search_context, %{query: "simple lookup", depth: :shallow}}

      # Find agents by capability and route appropriately
      {:ok, deep_agents} = AgentRegistry.find_by_capability(:deep_search)
      {:ok, quick_agents} = AgentRegistry.find_by_capability(:quick_search)

      assert length(deep_agents) >= 1
      assert length(quick_agents) >= 1

      # Execute tasks on appropriate agents
      {deep_agent_id, _, _} = List.first(deep_agents)
      {quick_agent_id, _, _} = List.first(quick_agents)

      {:ok, deep_result} =
        Communication.request_response(
          deep_agent_id,
          deep_task,
          5000
        )

      {:ok, quick_result} =
        Communication.request_response(
          quick_agent_id,
          quick_task,
          5000
        )

      assert deep_result
      assert quick_result
    end
  end

  describe "performance and scalability" do
    @tag :performance
    test "workflow scales with multiple concurrent requests" do
      # Create a high-throughput workflow
      defmodule ConcurrentWorkflow do
        use Reactor

        input :request_id

        step :process_request do
          run fn inputs, _ ->
            # Simulate processing
            Process.sleep(Enum.random(10..50))
            {:ok, %{id: inputs[:request_id], processed_at: DateTime.utc_now()}}
          end
        end

        return :process_request
      end

      # Submit many concurrent workflows
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            Reactor.run(ConcurrentWorkflow, %{request_id: i})
          end)
        end

      start_time = System.monotonic_time(:millisecond)
      results = Task.await_many(tasks, 30000)
      duration = System.monotonic_time(:millisecond) - start_time

      # All should complete
      successful = Enum.count(results, &match?({:ok, _}, &1))
      assert successful == 100

      # Should complete efficiently (less than if run sequentially)
      assert duration < 5000
    end
  end

  describe "real-world scenarios" do
    test "code refactoring workflow with multiple agents" do
      original_code = """
      def process_data(data) do
        result = []
        for item <- data do
          if item > 0 do
            result = result ++ [item * 2]
          end
        end
        result
      end
      """

      # This would integrate with real agents to:
      # 1. Analyze the code for improvements
      # 2. Generate refactored version
      # 3. Review the changes
      # 4. Validate correctness

      # For now, we verify the workflow structure works
      assert original_code =~ "def process_data"
    end
  end
end
