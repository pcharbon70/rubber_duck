defmodule RubberDuck.Engine.ManagerTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Engine.Manager
  alias RubberDuck.EngineSystem.Engine, as: EngineConfig
  alias RubberDuck.Engine.ServerTest.TestEngine

  # Test engines module
  defmodule TestEngines do
    use RubberDuck.EngineSystem

    engines do
      engine :manager_test1 do
        module RubberDuck.Engine.ServerTest.TestEngine
        description "Manager test engine 1"
        priority(100)
        timeout 2000
      end

      engine :manager_test2 do
        module RubberDuck.Engine.ServerTest.TestEngine
        description "Manager test engine 2"
        priority(50)
        timeout 1000
      end
    end
  end

  setup do
    # Clean up any running engines
    engines = Manager.list_engines()

    Enum.each(engines, fn {name, _pid} ->
      Manager.stop_engine(name)
    end)

    # Clean up registry
    RubberDuck.Engine.CapabilityRegistry.list_engines()
    |> Enum.each(fn engine ->
      RubberDuck.Engine.CapabilityRegistry.unregister_engine(engine.name)
    end)

    :ok
  end

  describe "load_engines/1" do
    test "loads engines from DSL module" do
      assert :ok = Manager.load_engines(TestEngines)

      engines = Manager.list_engines()
      assert length(engines) == 2

      names = Enum.map(engines, fn {name, _} -> name end)
      assert :manager_test1 in names
      assert :manager_test2 in names
    end

    test "handles partial failures" do
      # Create a module with a failing engine
      defmodule FailingTestEngines do
        use RubberDuck.EngineSystem

        engines do
          engine :good_engine do
            module RubberDuck.Engine.ServerTest.TestEngine
            description "Good engine"
          end

          engine :bad_engine do
            module NonExistentModule
            description "Bad engine"
          end
        end
      end

      {:error, failures} = Manager.load_engines(FailingTestEngines)
      assert length(failures) == 1

      # Good engine should still be loaded
      engines = Manager.list_engines()
      names = Enum.map(engines, fn {name, _} -> name end)
      assert :good_engine in names
    end
  end

  describe "start_engine/1" do
    test "starts individual engine" do
      config = %EngineConfig{
        name: :individual_test,
        module: TestEngine,
        description: "Individual test",
        priority: 50,
        timeout: 1000,
        config: []
      }

      assert {:ok, pid} = Manager.start_engine(config)
      assert Process.alive?(pid)

      Manager.stop_engine(config.name)
    end

    test "handles already started engines" do
      config = %EngineConfig{
        name: :duplicate_test,
        module: TestEngine,
        description: "Duplicate test",
        priority: 50,
        timeout: 1000,
        config: []
      }

      {:ok, pid1} = Manager.start_engine(config)
      {:ok, pid2} = Manager.start_engine(config)

      assert pid1 == pid2

      Manager.stop_engine(config.name)
    end
  end

  describe "execute/3" do
    setup do
      Manager.load_engines(TestEngines)
      :ok
    end

    test "executes on specific engine" do
      assert {:ok, "Hello"} =
               Manager.execute(:manager_test1, %{
                 command: "echo",
                 text: "Hello"
               })
    end

    test "returns error for non-existent engine" do
      assert {:error, :engine_not_found} = Manager.execute(:nonexistent, %{})
    end

    test "respects timeout" do
      assert {:error, :timeout} =
               Manager.execute(
                 :manager_test1,
                 %{command: "sleep", duration: 3000},
                 1000
               )
    end
  end

  describe "execute_by_capability/3" do
    setup do
      Manager.load_engines(TestEngines)
      :ok
    end

    test "executes on engine with capability" do
      assert {:ok, "Test"} =
               Manager.execute_by_capability(:echo, %{
                 command: "echo",
                 text: "Test"
               })
    end

    test "returns error when no engine has capability" do
      assert {:error, :no_engine_with_capability} =
               Manager.execute_by_capability(:nonexistent, %{})
    end

    test "supports different selection strategies" do
      # First strategy
      assert {:ok, _} =
               Manager.execute_by_capability(
                 :test,
                 %{command: "echo", text: "test"},
                 strategy: :first
               )

      # Random strategy
      assert {:ok, _} =
               Manager.execute_by_capability(
                 :test,
                 %{command: "echo", text: "test"},
                 strategy: :random
               )

      # Round-robin strategy
      assert {:ok, _} =
               Manager.execute_by_capability(
                 :test,
                 %{command: "echo", text: "test"},
                 strategy: :round_robin
               )
    end
  end

  describe "lifecycle management" do
    test "stop_engine/1" do
      Manager.load_engines(TestEngines)

      assert :ok = Manager.stop_engine(:manager_test1)

      engines = Manager.list_engines()
      names = Enum.map(engines, fn {name, _} -> name end)
      refute :manager_test1 in names
    end

    test "restart_engine/1" do
      Manager.load_engines(TestEngines)

      # Get original pid
      [{_, old_pid}] =
        Manager.list_engines()
        |> Enum.filter(fn {name, _} -> name == :manager_test1 end)

      assert {:ok, new_pid} = Manager.restart_engine(:manager_test1)
      assert new_pid != old_pid
      refute Process.alive?(old_pid)
      assert Process.alive?(new_pid)
    end
  end

  describe "status and health" do
    setup do
      Manager.load_engines(TestEngines)
      :ok
    end

    test "status/1 returns engine status" do
      status = Manager.status(:manager_test1)

      assert status.engine == :manager_test1
      assert status.status == :ready
      assert status.request_count == 0
      assert status.error_count == 0
    end

    test "health_status/1 returns health" do
      assert :healthy = Manager.health_status(:manager_test1)
      assert :not_found = Manager.health_status(:nonexistent)
    end
  end

  describe "discovery functions" do
    setup do
      Manager.load_engines(TestEngines)
      :ok
    end

    test "list_capabilities/0" do
      capabilities = Manager.list_capabilities()
      assert :test in capabilities
      assert :echo in capabilities
    end

    test "find_engines_by_capability/1" do
      engines = Manager.find_engines_by_capability(:test)
      assert length(engines) == 2

      names = Enum.map(engines, & &1.name)
      assert :manager_test1 in names
      assert :manager_test2 in names
    end
  end

  describe "stats/0" do
    test "returns aggregate statistics" do
      Manager.load_engines(TestEngines)

      stats = Manager.stats()

      assert stats.total_engines == 2
      assert Map.has_key?(stats.engines, :manager_test1)
      assert Map.has_key?(stats.engines, :manager_test2)
      assert :test in stats.capabilities
      assert :echo in stats.capabilities
    end
  end
end
