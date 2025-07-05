defmodule RubberDuck.Engine.PoolTest do
  use ExUnit.Case, async: false
  
  @moduletag :capture_log
  
  alias RubberDuck.Engine.{Pool, Manager}
  
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
  
  # Test engines with pool configuration
  defmodule PooledEngines do
    use RubberDuck.EngineSystem
    
    engines do
      engine :execution_pool_test do
        module RubberDuck.Engine.PoolTest.TestEngine
        description "Pooled test engine"
        pool_size 3
        max_overflow 2
        checkout_timeout 1000
      end
      
      engine :single_engine do
        module RubberDuck.Engine.PoolTest.TestEngine
        description "Single instance engine"
        pool_size 1
      end
    end
  end
  
  setup do
    # Clean up all running engines
    Manager.list_engines()
    |> Enum.each(fn {engine_name, _pid} ->
      try do
        Manager.stop_engine(engine_name)
      catch
        :exit, _ -> :ok
      end
    end)
    
    # Clean up registry
    RubberDuck.Engine.CapabilityRegistry.list_engines()
    |> Enum.each(fn engine ->
      RubberDuck.Engine.CapabilityRegistry.unregister_engine(engine.name)
    end)
    
    # Clean up any orphaned pools
    for pid <- Process.list() do
      case Process.info(pid, :registered_name) do
        {:registered_name, name} when is_atom(name) ->
          name_str = Atom.to_string(name)
          if String.ends_with?(name_str, "_pool") do
            Process.exit(pid, :kill)
          end
        _ -> :ok
      end
    end
    
    # Wait for cleanup
    Process.sleep(100)
    
    :ok
  end
  
  describe "pool creation" do
    test "creates pool when pool_size > 1" do
      # Define test-specific engines
      defmodule PoolCreationEngines do
        use RubberDuck.EngineSystem
        
        engines do
          engine :pool_creation_test do
            module RubberDuck.Engine.PoolTest.TestEngine
            description "Pool creation test engine"
            pool_size 3
            max_overflow 2
            checkout_timeout 1000
          end
        end
      end
      
      assert :ok = Manager.load_engines(PoolCreationEngines)
      
      # Check pool status
      status = Manager.status(:pool_creation_test)
      assert is_map(status)
      assert status.pool_size == 3
      assert status.available_workers == 3
      assert status.checked_out == 0
    end
    
    test "creates single instance when pool_size = 1" do
      # Define test-specific engines
      defmodule SingleInstanceEngines do
        use RubberDuck.EngineSystem
        
        engines do
          engine :single_instance_test do
            module RubberDuck.Engine.PoolTest.TestEngine
            description "Single instance test engine"
            pool_size 1
          end
        end
      end
      
      assert :ok = Manager.load_engines(SingleInstanceEngines)
      
      # Single instance should return regular status
      status = Manager.status(:single_instance_test)
      assert is_map(status)
      assert Map.has_key?(status, :engine)
      assert Map.has_key?(status, :request_count)
      refute Map.has_key?(status, :pool_size)
    end
  end
  
  describe "pool execution" do
    setup do
      defmodule ExecutionEngines do
        use RubberDuck.EngineSystem
        
        engines do
          engine :execution_pool_test do
            module RubberDuck.Engine.PoolTest.TestEngine
            description "Execution pool test engine"
            pool_size 3
            max_overflow 2
            checkout_timeout 1000
          end
        end
      end
      
      Manager.load_engines(ExecutionEngines)
      :ok
    end
    
    test "executes requests on pooled engine" do
      assert {:ok, "test"} = Manager.execute(:execution_pool_test, %{
        command: "echo",
        text: "test"
      })
    end
    
    test "handles concurrent requests" do
      # Start multiple concurrent requests
      tasks = for _i <- 1..5 do
        Task.async(fn ->
          Manager.execute(:execution_pool_test, %{
            command: "sleep",
            duration: 100
          })
        end)
      end
      
      # All should complete (3 from pool + 2 from overflow)
      results = Task.await_many(tasks, 2000)
      assert length(results) == 5
      assert Enum.all?(results, &match?({:ok, :slept}, &1))
    end
    
    test "respects max_overflow" do
      # Fill pool and overflow
      tasks = for _i <- 1..6 do
        Task.async(fn ->
          Manager.execute(:execution_pool_test, %{
            command: "sleep",
            duration: 200
          })
        end)
      end
      
      # Wait for some tasks to complete
      Process.sleep(300)
      
      # 6th request should timeout (pool_size=3 + max_overflow=2 = 5 max)
      results = tasks
      |> Enum.map(fn task ->
        case Task.yield(task, 100) do
          {:ok, result} -> result
          nil -> 
            Task.shutdown(task)
            {:error, :checkout_timeout}
        end
      end)
      
      success_count = Enum.count(results, &match?({:ok, _}, &1))
      timeout_count = Enum.count(results, &match?({:error, :checkout_timeout}, &1))
      
      # At least one should timeout since we can only handle 5 concurrent requests
      assert timeout_count >= 1
      assert success_count <= 5
    end
  end
  
  describe "pool status" do
    setup do
      defmodule StatusEngines do
        use RubberDuck.EngineSystem
        
        engines do
          engine :status_pool_test do
            module RubberDuck.Engine.PoolTest.TestEngine
            description "Status pool test engine"
            pool_size 3
            max_overflow 2
            checkout_timeout 1000
          end
        end
      end
      
      Manager.load_engines(StatusEngines)
      :ok
    end
    
    test "tracks checked out workers" do
      # Start a long-running request
      task = Task.async(fn ->
        Manager.execute(:status_pool_test, %{
          command: "sleep",
          duration: 500
        })
      end)
      
      # Give it time to check out
      Process.sleep(50)
      
      status = Manager.status(:status_pool_test)
      assert status.checked_out > 0
      assert status.available_workers < status.pool_size
      
      # Clean up
      Task.await(task)
    end
    
    test "tracks overflow workers" do
      # Fill the main pool
      tasks = for _i <- 1..4 do
        Task.async(fn ->
          Manager.execute(:status_pool_test, %{
            command: "sleep",
            duration: 200
          })
        end)
      end
      
      Process.sleep(50)
      
      status = Manager.status(:status_pool_test)
      assert status.overflow > 0
      assert status.total_workers > status.pool_size
      
      # Clean up
      Task.await_many(tasks, 1000)
    end
  end
  
  describe "pool health checks" do
    setup do
      defmodule HealthEngines do
        use RubberDuck.EngineSystem
        
        engines do
          engine :health_pool_test do
            module RubberDuck.Engine.PoolTest.TestEngine
            description "Health pool test engine"
            pool_size 3
            max_overflow 2
            checkout_timeout 1000
          end
        end
      end
      
      Manager.load_engines(HealthEngines)
      :ok
    end
    
    test "reports healthy when workers available" do
      assert :healthy = Manager.health_status(:health_pool_test)
    end
    
    test "reports unhealthy when all workers busy" do
      # Fill all workers including overflow
      tasks = for _i <- 1..5 do
        Task.async(fn ->
          Manager.execute(:health_pool_test, %{
            command: "sleep",
            duration: 500
          })
        end)
      end
      
      Process.sleep(50)
      
      assert :unhealthy = Manager.health_status(:health_pool_test)
      
      # Clean up
      Task.await_many(tasks, 1000)
    end
  end
  
  describe "pool telemetry" do
    setup do
      defmodule TelemetryEngines do
        use RubberDuck.EngineSystem
        
        engines do
          engine :telemetry_pool_test do
            module RubberDuck.Engine.PoolTest.TestEngine
            description "Telemetry pool test engine"
            pool_size 3
            max_overflow 2
            checkout_timeout 1000
          end
        end
      end
      
      Manager.load_engines(TelemetryEngines)
      
      # Attach telemetry handler
      :ok = :telemetry.attach(
        "pool-test-handler",
        [:rubber_duck, :engine, :pool],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      on_exit(fn -> :telemetry.detach("pool-test-handler") end)
      
      :ok
    end
    
    test "emits pool metrics" do
      # Wait for pool to be ready
      Process.sleep(200)
      
      # Check pool status first to ensure it's running
      status = Pool.status(:telemetry_pool_test)
      assert is_map(status), "Pool status should be a map, got: #{inspect(status)}"
      assert status.total_workers > 0, "Pool should have workers, status: #{inspect(status)}"
      
      Pool.emit_metrics(:telemetry_pool_test)
      
      assert_receive {:telemetry, [:rubber_duck, :engine, :pool], measurements, metadata}, 1000
      
      assert measurements.available_workers >= 0
      assert measurements.checked_out >= 0
      assert measurements.total_workers > 0
      assert metadata.engine == :telemetry_pool_test
      assert metadata.pool_size == 3
    end
  end
end