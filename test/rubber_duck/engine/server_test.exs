defmodule RubberDuck.Engine.ServerTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Engine.Server
  alias RubberDuck.EngineSystem.Engine, as: EngineConfig

  # Test engine implementation
  defmodule TestEngine do
    @behaviour RubberDuck.Engine

    @impl true
    def init(config) do
      {:ok, Map.new(config)}
    end

    @impl true
    def execute(%{command: "echo"} = input, _state) do
      result = Map.get(input, :text, "")
      {:ok, result}
    end

    def execute(%{command: "error"}, _state) do
      {:error, "Intentional error"}
    end

    def execute(%{command: "crash"}, _state) do
      raise "Intentional crash"
    end

    def execute(%{command: "sleep", duration: duration}, _state) do
      Process.sleep(duration)
      {:ok, :slept}
    end

    def execute(_input, _state) do
      {:error, "Unknown command"}
    end

    @impl true
    def capabilities do
      [:test, :echo]
    end
  end

  setup do
    engine_config = %EngineConfig{
      name: :test_engine,
      module: TestEngine,
      description: "Test engine",
      priority: 50,
      timeout: 1000,
      config: [test_mode: true]
    }

    {:ok, engine_config: engine_config}
  end

  describe "start_link/2" do
    test "starts engine server successfully", %{engine_config: config} do
      assert {:ok, pid} = Server.start_link(config, name: :test_server)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "initializes engine state", %{engine_config: config} do
      {:ok, pid} = Server.start_link(config, name: :test_server_init)

      status = Server.status(pid)
      assert status.engine == :test_engine
      assert status.status == :ready
      assert status.request_count == 0
      assert status.error_count == 0

      GenServer.stop(pid)
    end
  end

  describe "execute/3" do
    setup %{engine_config: config} do
      {:ok, pid} = Server.start_link(config, name: :test_server_exec)
      on_exit(fn -> GenServer.stop(pid) end)
      {:ok, server: pid}
    end

    test "executes successful requests", %{server: server} do
      assert {:ok, "Hello"} = Server.execute(server, %{command: "echo", text: "Hello"})

      status = Server.status(server)
      assert status.request_count == 1
      assert status.error_count == 0
    end

    test "handles error responses", %{server: server} do
      assert {:error, "Intentional error"} = Server.execute(server, %{command: "error"})

      status = Server.status(server)
      assert status.request_count == 1
      assert status.error_count == 1
    end

    test "handles crashes gracefully", %{server: server} do
      assert {:error, _} = Server.execute(server, %{command: "crash"})

      # Server should still be alive
      assert Process.alive?(server)

      status = Server.status(server)
      assert status.request_count == 1
      assert status.error_count == 1
    end

    test "enforces timeout", %{server: server} do
      assert {:error, :timeout} = Server.execute(server, %{command: "sleep", duration: 2000}, 100)

      status = Server.status(server)
      assert status.error_count == 1
    end
  end

  describe "health_check/1" do
    setup %{engine_config: config} do
      {:ok, pid} = Server.start_link(config, name: :test_server_health)
      on_exit(fn -> GenServer.stop(pid) end)
      {:ok, server: pid}
    end

    test "returns health status", %{server: server} do
      assert :healthy = Server.health_check(server)

      status = Server.status(server)
      assert status.last_health_check != nil
    end
  end

  describe "telemetry events" do
    setup %{engine_config: config} do
      # Attach telemetry handler
      :ok =
        :telemetry.attach(
          "test-handler",
          [:rubber_duck, :engine, :execute],
          fn event, measurements, metadata, _config ->
            send(self(), {:telemetry, event, measurements, metadata})
          end,
          nil
        )

      {:ok, pid} = Server.start_link(config, name: :test_server_telemetry)

      on_exit(fn ->
        GenServer.stop(pid)
        :telemetry.detach("test-handler")
      end)

      {:ok, server: pid}
    end

    test "emits telemetry events on execution", %{server: server} do
      Server.execute(server, %{command: "echo", text: "test"})

      assert_receive {:telemetry, [:rubber_duck, :engine, :execute], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.engine == :test_engine
      assert metadata.module == TestEngine
      assert metadata.status == :success
    end
  end
end
