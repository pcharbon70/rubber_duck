defmodule RubberDuck.EngineIntegrationTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Engine.Manager
  alias RubberDuck.EngineSystem
  alias RubberDuck.ExampleEngines

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

  describe "end-to-end engine system" do
    test "loading and using example engines" do
      # Load the example engines
      assert :ok = Manager.load_engines(ExampleEngines)

      # Verify engines are loaded
      engines = Manager.list_engines()
      assert length(engines) == 2

      # Test echo engine
      assert {:ok, "[ECHO] Hello World"} =
               Manager.execute(:echo, %{
                 text: "Hello World"
               })

      # Test reverse engine
      assert {:ok, "dlroW olleH"} =
               Manager.execute(:reverse, %{
                 text: "Hello World"
               })

      # Test capability-based execution
      assert {:ok, _result} =
               Manager.execute_by_capability(:text_processing, %{
                 text: "Test"
               })

      # Check engine status
      status = Manager.status(:echo)
      assert status.engine == :echo
      assert status.status == :ready
      assert status.request_count > 0

      # Test health check
      assert :healthy = Manager.health_status(:echo)

      # List capabilities
      capabilities = Manager.list_capabilities()
      assert :echo in capabilities
      assert :reverse in capabilities
      assert :text_processing in capabilities

      # Find engines by capability
      text_engines = Manager.find_engines_by_capability(:text_processing)
      assert length(text_engines) == 2

      # Test error handling
      assert {:error, "Missing required :text key in input"} =
               Manager.execute(:echo, %{invalid: "data"})

      # Test stats
      stats = Manager.stats()
      assert stats.total_engines == 2
      assert Map.has_key?(stats.engines, :echo)
      assert Map.has_key?(stats.engines, :reverse)
    end

    test "engine lifecycle management" do
      Manager.load_engines(ExampleEngines)

      # Stop an engine
      assert :ok = Manager.stop_engine(:echo)

      # Verify it's stopped
      assert {:error, :engine_not_found} = Manager.execute(:echo, %{text: "test"})

      # Restart it
      assert {:ok, _pid} = Manager.restart_engine(:echo)

      # Verify it works again
      assert {:ok, "[ECHO] test"} = Manager.execute(:echo, %{text: "test"})
    end
  end
end
