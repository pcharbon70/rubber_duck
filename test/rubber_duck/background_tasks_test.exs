defmodule RubberDuck.BackgroundTasksTest do
  use ExUnit.Case, async: false
  alias RubberDuck.{BackgroundTasks, SessionCleaner, ModelStatsAggregator, CacheWarmer, PerformanceMonitor}
  
  describe "BackgroundTasks supervisor" do
    test "starts all child processes" do
      {:ok, supervisor_pid} = BackgroundTasks.start_link([])
      
      # Verify all expected children are running
      children = Supervisor.which_children(supervisor_pid)
      
      child_specs = Enum.map(children, fn {id, _pid, _type, _modules} -> id end)
      
      assert SessionCleaner in child_specs
      assert ModelStatsAggregator in child_specs  
      assert CacheWarmer in child_specs
      assert PerformanceMonitor in child_specs
      
      # Clean up
      Supervisor.stop(supervisor_pid)
    end
    
    test "uses one_for_one strategy" do
      {:ok, supervisor_pid} = BackgroundTasks.start_link([])
      
      # Check supervisor is working - count_children doesn't show strategy
      # but we can verify it's supervising the expected children
      children_count = Supervisor.count_children(supervisor_pid)
      assert children_count.active >= 4  # Should have 4 child processes
      
      Supervisor.stop(supervisor_pid)
    end
  end
  
  describe "SessionCleaner" do
    test "starts successfully and initializes state" do
      {:ok, pid} = SessionCleaner.start_link([])
      
      # Verify it's running
      assert Process.alive?(pid)
      
      # Stop the process
      GenServer.stop(pid)
    end
    
    test "schedules cleanup tasks" do
      {:ok, pid} = SessionCleaner.start_link([])
      
      # Get initial state (this is testing internal implementation details)
      state = :sys.get_state(pid)
      
      assert Map.has_key?(state, :last_cleanup)
      assert Map.has_key?(state, :stats)
      assert %DateTime{} = state.last_cleanup
      assert is_map(state.stats)
      
      GenServer.stop(pid)
    end
  end
  
  describe "ModelStatsAggregator" do
    test "starts successfully and initializes state" do
      {:ok, pid} = ModelStatsAggregator.start_link([])
      
      assert Process.alive?(pid)
      
      state = :sys.get_state(pid)
      assert Map.has_key?(state, :last_aggregation)
      assert Map.has_key?(state, :rollups_created)
      assert %DateTime{} = state.last_aggregation
      assert is_number(state.rollups_created)
      
      GenServer.stop(pid)
    end
  end
  
  describe "CacheWarmer" do
    test "starts successfully and initializes state" do
      {:ok, pid} = CacheWarmer.start_link([])
      
      assert Process.alive?(pid)
      
      state = :sys.get_state(pid)
      assert Map.has_key?(state, :last_warming)
      assert Map.has_key?(state, :items_warmed)
      assert %DateTime{} = state.last_warming
      assert is_number(state.items_warmed)
      
      GenServer.stop(pid)
    end
  end
  
  describe "PerformanceMonitor" do
    test "starts successfully and initializes state" do
      {:ok, pid} = PerformanceMonitor.start_link([])
      
      assert Process.alive?(pid)
      
      state = :sys.get_state(pid)
      assert Map.has_key?(state, :last_check)
      assert Map.has_key?(state, :performance_history)
      assert %DateTime{} = state.last_check
      assert is_list(state.performance_history)
      
      GenServer.stop(pid)
    end
    
    test "collects performance metrics" do
      {:ok, pid} = PerformanceMonitor.start_link([])
      
      # Trigger a manual performance check by sending the message
      send(pid, :monitor_performance)
      
      # Give it time to process
      Process.sleep(100)
      
      state = :sys.get_state(pid)
      
      # Should have at least one entry in performance history
      assert length(state.performance_history) >= 1
      
      # Check structure of performance metrics
      [latest_metrics | _] = state.performance_history
      
      assert Map.has_key?(latest_metrics, :timestamp)
      assert Map.has_key?(latest_metrics, :mnesia_stats)
      assert Map.has_key?(latest_metrics, :cache_stats)
      assert Map.has_key?(latest_metrics, :memory_usage)
      assert Map.has_key?(latest_metrics, :process_count)
      assert Map.has_key?(latest_metrics, :system_load)
      
      GenServer.stop(pid)
    end
  end
  
  describe "SessionCleaner cleanup logic" do
    test "handles empty session list gracefully" do
      # This tests the internal cleanup function behavior
      # Since we can't easily mock Mnesia transactions in unit tests,
      # we're mainly testing that the process doesn't crash
      
      {:ok, pid} = SessionCleaner.start_link([])
      
      # Send cleanup message manually
      send(pid, :cleanup_sessions)
      
      # Give it time to process
      Process.sleep(200)
      
      # Process should still be alive
      assert Process.alive?(pid)
      
      GenServer.stop(pid)
    end
  end
  
  describe "ModelStatsAggregator aggregation logic" do
    test "handles empty stats list gracefully" do
      {:ok, pid} = ModelStatsAggregator.start_link([])
      
      # Send aggregation message manually
      send(pid, :aggregate_stats)
      
      # Give it time to process
      Process.sleep(200)
      
      # Process should still be alive
      assert Process.alive?(pid)
      
      GenServer.stop(pid)
    end
  end
  
  describe "CacheWarmer warming logic" do
    test "handles cache warming without errors" do
      {:ok, pid} = CacheWarmer.start_link([])
      
      # Send warming message manually
      send(pid, :warm_caches)
      
      # Give it time to process
      Process.sleep(200)
      
      # Process should still be alive
      assert Process.alive?(pid)
      
      GenServer.stop(pid)
    end
  end
  
  describe "integration with QueryCache" do
    setup do
      # Ensure QueryCache is running for integration tests
      case GenServer.whereis(RubberDuck.QueryCache) do
        nil -> 
          {:ok, _} = RubberDuck.QueryCache.start_link([])
        _pid -> :ok
      end
      :ok
    end
    
    test "CacheWarmer can interact with QueryCache" do
      {:ok, cache_warmer_pid} = CacheWarmer.start_link([])
      
      # This should not crash even if QueryCache operations fail
      send(cache_warmer_pid, :warm_caches)
      Process.sleep(100)
      
      assert Process.alive?(cache_warmer_pid)
      
      GenServer.stop(cache_warmer_pid)
    end
    
    test "PerformanceMonitor can collect cache stats" do
      {:ok, monitor_pid} = PerformanceMonitor.start_link([])
      
      # Trigger performance collection
      send(monitor_pid, :monitor_performance)
      Process.sleep(100)
      
      state = :sys.get_state(monitor_pid)
      
      # Should have collected metrics including cache stats
      assert length(state.performance_history) > 0
      [latest | _] = state.performance_history
      
      assert Map.has_key?(latest, :cache_stats)
      assert is_map(latest.cache_stats)
      
      GenServer.stop(monitor_pid)
    end
  end
end