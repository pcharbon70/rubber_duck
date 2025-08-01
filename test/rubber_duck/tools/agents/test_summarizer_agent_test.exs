defmodule RubberDuck.Tools.Agents.TestSummarizerAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.TestSummarizerAgent
  
  setup do
    {:ok, agent} = TestSummarizerAgent.start_link(id: "test_test_summarizer")
    
    on_exit(fn ->
      if Process.alive?(agent) do
        GenServer.stop(agent)
      end
    end)
    
    %{agent: agent}
  end
  
  describe "action execution" do
    test "executes tool via ExecuteToolAction", %{agent: agent} do
      params = %{
        test_output: """
        ....F..F..
        
        1) test addition (MathTest)
           test/math_test.exs:10
           Assertion with == failed
           code: assert add(1, 1) == 3
           left: 2
           right: 3
        
        2) test multiplication (MathTest)
           test/math_test.exs:20
           ** (ArithmeticError) bad argument in arithmetic expression
        
        Finished in 0.05 seconds
        10 tests, 2 failures
        """,
        format: "exunit",
        summary_type: "comprehensive"
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      result = TestSummarizerAgent.ExecuteToolAction.run(%{params: params}, context)
      
      assert match?({:ok, _}, result)
      {:ok, summary} = result
      
      assert summary.statistics.total == 10
      assert summary.statistics.failed == 2
      assert summary.statistics.passed == 8
      assert length(summary.failures) == 2
    end
    
    test "analyze trends action calculates trends over time", %{agent: agent} do
      # Add some test history
      state = GenServer.call(agent, :get_state)
      
      history = [
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -86400, :second),
          statistics: %{total: 100, passed: 90, failed: 10, pass_rate: 90.0, avg_duration: 45.0}
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -43200, :second),
          statistics: %{total: 100, passed: 92, failed: 8, pass_rate: 92.0, avg_duration: 42.0}
        },
        %{
          timestamp: DateTime.utc_now(),
          statistics: %{total: 100, passed: 95, failed: 5, pass_rate: 95.0, avg_duration: 40.0}
        }
      ]
      
      state = put_in(state.state.test_history, history)
      context = %{agent: state}
      
      {:ok, result} = TestSummarizerAgent.AnalyzeTrendsAction.run(
        %{
          time_window: :last_week,
          metrics: [:pass_rate, :duration],
          group_by: :day
        },
        context
      )
      
      assert result.data_points == 3
      assert Map.has_key?(result.trends, :pass_rate)
      assert Map.has_key?(result.trends, :duration)
      assert result.health_trend in [:improving, :stable, :declining]
    end
    
    test "identify flaky tests action finds inconsistent tests", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Create history with flaky test behavior
      history = [
        %{
          timestamp: DateTime.utc_now(),
          statistics: %{total: 10, passed: 9, failed: 1},
          failures: [%{test_name: "flaky_test", failure_type: :timeout}]
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -3600, :second),
          statistics: %{total: 10, passed: 10, failed: 0},
          failures: []
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -7200, :second),
          statistics: %{total: 10, passed: 9, failed: 1},
          failures: [%{test_name: "flaky_test", failure_type: :connection}]
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -10800, :second),
          statistics: %{total: 10, passed: 10, failed: 0},
          failures: []
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -14400, :second),
          statistics: %{total: 10, passed: 9, failed: 1},
          failures: [%{test_name: "flaky_test", failure_type: :timeout}]
        }
      ]
      
      state = put_in(state.state.test_history, history)
      context = %{agent: state}
      
      {:ok, result} = TestSummarizerAgent.IdentifyFlakyTestsAction.run(
        %{
          min_runs: 3,
          flakiness_threshold: 0.2,
          time_window: :last_week
        },
        context
      )
      
      assert result.total_tests_analyzed >= 0
      assert is_list(result.flaky_tests)
      assert is_list(result.recommendations)
    end
    
    test "generate improvement plan creates actionable recommendations", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set up state with issues
      state = put_in(state.state.test_metrics, %{
        average_pass_rate: 75.0,
        average_duration: 120.0,
        total_runs_analyzed: 10,
        health_trend: :declining
      })
      
      state = put_in(state.state.failure_patterns, %{
        by_type: %{assertion: 10, timeout: 5},
        by_test: %{},
        by_file: %{}
      })
      
      state = put_in(state.state.coverage_data, %{
        line_coverage: 65.0,
        branch_coverage: 50.0,
        uncovered_files: ["lib/important.ex", "lib/critical.ex"]
      })
      
      context = %{agent: state}
      
      {:ok, result} = TestSummarizerAgent.GenerateImprovementPlanAction.run(
        %{
          focus_areas: [:failures, :coverage, :performance],
          max_recommendations: 5
        },
        context
      )
      
      assert result.total_recommendations > 0
      assert Map.has_key?(result, :plan)
      assert Map.has_key?(result, :summary)
      assert Map.has_key?(result, :estimated_impact)
    end
    
    test "compare test runs identifies changes between runs", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      older_run = %{
        id: "run1",
        timestamp: DateTime.add(DateTime.utc_now(), -3600, :second),
        statistics: %{total: 100, passed: 80, failed: 20, pass_rate: 80.0},
        failures: [
          %{test_name: "test1", failure_type: :assertion},
          %{test_name: "test2", failure_type: :timeout}
        ]
      }
      
      newer_run = %{
        id: "run2",
        timestamp: DateTime.utc_now(),
        statistics: %{total: 100, passed: 90, failed: 10, pass_rate: 90.0},
        failures: [
          %{test_name: "test2", failure_type: :timeout},
          %{test_name: "test3", failure_type: :assertion}
        ]
      }
      
      state = put_in(state.state.test_history, [newer_run, older_run])
      context = %{agent: state}
      
      {:ok, result} = TestSummarizerAgent.CompareTestRunsAction.run(
        %{compare_latest: 2},
        context
      )
      
      assert Map.has_key?(result, :comparison)
      assert Map.has_key?(result, :improvements)
      assert Map.has_key?(result, :regressions)
      
      comparison = result.comparison
      assert "test1" in comparison.failures.fixed_tests
      assert "test3" in comparison.failures.new_failures
      assert "test2" in comparison.failures.persistent_failures
    end
    
    test "generate report action creates formatted report", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set up some test data
      state = put_in(state.state.test_metrics, %{
        average_pass_rate: 85.0,
        average_duration: 30.0,
        total_runs_analyzed: 25,
        health_trend: :stable
      })
      
      state = put_in(state.state.test_history, [
        %{
          timestamp: DateTime.utc_now(),
          statistics: %{total: 100, passed: 85, failed: 15, pass_rate: 85.0}
        }
      ])
      
      context = %{agent: state}
      
      {:ok, result} = TestSummarizerAgent.GenerateReportAction.run(
        %{
          format: :markdown,
          sections: [:summary, :trends, :recommendations]
        },
        context
      )
      
      assert result.format == :markdown
      assert is_binary(result.report)
      assert result.report =~ "Test Suite Report"
      assert Map.has_key?(result.metadata, :generated_at)
    end
  end
  
  describe "signal handling" do
    test "analyze_test_results signal triggers ExecuteToolAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_test_results",
        "data" => %{
          "test_output" => "5 tests, 1 failure",
          "format" => "exunit"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = TestSummarizerAgent.handle_signal(state, signal)
      
      assert true
    end
    
    test "analyze_trends signal triggers trend analysis", %{agent: agent} do
      signal = %{
        "type" => "analyze_trends",
        "data" => %{
          "time_window" => :last_week,
          "metrics" => [:pass_rate]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      result = TestSummarizerAgent.handle_signal(state, signal)
      
      assert match?({:ok, _}, result)
    end
    
    test "identify_flaky signal triggers flaky test detection", %{agent: agent} do
      signal = %{
        "type" => "identify_flaky",
        "data" => %{
          "min_runs" => 5
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = TestSummarizerAgent.handle_signal(state, signal)
      
      assert true
    end
  end
  
  describe "state management" do
    test "updates test history after analysis", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        statistics: %{total: 50, passed: 45, failed: 5, pass_rate: 90.0},
        failures: [
          %{test_name: "failing_test", failure_type: :assertion, file: "test.exs"}
        ],
        insights: %{key_findings: ["High pass rate"]},
        recommendations: ["Keep up the good work"]
      }
      
      {:ok, updated} = TestSummarizerAgent.handle_action_result(
        state,
        TestSummarizerAgent.ExecuteToolAction,
        {:ok, result},
        %{}
      )
      
      assert length(updated.test_history) == 1
      history_entry = hd(updated.test_history)
      assert history_entry.statistics == result.statistics
      assert history_entry.failures == result.failures
    end
    
    test "updates failure patterns tracking", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        statistics: %{total: 10, passed: 8, failed: 2, pass_rate: 80.0},
        failures: [
          %{test_name: "test1", failure_type: :assertion, file: "test1.exs"},
          %{test_name: "test2", failure_type: :timeout, file: "test2.exs"}
        ],
        insights: %{}
      }
      
      {:ok, updated} = TestSummarizerAgent.handle_action_result(
        state,
        TestSummarizerAgent.ExecuteToolAction,
        {:ok, result},
        %{}
      )
      
      patterns = updated.failure_patterns
      assert patterns.by_type[:assertion] == 1
      assert patterns.by_type[:timeout] == 1
      assert patterns.by_test["test1"] == 1
      assert patterns.by_file["test1.exs"] == 1
    end
    
    test "updates test metrics with running averages", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # First result
      result1 = %{
        statistics: %{total: 100, passed: 80, failed: 20, pass_rate: 80.0, avg_duration: 30.0},
        failures: [],
        insights: %{}
      }
      
      {:ok, updated1} = TestSummarizerAgent.handle_action_result(
        state,
        TestSummarizerAgent.ExecuteToolAction,
        {:ok, result1},
        %{}
      )
      
      assert updated1.test_metrics.average_pass_rate == 80.0
      assert updated1.test_metrics.average_duration == 30.0
      assert updated1.test_metrics.total_runs_analyzed == 1
      
      # Second result
      result2 = %{
        statistics: %{total: 100, passed: 90, failed: 10, pass_rate: 90.0, avg_duration: 40.0},
        failures: [],
        insights: %{}
      }
      
      {:ok, updated2} = TestSummarizerAgent.handle_action_result(
        updated1,
        TestSummarizerAgent.ExecuteToolAction,
        {:ok, result2},
        %{}
      )
      
      # Should be average of 80 and 90
      assert updated2.test_metrics.average_pass_rate == 85.0
      assert updated2.test_metrics.average_duration == 35.0
      assert updated2.test_metrics.total_runs_analyzed == 2
    end
    
    test "caches recommendations", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        statistics: %{total: 10, passed: 8, failed: 2, pass_rate: 80.0},
        failures: [],
        insights: %{},
        recommendations: ["Fix timeout issues", "Increase test coverage"]
      }
      
      {:ok, updated} = TestSummarizerAgent.handle_action_result(
        state,
        TestSummarizerAgent.ExecuteToolAction,
        {:ok, result},
        %{}
      )
      
      assert map_size(updated.recommendations_cache) == 2
    end
  end
  
  describe "agent initialization" do
    test "starts with default analysis configuration", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      config = state.state.analysis_config
      assert config.default_format == "auto"
      assert config.default_summary_type == "comprehensive"
      assert config.group_failures == true
      assert config.highlight_flaky == true
      assert config.suggest_fixes == true
    end
    
    test "starts with empty test history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      assert state.state.test_history == []
      assert state.state.active_analyses == %{}
    end
    
    test "starts with zero metrics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      metrics = state.state.test_metrics
      assert metrics.average_pass_rate == 0.0
      assert metrics.average_duration == 0.0
      assert metrics.total_runs_analyzed == 0
      assert metrics.health_trend == :stable
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = TestSummarizerAgent.additional_actions()
      
      assert length(actions) == 6
      assert TestSummarizerAgent.ExecuteToolAction in actions
      assert TestSummarizerAgent.AnalyzeTrendsAction in actions
      assert TestSummarizerAgent.IdentifyFlakyTestsAction in actions
      assert TestSummarizerAgent.GenerateImprovementPlanAction in actions
      assert TestSummarizerAgent.CompareTestRunsAction in actions
      assert TestSummarizerAgent.GenerateReportAction in actions
    end
  end
  
  describe "trend analysis" do
    test "calculates pass rate trends correctly", %{agent: agent} do
      history = [
        %{timestamp: DateTime.utc_now(), statistics: %{pass_rate: 95.0}},
        %{timestamp: DateTime.add(DateTime.utc_now(), -3600, :second), statistics: %{pass_rate: 90.0}},
        %{timestamp: DateTime.add(DateTime.utc_now(), -7200, :second), statistics: %{pass_rate: 85.0}}
      ]
      
      trend = TestSummarizerAgent.AnalyzeTrendsAction.calculate_trend(history, :pass_rate, :day)
      
      assert is_list(trend)
      assert length(trend) > 0
      
      first_point = hd(trend)
      assert Map.has_key?(first_point, :period)
      assert Map.has_key?(first_point, :value)
      assert Map.has_key?(first_point, :sample_size)
    end
    
    test "determines health trend from data", %{agent: agent} do
      improving_trend = %{
        pass_rate: [
          %{value: 80.0},
          %{value: 85.0},
          %{value: 90.0}
        ]
      }
      
      health = TestSummarizerAgent.AnalyzeTrendsAction.determine_health_trend(improving_trend)
      assert health == :improving
    end
  end
  
  describe "flaky test detection" do
    test "calculates flakiness score correctly", %{agent: agent} do
      test_data = %{
        total_runs: 10,
        failures: 5,
        failure_rate: 0.5,
        failure_reasons: %{timeout: 3, connection: 2}
      }
      
      score = TestSummarizerAgent.IdentifyFlakyTestsAction.calculate_flakiness_score(test_data)
      
      assert is_float(score)
      assert score >= 0 and score <= 1
    end
    
    test "generates appropriate recommendations for flaky tests", %{agent: agent} do
      flaky_tests = [
        %{test_name: "test1", failure_reasons: %{timeout: 5}},
        %{test_name: "test2", failure_reasons: %{connection: 3}}
      ]
      
      recommendations = TestSummarizerAgent.IdentifyFlakyTestsAction.generate_flaky_test_recommendations(flaky_tests)
      
      assert is_list(recommendations)
      assert Enum.any?(recommendations, &String.contains?(&1, "timeout"))
      assert Enum.any?(recommendations, &String.contains?(&1, "connection"))
    end
  end
  
  describe "improvement planning" do
    test "prioritizes recommendations correctly", %{agent: agent} do
      recommendations = [
        %{priority_score: 90, category: :failures},
        %{priority_score: 30, category: :coverage},
        %{priority_score: 60, category: :performance}
      ]
      
      filtered = TestSummarizerAgent.GenerateImprovementPlanAction.filter_by_priority(
        recommendations,
        :high
      )
      
      assert length(filtered) == 2
      assert Enum.all?(filtered, &(&1.priority_score >= 60))
    end
    
    test "estimates improvement impact", %{agent: agent} do
      state = %{test_metrics: %{average_pass_rate: 70.0}}
      
      recommendations = [
        %{category: :failures},
        %{category: :failures},
        %{category: :coverage}
      ]
      
      impact = TestSummarizerAgent.GenerateImprovementPlanAction.estimate_improvement_impact(
        recommendations,
        state
      )
      
      assert impact.current_pass_rate == 70.0
      assert impact.estimated_pass_rate > 70.0
      assert impact.improvement_percentage > 0
    end
  end
  
  describe "report generation" do
    test "formats markdown report correctly", %{agent: agent} do
      sections = %{
        summary: %{
          overall_health: :good,
          average_pass_rate: 85.0
        },
        trends: %{
          pass_rate_trend: [%{timestamp: DateTime.utc_now(), value: 85.0}]
        }
      }
      
      report = TestSummarizerAgent.GenerateReportAction.format_markdown_report(sections, %{})
      
      assert is_binary(report)
      assert report =~ "# Test Suite Report"
      assert report =~ "## Summary"
      assert report =~ "## Trends"
    end
    
    test "calculates health score accurately", %{agent: agent} do
      state = %{
        test_metrics: %{
          average_pass_rate: 85.0,
          health_trend: :stable
        },
        flaky_tests: %{"test1" => %{}, "test2" => %{}}
      }
      
      score = TestSummarizerAgent.GenerateReportAction.calculate_health_score(state)
      
      assert is_float(score) or is_integer(score)
      assert score >= 0 and score <= 100
      # 85 pass rate - 10 flaky penalty = 75
      assert score == 75
    end
  end
end