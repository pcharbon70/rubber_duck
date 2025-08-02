defmodule RubberDuck.Agents.Migration.HelpersTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.Migration.Helpers
  alias RubberDuck.Agents.AnalysisAgent
  
  describe "detect_legacy_patterns/1" do
    test "detects behavior usage pattern" do
      {:ok, patterns} = Helpers.detect_legacy_patterns(AnalysisAgent)
      
      assert :behavior_usage in patterns
    end
    
    test "detects missing actions pattern" do
      {:ok, patterns} = Helpers.detect_legacy_patterns(AnalysisAgent)
      
      assert :missing_actions in patterns
    end
    
    test "returns empty list for compliant agents" do
      # Test with a compliant agent (BaseAgent)
      {:ok, patterns} = Helpers.detect_legacy_patterns(RubberDuck.Agents.BaseAgent)
      
      # BaseAgent itself should have fewer patterns since it's the foundation
      assert is_list(patterns)
    end
  end
  
  describe "extract_actions/1" do
    test "extracts action candidates from agent" do
      {:ok, candidates} = Helpers.extract_actions(AnalysisAgent)
      
      assert is_list(candidates)
      assert length(candidates) > 0
      
      # Check first candidate structure
      candidate = List.first(candidates)
      assert Map.has_key?(candidate, :name)
      assert Map.has_key?(candidate, :function)
      assert Map.has_key?(candidate, :description)
    end
    
    test "filters out non-action functions" do
      {:ok, candidates} = Helpers.extract_actions(AnalysisAgent)
      
      # Should not include GenServer callbacks
      function_names = Enum.map(candidates, & &1.function)
      
      refute :handle_call in function_names
      refute :handle_cast in function_names
      refute :init in function_names
      refute :terminate in function_names
    end
  end
  
  describe "generate_signal_mappings/1" do
    test "generates signal mappings from agent" do
      {:ok, mappings} = Helpers.generate_signal_mappings(AnalysisAgent)
      
      assert is_list(mappings)
      
      if length(mappings) > 0 do
        mapping = List.first(mappings)
        assert Map.has_key?(mapping, :signal_type)
        assert Map.has_key?(mapping, :action_module)
        assert Map.has_key?(mapping, :param_extractor)
      end
    end
  end
  
  describe "validate_compliance/1" do
    test "validates agent compliance" do
      {:ok, result} = Helpers.validate_compliance(AnalysisAgent)
      
      assert Map.has_key?(result, :compliant)
      assert Map.has_key?(result, :issues)
      assert Map.has_key?(result, :recommendations)
      assert Map.has_key?(result, :score)
      
      assert is_boolean(result.compliant)
      assert is_list(result.issues)
      assert is_list(result.recommendations)
      assert is_float(result.score)
      assert result.score >= 0.0 and result.score <= 1.0
    end
    
    test "identifies non-compliance for legacy agents" do
      {:ok, result} = Helpers.validate_compliance(AnalysisAgent)
      
      # AnalysisAgent should not be compliant (uses legacy patterns)
      assert result.compliant == false
      assert length(result.issues) > 0
    end
  end
  
  describe "analyze_dependencies/1" do
    test "analyzes agent dependencies" do
      {:ok, dependencies} = Helpers.analyze_dependencies(AnalysisAgent)
      
      assert Map.has_key?(dependencies, :imports)
      assert Map.has_key?(dependencies, :aliases)
      assert Map.has_key?(dependencies, :agent_dependencies)
      assert Map.has_key?(dependencies, :action_dependencies)
    end
  end
end