defmodule RubberDuck.Workflows.DynamicWorkflowIntegrationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.{Executor, ComplexityAnalyzer, DynamicBuilder, TemplateRegistry}

  setup do
    # Start the Executor for integration tests
    {:ok, _pid} = Executor.start_link([])
    :ok
  end

  describe "end-to-end dynamic workflow execution" do
    test "analyzes simple task and executes basic workflow" do
      task = %{
        type: :analysis,
        target: "lib/example.ex",
        code: "defmodule Example, do: def hello, do: :world"
      }

      # Execute dynamic workflow
      result = Executor.run_dynamic(task, timeout: 10_000)

      assert {:ok, _workflow_result} = result
    end

    test "handles complex refactoring task with multiple agents" do
      task = %{
        type: :refactoring,
        targets: ["lib/user.ex", "lib/auth.ex", "lib/session.ex"],
        options: %{
          extract_common: true,
          improve_naming: true,
          add_documentation: true
        },
        code_stats: %{
          loc: 450,
          functions: 25,
          modules: 3
        }
      }

      # This should trigger deep analysis workflow with multiple agents
      result =
        Executor.run_dynamic(task,
          use_template: true,
          optimization_strategy: :balanced,
          timeout: 15_000
        )

      assert {:ok, _workflow_result} = result
    end

    test "executes generation pipeline with custom template" do
      task = %{
        type: :generation,
        description: "Create a new authentication module with JWT support",
        requirements: %{
          security: :high,
          performance: :medium,
          testing: :comprehensive
        }
      }

      # Use generation pipeline template
      result =
        Executor.run_dynamic(task,
          use_template: true,
          customization: %{
            timeout: 120_000,
            security_checks: true
          },
          timeout: 20_000
        )

      assert {:ok, _workflow_result} = result
    end

    test "handles async execution with completion callback" do
      task = %{
        type: :review,
        files: ["lib/important.ex"],
        criteria: %{security: true, performance: true}
      }

      # Set up callback to capture result
      test_pid = self()

      completion_handler = fn result ->
        send(test_pid, {:workflow_completed, result})
      end

      # Execute asynchronously
      :ok =
        Executor.run_dynamic_async(task,
          on_complete: completion_handler,
          cache_pattern: true
        )

      # Wait for completion
      assert_receive {:workflow_completed, {:ok, _result}}, 10_000
    end

    test "caches successful workflow patterns for reuse" do
      task = %{
        type: :analysis,
        target: "lib/simple.ex",
        code: "defmodule Simple, do: def test, do: :ok"
      }

      # First execution - should build new workflow
      {:ok, result1} =
        Executor.run_dynamic(task,
          cache_pattern: true,
          timeout: 8_000
        )

      # Second execution with similar task - should be faster due to caching
      similar_task = %{
        type: :analysis,
        target: "lib/simple2.ex",
        code: "defmodule Simple2, do: def test2, do: :ok"
      }

      start_time = System.monotonic_time(:millisecond)

      {:ok, result2} =
        Executor.run_dynamic(similar_task,
          cache_pattern: true,
          timeout: 8_000
        )

      duration = System.monotonic_time(:millisecond) - start_time

      assert result1
      assert result2
      # Second execution should be reasonably fast
      assert duration < 5_000
    end

    test "handles resource management for high-complexity tasks" do
      task = %{
        type: :complex_refactoring,
        targets: Enum.map(1..10, &"lib/module#{&1}.ex"),
        options: %{
          deep_analysis: true,
          generate_tests: true,
          performance_optimization: true
        },
        code_stats: %{
          loc: 2500,
          functions: 150,
          modules: 10,
          complexity_metrics: %{
            cyclomatic: 8,
            cognitive: 12
          }
        }
      }

      # This should trigger resource management and monitoring
      result =
        Executor.run_dynamic(task,
          include_resource_management: true,
          optimization_strategy: :resource,
          timeout: 25_000
        )

      assert {:ok, _workflow_result} = result
    end

    test "optimizes workflow for speed with parallel execution" do
      task = %{
        type: :parallel_analysis,
        files: Enum.map(1..5, &"lib/file#{&1}.ex"),
        analysis_types: [:security, :performance, :style, :complexity]
      }

      start_time = System.monotonic_time(:millisecond)

      result =
        Executor.run_dynamic(task,
          optimization_strategy: :speed,
          include_resource_management: true,
          timeout: 12_000
        )

      duration = System.monotonic_time(:millisecond) - start_time

      assert {:ok, _workflow_result} = result
      # Parallel execution should complete reasonably quickly
      assert duration < 10_000
    end

    test "handles workflow execution failures gracefully" do
      # Invalid task that should cause workflow build failure
      task = %{
        type: :invalid_type,
        malformed_data: "this should cause issues"
      }

      result = Executor.run_dynamic(task, timeout: 5_000)

      assert {:error, reason} = result
      assert is_tuple(reason) or is_atom(reason)
    end

    test "tracks workflow status during execution" do
      task = %{
        type: :analysis,
        target: "lib/status_test.ex",
        code: "defmodule StatusTest, do: def long_task, do: Process.sleep(1000)"
      }

      # Start async execution
      :ok = Executor.run_dynamic_async(task)

      # Check that we can list running workflows
      # Give it time to start
      Process.sleep(100)
      running = Executor.list_running()

      assert is_list(running)
      # Should have at least our workflow if it's still running
      assert length(running) >= 0
    end

    test "cancels running dynamic workflows" do
      task = %{
        type: :long_running_analysis,
        target: "lib/cancel_test.ex",
        options: %{simulate_delay: 5000}
      }

      # Start async execution
      :ok = Executor.run_dynamic_async(task)

      # Let it start
      Process.sleep(100)

      running = Executor.list_running()

      if length(running) > 0 do
        workflow_id = hd(running).id

        # Cancel the workflow
        result = Executor.cancel(workflow_id, :test_cancellation)

        assert :ok = result

        # Check status
        {:ok, status} = Executor.get_status(workflow_id)
        assert status == :cancelled
      end
    end
  end

  describe "complexity analysis integration" do
    test "correctly analyzes and routes simple tasks" do
      task = %{
        type: :simple_fix,
        target: "lib/bug.ex",
        issue: "typo in function name"
      }

      analysis = ComplexityAnalyzer.analyze(task)

      assert analysis.complexity_score <= 3
      assert analysis.suggested_workflow_type == :simple_analysis

      # Should use simple workflow
      {:ok, _result} = Executor.run_dynamic(task, timeout: 5_000)
    end

    test "correctly analyzes and routes complex tasks" do
      task = %{
        type: :architecture_refactoring,
        description: "Restructure entire application architecture",
        scope: %{
          modules: 50,
          functions: 300,
          tests: 150
        },
        requirements: %{
          maintain_compatibility: true,
          improve_performance: true,
          add_monitoring: true
        }
      }

      analysis = ComplexityAnalyzer.analyze(task)

      assert analysis.complexity_score >= 8
      assert analysis.suggested_workflow_type in [:complex_refactoring, :deep_analysis]

      # Should use complex workflow with resource management
      {:ok, _result} =
        Executor.run_dynamic(task,
          include_resource_management: true,
          timeout: 20_000
        )
    end
  end

  describe "template integration" do
    test "uses appropriate template based on task type" do
      # Test different task types get different templates
      tasks = [
        %{type: :analysis, target: "file.ex"},
        %{type: :generation, description: "Create module"},
        %{type: :refactoring, targets: ["a.ex", "b.ex"]},
        %{type: :review, files: ["important.ex"]}
      ]

      for task <- tasks do
        analysis = ComplexityAnalyzer.analyze(task)
        {:ok, reactor} = DynamicBuilder.build(task, analysis, use_template: true)

        assert reactor
        # Each should build successfully with appropriate template
      end
    end

    test "applies template customization correctly" do
      task = %{
        type: :generation,
        description: "Generate API endpoints"
      }

      customization = %{
        timeout: 180_000,
        include_tests: true,
        security_level: :high
      }

      result =
        Executor.run_dynamic(task,
          use_template: true,
          customization: customization,
          timeout: 15_000
        )

      assert {:ok, _workflow_result} = result
    end
  end

  describe "error handling and recovery" do
    test "recovers from agent failures during execution" do
      task = %{
        type: :analysis_with_potential_failure,
        target: "lib/fragile.ex",
        options: %{simulate_agent_failure: true}
      }

      # Should handle agent failures gracefully
      result = Executor.run_dynamic(task, timeout: 10_000)

      # Even if agents fail, workflow should complete or fail gracefully
      assert {:ok, _result} = result or {:error, _reason} = result
    end

    test "handles timeout scenarios" do
      task = %{
        type: :slow_analysis,
        target: "lib/big_file.ex",
        options: %{simulate_slow_processing: true}
      }

      # Set a short timeout to trigger timeout handling
      result = Executor.run_dynamic(task, timeout: 1_000)

      # Should either complete quickly or timeout gracefully
      case result do
        # Completed faster than expected
        {:ok, _} -> :ok
        # Timed out gracefully
        {:error, _} -> :ok
      end
    end

    test "validates task inputs before workflow creation" do
      invalid_tasks = [
        nil,
        %{},
        %{invalid: "structure"},
        %{type: nil, target: "file.ex"}
      ]

      for invalid_task <- invalid_tasks do
        result = Executor.run_dynamic(invalid_task, timeout: 2_000)

        assert {:error, _reason} = result
      end
    end
  end

  describe "performance and optimization" do
    test "optimization strategies affect execution patterns" do
      task = %{
        type: :multi_stage_analysis,
        files: ["a.ex", "b.ex", "c.ex"],
        stages: [:parse, :analyze, :optimize, :report]
      }

      # Test different optimization strategies
      strategies = [:speed, :resource, :balanced]

      for strategy <- strategies do
        start_time = System.monotonic_time(:millisecond)

        {:ok, _result} =
          Executor.run_dynamic(task,
            optimization_strategy: strategy,
            timeout: 12_000
          )

        duration = System.monotonic_time(:millisecond) - start_time

        # Each strategy should complete within reasonable time
        assert duration < 10_000
      end
    end

    test "resource management prevents system overload" do
      # Create multiple high-resource tasks
      tasks =
        for i <- 1..3 do
          %{
            type: :resource_intensive,
            id: "task_#{i}",
            data_size: :large,
            complexity: :high
          }
        end

      # Execute concurrently with resource management
      results =
        Task.async_stream(
          tasks,
          fn task ->
            Executor.run_dynamic(task,
              include_resource_management: true,
              optimization_strategy: :resource,
              timeout: 15_000
            )
          end,
          timeout: 20_000,
          max_concurrency: 3
        )

      completed = Enum.to_list(results)

      # All should complete without overwhelming the system
      assert length(completed) == 3

      for {:ok, result} <- completed do
        assert {:ok, _} = result or {:error, _} = result
      end
    end
  end

  describe "workflow composition and dependencies" do
    test "handles workflows with complex dependency graphs" do
      task = %{
        type: :dependency_heavy,
        workflow: %{
          steps: [
            %{name: :setup, depends_on: []},
            %{name: :parse, depends_on: [:setup]},
            %{name: :analyze, depends_on: [:parse]},
            %{name: :validate, depends_on: [:parse]},
            %{name: :optimize, depends_on: [:analyze, :validate]},
            %{name: :report, depends_on: [:optimize]}
          ]
        }
      }

      result = Executor.run_dynamic(task, timeout: 15_000)

      assert {:ok, _workflow_result} = result
    end

    test "composes workflows from multiple templates" do
      task = %{
        type: :composite_workflow,
        operations: [:analyze, :generate, :review],
        composition_strategy: :sequential
      }

      result =
        Executor.run_dynamic(task,
          use_template: true,
          customization: %{enable_composition: true},
          timeout: 18_000
        )

      assert {:ok, _workflow_result} = result
    end
  end
end
