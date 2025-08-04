defmodule RubberDuck.Agents.QualityImprovementAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.QualityImprovementAgent
  
  setup do
    # Start the agent with test configuration
    {:ok, agent} = QualityImprovementAgent.start_link(
      id: "test_quality_agent",
      quality_standards: %{
        complexity_threshold: 5,
        line_length_limit: 100,
        test_coverage: 0.8
      },
      best_practices: %{
        use_descriptive_names: true,
        avoid_deep_nesting: true
      }
    )
    
    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent)
    end)
    
    {:ok, agent: agent}
  end
  
  describe "signal_mappings/0" do
    test "returns correct action mappings" do
      mappings = QualityImprovementAgent.signal_mappings()
      
      assert Map.has_key?(mappings, "analyze_quality")
      assert Map.has_key?(mappings, "apply_improvements")
      assert Map.has_key?(mappings, "enforce_standards")
      assert Map.has_key?(mappings, "track_metrics")
      assert Map.has_key?(mappings, "generate_report")
      
      # Verify each mapping has an action and extractor
      Enum.each(mappings, fn {_signal_type, {action, extractor}} ->
        assert is_atom(action)
        assert is_function(extractor, 1)
      end)
    end
  end
  
  describe "parameter extraction" do
    test "extract_analyze_params/1 parses analyze quality signal correctly" do
      signal = %{
        "payload" => %{
          "code" => "def test, do: :ok",
          "language" => "elixir",
          "depth" => "comprehensive"
        }
      }
      
      mappings = QualityImprovementAgent.signal_mappings()
      {_action, extractor} = mappings["analyze_quality"]
      params = extractor.(signal)
      
      assert params.code == "def test, do: :ok"
      assert params.language == "elixir"
      assert params.analysis_depth == "comprehensive"
    end
    
    test "extract_improvements_params/1 parses apply improvements signal correctly" do
      signal = %{
        "payload" => %{
          "improvements" => ["refactor_function", "add_docs"],
          "code" => "def test, do: :ok",
          "apply_automatically" => true
        }
      }
      
      mappings = QualityImprovementAgent.signal_mappings()
      {_action, extractor} = mappings["apply_improvements"]
      params = extractor.(signal)
      
      assert params.improvements == ["refactor_function", "add_docs"]
      assert params.code == "def test, do: :ok"
      assert params.apply_automatically == true
      assert params.backup_original == true
    end
  end
  
  describe "lifecycle hooks" do
    test "on_before_init sets default configurations" do
      config = %{}
      updated_config = QualityImprovementAgent.on_before_init(config)
      
      assert Map.has_key?(updated_config, :quality_standards)
      assert Map.has_key?(updated_config, :best_practices)
      assert Map.has_key?(updated_config, :refactoring_patterns)
      
      # Check default values
      assert updated_config.quality_standards.complexity_threshold == 10
      assert updated_config.best_practices.use_descriptive_names == true
    end
    
    test "on_after_start logs agent information", %{agent: agent} do
      # This should not fail
      result = QualityImprovementAgent.on_after_start(agent)
      assert result == agent
    end
    
    test "on_after_run updates metrics for AnalyzeQualityAction", %{agent: agent} do
      action = QualityImprovementAgent.AnalyzeQualityAction
      result = {:ok, %{quality_score: 0.85}}
      
      # Get agent state/struct and call on_after_run
      # Create a mock agent struct with the expected state structure
      mock_agent = %{
        state: %{
          metrics: %{
            total_analyses: 0,
            quality_score: 0.0,
            improvements_applied: 0,
            avg_improvement_time: 0.0,
            quality_trends: %{}
          }
        }
      }
      
      {:ok, updated_agent} = QualityImprovementAgent.on_after_run(mock_agent, action, result)
      
      # Metrics should be updated
      assert updated_agent.state.metrics.total_analyses == 1
      assert updated_agent.state.metrics.quality_score == 0.85
    end
  end
  
  describe "health_check/1" do
    test "reports healthy status with valid configuration", %{agent: agent} do
      # Call health_check via GenServer
      {:healthy, status} = GenServer.call(agent, :health_check)
      
      assert status.status == "All systems operational"
      assert status.standards_count > 0
      assert is_struct(status.last_check, DateTime)
    end
    
    test "reports unhealthy status with missing standards" do
      {:ok, agent} = QualityImprovementAgent.start_link(
        id: "unhealthy_agent",
        quality_standards: %{},
        best_practices: %{}
      )
      
      try do
        {:unhealthy, status} = GenServer.call(agent, :health_check)
        assert "Missing quality standards" in status.issues
        assert "Missing best practices" in status.issues
      after
        GenServer.stop(agent)
      end
    end
  end
  
  describe "actions integration" do
    test "actions are defined and accessible" do
      # Verify that actions are properly defined
      assert Code.ensure_loaded?(QualityImprovementAgent.AnalyzeQualityAction)
      assert Code.ensure_loaded?(QualityImprovementAgent.ApplyImprovementAction)
      assert Code.ensure_loaded?(QualityImprovementAgent.EnforceStandardsAction)
      assert Code.ensure_loaded?(QualityImprovementAgent.TrackMetricsAction)
      assert Code.ensure_loaded?(QualityImprovementAgent.GenerateQualityReportAction)
    end
    
    test "AnalyzeQualityAction runs successfully" do
      params = %{
        code: "def test, do: :ok",
        language: "elixir",
        analysis_depth: "standard"
      }
      
      {:ok, result} = QualityImprovementAgent.AnalyzeQualityAction.run(params, %{})
      
      assert is_map(result)
      assert Map.has_key?(result, :metrics)
      assert Map.has_key?(result, :improvements)
    end
  end
end