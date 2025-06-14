defmodule RubberDuck.MnesiaOptimizerTest do
  use ExUnit.Case, async: false
  alias RubberDuck.MnesiaOptimizer
  
  describe "configure_for_ai_workloads/0" do
    test "configures Mnesia parameters without errors" do
      assert :ok = MnesiaOptimizer.configure_for_ai_workloads()
    end
  end
  
  describe "get_performance_stats/0" do
    test "returns comprehensive performance statistics" do
      stats = MnesiaOptimizer.get_performance_stats()
      
      assert %{
        system_info: system_info,
        table_stats: table_stats,
        memory_usage: memory_usage,
        fragmentation: fragmentation
      } = stats
      
      assert is_map(system_info)
      assert is_map(table_stats)
      assert is_map(memory_usage)
      assert is_map(fragmentation)
      
      # Check system info structure
      assert Map.has_key?(system_info, :is_running)
      assert Map.has_key?(system_info, :running_db_nodes)
      assert Map.has_key?(system_info, :held_locks)
      
      # Check memory usage structure
      assert Map.has_key?(memory_usage, :total)
      assert Map.has_key?(memory_usage, :mnesia)
      assert Map.has_key?(memory_usage, :processes)
    end
  end
  
  describe "analyze_performance/0" do
    test "returns performance analysis with recommendations" do
      analysis = MnesiaOptimizer.analyze_performance()
      
      assert %{
        current_stats: stats,
        recommendations: recommendations,
        analysis_time: analysis_time
      } = analysis
      
      assert is_map(stats)
      assert is_list(recommendations)
      assert %DateTime{} = analysis_time
    end
    
    test "includes recommendation structure when issues found" do
      analysis = MnesiaOptimizer.analyze_performance()
      
      Enum.each(analysis.recommendations, fn recommendation ->
        assert Map.has_key?(recommendation, :type)
        assert Map.has_key?(recommendation, :priority)
        assert Map.has_key?(recommendation, :description)
        assert Map.has_key?(recommendation, :action)
        
        assert recommendation.priority in [:high, :medium, :low]
      end)
    end
  end
  
  describe "fragment_table/2" do
    test "handles non-existent tables gracefully" do
      # This should not crash even if table doesn't exist
      result = MnesiaOptimizer.fragment_table(:non_existent_table, 2)
      assert result == :skipped or match?({:error, _}, result)
    end
    
    test "skips small tables" do
      # Most test tables will be small, so should be skipped
      result = MnesiaOptimizer.fragment_table(:sessions, 2)
      assert result in [:skipped, :already_fragmented] or match?({:error, _}, result)
    end
  end
  
  describe "optimize_table_indexes/0" do
    test "runs without errors" do
      assert :ok = MnesiaOptimizer.optimize_table_indexes()
    end
  end
  
  describe "auto_optimize/0" do
    test "applies optimizations and returns results" do
      applied = MnesiaOptimizer.auto_optimize()
      assert is_list(applied)
    end
    
    test "applied optimizations have correct structure" do
      applied = MnesiaOptimizer.auto_optimize()
      
      Enum.each(applied, fn optimization ->
        assert Map.has_key?(optimization, :type)
        assert Map.has_key?(optimization, :priority)
        assert Map.has_key?(optimization, :action)
      end)
    end
  end
end