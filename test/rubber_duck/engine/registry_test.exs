defmodule RubberDuck.Engine.CapabilityRegistryTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Engine.CapabilityRegistry, as: Registry
  alias RubberDuck.EngineSystem.Engine, as: EngineConfig
  alias RubberDuck.Engine.ServerTest.TestEngine

  setup do
    # Clean up registry state
    engines = Registry.list_engines()

    Enum.each(engines, fn engine ->
      Registry.unregister_engine(engine.name)
    end)

    engine_config = %EngineConfig{
      name: :registry_test_engine,
      module: TestEngine,
      description: "Registry test engine",
      priority: 50,
      timeout: 1000,
      config: []
    }

    {:ok, engine_config: engine_config}
  end

  describe "register_engine/1" do
    test "registers engine with capabilities", %{engine_config: config} do
      assert :ok = Registry.register_engine(config)

      engines = Registry.list_engines()
      assert config in engines

      capabilities = Registry.list_capabilities()
      assert :test in capabilities
      assert :echo in capabilities
    end

    test "handles duplicate registrations", %{engine_config: config} do
      assert :ok = Registry.register_engine(config)
      assert :ok = Registry.register_engine(config)

      # Should not duplicate in lists
      engines = Registry.list_engines()
      assert length(engines) == 1
    end
  end

  describe "unregister_engine/1" do
    test "removes engine from registry", %{engine_config: config} do
      Registry.register_engine(config)
      assert :ok = Registry.unregister_engine(config.name)

      engines = Registry.list_engines()
      assert engines == []
    end

    test "cleans up capabilities", %{engine_config: config} do
      Registry.register_engine(config)

      # Register another engine with different capabilities
      config2 = %{config | name: :other_engine, module: OtherTestEngine}

      defmodule OtherTestEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}
        def execute(_, state), do: {:ok, state}
        def capabilities, do: [:other]
      end

      Registry.register_engine(config2)

      # Start the second engine
      {:ok, _pid2} = RubberDuck.Engine.Supervisor.start_engine(config2)

      # Remove first engine
      Registry.unregister_engine(config.name)

      # Test and echo capabilities should be gone
      by_test = Registry.find_by_capability(:test)
      assert by_test == []

      by_echo = Registry.find_by_capability(:echo)
      assert by_echo == []

      # Other capability should remain
      by_other = Registry.find_by_capability(:other)
      assert length(by_other) == 1

      # Clean up
      RubberDuck.Engine.Supervisor.stop_engine(config2.name)
    end

    test "returns error for non-existent engine" do
      assert {:error, :not_found} = Registry.unregister_engine(:nonexistent)
    end
  end

  describe "find_by_capability/1" do
    test "finds engines with capability", %{engine_config: config} do
      Registry.register_engine(config)

      # Start the engine so it's considered "running"
      {:ok, _pid} = RubberDuck.Engine.Supervisor.start_engine(config)

      engines = Registry.find_by_capability(:test)
      assert length(engines) == 1
      assert hd(engines).name == config.name

      engines = Registry.find_by_capability(:echo)
      assert length(engines) == 1

      engines = Registry.find_by_capability(:nonexistent)
      assert engines == []

      RubberDuck.Engine.Supervisor.stop_engine(config.name)
    end

    test "only returns running engines", %{engine_config: config} do
      Registry.register_engine(config)

      # Don't start the engine
      engines = Registry.find_by_capability(:test)
      assert engines == []
    end
  end

  describe "get_engine/1" do
    test "returns engine config by name", %{engine_config: config} do
      Registry.register_engine(config)

      found = Registry.get_engine(config.name)
      assert found == config

      assert Registry.get_engine(:nonexistent) == nil
    end
  end

  describe "list_capabilities/0" do
    test "lists all unique capabilities" do
      config1 = %EngineConfig{
        name: :engine1,
        module: TestEngine,
        description: "Engine 1",
        priority: 50,
        timeout: 1000,
        config: []
      }

      config2 = %EngineConfig{
        name: :engine2,
        module: TestEngine,
        description: "Engine 2",
        priority: 50,
        timeout: 1000,
        config: []
      }

      Registry.register_engine(config1)
      Registry.register_engine(config2)

      capabilities = Registry.list_capabilities()
      assert :test in capabilities
      assert :echo in capabilities
      assert length(capabilities) == 2
    end
  end
end
