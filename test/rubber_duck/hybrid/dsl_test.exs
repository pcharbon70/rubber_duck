defmodule RubberDuck.Hybrid.DSLTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Hybrid.{DSL, CapabilityRegistry}

  # Create a test module using the hybrid DSL
  defmodule TestHybridModule do
    use RubberDuck.Hybrid.DSL, otp_app: :rubber_duck

    # Simplified hybrid configuration for testing
    hybrid do
      # Basic configuration - detailed parsing would be implemented in full version
      []
    end
  end

  setup do
    start_supervised!(CapabilityRegistry)
    :ok
  end

  describe "DSL compilation" do
    test "compiles hybrid configuration without errors" do
      # If this test passes, it means the DSL compiled successfully
      assert function_exported?(TestHybridModule, :start_hybrid_system, 0)
      assert function_exported?(TestHybridModule, :stop_hybrid_system, 0)
      assert function_exported?(TestHybridModule, :__hybrid_config__, 0)
    end

    test "provides hybrid configuration access" do
      config = TestHybridModule.__hybrid_config__()
      assert is_map(config) or is_list(config)
    end
  end

  describe "system setup and teardown" do
    test "sets up hybrid system and registers sample capabilities" do
      # Setup the hybrid system
      :ok = TestHybridModule.start_hybrid_system()

      # Check that sample capabilities were registered
      capabilities = CapabilityRegistry.list_capabilities()

      # Should have some registered capabilities
      assert length(capabilities) > 0

      # Cleanup
      TestHybridModule.stop_hybrid_system()
    end

    test "teardown completes without errors" do
      # Setup first
      :ok = TestHybridModule.start_hybrid_system()

      # Teardown should work
      :ok = TestHybridModule.stop_hybrid_system()
    end
  end

  describe "configuration validation" do
    test "validates configuration successfully" do
      assert :ok = DSL.validate_configuration(TestHybridModule)
    end
  end

  describe "helper functions" do
    test "gets capabilities for module" do
      :ok = TestHybridModule.start_hybrid_system()

      capabilities = DSL.get_capabilities(TestHybridModule)
      assert is_list(capabilities)

      TestHybridModule.stop_hybrid_system()
    end

    test "gets capability configuration" do
      :ok = TestHybridModule.start_hybrid_system()

      # Try to get configuration for a registered capability
      capabilities = CapabilityRegistry.list_capabilities()

      if length(capabilities) > 0 do
        capability = hd(capabilities)
        config = DSL.get_capability_config(TestHybridModule, capability)
        assert is_map(config) or is_nil(config)
      end

      # Non-existent capability should return nil
      config = DSL.get_capability_config(TestHybridModule, :nonexistent)
      assert is_nil(config)

      TestHybridModule.stop_hybrid_system()
    end
  end

  describe "DSL entity extraction" do
    test "extracts engines (simplified)" do
      {:ok, engines} = DSL.get_dsl_engines(TestHybridModule)
      assert is_list(engines)
    end

    test "extracts workflows (simplified)" do
      {:ok, workflows} = DSL.get_dsl_workflows(TestHybridModule)
      assert is_list(workflows)
    end

    test "extracts bridges (simplified)" do
      {:ok, bridges} = DSL.get_dsl_bridges(TestHybridModule)
      assert is_list(bridges)
    end
  end

  describe "error handling" do
    test "handles missing DSL sections gracefully" do
      defmodule EmptyModule do
        use RubberDuck.Hybrid.DSL, otp_app: :rubber_duck

        # No hybrid configuration
      end

      assert :ok = DSL.validate_configuration(EmptyModule)
      assert :ok = DSL.setup_hybrid_system(EmptyModule)
      assert :ok = DSL.teardown_hybrid_system(EmptyModule)
    end

    test "handles setup and teardown for modules without configuration" do
      defmodule MinimalModule do
        use RubberDuck.Hybrid.DSL, otp_app: :rubber_duck
      end

      # Should work even without hybrid block
      result = DSL.setup_hybrid_system(MinimalModule)
      assert result == :ok

      result = DSL.teardown_hybrid_system(MinimalModule)
      assert result == :ok
    end
  end

  describe "parser functions" do
    test "parser functions handle basic inputs" do
      # Test the parser functions directly
      result = DSL.parse_hybrid_block(nil)
      assert is_map(result)

      result = DSL.parse_engines_block(nil)
      assert is_list(result)

      result = DSL.parse_workflows_block(nil)
      assert is_list(result)

      result = DSL.parse_engine_block(:test, nil)
      assert is_map(result)
      assert result.name == :test

      result = DSL.parse_workflow_block(:test, nil)
      assert is_map(result)
      assert result.name == :test

      result = DSL.parse_bridge_block(:test, nil)
      assert is_map(result)
      assert result.name == :test
    end
  end

  describe "integration with capability registry" do
    test "can register and query capabilities after setup" do
      :ok = TestHybridModule.start_hybrid_system()

      # Should have some capabilities registered
      all_capabilities = CapabilityRegistry.list_capabilities()
      assert length(all_capabilities) > 0

      # Should be able to find registrations by type
      engines = CapabilityRegistry.find_by_type(:engine)
      workflows = CapabilityRegistry.find_by_type(:workflow)
      hybrids = CapabilityRegistry.find_by_type(:hybrid)

      # Should have at least some registrations
      total_registrations = length(engines) + length(workflows) + length(hybrids)
      assert total_registrations > 0

      TestHybridModule.stop_hybrid_system()
    end
  end
end
