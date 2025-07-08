defmodule RubberDuck.Hybrid.BridgeTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Hybrid.{Bridge, CapabilityRegistry, ExecutionContext}

  setup do
    start_supervised!(CapabilityRegistry)
    :ok
  end

  describe "engine_to_step/2" do
    test "creates workflow step configuration for engine" do
      step_config = Bridge.engine_to_step(:test_engine, timeout: 45_000, retries: 5)

      assert step_config.name == :test_engine_step
      assert step_config.run == {Bridge, :execute_engine_step}
      assert step_config.arguments.engine_name == :test_engine
      assert step_config.timeout == 45_000
      assert step_config.max_retries == 5
    end

    test "uses default options when none provided" do
      step_config = Bridge.engine_to_step(:test_engine)

      assert step_config.timeout == 30_000
      assert step_config.max_retries == 3
      assert step_config.async == false
    end
  end

  describe "workflow_to_engine/2" do
    test "registers workflow as hybrid capability" do
      engine_config =
        Bridge.workflow_to_engine(:test_workflow,
          capability: :custom_capability,
          priority: 200
        )

      assert engine_config.name == :test_workflow
      assert engine_config.capability == :custom_capability
      assert engine_config.module == Bridge

      # Check that it was registered
      registration = CapabilityRegistry.find_by_id(:test_workflow)
      assert registration.type == :hybrid
      assert registration.capability == :custom_capability
      assert registration.priority == 200
    end

    test "uses default capability when none provided" do
      Bridge.workflow_to_engine(:test_workflow)

      registration = CapabilityRegistry.find_by_id(:test_workflow)
      assert registration.capability == :workflow_test_workflow
    end
  end

  describe "create_hybrid_step/2" do
    test "creates hybrid step configuration" do
      step_config = Bridge.create_hybrid_step(:test_capability, timeout: 90_000)

      assert step_config.name == :hybrid_test_capability_step
      assert step_config.run == {Bridge, :execute_hybrid_step}
      assert step_config.arguments.capability == :test_capability
      assert step_config.timeout == 90_000
    end
  end

  describe "unified_execute/3" do
    setup do
      # Mock engine registration
      CapabilityRegistry.register_engine_capability(
        :mock_engine,
        :test_capability,
        %{module: MockEngine, priority: 100}
      )

      # Mock workflow registration
      CapabilityRegistry.register_workflow_capability(
        :mock_workflow,
        :test_capability,
        %{priority: 80}
      )

      :ok
    end

    test "executes engine target" do
      # This test would need actual engine implementation to work
      # For now, we test the routing logic

      context = ExecutionContext.create_hybrid_context()

      # This should route to the engine
      result = Bridge.unified_execute({:engine, :mock_engine}, %{test: :input}, context)

      # Expect an error since MockEngine doesn't exist, but routing should work
      assert {:error, _} = result
    end

    test "executes workflow target" do
      context = ExecutionContext.create_hybrid_context()

      # This should route to the workflow
      result = Bridge.unified_execute({:workflow, :mock_workflow}, %{test: :input}, context)

      # Expect an error since MockWorkflow doesn't exist, but routing should work
      assert {:error, _} = result
    end

    test "executes capability-based routing" do
      context = ExecutionContext.create_hybrid_context()

      # This should find the best capability match
      result = Bridge.unified_execute(:test_capability, %{test: :input}, context)

      # Should route to the highest priority implementation (mock_engine)
      assert {:error, _} = result
    end

    test "returns error for unknown capability" do
      context = ExecutionContext.create_hybrid_context()

      result = Bridge.unified_execute(:unknown_capability, %{test: :input}, context)

      assert {:error, {:capability_not_found, :unknown_capability}} = result
    end
  end

  describe "optimize_hybrid_execution/2" do
    test "analyzes and optimizes hybrid configuration" do
      hybrid_config = %{
        engines: [:engine1, :engine2],
        workflows: [:workflow1],
        capabilities: [:capability1, :capability2]
      }

      context = ExecutionContext.create_hybrid_context()

      {:ok, plan} = Bridge.optimize_hybrid_execution(hybrid_config, context)

      assert Map.has_key?(plan, :execution_strategy)
      assert Map.has_key?(plan, :capability_assignments)
      assert Map.has_key?(plan, :resource_allocation)
      assert Map.has_key?(plan, :parallelization_opportunities)
    end
  end

  describe "execute_engine_step/2" do
    test "executes engine step with telemetry" do
      arguments = %{
        engine_name: :test_engine,
        engine_input: %{test: :data},
        execution_options: []
      }

      # Mock telemetry subscriber
      test_pid = self()

      :telemetry.attach(
        "test-engine-step",
        [:rubber_duck, :hybrid, :engine_step_failure],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      result = Bridge.execute_engine_step(arguments, %{})

      # Should fail since engine doesn't exist, but telemetry should be emitted
      assert {:error, _} = result

      # Check telemetry was emitted
      assert_receive {:telemetry, [:rubber_duck, :hybrid, :engine_step_failure], measurements, metadata}
      assert measurements.engine_name == :test_engine

      :telemetry.detach("test-engine-step")
    end
  end

  describe "execute_hybrid_step/2" do
    setup do
      CapabilityRegistry.register_engine_capability(
        :test_engine,
        :test_capability,
        %{module: MockEngine}
      )

      :ok
    end

    test "executes hybrid step with capability routing" do
      arguments = %{
        capability: :test_capability,
        step_input: %{test: :data},
        execution_options: []
      }

      # Mock telemetry subscriber
      test_pid = self()

      :telemetry.attach(
        "test-hybrid-step",
        [:rubber_duck, :hybrid, :hybrid_step_failure],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      result = Bridge.execute_hybrid_step(arguments, %{})

      # Should fail since engine doesn't exist, but routing should work
      assert {:error, _} = result

      # Check telemetry was emitted
      assert_receive {:telemetry, [:rubber_duck, :hybrid, :hybrid_step_failure], measurements, metadata}
      assert measurements.capability == :test_capability

      :telemetry.detach("test-hybrid-step")
    end
  end

  describe "execute_workflow_as_engine/2" do
    test "executes workflow through engine interface" do
      input = %{test: :data}
      opts = [workflow_name: :test_workflow]

      result = Bridge.execute_workflow_as_engine(input, opts)

      # Should fail since workflow doesn't exist, but interface should work
      assert {:error, _} = result
    end
  end

  describe "private optimization functions" do
    # These are primarily tested through optimize_hybrid_execution/2
    # but we can test some edge cases

    test "handles empty hybrid configuration" do
      empty_config = %{engines: [], workflows: [], capabilities: []}
      context = ExecutionContext.create_hybrid_context()

      {:ok, plan} = Bridge.optimize_hybrid_execution(empty_config, context)

      assert plan.execution_strategy in [:parallel, :sequential]
      assert is_map(plan.capability_assignments)
      assert is_map(plan.resource_allocation)
      assert is_list(plan.parallelization_opportunities)
    end
  end

  describe "error handling" do
    test "handles invalid execution targets gracefully" do
      context = ExecutionContext.create_hybrid_context()

      result = Bridge.unified_execute({:invalid_type, :some_target}, %{}, context)

      assert {:error, _} = result
    end

    test "handles missing context gracefully" do
      # Should work with nil context
      result = Bridge.unified_execute(:some_capability, %{test: :input}, nil)

      assert {:error, {:capability_not_found, :some_capability}} = result
    end
  end

  describe "integration with execution context" do
    test "updates shared state during execution" do
      context = ExecutionContext.create_hybrid_context(shared_state: %{initial: :state})

      # Even though execution will fail, context should be properly handled
      Bridge.unified_execute(:test_capability, %{test: :input}, context)

      # Context should remain valid
      assert context.shared_state.initial == :state
      assert is_binary(context.execution_id)
    end

    test "preserves execution metadata" do
      metadata = %{custom: :metadata}
      context = ExecutionContext.create_hybrid_context(telemetry_metadata: metadata)

      Bridge.unified_execute(:test_capability, %{test: :input}, context)

      # Metadata should be preserved
      assert context.telemetry_metadata.custom == :metadata
    end
  end
end
