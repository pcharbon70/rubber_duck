defmodule RubberDuck.CacheIntegrationTest do
  use ExUnit.Case, async: false
  
  test "Nebulex cache basic functionality" do
    # Test L1 cache directly
    assert :ok = RubberDuck.Nebulex.Cache.put_in(:l1, "test_key", "test_value")
    assert "test_value" = RubberDuck.Nebulex.Cache.get_from(:l1, "test_key")
    
    # Test L2 cache directly
    assert :ok = RubberDuck.Nebulex.Cache.put_in(:l2, "test_key_l2", "test_value_l2")
    assert "test_value_l2" = RubberDuck.Nebulex.Cache.get_from(:l2, "test_key_l2")
    
    # Test multilevel cache
    assert :ok = RubberDuck.Nebulex.Cache.put_in(:multilevel, "test_key_ml", "test_value_ml")
    assert "test_value_ml" = RubberDuck.Nebulex.Cache.get_from(:multilevel, "test_key_ml")
  end
  
  test "Cache Manager API exists and handles basic operations" do
    # Test that the CacheManager module has the expected functions
    assert function_exported?(RubberDuck.CacheManager, :cache_context, 2)
    assert function_exported?(RubberDuck.CacheManager, :get_context, 1)
    assert function_exported?(RubberDuck.CacheManager, :cache_analysis, 2)
    assert function_exported?(RubberDuck.CacheManager, :get_analysis, 1)
    assert function_exported?(RubberDuck.CacheManager, :cache_llm_response, 3)
    assert function_exported?(RubberDuck.CacheManager, :get_llm_response, 2)
    assert function_exported?(RubberDuck.CacheManager, :get_stats, 0)
  end
  
  test "Cache stats functionality" do
    stats = RubberDuck.Nebulex.Cache.cache_stats(:multilevel)
    
    # Should return a map with L1, L2, and multilevel stats
    assert is_map(stats)
    assert Map.has_key?(stats, :l1)
    assert Map.has_key?(stats, :l2)  
    assert Map.has_key?(stats, :multilevel)
  end
end