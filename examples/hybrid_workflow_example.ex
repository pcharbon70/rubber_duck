defmodule RubberDuck.Examples.HybridWorkflowExample do
  @moduledoc """
  Example demonstrating the hybrid workflow architecture.

  This example shows how to:
  1. Define engines and workflows using the hybrid DSL
  2. Create bridges between engines and workflows
  3. Use capability-based routing
  4. Execute hybrid workflows with automatic optimization
  """

  use RubberDuck.Hybrid.DSL, otp_app: :rubber_duck

  alias RubberDuck.Hybrid.{Bridge, CapabilityRegistry, ExecutionContext}
  alias RubberDuck.Workflows.HybridSteps

  # Define hybrid configuration using the DSL
  hybrid do
    # Engine definitions
    engines do
      engine :semantic_analyzer do
        module RubberDuck.Examples.MockSemanticEngine
        capability :semantic_analysis
        priority(100)
        timeout 30_000
        workflow_compatible(true)
        pool_size(2)

        config(%{
          analysis_depth: :deep,
          include_dependencies: true
        })
      end

      engine :code_generator do
        module RubberDuck.Examples.MockCodeGenerator
        capability :code_generation
        priority(90)
        timeout 45_000
        workflow_compatible(true)

        config(%{
          style: :idiomatic,
          include_tests: true
        })
      end

      engine :performance_analyzer do
        module RubberDuck.Examples.MockPerformanceAnalyzer
        capability :performance_analysis
        priority(80)
        timeout 60_000
        workflow_compatible(true)
      end
    end

    # Workflow definitions
    workflows do
      workflow :code_review_workflow do
        capability :code_review
        priority(110)
        engine_compatible(true)
        timeout 120_000

        resource_requirements(%{
          memory: :medium,
          cpu_cores: 2
        })

        steps([
          %{name: :static_analysis, engine_capability: :semantic_analysis},
          %{name: :performance_check, engine_capability: :performance_analysis},
          %{name: :final_review, run: FinalReviewStep}
        ])
      end

      workflow :refactoring_pipeline do
        capability :code_refactoring
        priority(120)
        engine_compatible(true)
        timeout 180_000

        steps([
          %{name: :analyze_structure, engine_capability: :semantic_analysis},
          %{name: :generate_improved_code, engine_capability: :code_generation},
          %{name: :validate_changes, run: ValidationStep}
        ])
      end
    end

    # Hybrid bridges
    hybrid do
      bridge :intelligent_refactoring do
        engine :semantic_analyzer
        workflow(:refactoring_pipeline)
        capability :intelligent_refactoring
        priority(150)
        bidirectional(true)
        optimization_strategy(:performance_first)
      end

      bridge :comprehensive_analysis do
        engine :performance_analyzer
        workflow(:code_review_workflow)
        capability :comprehensive_analysis
        priority(140)
        optimization_strategy(:balanced)
      end

      capability_mapping :smart_code_generation do
        capability :smart_code_generation
        preferred_type(:hybrid)
        fallback_order([:engine, :workflow])
        load_balancing(:round_robin)
      end
    end
  end

  @doc """
  Demonstrates basic hybrid workflow execution.
  """
  def demonstrate_basic_hybrid_execution do
    # Start the hybrid system
    :ok = start_hybrid_system()

    # Example 1: Direct capability execution
    IO.puts("=== Example 1: Direct Capability Execution ===")

    result =
      Bridge.unified_execute(:semantic_analysis, %{
        code: """
        defmodule Example do
          def slow_function(list) do
            Enum.map(list, fn x ->
              :timer.sleep(100)  # Simulate slow operation
              x * 2
            end)
          end
        end
        """,
        options: %{analysis_type: :performance}
      })

    IO.puts("Semantic Analysis Result: #{inspect(result)}")

    # Example 2: Workflow execution through engine interface
    IO.puts("\n=== Example 2: Workflow as Engine ===")

    result =
      Bridge.unified_execute(:code_review, %{
        code: """
        defmodule ReviewExample do
          def process_data(data) do
            data
            |> Enum.filter(&valid?/1)
            |> Enum.map(&transform/1)
          end

          defp valid?(item), do: not is_nil(item)
          defp transform(item), do: String.upcase(item)
        end
        """,
        review_criteria: [:performance, :style, :security]
      })

    IO.puts("Code Review Result: #{inspect(result)}")

    # Example 3: Hybrid capability execution
    IO.puts("\n=== Example 3: Hybrid Capability ===")

    result =
      Bridge.unified_execute(:intelligent_refactoring, %{
        code: """
        defmodule RefactorExample do
          def calculate_total(items) do
            items
            |> Enum.reduce(0, fn item, acc ->
              case item do
                %{price: price, quantity: qty} -> acc + (price * qty)
                _ -> acc
              end
            end)
          end
        end
        """,
        refactoring_goals: [:performance, :readability, :maintainability]
      })

    IO.puts("Intelligent Refactoring Result: #{inspect(result)}")

    # Cleanup
    stop_hybrid_system()
  end

  @doc """
  Demonstrates advanced hybrid workflow patterns.
  """
  def demonstrate_advanced_patterns do
    :ok = start_hybrid_system()

    IO.puts("\n=== Advanced Pattern 1: Load-Balanced Execution ===")

    # Create a load-balanced step for semantic analysis
    step_config =
      HybridSteps.generate_load_balanced_step(:semantic_analysis,
        load_balancing: :least_loaded,
        timeout: 60_000
      )

    IO.puts("Load-Balanced Step Config: #{inspect(step_config)}")

    IO.puts("\n=== Advanced Pattern 2: Parallel Capability Execution ===")

    # Generate parallel steps for the same capability
    parallel_steps =
      HybridSteps.generate_parallel_capability_steps(:semantic_analysis,
        parallel_strategy: :consensus,
        max_parallel: 3,
        aggregation_timeout: 15_000
      )

    IO.puts("Generated #{length(parallel_steps)} parallel steps")

    Enum.each(parallel_steps, fn step ->
      IO.puts("  - #{step.name}: #{inspect(step.run)}")
    end)

    IO.puts("\n=== Advanced Pattern 3: Hybrid Step with Dynamic Routing ===")

    # Create hybrid step with intelligent routing
    hybrid_step =
      Bridge.create_hybrid_step(:comprehensive_analysis,
        timeout: 120_000,
        retries: 2
      )

    IO.puts("Hybrid Step Config: #{inspect(hybrid_step)}")

    IO.puts("\n=== Advanced Pattern 4: Optimization Planning ===")

    # Demonstrate optimization planning
    hybrid_config = %{
      engines: [:semantic_analyzer, :code_generator, :performance_analyzer],
      workflows: [:code_review_workflow, :refactoring_pipeline],
      capabilities: [:semantic_analysis, :code_generation, :performance_analysis, :code_review]
    }

    context = ExecutionContext.create_hybrid_context(shared_state: %{project_size: :large, deadline: :urgent})

    case Bridge.optimize_hybrid_execution(hybrid_config, context) do
      {:ok, optimization_plan} ->
        IO.puts("Optimization Plan:")
        IO.puts("  Strategy: #{optimization_plan.execution_strategy}")
        IO.puts("  Parallelization Opportunities: #{inspect(optimization_plan.parallelization_opportunities)}")
        IO.puts("  Resource Allocation: #{inspect(optimization_plan.resource_allocation)}")

      {:error, reason} ->
        IO.puts("Optimization failed: #{inspect(reason)}")
    end

    stop_hybrid_system()
  end

  @doc """
  Demonstrates error handling and fallback mechanisms.
  """
  def demonstrate_error_handling do
    :ok = start_hybrid_system()

    IO.puts("\n=== Error Handling Example 1: Missing Capability ===")

    result = Bridge.unified_execute(:nonexistent_capability, %{test: :data})
    IO.puts("Missing Capability Result: #{inspect(result)}")

    IO.puts("\n=== Error Handling Example 2: Engine Fallback ===")

    # This would demonstrate fallback to alternative engines
    # In a real scenario, if the primary engine fails, it would try the next best
    step_config =
      HybridSteps.generate_engine_step(:semantic_analysis,
        fallback_strategy: :next_best,
        retries: 3
      )

    IO.puts("Engine Step with Fallback: #{inspect(step_config)}")

    IO.puts("\n=== Error Handling Example 3: Graceful Degradation ===")

    # Demonstrate how hybrid system handles partial failures
    parallel_steps =
      HybridSteps.generate_parallel_capability_steps(:semantic_analysis,
        # Takes first successful result
        parallel_strategy: :first_success,
        max_parallel: 2
      )

    IO.puts("Parallel execution with graceful degradation:")

    Enum.each(parallel_steps, fn step ->
      IO.puts("  - #{step.name}")
    end)

    stop_hybrid_system()
  end

  @doc """
  Shows the complete capability registry state.
  """
  def show_registry_state do
    :ok = start_hybrid_system()

    IO.puts("\n=== Capability Registry State ===")

    # Show all registered capabilities
    capabilities = CapabilityRegistry.list_capabilities()
    IO.puts("Registered Capabilities:")

    Enum.each(capabilities, fn capability ->
      implementations = CapabilityRegistry.find_by_capability(capability)
      IO.puts("  #{capability}:")

      Enum.each(implementations, fn impl ->
        IO.puts("    - #{impl.id} (#{impl.type}, priority: #{impl.priority})")
      end)
    end)

    # Show hybrid-compatible implementations
    IO.puts("\nHybrid-Compatible Implementations:")

    Enum.each(capabilities, fn capability ->
      compatible = CapabilityRegistry.find_hybrid_compatible(capability)

      if length(compatible) > 0 do
        IO.puts("  #{capability}: #{length(compatible)} compatible implementations")
      end
    end)

    # Show type distribution
    all_registrations = CapabilityRegistry.list_all()
    type_counts = Enum.frequencies_by(all_registrations, & &1.type)
    IO.puts("\nType Distribution:")

    Enum.each(type_counts, fn {type, count} ->
      IO.puts("  #{type}: #{count}")
    end)

    stop_hybrid_system()
  end

  @doc """
  Run all examples in sequence.
  """
  def run_all_examples do
    IO.puts("🚀 Starting Hybrid Workflow Architecture Examples")
    IO.puts("=" |> String.duplicate(60))

    demonstrate_basic_hybrid_execution()
    demonstrate_advanced_patterns()
    demonstrate_error_handling()
    show_registry_state()

    IO.puts("\n✅ All examples completed!")
    IO.puts("=" |> String.duplicate(60))
  end
end

# Mock modules for demonstration (would be real implementations in practice)
defmodule RubberDuck.Examples.MockSemanticEngine do
  @moduledoc """
  Mock semantic analysis engine for demonstration purposes.
  """
  @behaviour RubberDuck.Engine

  def init(_config), do: {:ok, %{}}
  def execute(input, _state), do: {:ok, %{analysis: "semantic analysis of: #{inspect(input)}"}}
  def capabilities, do: [:semantic_analysis]
end

defmodule RubberDuck.Examples.MockCodeGenerator do
  @moduledoc """
  Mock code generation engine for demonstration purposes.
  """
  @behaviour RubberDuck.Engine

  def init(_config), do: {:ok, %{}}
  def execute(input, _state), do: {:ok, %{generated_code: "# Generated code for: #{inspect(input)}"}}
  def capabilities, do: [:code_generation]
end

defmodule RubberDuck.Examples.MockPerformanceAnalyzer do
  @moduledoc """
  Mock performance analysis engine for demonstration purposes.
  """
  @behaviour RubberDuck.Engine

  def init(_config), do: {:ok, %{}}
  def execute(input, _state), do: {:ok, %{performance_report: "Performance analysis: #{inspect(input)}"}}
  def capabilities, do: [:performance_analysis]
end
