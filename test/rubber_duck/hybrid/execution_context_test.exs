defmodule RubberDuck.Hybrid.ExecutionContextTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Hybrid.ExecutionContext

  describe "create_hybrid_context/1" do
    test "creates context with default values" do
      context = ExecutionContext.create_hybrid_context()

      assert is_binary(context.execution_id)
      assert context.engine_context == %{}
      assert context.workflow_context == %{}
      assert context.shared_state == %{}
      assert is_map(context.telemetry_metadata)
      assert context.resource_allocation == %{}
      assert %DateTime{} = context.started_at
      assert is_nil(context.parent_context)
    end

    test "creates context with provided options" do
      opts = [
        execution_id: "test-id",
        engine_context: %{test: :engine},
        workflow_context: %{test: :workflow},
        shared_state: %{test: :shared}
      ]

      context = ExecutionContext.create_hybrid_context(opts)

      assert context.execution_id == "test-id"
      assert context.engine_context == %{test: :engine}
      assert context.workflow_context == %{test: :workflow}
      assert context.shared_state == %{test: :shared}
    end

    test "generates unique execution IDs" do
      context1 = ExecutionContext.create_hybrid_context()
      context2 = ExecutionContext.create_hybrid_context()

      assert context1.execution_id != context2.execution_id
    end
  end

  describe "merge_contexts/2" do
    test "merges engine and workflow contexts" do
      engine_context = %{engine_data: "test", shared_state: %{from_engine: true}}
      workflow_context = %{workflow_data: "test", shared_state: %{from_workflow: true}}

      context = ExecutionContext.merge_contexts(engine_context, workflow_context)

      assert context.engine_context == engine_context
      assert context.workflow_context == workflow_context
      assert context.shared_state == %{from_engine: true, from_workflow: true}
    end

    test "merges telemetry metadata from both contexts" do
      engine_context = %{telemetry_metadata: %{engine_metric: 1}}
      workflow_context = %{telemetry_metadata: %{workflow_metric: 2}}

      context = ExecutionContext.merge_contexts(engine_context, workflow_context)

      assert context.telemetry_metadata.engine_metric == 1
      assert context.telemetry_metadata.workflow_metric == 2
      assert Map.has_key?(context.telemetry_metadata, :merged_at)
      assert context.telemetry_metadata.execution_type == :hybrid
    end
  end

  describe "update_engine_context/2" do
    test "updates engine context" do
      context = ExecutionContext.create_hybrid_context()
      new_engine_context = %{updated: true}

      updated_context = ExecutionContext.update_engine_context(context, new_engine_context)

      assert updated_context.engine_context == new_engine_context
      assert updated_context.workflow_context == context.workflow_context
    end
  end

  describe "update_workflow_context/2" do
    test "updates workflow context" do
      context = ExecutionContext.create_hybrid_context()
      new_workflow_context = %{updated: true}

      updated_context = ExecutionContext.update_workflow_context(context, new_workflow_context)

      assert updated_context.workflow_context == new_workflow_context
      assert updated_context.engine_context == context.engine_context
    end
  end

  describe "update_shared_state/2" do
    test "merges with existing shared state" do
      context = ExecutionContext.create_hybrid_context(shared_state: %{existing: :data})

      updated_context = ExecutionContext.update_shared_state(context, %{new: :data})

      assert updated_context.shared_state == %{existing: :data, new: :data}
    end

    test "overwrites existing keys" do
      context = ExecutionContext.create_hybrid_context(shared_state: %{key: :old_value})

      updated_context = ExecutionContext.update_shared_state(context, %{key: :new_value})

      assert updated_context.shared_state == %{key: :new_value}
    end
  end

  describe "add_telemetry_metadata/2" do
    test "merges with existing telemetry metadata" do
      context = ExecutionContext.create_hybrid_context()
      original_metadata = context.telemetry_metadata

      updated_context = ExecutionContext.add_telemetry_metadata(context, %{custom: :metric})

      expected_metadata = Map.merge(original_metadata, %{custom: :metric})
      assert updated_context.telemetry_metadata == expected_metadata
    end
  end

  describe "create_child_context/2" do
    test "creates child context with parent reference" do
      parent_context = ExecutionContext.create_hybrid_context(shared_state: %{parent: :data})

      child_context = ExecutionContext.create_child_context(parent_context)

      assert child_context.parent_context == parent_context
      assert child_context.shared_state == %{parent: :data}
      assert child_context.execution_id != parent_context.execution_id
    end

    test "can override shared state in child" do
      parent_context = ExecutionContext.create_hybrid_context(shared_state: %{parent: :data})

      child_context =
        ExecutionContext.create_child_context(parent_context,
          shared_state: %{child: :data}
        )

      assert child_context.shared_state == %{child: :data}
    end
  end

  describe "extract_engine_context/1" do
    test "extracts engine context with additional data" do
      context =
        ExecutionContext.create_hybrid_context(
          engine_context: %{engine_specific: :data},
          shared_state: %{shared: :data}
        )

      engine_context = ExecutionContext.extract_engine_context(context)

      assert engine_context.engine_specific == :data
      assert engine_context.execution_id == context.execution_id
      assert engine_context.shared_state == %{shared: :data}
      assert Map.has_key?(engine_context, :telemetry_metadata)
    end
  end

  describe "extract_workflow_context/1" do
    test "extracts workflow context with additional data" do
      context =
        ExecutionContext.create_hybrid_context(
          workflow_context: %{workflow_specific: :data},
          shared_state: %{shared: :data}
        )

      workflow_context = ExecutionContext.extract_workflow_context(context)

      assert workflow_context.workflow_specific == :data
      assert workflow_context.execution_id == context.execution_id
      assert workflow_context.shared_state == %{shared: :data}
      assert Map.has_key?(workflow_context, :telemetry_metadata)
    end
  end

  describe "execution_duration/1" do
    test "calculates execution duration" do
      context = ExecutionContext.create_hybrid_context()

      # Sleep a small amount to ensure duration > 0
      Process.sleep(10)

      duration = ExecutionContext.execution_duration(context)

      assert is_integer(duration)
      assert duration > 0
    end
  end

  describe "has_parent?/1" do
    test "returns false for root context" do
      context = ExecutionContext.create_hybrid_context()

      refute ExecutionContext.has_parent?(context)
    end

    test "returns true for child context" do
      parent_context = ExecutionContext.create_hybrid_context()
      child_context = ExecutionContext.create_child_context(parent_context)

      assert ExecutionContext.has_parent?(child_context)
    end
  end

  describe "get_root_context/1" do
    test "returns self for root context" do
      root_context = ExecutionContext.create_hybrid_context()

      assert ExecutionContext.get_root_context(root_context) == root_context
    end

    test "returns root for nested child contexts" do
      root_context = ExecutionContext.create_hybrid_context()
      child_context = ExecutionContext.create_child_context(root_context)
      grandchild_context = ExecutionContext.create_child_context(child_context)

      assert ExecutionContext.get_root_context(grandchild_context) == root_context
    end
  end
end
