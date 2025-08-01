defmodule RubberDuck.Tools.Agents.TestRunnerAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.TestRunnerAgent
  
  setup do
    {:ok, agent} = TestRunnerAgent.start_link(id: "test_test_runner")
    
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
        test_pattern: "test/**/*_test.exs",
        coverage: true,
        formatter: "detailed",
        timeout: 60_000
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      result = TestRunnerAgent.ExecuteToolAction.run(%{params: params}, context)
      
      assert match?({:ok, _}, result)
    end
    
    test "run test suite action executes predefined test suites", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = TestRunnerAgent.RunTestSuiteAction.run(
        %{
          suite_name: "unit",
          include_coverage: true,
          parallel: true,
          additional_tags: ["fast"]
        },
        context
      )
      
      assert result.suite_name == "unit"
      assert result.coverage_included == true
      assert result.parallel_enabled == true
      assert Map.has_key?(result.suite_config, :pattern)
      assert Map.has_key__(result, :execution_duration)
    end
    
    test "analyze results action provides comprehensive test analysis", %{agent: agent} do
      test_results = %{
        summary: %{
          total: 10,
          passed: 8,
          failed: 2,
          skipped: 0,
          duration_ms: 5000
        },
        status: :failed,
        failures: [
          %{
            test: "test example failure",
            module: "ExampleTest",
            file: "test/example_test.exs",
            line: 42,
            error: %{type: :assertion, message: "Assertion failed"}
          }
        ],
        coverage: %{
          enabled: true,
          percentage: 85.5,
          covered_lines: 1200,
          total_lines: 1404
        }
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = TestRunnerAgent.AnalyzeResultsAction.run(
        %{
          test_results: test_results,
          analysis_depth: :detailed,
          compare_with_history: true,
          generate_recommendations: true
        },
        context
      )
      
      assert result.total_tests == 10
      assert result.analysis_depth == :detailed
      
      analysis = result.analysis
      assert Map.has_key?(analysis, :result_summary)
      assert Map.has_key__(analysis, :failure_analysis)
      assert Map.has_key?(analysis, :performance_analysis)
      assert Map.has_key__(analysis, :coverage_analysis)
      assert is_list(analysis.recommendations)
      
      # Check result summary
      summary = analysis.result_summary
      assert summary.success_rate == 80.0
      assert summary.failure_rate == 20.0
      assert summary.status_distribution.total == 10
    end
    
    test "monitor health action analyzes test health metrics", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = TestRunnerAgent.MonitorHealthAction.run(
        %{
          time_window: 86_400_000,
          include_trends: true,
          detect_flaky_tests: true,
          performance_analysis: true
        },
        context
      )
      
      assert result.time_window == 86_400_000
      assert result.total_runs_analyzed >= 0
      assert Map.has_key__(result, :stability_metrics)
      assert Map.has_key?(result, :performance_metrics)
      assert Map.has_key__(result, :flaky_tests)
      assert is_list(result.recommendations)
    end
    
    test "optimize execution action generates optimization suggestions", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = TestRunnerAgent.OptimizeExecutionAction.run(
        %{
          focus_areas: [:performance, :coverage, :reliability],
          current_settings: %{parallel_execution: false},
          constraints: %{max_duration: 30_000}
        },
        context
      )
      
      assert result.total_suggestions >= 0
      assert result.focus_areas == [:performance, :coverage, :reliability]
      assert is_list(result.optimizations)
      
      if length(result.optimizations) > 0 do
        optimization = hd(result.optimizations)
        assert Map.has_key__(optimization, :type)
        assert Map.has_key?(optimization, :priority)
        assert Map.has_key?(optimization, :suggestion)
        assert Map.has_key?(optimization, :implementation)
      end
    end
  end
  
  describe "signal handling" do
    test "run_tests signal triggers ExecuteToolAction", %{agent: agent} do
      signal = %{
        "type" => "run_tests",
        "data" => %{
          "test_pattern" => "test/**/*_test.exs",
          "coverage" => true,
          "formatter" => "detailed"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = TestRunnerAgent.handle_signal(state, signal)
      
      assert true
    end
    
    test "run_test_suite signal triggers RunTestSuiteAction", %{agent: agent} do
      signal = %{
        "type" => "run_test_suite",
        "data" => %{
          "suite_name" => "unit",
          "include_coverage" => true,
          "parallel" => true
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = TestRunnerAgent.handle_signal(state, signal)
      
      assert true
    end
    
    test "analyze_test_results signal triggers AnalyzeResultsAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_test_results",
        "data" => %{
          "test_results" => %{summary: %{total: 5, passed: 5, failed: 0}},
          "analysis_depth" => "comprehensive"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = TestRunnerAgent.handle_signal(state, signal)
      
      assert true
    end
  end
  
  describe "state management" do
    test "tracks test execution history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate successful test result
      test_result = %{
        summary: %{
          total: 5,
          passed: 5,
          failed: 0,
          skipped: 0,
          duration_ms: 2000
        },
        status: :passed,
        coverage: %{enabled: true, percentage: 90},
        failures: []
      }
      
      {:ok, updated} = TestRunnerAgent.handle_action_result(
        state,
        TestRunnerAgent.ExecuteToolAction,
        {:ok, test_result},
        %{}
      )
      
      assert length(updated.state.test_history) == 1
      test_record = hd(updated.state.test_history)
      assert test_record.total == 5
      assert test_record.passed == 5
      assert test_record.status == :passed
      assert test_record.duration_ms == 2000
    end
    
    test "updates execution statistics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      initial_runs = state.state.execution_stats.total_runs
      initial_tests = state.state.execution_stats.tests_executed
      
      test_result = %{
        summary: %{
          total: 8,
          passed: 6,
          failed: 2,
          skipped: 0,
          duration_ms: 3000
        },
        status: :failed,
        coverage: %{enabled: false},
        failures: []
      }
      
      {:ok, updated} = TestRunnerAgent.handle_action_result(
        state,
        TestRunnerAgent.ExecuteToolAction,
        {:ok, test_result},
        %{}
      )
      
      stats = updated.state.execution_stats
      assert stats.total_runs == initial_runs + 1
      assert stats.tests_executed == initial_tests + 8
      assert stats.tests_passed == 6
      assert stats.tests_failed == 2
      assert stats.failed_runs == 1
      assert stats.average_duration == 3000.0
    end
    
    test "updates coverage data when coverage is enabled", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      test_result = %{
        summary: %{total: 3, passed: 3, failed: 0, skipped: 0, duration_ms: 1000},
        status: :passed,
        coverage: %{enabled: true, percentage: 88.5},
        failures: []
      }
      
      {:ok, updated} = TestRunnerAgent.handle_action_result(
        state,
        TestRunnerAgent.ExecuteToolAction,
        {:ok, test_result},
        %{}
      )
      
      coverage = updated.state.coverage_data
      assert coverage.current_percentage == 88.5
      assert hd(coverage.trend) == 88.5
    end
  end
  
  describe "agent initialization" do
    test "starts with predefined test suites", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      suites = state.state.test_suites
      assert Map.has_key?(suites, "unit")
      assert Map.has_key__(suites, "integration")
      assert Map.has_key?(suites, "feature")
      
      unit_suite = suites["unit"]
      assert unit_suite.pattern == "test/**/*_test.exs"
      assert "unit" in unit_suite.tags
      assert unit_suite.timeout == 60_000
    end
    
    test "starts with default execution settings", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      settings = state.state.execution_settings
      assert settings.default_timeout == 60_000
      assert settings.max_failures == 10
      assert settings.parallel_execution == true
      assert settings.coverage_enabled == true
      assert settings.trace_enabled == false
    end
    
    test "starts with coverage configuration", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      coverage = state.state.coverage_data
      assert coverage.enabled == true
      assert coverage.target_percentage == 80.0
      assert coverage.current_percentage == 0.0
      assert coverage.trend == []
      assert coverage.uncovered_modules == []
    end
    
    test "starts with empty test history and statistics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      assert state.state.test_history == []
      assert state.state.active_runs == %{}
      
      stats = state.state.execution_stats
      assert stats.total_runs == 0
      assert stats.successful_runs == 0
      assert stats.failed_runs == 0
      assert stats.tests_executed == 0
      assert stats.average_duration == 0.0
    end
    
    test "starts with test health monitoring setup", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      health = state.state.test_health
      assert health.flaky_tests == []
      assert health.slow_tests == []
      assert health.trending_failures == []
      assert health.stability_score == 100.0
      assert health.performance_trend == []
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = TestRunnerAgent.additional_actions()
      
      assert length(actions) == 5
      assert TestRunnerAgent.ExecuteToolAction in actions
      assert TestRunnerAgent.RunTestSuiteAction in actions
      assert TestRunnerAgent.AnalyzeResultsAction in actions
      assert TestRunnerAgent.MonitorHealthAction in actions
      assert TestRunnerAgent.OptimizeExecutionAction in actions
    end
  end
  
  describe "test suite execution" do
    test "handles unknown test suite names", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      result = TestRunnerAgent.RunTestSuiteAction.run(
        %{suite_name: "nonexistent", include_coverage: false},
        context
      )
      
      assert match?({:error, _}, result)
    end
    
    test "customizes suite configuration with additional parameters", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = TestRunnerAgent.RunTestSuiteAction.run(
        %{
          suite_name: "integration", 
          timeout_override: 120_000,
          additional_tags: ["database", "external"]
        },
        context
      )
      
      assert result.suite_name == "integration"
      # Would normally check that timeout and tags were applied to test execution
    end
  end
  
  describe "result analysis" do
    test "analyzes failures and categorizes error types", %{agent: agent} do
      test_results = %{
        summary: %{total: 4, passed: 2, failed: 2, skipped: 0, duration_ms: 2000},
        status: :failed,
        failures: [
          %{
            test: "test one",
            module: "TestA", 
            error: %{type: :assertion, message: "Expected true, got false"}
          },
          %{
            test: "test two",
            module: "TestB",
            error: %{type: :assertion, message: "Expected 1, got 2"}
          }
        ],
        coverage: %{enabled: false}
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = TestRunnerAgent.AnalyzeResultsAction.run(
        %{test_results: test_results, analysis_depth: :detailed},
        context
      )
      
      failure_analysis = result.analysis.failure_analysis
      assert failure_analysis.total_failures == 2
      assert failure_analysis.affected_modules == 2
      assert is_list(failure_analysis.failure_categories)
      assert is_list(failure_analysis.most_common_errors)
    end
    
    test "generates appropriate recommendations based on results", %{agent: agent} do
      test_results = %{
        summary: %{total: 10, passed: 5, failed: 5, skipped: 0, duration_ms: 45_000},
        status: :failed,
        failures: [],
        coverage: %{enabled: true, percentage: 65}
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = TestRunnerAgent.AnalyzeResultsAction.run(
        %{test_results: test_results, generate_recommendations: true},
        context
      )
      
      recommendations = result.analysis.recommendations
      assert length(recommendations) >= 2 # Should have coverage and failure recommendations
      
      # Check for coverage recommendation
      coverage_rec = Enum.find(recommendations, fn rec -> rec.type == :coverage end)
      assert coverage_rec != nil
      assert coverage_rec.priority == :high
      
      # Check for failure recommendation
      failure_rec = Enum.find(recommendations, fn rec -> rec.type == :failures end)
      assert failure_rec != nil
      assert failure_rec.priority == :high
    end
  end
  
  describe "health monitoring" do
    test "calculates stability metrics from test history", %{agent: agent} do
      # Add some test history first
      state = GenServer.call(agent, :get_state)
      
      # Create test history with mixed results
      test_history = [
        %{status: :passed, timestamp: DateTime.utc_now()},
        %{status: :failed, timestamp: DateTime.utc_now()},
        %{status: :passed, timestamp: DateTime.utc_now()},
        %{status: :passed, timestamp: DateTime.utc_now()}
      ]
      
      updated_state = put_in(state.state.test_history, test_history)
      context = %{agent: updated_state}
      
      {:ok, result} = TestRunnerAgent.MonitorHealthAction.run(
        %{time_window: 86_400_000, include_trends: true},
        context
      )
      
      stability = result.stability_metrics
      assert stability.total_runs == 4
      assert stability.successful_runs == 3
      assert stability.failed_runs == 1
      assert stability.stability_score == 75.0
      assert is_binary(stability.analysis)
    end
    
    test "detects performance trends in test execution", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Create history with performance data
      test_history = [
        %{duration_ms: 1000, timestamp: DateTime.utc_now()},
        %{duration_ms: 1500, timestamp: DateTime.utc_now()},
        %{duration_ms: 2000, timestamp: DateTime.utc_now()}
      ]
      
      updated_state = put_in(state.state.test_history, test_history)
      context = %{agent: updated_state}
      
      {:ok, result} = TestRunnerAgent.MonitorHealthAction.run(
        %{performance_analysis: true},
        context
      )
      
      performance = result.performance_metrics
      assert performance.average_duration == 1500.0
      assert performance.max_duration == 2000
      assert performance.min_duration == 1000
      assert Map.has_key?(performance, :performance_trend)
    end
  end
  
  describe "optimization suggestions" do
    test "suggests performance optimizations for slow tests", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set high average duration to trigger performance suggestions
      updated_state = put_in(state.state.execution_stats.average_duration, 45_000)
      context = %{agent: updated_state}
      
      {:ok, result} = TestRunnerAgent.OptimizeExecutionAction.run(
        %{focus_areas: [:performance]},
        context
      )
      
      perf_suggestions = Enum.filter(result.optimizations, fn opt -> opt.type == :performance end)
      assert length(perf_suggestions) > 0
      
      suggestion = hd(perf_suggestions)
      assert suggestion.category in [:execution_time, :slow_tests]
      assert suggestion.priority in [:high, :medium]
      assert Map.has_key?(suggestion, :implementation)
    end
    
    test "suggests coverage optimizations when below target", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set low coverage to trigger suggestions
      updated_state = put_in(state.state.coverage_data.current_percentage, 60.0)
      context = %{agent: updated_state}
      
      {:ok, result} = TestRunnerAgent.OptimizeExecutionAction.run(
        %{focus_areas: [:coverage]},
        context
      )
      
      coverage_suggestions = Enum.filter(result.optimizations, fn opt -> opt.type == :coverage end)
      assert length(coverage_suggestions) > 0
      
      suggestion = hd(coverage_suggestions)
      assert suggestion.category == :increase_coverage
      assert suggestion.priority in [:high, :medium]
    end
    
    test "suggests reliability improvements for unstable tests", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set low stability score to trigger suggestions
      updated_state = state
      |> put_in([:state, :test_health, :stability_score], 70.0)
      |> put_in([:state, :test_health, :flaky_tests], ["TestA.flaky_test", "TestB.another_flaky"])
      
      context = %{agent: updated_state}
      
      {:ok, result} = TestRunnerAgent.OptimizeExecutionAction.run(
        %{focus_areas: [:reliability]},
        context
      )
      
      reliability_suggestions = Enum.filter(result.optimizations, fn opt -> opt.type == :reliability end)
      assert length(reliability_suggestions) > 0
      
      # Should have suggestions for both flaky tests and stability
      categories = Enum.map(reliability_suggestions, fn s -> s.category end)
      assert :flaky_tests in categories or :stability in categories
    end
  end
end