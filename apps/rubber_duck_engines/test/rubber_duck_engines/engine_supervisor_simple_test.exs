defmodule RubberDuckEngines.EngineSupervisorSimpleTest do
  use ExUnit.Case, async: false

  alias RubberDuckEngines.EngineSupervisor

  # Create a simple test engine for testing purposes
  defmodule TestEngine do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
    end

    def init(opts) do
      # Register with the engines registry
      Registry.register(RubberDuckEngines.Registry, __MODULE__, %{})
      {:ok, opts}
    end

    def handle_call(:capabilities, _from, state) do
      {:reply, [%{input_types: [:test], output_type: :test}], state}
    end

    def handle_call(_, _from, state) do
      {:reply, :ok, state}
    end
  end

  describe "DynamicSupervisor functionality" do
    test "can start and stop engines" do
      config = %{test_mode: true}

      # Start engine
      assert {:ok, pid} = EngineSupervisor.start_engine(TestEngine, config)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Stop engine
      assert :ok = EngineSupervisor.stop_engine(TestEngine)

      # Give it a moment to terminate
      Process.sleep(10)

      # Verify it's no longer registered
      assert [] = Registry.lookup(RubberDuckEngines.Registry, TestEngine)
    end

    test "can list running engines" do
      config = %{test_mode: true}

      # Get initial count
      initial_engines = EngineSupervisor.list_engines()
      initial_count = length(initial_engines)

      # Start an engine
      {:ok, _pid} = EngineSupervisor.start_engine(TestEngine, config)

      # List engines should include our new one
      engines = EngineSupervisor.list_engines()
      assert length(engines) > initial_count

      # Clean up
      EngineSupervisor.stop_engine(TestEngine)
    end

    test "can get engine count" do
      count_info = EngineSupervisor.engine_count()

      assert Map.has_key?(count_info, :workers)
      assert is_integer(count_info.workers)
    end

    test "can check if engine is running" do
      config = %{test_mode: true}

      # Initially not running
      assert EngineSupervisor.engine_running?(TestEngine) == false

      # Start engine
      {:ok, _pid} = EngineSupervisor.start_engine(TestEngine, config)

      # Now it should be running
      assert EngineSupervisor.engine_running?(TestEngine) == true

      # Clean up
      EngineSupervisor.stop_engine(TestEngine)

      # Should not be running anymore
      assert EngineSupervisor.engine_running?(TestEngine) == false
    end

    test "emits telemetry events" do
      config = %{test_mode: true}

      # Attach telemetry handler
      :telemetry.attach(
        "test-engine-lifecycle",
        [:rubber_duck_engines, :engine_supervisor, :engine_started],
        fn event, measurements, metadata, _ ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Start engine
      {:ok, _pid} = EngineSupervisor.start_engine(TestEngine, config)

      # Should receive telemetry event
      assert_receive {:telemetry, [:rubber_duck_engines, :engine_supervisor, :engine_started],
                      measurements, metadata}

      assert metadata.engine == TestEngine
      assert is_pid(metadata.pid)
      assert is_integer(measurements.start_time)

      # Clean up
      :telemetry.detach("test-engine-lifecycle")
      EngineSupervisor.stop_engine(TestEngine)
    end

    test "handles already started engines gracefully" do
      config = %{test_mode: true}

      # Start engine first time
      assert {:ok, pid1} = EngineSupervisor.start_engine(TestEngine, config)

      # Start same engine again - should return same pid
      assert {:ok, pid2} = EngineSupervisor.start_engine(TestEngine, config)
      assert pid1 == pid2

      # Clean up
      EngineSupervisor.stop_engine(TestEngine)
    end

    test "handles stopping non-existent engines" do
      assert {:error, :not_found} = EngineSupervisor.stop_engine(:non_existent_engine)
    end
  end

  # Cleanup after each test
  setup do
    on_exit(fn ->
      # Stop test engine if it's running
      if EngineSupervisor.engine_running?(TestEngine) do
        EngineSupervisor.stop_engine(TestEngine)
      end
    end)
  end
end
