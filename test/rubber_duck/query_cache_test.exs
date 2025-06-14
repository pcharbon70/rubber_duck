defmodule RubberDuck.QueryCacheTest do
  use ExUnit.Case, async: false
  alias RubberDuck.QueryCache
  
  setup do
    # Start QueryCache if not already running
    case GenServer.whereis(QueryCache) do
      nil -> QueryCache.start_link([])
      _pid -> :ok
    end
    
    # Clear all caches before each test
    QueryCache.clear_all_caches()
    :ok
  end
  
  describe "session caching" do
    test "can store and retrieve session data" do
      session_id = "test_session_123"
      session_data = %{id: session_id, messages: ["Hello", "World"], created_at: DateTime.utc_now()}
      
      # Put session in cache
      assert :ok = QueryCache.put_session(session_id, session_data)
      
      # Retrieve session with fetch function (should hit cache)
      fetch_called = ref = make_ref()
      fetch_fun = fn ->
        send(self(), {fetch_called, ref})
        session_data
      end
      
      assert {:ok, ^session_data} = QueryCache.get_session(session_id, fetch_fun)
      
      # Verify fetch function was not called (cache hit)
      refute_received {^fetch_called, ^ref}
    end
    
    test "calls fetch function on cache miss" do
      session_id = "missing_session"
      session_data = %{id: session_id, messages: []}
      
      fetch_called = ref = make_ref()
      fetch_fun = fn ->
        send(self(), {fetch_called, ref})
        session_data
      end
      
      assert {:ok, ^session_data} = QueryCache.get_session(session_id, fetch_fun)
      
      # Verify fetch function was called (cache miss)
      assert_received {^fetch_called, ^ref}
    end
    
    test "can invalidate session cache" do
      session_id = "test_session_456"
      session_data = %{id: session_id, messages: ["Cached"]}
      
      # Cache the session
      QueryCache.put_session(session_id, session_data)
      
      # Invalidate it
      assert :ok = QueryCache.invalidate_session(session_id)
      
      # Should call fetch function again
      fetch_called = ref = make_ref()
      fetch_fun = fn ->
        send(self(), {fetch_called, ref})
        %{id: session_id, messages: ["Fresh"]}
      end
      
      QueryCache.get_session(session_id, fetch_fun)
      assert_received {^fetch_called, ^ref}
    end
  end
  
  describe "model caching" do
    test "can store and retrieve model data" do
      model_name = "test_model"
      model_data = %{name: model_name, type: :llm, capabilities: [:chat]}
      
      assert :ok = QueryCache.put_model(model_name, model_data)
      
      fetch_fun = fn -> model_data end
      assert {:ok, ^model_data} = QueryCache.get_model(model_name, fetch_fun)
    end
    
    test "can invalidate model cache" do
      model_name = "test_model_2"
      model_data = %{name: model_name, health: :healthy}
      
      QueryCache.put_model(model_name, model_data)
      assert :ok = QueryCache.invalidate_model(model_name)
      
      # Should call fetch function after invalidation
      fetch_called = ref = make_ref()
      fetch_fun = fn ->
        send(self(), {fetch_called, ref})
        model_data
      end
      
      QueryCache.get_model(model_name, fetch_fun)
      assert_received {^fetch_called, ^ref}
    end
  end
  
  describe "query result caching" do
    test "can cache and retrieve query results" do
      query_key = "complex_query_abc"
      result = %{rows: [%{id: 1, name: "test"}], count: 1}
      
      assert :ok = QueryCache.put_query_result(query_key, result)
      
      fetch_fun = fn -> result end
      assert {:ok, ^result} = QueryCache.get_query_result(query_key, fetch_fun)
    end
  end
  
  describe "statistics caching" do
    test "can cache and retrieve statistics" do
      stats_key = "model_performance_daily"
      stats_data = %{success_rate: 0.95, avg_latency: 150, requests: 1000}
      
      assert :ok = QueryCache.put_stats(stats_key, stats_data)
      
      fetch_fun = fn -> stats_data end
      assert {:ok, ^stats_data} = QueryCache.get_stats(stats_key, fetch_fun)
    end
  end
  
  describe "cache statistics" do
    test "returns cache performance statistics" do
      stats = QueryCache.get_cache_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :session_cache)
      assert Map.has_key?(stats, :query_cache)
      assert Map.has_key?(stats, :model_cache)
      assert Map.has_key?(stats, :stats_cache)
      
      # Check structure of individual cache stats
      Enum.each(stats, fn {_cache_name, cache_stats} ->
        assert Map.has_key?(cache_stats, :hit_rate)
        assert Map.has_key?(cache_stats, :size)
        assert Map.has_key?(cache_stats, :memory)
        assert Map.has_key?(cache_stats, :operations)
        
        assert is_number(cache_stats.hit_rate)
        assert is_number(cache_stats.size)
        assert is_number(cache_stats.memory)
        assert is_map(cache_stats.operations)
      end)
    end
  end
  
  describe "cache warming" do
    test "can warm cache with data list" do
      data_list = [
        {"session_1", %{id: "session_1", messages: ["warm1"]}},
        {"session_2", %{id: "session_2", messages: ["warm2"]}}
      ]
      
      assert :ok = QueryCache.warm_cache(:session_cache, data_list)
      
      # Verify data was cached
      fetch_fun = fn -> %{id: "session_1", messages: ["fresh"]} end
      
      # Should return warmed data, not call fetch function
      {:ok, result} = QueryCache.get_session("session_1", fetch_fun)
      assert result.messages == ["warm1"]
    end
  end
  
  describe "query key generation" do
    test "generates consistent keys for same parameters" do
      key1 = QueryCache.generate_query_key(:sessions, :read, %{session_id: "123"})
      key2 = QueryCache.generate_query_key(:sessions, :read, %{session_id: "123"})
      
      assert key1 == key2
      assert is_binary(key1)
      assert byte_size(key1) == 16
    end
    
    test "generates different keys for different parameters" do
      key1 = QueryCache.generate_query_key(:sessions, :read, %{session_id: "123"})
      key2 = QueryCache.generate_query_key(:sessions, :read, %{session_id: "456"})
      
      assert key1 != key2
    end
  end
  
  describe "cache management" do
    test "can clear individual caches" do
      # Add some data
      QueryCache.put_session("test", %{data: "test"})
      QueryCache.put_model("model", %{name: "model"})
      
      # Clear session cache only
      assert {:ok, _} = QueryCache.clear_cache(:session_cache)
      
      # Session cache should be empty, model cache should still have data
      stats = QueryCache.get_cache_stats()
      assert stats.session_cache.size == 0
      # Note: model_cache might be 0 or 1 depending on cache behavior
    end
    
    test "can clear all caches" do
      # Add data to multiple caches
      QueryCache.put_session("test", %{data: "test"})
      QueryCache.put_model("model", %{name: "model"})
      QueryCache.put_stats("stats", %{value: 100})
      
      assert :ok = QueryCache.clear_all_caches()
      
      stats = QueryCache.get_cache_stats()
      assert stats.session_cache.size == 0
      assert stats.model_cache.size == 0
      assert stats.stats_cache.size == 0
    end
  end
  
  describe "prefetching" do
    test "can prefetch sessions asynchronously" do
      session_ids = ["prefetch_1", "prefetch_2"]
      
      # This should not crash and should return quickly
      assert :ok = QueryCache.prefetch_sessions(session_ids)
      
      # Give it a moment to process
      Process.sleep(100)
    end
    
    test "can prefetch models asynchronously" do
      model_names = ["prefetch_model_1", "prefetch_model_2"]
      
      assert :ok = QueryCache.prefetch_models(model_names)
      Process.sleep(100)
    end
  end
end