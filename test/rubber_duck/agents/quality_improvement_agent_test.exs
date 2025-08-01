defmodule RubberDuck.Agents.QualityImprovementAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.QualityImprovementAgent
  
  @sample_code """
  defmodule TestModule do
    @moduledoc "Test module for quality analysis"
    
    def complex_function(x, y, z) do
      if x > 0 do
        if y > 0 do
          if z > 0 do
            x + y + z
          else
            x + y
          end
        else
          x
        end
      else
        0
      end
    end
    
    def simple_function(a, b) do
      a + b
    end
  end
  """
  
  describe "Quality Improvement Agent initialization" do
    test "mounts successfully with default configuration" do
      agent = %{id: "test_agent", state: %{}}
      
      {:ok, mounted_agent} = QualityImprovementAgent.mount(agent)
      
      assert mounted_agent.state.analysis_status == :idle
      assert mounted_agent.state.active_analyses == %{}
      assert mounted_agent.state.improvement_history == []
      assert is_map(mounted_agent.state.quality_standards)
      assert is_map(mounted_agent.state.best_practices)
      assert is_map(mounted_agent.state.refactoring_patterns)
      assert is_map(mounted_agent.state.metrics)
    end
    
    test "initializes with default quality standards" do
      agent = %{id: "test_agent", state: %{}}
      
      {:ok, mounted_agent} = QualityImprovementAgent.mount(agent)
      
      standards = mounted_agent.state.quality_standards
      assert Map.has_key?(standards, "cyclomatic_complexity")
      assert Map.has_key?(standards, "method_length")
      assert Map.has_key?(standards, "documentation_coverage")
    end
    
    test "initializes with default best practices" do
      agent = %{id: "test_agent", state: %{}}
      
      {:ok, mounted_agent} = QualityImprovementAgent.mount(agent)
      
      practices = mounted_agent.state.best_practices
      assert Map.has_key?(practices, "single_responsibility")
      assert Map.has_key?(practices, "dry_principle")
      assert Map.has_key?(practices, "meaningful_names")
    end
  end
  
  describe "analyze_quality signal handling" do
    setup do
      agent = %{
        id: "test_agent",
        state: %{
          analysis_status: :idle,
          active_analyses: %{},
          improvement_history: [],
          quality_standards: %{},
          best_practices: %{},
          refactoring_patterns: %{},
          metrics: %{}
        }
      }
      
      {:ok, mounted_agent} = QualityImprovementAgent.mount(agent)
      {:ok, agent: mounted_agent}
    end
    
    test "handles metrics analysis request", %{agent: agent} do
      signal = %{
        "type" => "analyze_quality",
        "analysis_id" => "test_analysis_1",
        "code" => @sample_code,
        "analysis_scope" => "metrics",
        "options" => %{}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, updated_agent} = result
      assert response.analysis_id == "test_analysis_1"
      assert response.success == true
      assert is_map(response.result)
      assert response.result.type == :metrics_analysis
      
      # Check agent state updates
      assert updated_agent.state.analysis_status == :idle
      assert length(updated_agent.state.improvement_history) == 1
    end
    
    test "handles style analysis request", %{agent: agent} do
      signal = %{
        "type" => "analyze_quality",
        "analysis_id" => "test_analysis_2",
        "code" => @sample_code,
        "analysis_scope" => "style",
        "options" => %{}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, updated_agent} = result
      assert response.result.type == :style_analysis
      assert is_list(response.result.formatting_issues)
      assert is_list(response.result.naming_violations)
    end
    
    test "handles comprehensive analysis request", %{agent: agent} do
      signal = %{
        "type" => "analyze_quality",
        "analysis_id" => "test_analysis_3",
        "code" => @sample_code,
        "analysis_scope" => "comprehensive",
        "options" => %{}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, updated_agent} = result
      assert response.result.type == :comprehensive_quality
      assert is_map(response.result.analyses)
      assert is_number(response.result.overall_quality_score)
      assert is_list(response.result.priority_issues)
      assert is_list(response.result.improvement_roadmap)
    end
    
    test "handles invalid code gracefully", %{agent: agent} do
      signal = %{
        "type" => "analyze_quality",
        "analysis_id" => "test_analysis_4",
        "code" => "invalid elixir code {{{",
        "analysis_scope" => "metrics",
        "options" => %{}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:error, _reason, updated_agent} = result
      assert updated_agent.state.analysis_status == :idle
      assert length(updated_agent.state.improvement_history) == 1
    end
  end
  
  describe "apply_improvements signal handling" do
    setup do
      agent = %{
        id: "test_agent",
        state: %{
          analysis_status: :idle,
          active_analyses: %{},
          improvement_history: [],
          quality_standards: %{},
          best_practices: %{},
          refactoring_patterns: %{},
          metrics: %{}
        }
      }
      
      {:ok, mounted_agent} = QualityImprovementAgent.mount(agent)
      {:ok, agent: mounted_agent}
    end
    
    test "applies conservative improvements", %{agent: agent} do
      improvements = [
        %{
          "type" => "rename_for_clarity",
          "old_name" => "x",
          "new_name" => "input_value",
          "name_type" => "variable",
          "risk_level" => "low",
          "confidence" => 0.9
        }
      ]
      
      signal = %{
        "type" => "apply_improvements",
        "improvement_id" => "improvement_1",
        "code" => @sample_code,
        "improvements" => improvements,
        "strategy" => "conservative",
        "options" => %{}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, updated_agent} = result
      assert response.strategy == "conservative"
      assert is_binary(response.improved_code)
      assert is_list(response.improvements_applied)
      assert is_map(response.quality_delta)
      
      # Check history update
      assert length(updated_agent.state.improvement_history) == 1
    end
    
    test "applies targeted improvements", %{agent: agent} do
      improvements = [
        %{
          "type" => "reduce_complexity",
          "complexity_type" => "cyclomatic",
          "target_function" => "complex_function",
          "area" => "complexity",
          "risk_level" => "medium"
        }
      ]
      
      signal = %{
        "type" => "apply_improvements",
        "improvement_id" => "improvement_2",
        "code" => @sample_code,
        "improvements" => improvements,
        "strategy" => "targeted",
        "options" => %{"target_area" => "complexity"}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, _updated_agent} = result
      assert response.strategy == "targeted"
      assert is_map(response.validation_status)
    end
  end
  
  describe "check_best_practices signal handling" do
    setup do
      agent = %{
        id: "test_agent",
        state: %{
          analysis_status: :idle,
          active_analyses: %{},
          improvement_history: [],
          quality_standards: %{},
          best_practices: %{
            "single_responsibility" => %{
              definition: %{description: "Each class should have only one reason to change"}
            },
            "dry_principle" => %{
              definition: %{description: "Don't repeat yourself"}
            }
          },
          refactoring_patterns: %{},
          metrics: %{}
        }
      }
      
      {:ok, mounted_agent} = QualityImprovementAgent.mount(agent)
      {:ok, agent: mounted_agent}
    end
    
    test "checks best practices compliance", %{agent: agent} do
      practices = ["single_responsibility", "dry_principle"]
      
      signal = %{
        "type" => "check_best_practices",
        "code" => @sample_code,
        "practices" => practices,
        "options" => %{}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, _updated_agent} = result
      assert response.practices_checked == 2
      assert is_list(response.violations)
      assert is_list(response.compliant_practices)
      assert is_number(response.compliance_score)
      assert is_list(response.recommendations)
    end
  end
  
  describe "refactor_code signal handling" do
    setup do
      agent = %{
        id: "test_agent",
        state: %{
          analysis_status: :idle,
          active_analyses: %{},
          improvement_history: [],
          quality_standards: %{},
          best_practices: %{},
          refactoring_patterns: %{
            "extract_method" => %{
              definition: %{description: "Extract repeated code into separate methods"}
            }
          },
          metrics: %{}
        }
      }
      
      {:ok, mounted_agent} = QualityImprovementAgent.mount(agent)
      {:ok, agent: mounted_agent}
    end
    
    test "performs extract method refactoring", %{agent: agent} do
      signal = %{
        "type" => "refactor_code",
        "code" => @sample_code,
        "refactoring_type" => "extract_method",
        "target" => "complex_logic",
        "options" => %{"new_method_name" => "extracted_logic"}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, _updated_agent} = result
      assert is_binary(response.refactored_code)
      assert response.refactoring_type == "extract_method"
      assert response.target == "complex_logic"
      assert is_map(response.changes_made)
      assert is_map(response.impact_analysis)
      assert is_map(response.validation_status)
    end
    
    test "performs rename method refactoring", %{agent: agent} do
      signal = %{
        "type" => "refactor_code",
        "code" => @sample_code,
        "refactoring_type" => "rename_method",
        "target" => "complex_function",
        "options" => %{"new_name" => "calculate_complex_value"}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, _updated_agent} = result
      assert response.refactoring_type == "rename_method"
    end
  end
  
  describe "optimize_performance signal handling" do
    setup do
      agent = %{
        id: "test_agent",
        state: %{
          analysis_status: :idle,
          active_analyses: %{},
          improvement_history: [],
          quality_standards: %{},
          best_practices: %{},
          refactoring_patterns: %{},
          metrics: %{}
        }
      }
      
      {:ok, mounted_agent} = QualityImprovementAgent.mount(agent)
      {:ok, agent: mounted_agent}
    end
    
    test "applies memory optimizations", %{agent: agent} do
      signal = %{
        "type" => "optimize_performance",
        "code" => @sample_code,
        "optimization_target" => "memory",
        "options" => %{}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, _updated_agent} = result
      assert is_binary(response.optimized_code)
      assert response.target == "memory"
      assert is_list(response.optimizations_applied)
      assert is_map(response.performance_improvement)
      assert is_map(response.validation_status)
    end
    
    test "applies general optimizations", %{agent: agent} do
      signal = %{
        "type" => "optimize_performance",
        "code" => @sample_code,
        "optimization_target" => "general",
        "options" => %{}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, _updated_agent} = result
      assert response.target == "general"
      assert is_map(response.performance_improvement)
    end
  end
  
  describe "get_quality_metrics signal handling" do
    setup do
      # Setup agent with some history
      improvement_entry = %{
        type: :improvement,
        improvement_id: "test_improvement",
        result: %{overall_score: 0.75},
        timestamp: DateTime.utc_now()
      }
      
      agent = %{
        id: "test_agent",
        state: %{
          analysis_status: :idle,
          active_analyses: %{},
          improvement_history: [improvement_entry],
          quality_standards: %{},
          best_practices: %{},
          refactoring_patterns: %{},
          metrics: %{
            total_analyses: 5,
            successful_analyses: 4,
            failed_analyses: 1,
            quality_score: 0.8
          }
        }
      }
      
      {:ok, agent: agent}
    end
    
    test "returns quality metrics for all time", %{agent: agent} do
      signal = %{
        "type" => "get_quality_metrics",
        "time_range" => "all"
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, _updated_agent} = result
      assert response.total_analyses == 5
      assert response.successful_analyses == 4
      assert response.failed_analyses == 1
      assert response.quality_score == 0.8
    end
    
    test "returns quality metrics for specific time range", %{agent: agent} do
      signal = %{
        "type" => "get_quality_metrics",
        "time_range" => "day"
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, _updated_agent} = result
      assert is_map(response)
      assert Map.has_key?(response, :time_range)
    end
  end
  
  describe "configuration signal handling" do
    setup do
      agent = %{
        id: "test_agent",
        state: %{
          analysis_status: :idle,
          active_analyses: %{},
          improvement_history: [],
          quality_standards: %{},
          best_practices: %{},
          refactoring_patterns: %{},
          metrics: %{}
        }
      }
      
      {:ok, agent: agent}
    end
    
    test "adds quality standard", %{agent: agent} do
      signal = %{
        "type" => "update_standards",
        "standard_id" => "test_standard",
        "standard_definition" => %{
          "max_complexity" => 15,
          "description" => "Maximum allowed complexity"
        }
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, updated_agent} = result
      assert response.updated == true
      assert response.standard_id == "test_standard"
      assert Map.has_key?(updated_agent.state.quality_standards, "test_standard")
    end
    
    test "adds best practice", %{agent: agent} do
      signal = %{
        "type" => "add_best_practice",
        "practice_id" => "test_practice",
        "practice_definition" => %{
          "description" => "Test practice description"
        }
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, updated_agent} = result
      assert response.added == true
      assert response.practice_id == "test_practice"
      assert Map.has_key?(updated_agent.state.best_practices, "test_practice")
    end
    
    test "adds refactoring pattern", %{agent: agent} do
      signal = %{
        "type" => "add_refactoring_pattern",
        "pattern_id" => "test_pattern",
        "pattern_definition" => %{
          "description" => "Test refactoring pattern"
        }
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:ok, response, updated_agent} = result
      assert response.added == true
      assert response.pattern_id == "test_pattern"
      assert Map.has_key?(updated_agent.state.refactoring_patterns, "test_pattern")
    end
  end
  
  describe "error handling" do
    setup do
      agent = %{
        id: "test_agent",
        state: %{
          analysis_status: :idle,
          active_analyses: %{},
          improvement_history: [],
          quality_standards: %{},
          best_practices: %{},
          refactoring_patterns: %{},
          metrics: %{}
        }
      }
      
      {:ok, agent: agent}
    end
    
    test "handles unknown signal type", %{agent: agent} do
      signal = %{
        "type" => "unknown_signal",
        "data" => "test"
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:error, error_message, _updated_agent} = result
      assert String.contains?(error_message, "Unknown signal type")
    end
    
    test "handles invalid analysis scope", %{agent: agent} do
      signal = %{
        "type" => "analyze_quality",
        "analysis_id" => "test_analysis",
        "code" => @sample_code,
        "analysis_scope" => "invalid_scope",
        "options" => %{}
      }
      
      result = QualityImprovementAgent.handle_signal(agent, signal)
      
      assert {:error, _reason, updated_agent} = result
      assert updated_agent.state.analysis_status == :idle
    end
  end
  
  describe "agent lifecycle" do
    test "unmounts successfully and cleans up active analyses" do
      # Setup agent with active analysis
      analysis_info = %{
        analysis_id: "active_analysis",
        status: :in_progress,
        started_at: DateTime.utc_now()
      }
      
      agent = %{
        id: "test_agent",
        state: %{
          analysis_status: :analyzing,
          active_analyses: %{"active_analysis" => analysis_info},
          improvement_history: [],
          quality_standards: %{},
          best_practices: %{},
          refactoring_patterns: %{},
          metrics: %{}
        }
      }
      
      {:ok, unmounted_agent} = QualityImprovementAgent.unmount(agent)
      
      assert unmounted_agent.state.active_analyses == %{}
      assert length(unmounted_agent.state.improvement_history) == 1
      
      # Check that the active analysis was marked as interrupted
      interrupted_analysis = List.first(unmounted_agent.state.improvement_history)
      assert interrupted_analysis.status == :interrupted
    end
  end
end