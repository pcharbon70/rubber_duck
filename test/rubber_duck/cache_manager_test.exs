defmodule RubberDuck.CacheManagerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.CacheManager
  
  setup do
    # Ensure cache manager is not running
    case Process.whereis(CacheManager) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
    
    # Cache will be started by CacheManager itself
    
    {:ok, pid} = CacheManager.start_link([])
    
    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      # Cache is stopped when CacheManager stops
    end)
    
    :ok
  end
  
  describe "context caching" do
    test "caches and retrieves context" do
      session_id = "test-session-123"
      context = %{user: "test", messages: ["hello", "world"]}
      
      CacheManager.cache_context(session_id, context)
      Process.sleep(50)  # Allow async cast to complete
      
      assert {:ok, ^context} = CacheManager.get_context(session_id)
    end
    
    test "returns nil for non-existent context" do
      assert {:ok, nil} = CacheManager.get_context("non-existent")
    end
  end
  
  describe "analysis caching" do
    test "caches and retrieves analysis results" do
      file_path = "/path/to/file.ex"
      analysis = %{
        functions: ["foo", "bar"],
        modules: ["TestModule"],
        complexity: 5
      }
      
      CacheManager.cache_analysis(file_path, analysis)
      Process.sleep(50)
      
      assert {:ok, ^analysis} = CacheManager.get_analysis(file_path)
    end
  end
  
  describe "LLM response caching" do
    test "caches and retrieves LLM responses" do
      prompt = "Explain what a GenServer is"
      model = "gpt-4"
      response = "A GenServer is an OTP behavior module..."
      
      CacheManager.cache_llm_response(prompt, model, response)
      Process.sleep(50)
      
      assert {:ok, ^response} = CacheManager.get_llm_response(prompt, model)
    end
    
    test "generates consistent keys for same prompt/model" do
      prompt = "Test prompt"
      model = "claude-3"
      response = "Test response"
      
      CacheManager.cache_llm_response(prompt, model, response)
      Process.sleep(50)
      
      # Should retrieve the same response
      assert {:ok, ^response} = CacheManager.get_llm_response(prompt, model)
      
      # Different model should have different key
      assert {:ok, nil} = CacheManager.get_llm_response(prompt, "different-model")
    end
  end
  
  describe "precomputation" do
    test "precomputes common queries" do
      queries = ["common query 1", "common query 2", "common query 3"]
      
      CacheManager.precompute_common_queries(queries)
      Process.sleep(500)  # Allow async computation
      
      # Verify cache size increased
      stats = CacheManager.get_stats()
      assert {:ok, size} = stats.size
      assert size >= 3
    end
  end
  
  describe "cache statistics" do
    test "returns cache statistics" do
      # Add some cache entries
      CacheManager.cache_context("stat-test", %{data: "test"})
      Process.sleep(50)
      
      stats = CacheManager.get_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :hit_rate)
      assert Map.has_key?(stats, :size)
      assert Map.has_key?(stats, :memory)
      assert Map.has_key?(stats, :last_cleanup)
    end
  end
  
  describe "pattern clearing" do
    test "clears entries matching pattern" do
      # Add multiple entries
      CacheManager.cache_context("session-1", %{id: 1})
      CacheManager.cache_context("session-2", %{id: 2})
      CacheManager.cache_analysis("/file1.ex", %{})
      Process.sleep(100)
      
      # Clear all context entries
      {:ok, count} = CacheManager.clear_pattern("^context:")
      assert count >= 2
      
      # Context entries should be gone
      assert {:ok, nil} = CacheManager.get_context("session-1")
      assert {:ok, nil} = CacheManager.get_context("session-2")
      
      # Analysis entry should remain
      assert {:ok, %{}} = CacheManager.get_analysis("/file1.ex")
    end
  end
  
  describe "maintenance" do
    test "runs periodic maintenance" do
      # Trigger maintenance manually
      send(Process.whereis(CacheManager), :maintenance)
      Process.sleep(100)
      
      # Verify process is still alive
      assert Process.alive?(Process.whereis(CacheManager))
      
      # Check that last_cleanup was updated
      stats = CacheManager.get_stats()
      assert stats.last_cleanup != nil
    end
  end
end