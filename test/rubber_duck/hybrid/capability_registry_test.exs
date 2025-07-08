defmodule RubberDuck.Hybrid.CapabilityRegistryTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Hybrid.CapabilityRegistry

  setup do
    # Start the registry for each test
    start_supervised!(CapabilityRegistry)
    :ok
  end

  describe "register_engine_capability/3" do
    test "registers engine capability successfully" do
      assert :ok =
               CapabilityRegistry.register_engine_capability(
                 :test_engine,
                 :code_completion,
                 %{module: TestEngine, priority: 100}
               )
    end

    test "registers engine with workflow integration metadata" do
      :ok =
        CapabilityRegistry.register_engine_capability(
          :test_engine,
          :code_completion,
          %{module: TestEngine}
        )

      registration = CapabilityRegistry.find_by_id(:test_engine)
      assert registration.metadata.can_integrate_with_workflows == true
    end
  end

  describe "register_workflow_capability/3" do
    test "registers workflow capability successfully" do
      assert :ok =
               CapabilityRegistry.register_workflow_capability(
                 :test_workflow,
                 :code_analysis,
                 %{module: TestWorkflow, priority: 150}
               )
    end

    test "registers workflow with engine integration metadata" do
      :ok =
        CapabilityRegistry.register_workflow_capability(
          :test_workflow,
          :code_analysis,
          %{module: TestWorkflow}
        )

      registration = CapabilityRegistry.find_by_id(:test_workflow)
      assert registration.metadata.can_integrate_with_engines == true
    end
  end

  describe "register_hybrid_capability/3" do
    test "registers hybrid capability with higher default priority" do
      :ok =
        CapabilityRegistry.register_hybrid_capability(
          :test_hybrid,
          :full_analysis,
          %{module: TestHybrid}
        )

      registration = CapabilityRegistry.find_by_id(:test_hybrid)
      assert registration.priority == 150
      assert registration.type == :hybrid
    end
  end

  describe "find_by_capability/2" do
    setup do
      CapabilityRegistry.register_engine_capability(
        :engine1,
        :code_completion,
        %{priority: 100}
      )

      CapabilityRegistry.register_workflow_capability(
        :workflow1,
        :code_completion,
        %{priority: 80}
      )

      CapabilityRegistry.register_hybrid_capability(
        :hybrid1,
        :code_completion,
        %{priority: 120}
      )

      :ok
    end

    test "finds all registrations for capability sorted by priority" do
      results = CapabilityRegistry.find_by_capability(:code_completion)

      assert length(results) == 3
      # Should be sorted by priority (highest first)
      # hybrid default priority
      assert hd(results).priority == 150
    end

    test "filters by type when specified" do
      engine_results = CapabilityRegistry.find_by_capability(:code_completion, :engine)
      workflow_results = CapabilityRegistry.find_by_capability(:code_completion, :workflow)

      assert length(engine_results) == 1
      assert hd(engine_results).type == :engine

      assert length(workflow_results) == 1
      assert hd(workflow_results).type == :workflow
    end

    test "returns empty list for unknown capability" do
      results = CapabilityRegistry.find_by_capability(:unknown_capability)
      assert results == []
    end
  end

  describe "find_best_for_capability/2" do
    setup do
      CapabilityRegistry.register_engine_capability(
        :low_priority_engine,
        :code_completion,
        %{priority: 50}
      )

      CapabilityRegistry.register_engine_capability(
        :high_priority_engine,
        :code_completion,
        %{priority: 200}
      )

      :ok
    end

    test "returns highest priority registration" do
      result = CapabilityRegistry.find_best_for_capability(:code_completion)

      assert result.id == :high_priority_engine
      assert result.priority == 200
    end

    test "returns nil for unknown capability" do
      result = CapabilityRegistry.find_best_for_capability(:unknown_capability)
      assert is_nil(result)
    end

    test "respects type preference" do
      CapabilityRegistry.register_workflow_capability(
        :preferred_workflow,
        :code_completion,
        %{priority: 300}
      )

      result = CapabilityRegistry.find_best_for_capability(:code_completion, :engine)
      assert result.type == :engine
      assert result.id == :high_priority_engine
    end
  end

  describe "find_by_type/1" do
    setup do
      CapabilityRegistry.register_engine_capability(
        :engine1,
        :capability1,
        %{priority: 100}
      )

      CapabilityRegistry.register_engine_capability(
        :engine2,
        :capability2,
        %{priority: 80}
      )

      CapabilityRegistry.register_workflow_capability(
        :workflow1,
        :capability3,
        %{priority: 120}
      )

      :ok
    end

    test "finds all registrations of specific type" do
      engine_results = CapabilityRegistry.find_by_type(:engine)
      workflow_results = CapabilityRegistry.find_by_type(:workflow)

      assert length(engine_results) == 2
      assert length(workflow_results) == 1

      Enum.each(engine_results, fn result ->
        assert result.type == :engine
      end)

      Enum.each(workflow_results, fn result ->
        assert result.type == :workflow
      end)
    end

    test "results are sorted by priority" do
      results = CapabilityRegistry.find_by_type(:engine)

      priorities = Enum.map(results, & &1.priority)
      assert priorities == Enum.sort(priorities, &(&1 >= &2))
    end
  end

  describe "find_by_id/1" do
    test "finds registration by ID" do
      CapabilityRegistry.register_engine_capability(
        :test_engine,
        :test_capability,
        %{test: :metadata}
      )

      result = CapabilityRegistry.find_by_id(:test_engine)

      assert result.id == :test_engine
      assert result.capability == :test_capability
      assert result.metadata.test == :metadata
    end

    test "returns nil for unknown ID" do
      result = CapabilityRegistry.find_by_id(:unknown_id)
      assert is_nil(result)
    end
  end

  describe "list_capabilities/0" do
    test "lists all unique capabilities" do
      CapabilityRegistry.register_engine_capability(:engine1, :capability1, %{})
      # duplicate
      CapabilityRegistry.register_engine_capability(:engine2, :capability1, %{})
      CapabilityRegistry.register_workflow_capability(:workflow1, :capability2, %{})

      capabilities = CapabilityRegistry.list_capabilities()

      assert :capability1 in capabilities
      assert :capability2 in capabilities
      # no duplicates
      assert length(Enum.uniq(capabilities)) == length(capabilities)
    end
  end

  describe "list_all/0" do
    test "lists all registrations sorted by priority" do
      CapabilityRegistry.register_engine_capability(:engine1, :cap1, %{priority: 50})
      CapabilityRegistry.register_workflow_capability(:workflow1, :cap2, %{priority: 200})

      results = CapabilityRegistry.list_all()

      assert length(results) == 2
      priorities = Enum.map(results, & &1.priority)
      assert priorities == Enum.sort(priorities, &(&1 >= &2))
    end
  end

  describe "unregister/1" do
    test "unregisters entity and removes from all indexes" do
      CapabilityRegistry.register_engine_capability(:test_engine, :test_capability, %{})

      # Verify it's registered
      assert CapabilityRegistry.find_by_id(:test_engine)
      assert length(CapabilityRegistry.find_by_capability(:test_capability)) == 1

      # Unregister
      :ok = CapabilityRegistry.unregister(:test_engine)

      # Verify it's gone
      assert is_nil(CapabilityRegistry.find_by_id(:test_engine))
      assert CapabilityRegistry.find_by_capability(:test_capability) == []
    end

    test "unregistering unknown ID is safe" do
      assert :ok = CapabilityRegistry.unregister(:unknown_id)
    end
  end

  describe "update_metadata/2" do
    test "updates metadata for existing registration" do
      CapabilityRegistry.register_engine_capability(
        :test_engine,
        :test_capability,
        %{original: :metadata}
      )

      assert :ok =
               CapabilityRegistry.update_metadata(
                 :test_engine,
                 %{updated: :metadata}
               )

      registration = CapabilityRegistry.find_by_id(:test_engine)
      assert registration.metadata == %{updated: :metadata}
    end

    test "returns error for non-existent entity" do
      assert {:error, :not_found} =
               CapabilityRegistry.update_metadata(
                 :unknown_id,
                 %{test: :metadata}
               )
    end
  end

  describe "supports_capability?/2" do
    test "returns true for matching capability" do
      CapabilityRegistry.register_engine_capability(
        :test_engine,
        :test_capability,
        %{}
      )

      assert CapabilityRegistry.supports_capability?(:test_engine, :test_capability)
    end

    test "returns false for non-matching capability" do
      CapabilityRegistry.register_engine_capability(
        :test_engine,
        :test_capability,
        %{}
      )

      refute CapabilityRegistry.supports_capability?(:test_engine, :other_capability)
    end

    test "returns false for unknown entity" do
      refute CapabilityRegistry.supports_capability?(:unknown_engine, :any_capability)
    end
  end

  describe "find_hybrid_compatible/1" do
    setup do
      # Hybrid entity (always compatible)
      CapabilityRegistry.register_hybrid_capability(
        :hybrid1,
        :test_capability,
        %{}
      )

      # Engine with workflow integration
      CapabilityRegistry.register_engine_capability(
        :compatible_engine,
        :test_capability,
        %{can_integrate_with_workflows: true}
      )

      # Engine without workflow integration
      CapabilityRegistry.register_engine_capability(
        :incompatible_engine,
        :test_capability,
        %{can_integrate_with_workflows: false}
      )

      # Workflow with engine integration
      CapabilityRegistry.register_workflow_capability(
        :compatible_workflow,
        :test_capability,
        %{can_integrate_with_engines: true}
      )

      :ok
    end

    test "returns only hybrid-compatible entities" do
      results = CapabilityRegistry.find_hybrid_compatible(:test_capability)

      entity_ids = Enum.map(results, & &1.id)
      assert :hybrid1 in entity_ids
      assert :compatible_engine in entity_ids
      assert :compatible_workflow in entity_ids
      refute :incompatible_engine in entity_ids
    end

    test "returns empty list for unknown capability" do
      results = CapabilityRegistry.find_hybrid_compatible(:unknown_capability)
      assert results == []
    end
  end
end
