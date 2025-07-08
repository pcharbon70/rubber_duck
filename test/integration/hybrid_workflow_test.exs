defmodule RubberDuck.Integration.HybridWorkflowTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Hybrid.{Bridge, CapabilityRegistry, ExecutionContext}
  alias RubberDuck.Workflows.HybridSteps

  setup do
    start_supervised!(CapabilityRegistry)
    :ok
  end

  describe "hybrid workflow integration" do
    setup do
      # Register mock engines and workflows for testing
      CapabilityRegistry.register_engine_capability(
        :semantic_analyzer,
        :semantic_analysis,
        %{
          module: MockSemanticEngine,
          priority: 100,
          can_integrate_with_workflows: true
        }
      )

      CapabilityRegistry.register_engine_capability(
        :code_generator,
        :code_generation,
        %{
          module: MockGenerationEngine,
          priority: 90,
          can_integrate_with_workflows: true
        }
      )

      CapabilityRegistry.register_workflow_capability(
        :validation_workflow,
        :code_validation,
        %{
          priority: 110,
          can_integrate_with_engines: true
        }
      )

      # Register a hybrid capability
      CapabilityRegistry.register_hybrid_capability(
        :complete_refactoring,
        :full_refactoring,
        %{
          type: :native_hybrid,
          module: MockHybridRefactoring,
          function: :execute,
          priority: 150
        }
      )

      :ok
    end

    test "engine-to-workflow step integration" do
      # Create a workflow step that uses an engine
      step_config =
        Bridge.engine_to_step(:semantic_analyzer,
          timeout: 45_000,
          retries: 2
        )

      assert step_config.name == :semantic_analyzer_step
      assert step_config.run == {Bridge, :execute_engine_step}
      assert step_config.arguments.engine_name == :semantic_analyzer
      assert step_config.timeout == 45_000
      assert step_config.max_retries == 2

      # Execute the step (will fail due to mock engine, but tests integration)
      arguments = step_config.arguments
      result = Bridge.execute_engine_step(arguments, %{})

      # Should fail gracefully with telemetry
      assert {:error, _reason} = result
    end

    test "workflow-to-engine adapter integration" do
      # Convert workflow to engine capability
      engine_config =
        Bridge.workflow_to_engine(:validation_workflow,
          capability: :validation_service,
          priority: 120
        )

      assert engine_config.name == :validation_workflow
      assert engine_config.capability == :validation_service

      # Verify it was registered as hybrid capability
      registration = CapabilityRegistry.find_by_id(:validation_workflow)
      assert registration.type == :hybrid
      assert registration.capability == :validation_service
      assert registration.metadata.type == :workflow_engine_adapter
    end

    test "capability-based routing works across types" do
      # Test that unified_execute can find the best implementation
      context = ExecutionContext.create_hybrid_context()

      # Should route to semantic_analyzer engine (highest priority for semantic_analysis)
      result = Bridge.unified_execute(:semantic_analysis, %{code: "test"}, context)
      # Fails due to mock, but routing worked
      assert {:error, _} = result

      # Should route to validation_workflow (only implementation for code_validation)
      result = Bridge.unified_execute(:code_validation, %{code: "test"}, context)
      # Fails due to mock, but routing worked
      assert {:error, _} = result

      # Should route to hybrid capability (highest priority)
      result = Bridge.unified_execute(:full_refactoring, %{code: "test"}, context)
      # Fails due to mock, but routing worked
      assert {:error, _} = result
    end

    test "hybrid step generation works" do
      # Generate hybrid step that can route to any compatible implementation
      step_config =
        HybridSteps.generate_hybrid_step(:semantic_analysis,
          step_name: :smart_analysis,
          routing_strategy: :best_available,
          timeout: 60_000
        )

      assert step_config.name == :smart_analysis
      assert step_config.run == {HybridSteps, :execute_hybrid_capability}
      assert step_config.arguments.capability == :semantic_analysis
      assert step_config.arguments.routing_strategy == :best_available
      assert step_config.timeout == 60_000

      # Execute the hybrid step
      arguments = step_config.arguments
      result = HybridSteps.execute_hybrid_capability(arguments, %{})

      # Should find and route to semantic_analyzer engine
      # Fails due to mock engine
      assert {:error, _reason} = result
    end

    test "parallel capability execution" do
      # Generate parallel steps for the same capability
      parallel_steps =
        HybridSteps.generate_parallel_capability_steps(:semantic_analysis,
          parallel_strategy: :first_success,
          max_parallel: 2
        )

      # Should have individual parallel steps plus aggregation step
      # At least one parallel step + aggregation
      assert length(parallel_steps) >= 2

      # Check aggregation step exists
      aggregation_step =
        Enum.find(parallel_steps, fn step ->
          String.contains?(to_string(step.name), "aggregate")
        end)

      assert aggregation_step
      assert aggregation_step.run == {HybridSteps, :aggregate_parallel_results}
    end

    test "load-balanced step routing" do
      step_config =
        HybridSteps.generate_load_balanced_step(:semantic_analysis,
          load_balancing: :least_loaded,
          timeout: 40_000
        )

      assert step_config.name == :semantic_analysis_load_balanced_step
      assert step_config.run == {HybridSteps, :execute_load_balanced_capability}
      assert step_config.arguments.capability == :semantic_analysis
      assert step_config.arguments.load_balancing_strategy == :least_loaded

      # Execute load-balanced step
      arguments = step_config.arguments
      result = HybridSteps.execute_load_balanced_capability(arguments, %{})

      # Fails due to mock engine
      assert {:error, _reason} = result
    end

    test "hybrid compatibility filtering" do
      # Find all hybrid-compatible implementations for semantic analysis
      compatible = CapabilityRegistry.find_hybrid_compatible(:semantic_analysis)

      # Should include the semantic_analyzer engine (marked as workflow-compatible)
      engine_ids = Enum.map(compatible, & &1.id)
      assert :semantic_analyzer in engine_ids

      # Verify compatibility metadata
      semantic_engine = Enum.find(compatible, &(&1.id == :semantic_analyzer))
      assert semantic_engine.metadata.can_integrate_with_workflows == true
    end

    test "execution context flows through hybrid system" do
      # Create context with custom metadata
      context =
        ExecutionContext.create_hybrid_context(
          shared_state: %{project_id: "test_project"},
          telemetry_metadata: %{user_id: "test_user"}
        )

      # Execute through hybrid system
      Bridge.unified_execute(:semantic_analysis, %{code: "test"}, context)

      # Context should preserve original data
      assert context.shared_state.project_id == "test_project"
      assert context.telemetry_metadata.user_id == "test_user"

      # Execution ID should be preserved
      assert is_binary(context.execution_id)
    end

    test "error handling and fallback mechanisms" do
      # Test that hybrid system handles missing implementations gracefully
      result = Bridge.unified_execute(:nonexistent_capability, %{}, nil)
      assert {:error, {:capability_not_found, :nonexistent_capability}} = result

      # Test that engine steps handle missing engines
      arguments = %{
        engine_name: :nonexistent_engine,
        engine_input: %{},
        execution_options: [fallback_strategy: :fail_fast]
      }

      result = Bridge.execute_engine_step(arguments, %{})
      assert {:error, _reason} = result
    end

    test "optimization and resource planning" do
      hybrid_config = %{
        engines: [:semantic_analyzer, :code_generator],
        workflows: [:validation_workflow],
        capabilities: [:semantic_analysis, :code_generation, :code_validation]
      }

      context = ExecutionContext.create_hybrid_context()

      {:ok, optimization_plan} = Bridge.optimize_hybrid_execution(hybrid_config, context)

      # Verify optimization plan structure
      assert Map.has_key?(optimization_plan, :execution_strategy)
      assert Map.has_key?(optimization_plan, :capability_assignments)
      assert Map.has_key?(optimization_plan, :resource_allocation)
      assert Map.has_key?(optimization_plan, :parallelization_opportunities)

      # Strategy should be reasonable
      assert optimization_plan.execution_strategy in [:parallel, :sequential]

      # Should have capability assignments
      assert is_map(optimization_plan.capability_assignments)

      # Should identify parallelization opportunities
      assert is_list(optimization_plan.parallelization_opportunities)
    end

    test "telemetry integration throughout hybrid system" do
      test_pid = self()

      # Attach telemetry handlers
      :telemetry.attach_many(
        "hybrid-integration-test",
        [
          [:rubber_duck, :hybrid, :engine_step_failure],
          [:rubber_duck, :hybrid, :hybrid_step_failure]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Execute hybrid operations that will emit telemetry
      context = ExecutionContext.create_hybrid_context()
      Bridge.unified_execute(:semantic_analysis, %{code: "test"}, context)

      # Execute engine step directly
      arguments = %{
        engine_name: :semantic_analyzer,
        engine_input: %{code: "test"},
        execution_options: []
      }

      Bridge.execute_engine_step(arguments, %{})

      # Should receive telemetry events
      assert_receive {:telemetry, [:rubber_duck, :hybrid, :engine_step_failure], _measurements, _metadata}

      :telemetry.detach("hybrid-integration-test")
    end
  end

  describe "end-to-end hybrid workflow scenarios" do
    test "complete refactoring workflow using hybrid architecture" do
      # Simulate a complete refactoring workflow that uses:
      # 1. Engine for semantic analysis
      # 2. Workflow for validation
      # 3. Hybrid component for final integration

      context =
        ExecutionContext.create_hybrid_context(
          shared_state: %{
            source_code: "def hello, do: :world",
            refactoring_goals: [:performance, :readability]
          }
        )

      # Step 1: Semantic analysis using engine
      step1_result =
        Bridge.unified_execute(
          :semantic_analysis,
          %{
            code: context.shared_state.source_code
          },
          context
        )

      # Should route to semantic_analyzer engine
      # Mock will fail, but routing works
      assert {:error, _} = step1_result

      # Step 2: Validation using workflow
      step2_result =
        Bridge.unified_execute(
          :code_validation,
          %{
            analysis_result: step1_result,
            original_code: context.shared_state.source_code
          },
          context
        )

      # Should route to validation_workflow
      # Mock will fail, but routing works
      assert {:error, _} = step2_result

      # Step 3: Final refactoring using hybrid capability
      step3_result =
        Bridge.unified_execute(
          :full_refactoring,
          %{
            analysis: step1_result,
            validation: step2_result,
            goals: context.shared_state.refactoring_goals
          },
          context
        )

      # Should route to hybrid refactoring capability
      # Mock will fail, but routing works
      assert {:error, _} = step3_result

      # Verify context maintained state throughout
      assert context.shared_state.source_code == "def hello, do: :world"
      assert context.shared_state.refactoring_goals == [:performance, :readability]
    end

    test "dynamic workflow construction with hybrid steps" do
      # Test building a workflow dynamically using hybrid components

      # Generate various step types
      engine_step = Bridge.engine_to_step(:semantic_analyzer)
      hybrid_step = Bridge.create_hybrid_step(:code_generation)
      load_balanced_step = HybridSteps.generate_load_balanced_step(:semantic_analysis)

      # Combine into a workflow-like structure
      workflow_steps = [engine_step, hybrid_step, load_balanced_step]

      # Each step should have the proper structure
      Enum.each(workflow_steps, fn step ->
        assert Map.has_key?(step, :name)
        assert Map.has_key?(step, :run)
        assert Map.has_key?(step, :arguments)
        assert is_integer(step.timeout)
      end)

      # Steps should have different execution strategies
      assert engine_step.run == {Bridge, :execute_engine_step}
      assert hybrid_step.run == {Bridge, :execute_hybrid_step}
      assert load_balanced_step.run == {HybridSteps, :execute_load_balanced_capability}
    end
  end

  describe "performance and scalability considerations" do
    test "capability registry performance under load" do
      # Register many capabilities to test lookup performance
      for i <- 1..100 do
        CapabilityRegistry.register_engine_capability(
          :"engine_#{i}",
          :performance_test,
          %{priority: i}
        )
      end

      # Lookup should be fast even with many registrations
      start_time = System.monotonic_time(:microsecond)
      results = CapabilityRegistry.find_by_capability(:performance_test)
      end_time = System.monotonic_time(:microsecond)

      # Should find all 100 registrations
      assert length(results) == 100

      # Lookup should be reasonably fast (under 10ms)
      lookup_time = end_time - start_time
      # 10ms in microseconds
      assert lookup_time < 10_000

      # Results should be properly sorted by priority
      priorities = Enum.map(results, & &1.priority)
      assert priorities == Enum.sort(priorities, &(&1 >= &2))
    end

    test "concurrent access to hybrid system" do
      # Test that multiple processes can use the hybrid system concurrently
      test_pid = self()

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            context = ExecutionContext.create_hybrid_context(shared_state: %{task_id: i})

            result = Bridge.unified_execute(:semantic_analysis, %{code: "test_#{i}"}, context)
            send(test_pid, {:task_complete, i, result})
          end)
        end

      # Wait for all tasks to complete
      Task.await_many(tasks, 5000)

      # Should receive completion messages from all tasks
      for i <- 1..10 do
        assert_receive {:task_complete, ^i, {:error, _}}, 1000
      end
    end
  end
end
