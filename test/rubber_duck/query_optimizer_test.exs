defmodule RubberDuck.QueryOptimizerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.{QueryOptimizer, MnesiaManager, CacheManager}
  
  setup do
    # Ensure Mnesia is started
    case :mnesia.system_info(:is_running) do
      :no -> :mnesia.start()
      _ -> :ok
    end
    
    # Ensure MnesiaManager is started
    case Process.whereis(MnesiaManager) do
      nil -> 
        {:ok, _} = MnesiaManager.start_link([])
      pid -> 
        Process.alive?(pid)
    end
    
    # Ensure CacheManager is started
    case Process.whereis(CacheManager) do
      nil -> 
        {:ok, _} = CacheManager.start_link([])
      pid ->
        GenServer.stop(pid)
        {:ok, _} = CacheManager.start_link([])
    end
    
    on_exit(fn ->
      # Clean up test data
      :mnesia.clear_table(:ai_context)
      :mnesia.clear_table(:code_analysis_cache)
      :mnesia.clear_table(:llm_interaction)
    end)
    
    :ok
  end
  
  describe "get_context/2" do
    test "retrieves context from cache when available" do
      session_id = "test-session-opt"
      context = %{user: "test", data: "cached"}
      
      # Pre-populate cache
      CacheManager.cache_context(session_id, context)
      Process.sleep(50)
      
      # Should get from cache
      assert {:ok, ^context} = QueryOptimizer.get_context(session_id)
    end
    
    test "queries Mnesia when cache miss" do
      session_id = "test-session-mnesia"
      context_data = %{user: "test", data: "from mnesia"}
      
      # Insert directly into Mnesia
      :mnesia.transaction(fn ->
        :mnesia.write({:ai_context, "ctx-1", session_id, context_data, %{}, DateTime.utc_now()})
      end)
      
      # Should query Mnesia and cache result
      result = QueryOptimizer.get_context(session_id)
      assert {:ok, fetched} = result
      assert fetched.session_id == session_id
      assert fetched.content == context_data
      
      # Verify it was cached
      Process.sleep(50)
      assert {:ok, cached} = CacheManager.get_context(session_id)
      assert cached == fetched
    end
    
    test "bypasses cache when use_cache is false" do
      session_id = "test-no-cache"
      
      # Should return nil without checking cache
      assert {:ok, nil} = QueryOptimizer.get_context(session_id, use_cache: false)
    end
  end
  
  describe "get_contexts_batch/1" do
    test "retrieves multiple contexts in parallel" do
      session_ids = ["batch-1", "batch-2", "batch-3"]
      
      # Insert test data
      :mnesia.transaction(fn ->
        Enum.each(session_ids, fn id ->
          :mnesia.write({:ai_context, id, id, %{batch: true}, %{}, DateTime.utc_now()})
        end)
      end)
      
      results = QueryOptimizer.get_contexts_batch(session_ids)
      
      assert is_map(results)
      assert map_size(results) == 3
      
      Enum.each(session_ids, fn id ->
        assert {:ok, context} = Map.get(results, id)
        assert context.session_id == id
      end)
    end
  end
  
  describe "get_analysis/2" do
    test "retrieves analysis with caching" do
      file_path = "/test/file.ex"
      analysis = %{functions: ["foo"], complexity: 5}
      
      # Insert into Mnesia
      :mnesia.transaction(fn ->
        :mnesia.write({:code_analysis_cache, "analysis-1", file_path, analysis, %{}, DateTime.utc_now()})
      end)
      
      # First call should query Mnesia
      assert {:ok, result} = QueryOptimizer.get_analysis(file_path)
      assert result.analysis == analysis
      
      # Second call should use cache
      assert {:ok, ^result} = QueryOptimizer.get_analysis(file_path)
    end
    
    test "forces refresh when requested" do
      file_path = "/test/refresh.ex"
      
      # Even with cache, should query Mnesia
      assert {:ok, nil} = QueryOptimizer.get_analysis(file_path, force_refresh: true)
    end
  end
  
  describe "get_recent_interactions/2" do
    test "retrieves recent interactions within time range" do
      now = DateTime.utc_now()
      old_time = DateTime.add(now, -7200, :second)  # 2 hours ago
      recent_time = DateTime.add(now, -1800, :second)  # 30 minutes ago
      
      # Insert test interactions
      :mnesia.transaction(fn ->
        :mnesia.write({:llm_interaction, "int-1", "session-1", "old prompt", "old response", old_time})
        :mnesia.write({:llm_interaction, "int-2", "session-2", "recent prompt", "recent response", recent_time})
        :mnesia.write({:llm_interaction, "int-3", "session-3", "newest prompt", "newest response", now})
      end)
      
      # Get interactions from last hour
      {:ok, results} = QueryOptimizer.get_recent_interactions(10, DateTime.add(now, -3600, :second))
      
      assert length(results) == 2
      assert Enum.all?(results, fn r -> DateTime.compare(r.timestamp, DateTime.add(now, -3600, :second)) == :gt end)
    end
  end
  
  describe "aggregate_metrics/2" do
    test "aggregates metrics for specified time range" do
      now = DateTime.utc_now()
      
      # Insert test data with metrics
      :mnesia.transaction(fn ->
        :mnesia.write({:llm_interaction, "m-1", "s-1", "p1", "r1", now, %{latency: 100}})
        :mnesia.write({:llm_interaction, "m-2", "s-2", "p2", "r2", now, %{latency: 200}})
        :mnesia.write({:llm_interaction, "m-3", "s-3", "p3", "r3", now, %{latency: 150}})
      end)
      
      {:ok, metrics} = QueryOptimizer.aggregate_metrics(:latency, :hour)
      
      assert metrics.count == 3
      assert metrics.total == 450
      assert metrics.average == 150.0
      assert metrics.max == 200
      assert metrics.min == 100
    end
  end
  
  describe "search_contexts/2" do
    test "searches contexts by content" do
      # Insert test contexts
      :mnesia.transaction(fn ->
        :mnesia.write({:ai_context, "search-1", "s1", "This contains elixir code", %{}, DateTime.utc_now()})
        :mnesia.write({:ai_context, "search-2", "s2", "This contains python code", %{}, DateTime.utc_now()})
        :mnesia.write({:ai_context, "search-3", "s3", "This also has elixir examples", %{}, DateTime.utc_now()})
      end)
      
      {:ok, results} = QueryOptimizer.search_contexts("elixir")
      
      assert length(results) == 2
      assert Enum.all?(results, fn r -> String.contains?(r.content, "elixir") end)
    end
    
    test "limits search results" do
      # Insert many contexts
      :mnesia.transaction(fn ->
        Enum.each(1..10, fn i ->
          :mnesia.write({:ai_context, "limit-#{i}", "s#{i}", "test content #{i}", %{}, DateTime.utc_now()})
        end)
      end)
      
      {:ok, results} = QueryOptimizer.search_contexts("test", limit: 5)
      
      assert length(results) == 5
    end
  end
  
  describe "create_optimized_indexes/0" do
    test "creates indexes for common query patterns" do
      result = QueryOptimizer.create_optimized_indexes()
      
      assert is_map(result)
      assert result.created >= 0
      assert result.failed == 0
      assert is_list(result.details)
    end
  end
end