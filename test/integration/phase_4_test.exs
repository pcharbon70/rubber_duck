defmodule RubberDuck.Integration.Phase4Test do
  @moduledoc """
  Comprehensive integration tests for Phase 4: Workflow Orchestration & Analysis.

  These tests verify that all Phase 4 components work together correctly:
  - Reactor workflow foundation
  - AST parsing
  - Code analysis engines
  - Complete analysis workflow
  - Agentic workflows
  - Dynamic workflow generation
  - Hybrid engine-workflow architecture
  """

  use ExUnit.Case, async: false

  alias RubberDuck.Workflows.{Executor, CompleteAnalysis, Registry}
  alias RubberDuck.Analysis.{AST, Semantic, Style, Security}
  alias RubberDuck.Agents.{Supervisor, Coordinator, ResearchAgent, AnalysisAgent}
  alias RubberDuck.Workflows.{DynamicBuilder, ComplexityAnalyzer}
  alias RubberDuck.Hybrid.{Bridge, CapabilityRegistry, ExecutionContext}
  alias RubberDuck.Workspace

  require Logger

  setup_all do
    # Start necessary applications
    {:ok, _} = Application.ensure_all_started(:rubber_duck)

    # Create test project
    {:ok, project} = create_test_project()

    # Ensure all supervisors are running
    ensure_supervisors_started()

    %{project: project}
  end

  setup do
    # Clear any cached data between tests
    clear_test_caches()

    :ok
  end

  describe "Complete Project Analysis Workflow" do
    test "analyzes entire project with all analysis engines", %{project: project} do
      # Create test files
      {:ok, elixir_file} =
        create_test_file(project, "lib/example.ex", """
        defmodule Example do
          @unused_var 42
          
          def complex_function(x) do
            if x > 0 do
              result = x * 2
              result + 1
            else
              0
            end
          end
          
          def sql_query(user_input) do
            # Potential SQL injection
            Repo.query("SELECT * FROM users WHERE name = '\#{user_input}'")
          end
        end
        """)

      {:ok, python_file} =
        create_test_file(project, "lib/example.py", """
        def unused_function():
            pass

        def complex_function(x):
            if x > 0:
                for i in range(x):
                    if i % 2 == 0:
                        print(i)
            return x * 2

        password = "hardcoded_password"  # Security issue
        """)

      # Run complete analysis workflow
      {:ok, results} = CompleteAnalysis.run(project.id, %{})

      # Verify all analysis types ran
      assert results.semantic_issues
      assert results.style_issues
      assert results.security_issues

      # Verify issues were found
      assert length(results.semantic_issues) > 0
      assert length(results.security_issues) > 0

      # Verify multi-language support
      elixir_issues = Enum.filter(results.all_issues, &(&1.file_id == elixir_file.id))
      python_issues = Enum.filter(results.all_issues, &(&1.file_id == python_file.id))

      assert length(elixir_issues) > 0
      assert length(python_issues) > 0
    end

    test "performs incremental analysis on file changes", %{project: project} do
      # Create initial file
      {:ok, file} =
        create_test_file(project, "lib/incremental.ex", """
        defmodule Incremental do
          def hello, do: "world"
        end
        """)

      # Run initial analysis
      {:ok, initial_results} = CompleteAnalysis.run(project.id, %{})
      initial_count = length(initial_results.all_issues)

      # Update file with issues
      {:ok, _} =
        update_test_file(file, """
        defmodule Incremental do
          @unused_var 123
          
          def hello, do: "world"
          
          def complex_nested_function(x) do
            if x > 0 do
              if x > 10 do
                if x > 100 do
                  "very large"
                else
                  "large"
                end
              else
                "small"
              end
            else
              "negative"
            end
          end
        end
        """)

      # Run incremental analysis
      {:ok, updated_results} =
        CompleteAnalysis.run(project.id, %{
          incremental: true,
          changed_files: [file.id]
        })

      # Verify new issues were found
      assert length(updated_results.all_issues) > initial_count

      # Verify only changed file was analyzed
      assert updated_results.metadata.files_analyzed == 1
    end
  end

  describe "Custom Workflow Composition" do
    test "composes custom analysis workflow using hybrid architecture" do
      # Register custom analysis engine
      {:ok, _} =
        CapabilityRegistry.register_engine_capability(
          :custom_analyzer,
          :custom_analysis,
          %{
            module: CustomAnalysisEngine,
            priority: 100,
            can_integrate_with_workflows: true
          }
        )

      # Create hybrid workflow that combines engine and workflow steps
      workflow_config = %{
        name: :custom_hybrid_workflow,
        steps: [
          # Engine step via hybrid bridge
          Bridge.engine_to_step(:custom_analyzer, timeout: 5000),
          # Standard workflow step
          %{
            name: :aggregate_results,
            run: {ResultAggregator, :run, []},
            arguments: %{
              input: {:result, :custom_analyzer_step}
            }
          },
          # Another engine step
          Bridge.engine_to_step(:semantic_analyzer, timeout: 10000)
        ]
      }

      # Execute custom workflow
      context = ExecutionContext.create_hybrid_context()

      {:ok, result} =
        Bridge.unified_execute(
          {:workflow, :custom_hybrid_workflow},
          %{code: "defmodule Test do\nend"},
          context
        )

      assert result.custom_analysis
      assert result.semantic_analysis
      assert result.aggregated_results
    end
  end

  describe "Parallel Analysis Performance" do
    test "executes analysis steps in parallel for performance", %{project: project} do
      # Create multiple files
      files =
        for i <- 1..10 do
          {:ok, file} =
            create_test_file(project, "lib/file_#{i}.ex", """
            defmodule File#{i} do
              def function_#{i}, do: #{i}
            end
            """)

          file
        end

      # Measure parallel execution time
      start_time = System.monotonic_time(:millisecond)

      {:ok, results} =
        CompleteAnalysis.run(project.id, %{
          parallel: true,
          max_concurrency: 5
        })

      parallel_time = System.monotonic_time(:millisecond) - start_time

      # Run sequential for comparison
      start_time = System.monotonic_time(:millisecond)

      {:ok, _sequential_results} =
        CompleteAnalysis.run(project.id, %{
          parallel: false
        })

      sequential_time = System.monotonic_time(:millisecond) - start_time

      # Verify parallel is faster
      assert parallel_time < sequential_time

      # Verify all files were analyzed
      assert length(results.analyzed_files) == 10
    end
  end

  describe "Analysis Caching" do
    test "caches analysis results for unchanged files", %{project: project} do
      # Create test file
      {:ok, file} =
        create_test_file(project, "lib/cached.ex", """
        defmodule Cached do
          def expensive_to_analyze do
            # Complex nested structure
            Enum.map(1..100, fn x ->
              Enum.map(1..100, fn y ->
                {x, y, x * y}
              end)
            end)
          end
        end
        """)

      # First analysis (cache miss)
      start_time = System.monotonic_time(:millisecond)
      {:ok, first_results} = CompleteAnalysis.run(project.id, %{})
      first_time = System.monotonic_time(:millisecond) - start_time

      # Second analysis (cache hit)
      start_time = System.monotonic_time(:millisecond)
      {:ok, second_results} = CompleteAnalysis.run(project.id, %{})
      second_time = System.monotonic_time(:millisecond) - start_time

      # Cache should make second run significantly faster
      assert second_time < first_time * 0.5

      # Results should be identical
      assert first_results == second_results
    end
  end

  describe "Cross-File Dependency Analysis" do
    test "detects and analyzes cross-file dependencies", %{project: project} do
      # Create interconnected modules
      {:ok, _module_a} =
        create_test_file(project, "lib/module_a.ex", """
        defmodule ModuleA do
          alias ModuleB
          
          def call_b(x) do
            ModuleB.process(x)
          end
        end
        """)

      {:ok, _module_b} =
        create_test_file(project, "lib/module_b.ex", """
        defmodule ModuleB do
          alias ModuleC
          
          def process(x) do
            ModuleC.transform(x * 2)
          end
        end
        """)

      {:ok, _module_c} =
        create_test_file(project, "lib/module_c.ex", """
        defmodule ModuleC do
          alias ModuleA  # Circular dependency!
          
          def transform(x) do
            if x > 100 do
              ModuleA.call_b(x / 2)
            else
              x
            end
          end
        end
        """)

      # Run analysis
      {:ok, results} =
        CompleteAnalysis.run(project.id, %{
          analyze_dependencies: true
        })

      # Find circular dependency issue
      circular_deps =
        Enum.filter(results.semantic_issues, fn issue ->
          issue.type == :circular_dependency
        end)

      assert length(circular_deps) > 0

      # Verify dependency graph was built
      assert results.metadata.dependency_graph
      assert map_size(results.metadata.dependency_graph) == 3
    end
  end

  describe "Multi-Language Project Handling" do
    test "handles projects with multiple programming languages", %{project: project} do
      # Create files in different languages
      {:ok, _elixir_file} =
        create_test_file(project, "lib/elixir_code.ex", """
        defmodule ElixirCode do
          def elixir_function(x) do
            x * 2
          end
        end
        """)

      {:ok, _python_file} =
        create_test_file(project, "lib/python_code.py", """
        class PythonCode:
            def python_method(self, x):
                return x * 2
                
        def standalone_function():
            return "Python"
        """)

      # Run multi-language analysis
      {:ok, results} = CompleteAnalysis.run(project.id, %{})

      # Verify both languages were analyzed
      assert results.metadata.languages_detected == [:elixir, :python]

      # Verify language-specific analysis ran
      elixir_ast = Enum.find(results.metadata.ast_results, &(&1.language == :elixir))
      python_ast = Enum.find(results.metadata.ast_results, &(&1.language == :python))

      assert elixir_ast
      assert python_ast

      # Verify correct parsing
      assert length(elixir_ast.functions) == 1
      assert length(python_ast.functions) == 2
    end
  end

  describe "Agent-Based Task Execution" do
    test "executes complex tasks using multiple specialized agents" do
      # Start agent supervisor
      {:ok, _sup} = Supervisor.start_link()

      # Define complex task requiring multiple agents
      task = %{
        type: :code_improvement,
        description: "Analyze and improve the codebase",
        code: """
        defmodule NeedsImprovement do
          def bad_function(list) do
            result = []
            for item <- list do
              result = result ++ [item * 2]
            end
            result
          end
        end
        """,
        requirements: [
          :performance_analysis,
          :code_generation,
          :quality_review
        ]
      }

      # Execute via coordinator
      {:ok, coordinator} = Coordinator.start_link()
      {:ok, result} = Coordinator.execute_task(coordinator, task)

      # Verify multiple agents were involved
      assert result.agents_used |> MapSet.size() >= 3
      assert MapSet.member?(result.agents_used, AnalysisAgent)
      assert MapSet.member?(result.agents_used, RubberDuck.Agents.GenerationAgent)
      assert MapSet.member?(result.agents_used, RubberDuck.Agents.ReviewAgent)

      # Verify improved code was generated
      assert result.improved_code
      # Should use Enum.map instead of loop
      assert result.improved_code =~ "Enum.map"

      # Verify analysis was performed
      assert result.analysis.performance_issues
      assert length(result.analysis.performance_issues) > 0
    end
  end

  describe "Dynamic Workflow Generation" do
    test "dynamically generates workflows based on task complexity" do
      # Simple task
      simple_task = %{
        type: :analyze,
        target: "def hello, do: :world",
        options: %{}
      }

      # Complex task
      complex_task = %{
        type: :refactor,
        target: """
        defmodule ComplexModule do
          # 500 lines of complex code...
          #{Enum.map(1..50, fn i -> "def function_#{i}(x), do: x * #{i}" end) |> Enum.join("\n")}
        end
        """,
        options: %{
          optimize_performance: true,
          improve_readability: true,
          add_documentation: true
        }
      }

      # Generate workflows
      {:ok, simple_workflow} = DynamicBuilder.build(simple_task)
      {:ok, complex_workflow} = DynamicBuilder.build(complex_task)

      # Simple workflow should have fewer steps
      assert length(simple_workflow.steps) < length(complex_workflow.steps)

      # Complex workflow should include optimization steps
      optimization_steps =
        Enum.filter(complex_workflow.steps, fn step ->
          step.name =~ "optimize" or step.name =~ "performance"
        end)

      assert length(optimization_steps) > 0

      # Complex workflow should parallelize where possible
      parallel_groups = complex_workflow.metadata.parallel_groups
      assert length(parallel_groups) > 0
    end

    test "adapts workflow based on available resources" do
      # Simulate limited resources
      resource_context = %{
        available_memory: :low,
        cpu_cores: 2,
        time_constraint: :strict
      }

      task = %{
        type: :analyze,
        target: "large codebase",
        size: :large
      }

      # Generate resource-aware workflow
      {:ok, workflow} =
        DynamicBuilder.build(task, %{
          resource_context: resource_context,
          optimization_strategy: :resource_efficient
        })

      # Should use memory-efficient strategies
      assert workflow.metadata.memory_strategy == :streaming
      assert workflow.metadata.max_parallel_steps <= 2

      # Should have timeout constraints
      assert Enum.all?(workflow.steps, fn step ->
               step.timeout && step.timeout <= 30_000
             end)
    end
  end

  describe "Hybrid Architecture Performance" do
    test "seamlessly bridges engines and workflows with minimal overhead" do
      # Create test scenario using both engines and workflows
      hybrid_task = %{
        steps: [
          # Start with engine
          {:engine, :code_analyzer},
          # Process with workflow
          {:workflow, :result_processor},
          # Back to engine
          {:engine, :code_generator},
          # Finish with workflow
          {:workflow, :quality_checker}
        ],
        input: %{
          code: "defmodule Test do\n  def test, do: :ok\nend"
        }
      }

      # Execute through hybrid bridge
      start_time = System.monotonic_time(:microsecond)

      context = ExecutionContext.create_hybrid_context()
      {:ok, result} = execute_hybrid_task(hybrid_task, context)

      execution_time = System.monotonic_time(:microsecond) - start_time

      # Verify all steps executed
      assert result.analysis
      assert result.processed_results
      assert result.generated_code
      assert result.quality_score

      # Verify context was shared across boundaries
      assert context.shared_state.analysis_complete
      assert context.shared_state.generation_complete

      # Performance should be reasonable (< 100ms overhead)
      # microseconds
      assert execution_time < 100_000
    end
  end

  describe "Complex Multi-Agent Scenarios" do
    test "handles research, analysis, and generation in coordinated manner" do
      # Complex refactoring task
      task = %{
        type: :complex_refactoring,
        description: "Refactor legacy code to use modern patterns",
        target_file: create_legacy_code_file(),
        requirements: [
          "Research modern Elixir patterns",
          "Analyze current code structure",
          "Generate refactored version",
          "Ensure backward compatibility",
          "Add comprehensive tests"
        ]
      }

      # Execute multi-agent workflow
      {:ok, coordinator} = Coordinator.start_link()
      {:ok, result} = Coordinator.execute_complex_task(coordinator, task)

      # Verify research was performed
      assert result.research_findings
      assert length(result.research_findings.modern_patterns) > 0

      # Verify analysis identified issues
      assert result.analysis.legacy_patterns_found > 0
      assert result.analysis.refactoring_opportunities

      # Verify code was generated
      assert result.refactored_code
      assert result.test_code

      # Verify coordination metrics
      assert result.coordination_metrics.total_agents >= 4
      assert result.coordination_metrics.messages_exchanged > 10
      assert result.coordination_metrics.parallel_executions > 0
    end

    test "handles agent failures gracefully with fallback strategies" do
      # Simulate agent failure scenario
      failing_task = %{
        type: :analysis_with_failures,
        code: "defmodule Test do end",
        simulate_failures: [:analysis_agent_crash, :network_timeout]
      }

      {:ok, coordinator} = Coordinator.start_link()
      {:ok, result} = Coordinator.execute_task(coordinator, failing_task)

      # Task should still complete
      assert result.status == :completed_with_fallbacks

      # Verify fallback strategies were used
      assert result.fallbacks_used
      assert :backup_analysis in result.fallbacks_used

      # Verify partial results were obtained
      assert result.partial_results
      assert map_size(result.partial_results) > 0
    end
  end

  describe "Workflow Optimization Effectiveness" do
    test "optimizes workflow execution based on historical data" do
      # Run same type of task multiple times to build history
      task_template = %{
        type: :code_analysis,
        size: :medium
      }

      # First run (no optimization)
      {:ok, first_result} = DynamicBuilder.build(task_template)
      first_time = execute_and_measure(first_result)

      # Run several times to build history
      for _ <- 1..5 do
        {:ok, workflow} = DynamicBuilder.build(task_template)
        execute_workflow(workflow)
      end

      # Run with optimization enabled
      {:ok, optimized_workflow} =
        DynamicBuilder.build(task_template, %{
          use_ml_optimization: true,
          historical_data: true
        })

      optimized_time = execute_and_measure(optimized_workflow)

      # Optimized should be faster
      assert optimized_time < first_time * 0.8

      # Verify optimization strategies were applied
      assert optimized_workflow.metadata.optimizations_applied
      assert :step_reordering in optimized_workflow.metadata.optimizations_applied
      assert :parallel_grouping in optimized_workflow.metadata.optimizations_applied
    end

    test "dynamically adjusts resource allocation during execution" do
      # Create workflow with dynamic resource management
      adaptive_task = %{
        type: :adaptive_analysis,
        files: create_files_with_varying_complexity(10),
        options: %{
          adaptive_resources: true,
          initial_allocation: %{memory: :low, cpu: :low}
        }
      }

      {:ok, workflow} = DynamicBuilder.build(adaptive_task)
      {:ok, result} = Executor.run_with_monitoring(workflow)

      # Verify resource adjustments were made
      assert result.resource_adjustments
      assert length(result.resource_adjustments) > 0

      # Verify performance improved after adjustments
      initial_step_times = result.step_timings |> Enum.take(3) |> Enum.map(&elem(&1, 1))
      final_step_times = result.step_timings |> Enum.take(-3) |> Enum.map(&elem(&1, 1))

      avg_initial = Enum.sum(initial_step_times) / length(initial_step_times)
      avg_final = Enum.sum(final_step_times) / length(final_step_times)

      assert avg_final < avg_initial
    end
  end

  # Helper Functions

  defp create_test_project do
    Workspace.create_project(%{
      name: "Integration Test Project",
      description: "Project for Phase 4 integration tests"
    })
  end

  defp create_test_file(project, path, content) do
    Workspace.create_code_file(%{
      project_id: project.id,
      path: path,
      content: content,
      language: detect_language(path)
    })
  end

  defp update_test_file(file, new_content) do
    Workspace.update_code_file(file, %{content: new_content})
  end

  defp detect_language(path) do
    cond do
      String.ends_with?(path, ".ex") -> :elixir
      String.ends_with?(path, ".exs") -> :elixir
      String.ends_with?(path, ".py") -> :python
      true -> :unknown
    end
  end

  defp ensure_supervisors_started do
    # Ensure all necessary supervisors are running
    supervisors = [
      RubberDuck.Workflows.Supervisor,
      RubberDuck.Agents.Supervisor,
      RubberDuck.Engine.Supervisor
    ]

    Enum.each(supervisors, fn sup ->
      case Process.whereis(sup) do
        nil -> {:ok, _} = sup.start_link()
        _pid -> :ok
      end
    end)
  end

  defp clear_test_caches do
    # Clear various caches to ensure test isolation
    RubberDuck.Analysis.Cache.clear()
    RubberDuck.Workflows.Cache.clear()
    :ok
  end

  defp execute_hybrid_task(task, context) do
    Enum.reduce_while(task.steps, {:ok, task.input}, fn step, {:ok, acc} ->
      result =
        case step do
          {:engine, name} ->
            Bridge.unified_execute({:engine, name}, acc, context)

          {:workflow, name} ->
            Bridge.unified_execute({:workflow, name}, acc, context)
        end

      case result do
        {:ok, output} -> {:cont, {:ok, Map.merge(acc, output)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp create_legacy_code_file do
    %{
      path: "lib/legacy.ex",
      content: """
      defmodule LegacyCode do
        # Old-style module with issues
        
        def process_data(data) do
          result = []
          for item <- data do
            if item != nil do
              processed = item |> String.downcase |> String.trim
              result = result ++ [processed]
            end
          end
          result
        end
        
        def calculate(x, y) do
          if x == nil do
            0
          else
            if y == nil do
              x
            else
              x + y
            end
          end
        end
      end
      """
    }
  end

  defp execute_and_measure(workflow) do
    start = System.monotonic_time(:millisecond)
    {:ok, _} = execute_workflow(workflow)
    System.monotonic_time(:millisecond) - start
  end

  defp execute_workflow(workflow) do
    Executor.run(workflow, %{test_input: "data"})
  end

  defp create_files_with_varying_complexity(count) do
    Enum.map(1..count, fn i ->
      complexity = rem(i, 3)

      content =
        case complexity do
          0 -> "defmodule Simple#{i} do\n  def foo, do: :ok\nend"
          1 -> generate_medium_complexity_code(i)
          2 -> generate_high_complexity_code(i)
        end

      %{
        name: "file_#{i}.ex",
        content: content,
        expected_complexity: complexity
      }
    end)
  end

  defp generate_medium_complexity_code(i) do
    """
    defmodule Medium#{i} do
      def process(list) do
        list
        |> Enum.filter(&(&1 > 0))
        |> Enum.map(&(&1 * 2))
        |> Enum.reduce(0, &+/2)
      end
      
      def conditional(x) do
        cond do
          x > 100 -> :large
          x > 10 -> :medium  
          true -> :small
        end
      end
    end
    """
  end

  defp generate_high_complexity_code(i) do
    """
    defmodule Complex#{i} do
      def nested_loops(matrix) do
        for row <- matrix do
          for col <- row do
            if col > 0 do
              for i <- 1..col do
                i * 2
              end
            else
              [0]
            end
          end
        end
      end
      
      def recursive_process(list, acc \\ [])
      def recursive_process([], acc), do: Enum.reverse(acc)
      def recursive_process([h | t], acc) do
        processed = 
          case h do
            x when is_number(x) -> x * 2
            x when is_binary(x) -> String.upcase(x)
            _ -> h
          end
        recursive_process(t, [processed | acc])
      end
    end
    """
  end

  # Mock modules for testing

  defmodule CustomAnalysisEngine do
    @behaviour RubberDuck.Engine

    def init(_config), do: {:ok, %{}}

    def execute(input, state) do
      {:ok, %{custom_analysis: "Analyzed: #{inspect(input)}"}}
    end

    def capabilities, do: [:custom_analysis]
  end

  defmodule ResultAggregator do
    def run(%{input: input}, _context) do
      {:ok, %{aggregated_results: "Aggregated: #{inspect(input)}"}}
    end
  end
end
