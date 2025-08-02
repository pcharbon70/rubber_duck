defmodule RubberDuck.Agents.Migration.ScriptsTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.Migration.Scripts
  alias RubberDuck.Agents.AnalysisAgent
  
  describe "detect_migration_candidates/0" do
    test "detects migration candidates" do
      {:ok, candidates} = Scripts.detect_migration_candidates()
      
      assert is_list(candidates)
      
      if length(candidates) > 0 do
        candidate = List.first(candidates)
        assert Map.has_key?(candidate, :module)
        assert Map.has_key?(candidate, :patterns)
        assert Map.has_key?(candidate, :priority)
        assert Map.has_key?(candidate, :dependencies)
        assert Map.has_key?(candidate, :estimated_effort)
        
        assert candidate.priority in [:critical, :high, :medium, :low]
        assert is_integer(candidate.estimated_effort)
        assert is_list(candidate.patterns)
      end
    end
    
    test "prioritizes critical agents" do
      {:ok, candidates} = Scripts.detect_migration_candidates()
      
      # Look for critical priority agents
      critical_candidates = Enum.filter(candidates, &(&1.priority == :critical))
      
      # Should have some critical agents (like AnalysisAgent)
      if length(critical_candidates) > 0 do
        critical_candidate = List.first(critical_candidates)
        module_name = Atom.to_string(critical_candidate.module)
        
        assert String.contains?(module_name, "Analysis") or 
               String.contains?(module_name, "Generation") or
               String.contains?(module_name, "Provider")
      end
    end
  end
  
  describe "migrate_agent/2" do
    test "performs migration for legacy agent" do
      options = [write_files: false, include_tests: true]
      
      {:ok, result} = Scripts.migrate_agent(AnalysisAgent, options)
      
      assert Map.has_key?(result, :module)
      assert Map.has_key?(result, :success)
      assert Map.has_key?(result, :artifacts)
      assert Map.has_key?(result, :issues)
      assert Map.has_key?(result, :warnings)
      
      assert result.module == AnalysisAgent
      assert is_boolean(result.success)
      assert is_list(result.issues)
      assert is_list(result.warnings)
      
      # Check artifacts structure
      assert Map.has_key?(result.artifacts, :agent_code)
      assert Map.has_key?(result.artifacts, :actions)
      assert Map.has_key?(result.artifacts, :tests)
    end
    
    test "handles already compliant agents" do
      # BaseAgent should be compliant
      {:ok, result} = Scripts.migrate_agent(RubberDuck.Agents.BaseAgent, [])
      
      # Should report as already compliant
      assert result.success == true
      assert "already compliant" in Enum.join(result.warnings, " ")
    end
  end
  
  describe "generate_migration_report/0" do
    test "generates comprehensive migration report" do
      {:ok, report} = Scripts.generate_migration_report()
      
      assert Map.has_key?(report, :total_agents)
      assert Map.has_key?(report, :migrated)
      assert Map.has_key?(report, :remaining)
      assert Map.has_key?(report, :compliance_score)
      assert Map.has_key?(report, :issues)
      assert Map.has_key?(report, :recommendations)
      
      assert is_integer(report.total_agents)
      assert is_integer(report.migrated)
      assert is_integer(report.remaining)
      assert is_float(report.compliance_score)
      assert is_list(report.issues)
      assert is_list(report.recommendations)
      
      # Sanity checks
      assert report.total_agents >= 0
      assert report.migrated >= 0
      assert report.remaining >= 0
      assert report.compliance_score >= 0.0 and report.compliance_score <= 1.0
      assert report.total_agents == report.migrated + report.remaining
    end
  end
  
  describe "validate_migration/1" do
    test "validates migration results" do
      {:ok, validation} = Scripts.validate_migration(AnalysisAgent)
      
      assert Map.has_key?(validation, :compliance)
      assert Map.has_key?(validation, :actions_extracted)
      assert Map.has_key?(validation, :signal_mappings)
      assert Map.has_key?(validation, :state_management)
      assert Map.has_key?(validation, :test_coverage)
      
      # Check compliance structure
      compliance = validation.compliance
      assert Map.has_key?(compliance, :compliant)
      assert Map.has_key?(compliance, :score)
      assert is_boolean(compliance.compliant)
      assert is_float(compliance.score)
    end
  end
end