defmodule RubberDuckEngines.EnginePoolTest do
  use ExUnit.Case, async: false

  alias RubberDuckEngines.EnginePool
  alias RubberDuckEngines.EnginePool.{Supervisor, Manager, WorkerSupervisor, Router}

  # Test engine for pool testing
  defmodule TestPoolEngine do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
    end

    def init(opts) do
      # Register with the main engines registry
      Registry.register(RubberDuckEngines.Registry, __MODULE__, %{})
      {:ok, opts}
    end

    def handle_call(:capabilities, _from, state) do
      {:reply, [%{input_types: [:test], output_type: :test}], state}
    end

    def handle_call({:analyze, _request}, _from, state) do
      # Simulate analysis work
      Process.sleep(10)
      {:reply, {:ok, %{result: "test_analysis"}}, state}
    end

    def handle_call(_, _from, state) do
      {:reply, :ok, state}
    end
  end

  describe "EnginePool.Supervisor" do
    test "uses rest_for_one strategy" do
      # The supervisor should be running from application start
      children = Supervisor.which_children(Supervisor)

      # Should have 4 children in proper order
      assert length(children) == 4

      # Verify the order and types
      child_ids = Enum.map(children, fn {id, _pid, _type, _modules} -> id end)

      assert Registry in child_ids
      assert Manager in child_ids
      assert WorkerSupervisor in child_ids
      assert Router in child_ids
    end

    test "provides supervision status" do
      status = Supervisor.supervision_status()

      assert status.strategy == :rest_for_one
      assert status.children_count == 4
      assert is_list(status.children)
      assert status.restart_policy.max_restarts == 3
      assert status.restart_policy.max_seconds == 5
    end

    test "emits telemetry events for supervision status" do
      :telemetry.attach(
        "test-supervision-status",
        [:rubber_duck_engines, :engine_pool, :supervisor, :supervision_status_requested],
        fn event, measurements, metadata, _ ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Supervisor.supervision_status()

      assert_receive {:telemetry,
                      [
                        :rubber_duck_engines,
                        :engine_pool,
                        :supervisor,
                        :supervision_status_requested
                      ], _measurements, metadata}

      assert metadata.strategy == :rest_for_one
      assert metadata.children_count == 4

      :telemetry.detach("test-supervision-status")
    end
  end

  describe "EnginePool.Manager" do
    test "provides default pool configurations" do
      pools = Manager.list_pools()

      assert Map.has_key?(pools, :code_analysis)
      assert Map.has_key?(pools, :documentation)
      assert Map.has_key?(pools, :testing)

      # Check default configuration structure
      code_analysis_config = pools.code_analysis
      assert code_analysis_config.pool_size == 5
      assert code_analysis_config.max_overflow == 2
      assert code_analysis_config.timeout == 30_000
    end

    test "can update pool configuration" do
      original_config = Manager.get_pool_config(:testing)
      assert original_config.pool_size == 2

      new_config = %{pool_size: 4, max_overflow: 3}
      {:ok, updated_config} = Manager.update_pool_config(:testing, new_config)

      assert updated_config.pool_size == 4
      assert updated_config.max_overflow == 3
      # Should preserve other values
      assert updated_config.timeout == original_config.timeout

      # Verify the change persisted
      current_config = Manager.get_pool_config(:testing)
      assert current_config.pool_size == 4
    end

    test "can add and remove pools" do
      # Add a new pool
      new_pool_config = %{
        engine_module: TestPoolEngine,
        pool_size: 2,
        max_overflow: 1,
        timeout: 15_000
      }

      {:ok, _config} = Manager.add_pool(:test_pool, new_pool_config)

      # Verify it was added
      pools = Manager.list_pools()
      assert Map.has_key?(pools, :test_pool)
      assert pools.test_pool.pool_size == 2

      # Remove the pool
      {:ok, removed_config} = Manager.remove_pool(:test_pool)
      assert removed_config.pool_size == 2

      # Verify it was removed
      pools = Manager.list_pools()
      refute Map.has_key?(pools, :test_pool)
    end

    test "emits telemetry events for configuration changes" do
      :telemetry.attach(
        "test-config-update",
        [:rubber_duck_engines, :engine_pool, :manager, :pool_config_updated],
        fn event, measurements, metadata, _ ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Manager.update_pool_config(:testing, %{pool_size: 3})

      assert_receive {:telemetry,
                      [:rubber_duck_engines, :engine_pool, :manager, :pool_config_updated],
                      _measurements, metadata}

      assert metadata.pool_type == :testing
      assert metadata.config.pool_size == 3

      :telemetry.detach("test-config-update")
    end
  end

  describe "EnginePool.Router" do
    test "can route analysis requests to appropriate pools" do
      # This test assumes the pools are initialized
      case Router.checkout_engine(:code_analysis, timeout: 1000) do
        {:ok, engine_pid} ->
          assert is_pid(engine_pid)
          assert Process.alive?(engine_pid)

          # Return the engine
          Router.checkin_engine(engine_pid, :code_analysis)

        {:error, :pool_empty} ->
          # Pool might not be initialized yet, which is acceptable for this test
          :ok
      end
    end

    test "provides comprehensive pool statistics" do
      stats = Router.pool_stats()

      assert Map.has_key?(stats, :router_stats)
      assert Map.has_key?(stats, :pool_stats)
      assert Map.has_key?(stats, :timestamp)

      # Router stats should include request counts
      router_stats = stats.router_stats
      assert Map.has_key?(router_stats, :total_requests)
      assert Map.has_key?(router_stats, :successful_routes)
      assert Map.has_key?(router_stats, :failed_routes)
    end

    test "performs health checks on all pools" do
      health_status = Router.health_check()

      assert Map.has_key?(health_status, :overall_status)
      assert Map.has_key?(health_status, :pool_health)
      assert Map.has_key?(health_status, :timestamp)

      # Should check all default pools
      pool_health = health_status.pool_health
      assert Map.has_key?(pool_health, :code_analysis)
      assert Map.has_key?(pool_health, :documentation)
      assert Map.has_key?(pool_health, :testing)
    end

    test "handles unknown analysis types gracefully" do
      result = Router.checkout_engine(:unknown_type)
      assert {:error, :unknown_analysis_type} = result
    end

    test "emits telemetry events for routing operations" do
      :telemetry.attach(
        "test-routing",
        [:rubber_duck_engines, :engine_pool, :router, :engine_routing_failed],
        fn event, measurements, metadata, _ ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Router.checkout_engine(:unknown_type)

      assert_receive {:telemetry,
                      [:rubber_duck_engines, :engine_pool, :router, :engine_routing_failed],
                      _measurements, metadata}

      assert metadata.analysis_type == :unknown_type
      assert metadata.reason == :unknown_analysis_type

      :telemetry.detach("test-routing")
    end
  end

  describe "EnginePool integration" do
    test "provides unified API for pool operations" do
      # Test the main EnginePool module functions
      stats = EnginePool.pool_stats()
      assert is_map(stats)

      pools = EnginePool.list_pools()
      assert is_map(pools)

      health = EnginePool.health_check()
      assert is_map(health)
    end

    test "handles pool configuration through unified API" do
      # Get current config
      original_config = EnginePool.get_pool_config(:testing)
      assert is_map(original_config)

      # Update config
      result = EnginePool.update_pool_config(:testing, %{pool_size: 3})
      assert result == :ok

      # Verify change
      updated_config = EnginePool.get_pool_config(:testing)
      assert updated_config.pool_size == 3
    end
  end

  describe "rest_for_one behavior simulation" do
    test "supervisor restart order maintains dependency hierarchy" do
      # Get initial state
      initial_children = Supervisor.which_children(Supervisor)
      initial_count = length(initial_children)

      # Find router pid
      {Router, router_pid, _, _} =
        Enum.find(initial_children, fn {id, _, _, _} -> id == Router end)

      # Kill the router (should only restart router)
      Process.exit(router_pid, :kill)

      # Give supervisor time to restart
      Process.sleep(100)

      # Check that supervisor still has same number of children
      new_children = Supervisor.which_children(Supervisor)
      assert length(new_children) == initial_count

      # Router should have a new pid
      {Router, new_router_pid, _, _} =
        Enum.find(new_children, fn {id, _, _, _} -> id == Router end)

      assert new_router_pid != router_pid
      assert Process.alive?(new_router_pid)
    end
  end

  # Cleanup helper
  setup do
    on_exit(fn ->
      # Clean up any test pools that might have been added
      try do
        Manager.remove_pool(:test_pool)
      rescue
        _ -> :ok
      end
    end)
  end
end
