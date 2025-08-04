defmodule RubberDuck.Tools.Agents.TestRunnerAgent do
  @moduledoc """
  Agent that orchestrates the TestRunner tool for intelligent test execution workflows.
  
  This agent manages test execution requests, maintains test run history, handles test
  suites and coverage analysis, and provides smart test execution recommendations.
  
  ## Signals
  
  ### Input Signals
  - `run_tests` - Execute tests with specified parameters
  - `run_test_suite` - Run complete test suite with coverage
  - `run_focused_tests` - Run tests matching specific patterns or filters
  - `analyze_test_results` - Analyze test results for patterns and insights
  - `monitor_test_health` - Monitor ongoing test health and trends
  - `optimize_test_execution` - Suggest test execution optimizations
  
  ### Output Signals
  - `tests_completed` - Test run completed successfully
  - `tests_failed` - Test run completed with failures
  - `test_results_analyzed` - Test result analysis completed
  - `test_health_report` - Test health monitoring report ready
  - `test_optimization_suggestions` - Test optimization suggestions generated
  - `test_execution_error` - Error during test execution
  """
  
  use Jido.Agent,
    name: "test_runner_agent",
    description: "Manages intelligent test execution and analysis workflows",
    category: "testing",
    tags: ["testing", "quality", "ci", "automation", "coverage"],
    schema: [
      # Test execution history
      test_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 100],
      
      # Test suite management
      test_suites: [type: :map, default: %{
        "unit" => %{
          pattern: "test/**/*_test.exs",
          tags: ["unit"],
          timeout: 60_000
        },
        "integration" => %{
          pattern: "test/integration/**/*_test.exs", 
          tags: ["integration"],
          timeout: 300_000
        },
        "feature" => %{
          pattern: "test/features/**/*_test.exs",
          tags: ["feature"],
          timeout: 600_000
        }
      }],
      
      # Coverage tracking
      coverage_data: [type: :map, default: %{
        enabled: true,
        target_percentage: 80.0,
        current_percentage: 0.0,
        trend: [],
        uncovered_modules: []
      }],
      
      # Test execution settings
      execution_settings: [type: :map, default: %{
        default_timeout: 60_000,
        max_failures: 10,
        parallel_execution: true,
        coverage_enabled: true,
        trace_enabled: false
      }],
      
      # Test health monitoring
      test_health: [type: :map, default: %{
        flaky_tests: [],
        slow_tests: [],
        trending_failures: [],
        stability_score: 100.0,
        performance_trend: []
      }],
      
      # Active test runs
      active_runs: [type: :map, default: %{}],
      
      # Test execution statistics
      execution_stats: [type: :map, default: %{
        total_runs: 0,
        successful_runs: 0,
        failed_runs: 0,
        average_duration: 0.0,
        tests_executed: 0,
        tests_passed: 0,
        tests_failed: 0,
        coverage_trend: []
      }],
      
      # Optimization suggestions
      optimization_suggestions: [type: {:list, :map}, default: []],
      
      # Test patterns and filters
      test_patterns: [type: :map, default: %{
        "failed_last_run" => %{
          description: "Tests that failed in the last run",
          filter_type: :failed_history
        },
        "changed_files" => %{
          description: "Tests for recently changed files",
          filter_type: :git_changed
        },
        "slow_tests" => %{
          description: "Tests that take longer than average",
          filter_type: "performance"
        }
      }]
    ]
  
  require Logger
  
  # Define additional actions for this agent
  def additional_actions do
    [
      __MODULE__.ExecuteToolAction,
      __MODULE__.RunTestSuiteAction,
      __MODULE__.AnalyzeResultsAction,
      __MODULE__.MonitorHealthAction,
      __MODULE__.OptimizeExecutionAction
    ]
  end
  
  # Action modules
  
  defmodule ExecuteToolAction do
    @moduledoc false
    use Jido.Action,
      name: "execute_tool",
      description: "Execute the TestRunner tool with specified parameters",
      schema: [
        params: [type: :map, required: true, doc: "Parameters for the TestRunner tool"]
      ]
    
    @impl true
    def run(action_params, context) do
      _agent = context.agent
      params = action_params.params
      
      # Execute the TestRunner tool
      case RubberDuck.Tools.TestRunner.execute(params, %{}) do
        {:ok, result} -> 
          {:ok, result}
        {:error, reason} -> 
          {:error, reason}
      end
    end
  end
  
  defmodule RunTestSuiteAction do
    @moduledoc false
    use Jido.Action,
      name: "run_test_suite",
      description: "Execute a complete test suite with comprehensive analysis",
      schema: [
        suite_name: [type: :string, required: true, doc: "Name of the test suite to run"],
        include_coverage: [type: :boolean, default: true],
        parallel: [type: :boolean, default: true],
        timeout_override: [type: :integer, required: false],
        additional_tags: [type: {:list, :string}, default: []]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      # Get suite configuration
      suite_config = case Map.get(agent.state.test_suites, params.suite_name) do
        nil -> {:error, "Unknown test suite: #{params.suite_name}"}
        config -> {:ok, config}
      end
      
      case suite_config do
        {:ok, config} ->
          # Build test parameters
          test_params = %{
            test_pattern: config.pattern,
            tags: config.tags ++ params.additional_tags,
            timeout: params.timeout_override || config.timeout,
            coverage: params.include_coverage,
            formatter: "detailed",
            max_failures: agent.state.execution_settings.max_failures
          }
          
          # Execute the test suite
          start_time = System.monotonic_time(:millisecond)
          
          case RubberDuck.Tools.TestRunner.execute(test_params, %{}) do
            {:ok, result} ->
              end_time = System.monotonic_time(:millisecond)
              duration = end_time - start_time
              
              # Enhance result with suite information
              enhanced_result = Map.merge(result, %{
                suite_name: params.suite_name,
                suite_config: config,
                execution_duration: duration,
                parallel_enabled: params.parallel,
                coverage_included: params.include_coverage
              })
              
              {:ok, enhanced_result}
            
            {:error, reason} ->
              {:error, reason}
          end
        
        {:error, reason} ->
          {:error, reason}
      end
    end
  end
  
  defmodule AnalyzeResultsAction do
    @moduledoc false
    use Jido.Action,
      name: "analyze_results",
      description: "Analyze test results to identify patterns, trends, and insights",
      schema: [
        test_results: [type: :map, required: true, doc: "Test results to analyze"],
        analysis_depth: [type: :atom, values: [:basic, :detailed, :comprehensive], default: :detailed],
        compare_with_history: [type: :boolean, default: true],
        generate_recommendations: [type: :boolean, default: true]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      results = params.test_results
      
      analysis = %{
        result_summary: analyze_result_summary(results),
        failure_analysis: analyze_failures(results),
        performance_analysis: analyze_performance(results, agent),
        coverage_analysis: analyze_coverage(results),
        trend_analysis: if(params.compare_with_history, do: analyze_trends(results, agent), else: %{}),
        recommendations: if(params.generate_recommendations, do: generate_recommendations(results, agent), else: [])
      }
      
      {:ok, %{
        suite_name: results[:suite_name] || "unknown",
        analysis_depth: params.analysis_depth,
        total_tests: results.summary.total,
        analysis: analysis,
        analyzed_at: DateTime.utc_now()
      }}
    end
    
    defp analyze_result_summary(results) do
      summary = results.summary
      
      %{
        success_rate: if(summary.total > 0, do: summary.passed / summary.total * 100, else: 0),
        failure_rate: if(summary.total > 0, do: summary.failed / summary.total * 100, else: 0),
        skip_rate: if(summary.total > 0, do: summary.skipped / summary.total * 100, else: 0),
        duration_analysis: %{
          total_duration: summary.duration_ms,
          average_test_duration: if(summary.total > 0, do: summary.duration_ms / summary.total, else: 0),
          performance_rating: rate_performance(summary.duration_ms, summary.total)
        },
        status_distribution: %{
          passed: summary.passed,
          failed: summary.failed,
          skipped: summary.skipped,
          total: summary.total
        }
      }
    end
    
    defp analyze_failures(results) do
      failures = results.failures || []
      
      %{
        total_failures: length(failures),
        failure_categories: categorize_failures(failures),
        most_common_errors: find_common_error_types(failures),
        affected_modules: failures |> Enum.map(& &1.module) |> Enum.uniq() |> length(),
        failure_distribution: analyze_failure_distribution(failures)
      }
    end
    
    defp analyze_performance(results, agent) do
      duration = results.summary.duration_ms
      total_tests = results.summary.total
      
      history_durations = agent.state.test_history
      |> Enum.take(10)
      |> Enum.map(fn run -> run.duration_ms end)
      |> Enum.reject(&is_nil/1)
      
      avg_historical = if length(history_durations) > 0 do
        Enum.sum(history_durations) / length(history_durations)
      else
        duration
      end
      
      %{
        current_duration: duration,
        average_duration: avg_historical,
        performance_trend: calculate_performance_trend(duration, avg_historical),
        tests_per_second: if(duration > 0, do: total_tests / (duration / 1000), else: 0),
        efficiency_score: calculate_efficiency_score(duration, total_tests)
      }
    end
    
    defp analyze_coverage(results) do
      coverage = results.coverage || %{}
      
      if coverage.enabled do
        %{
          enabled: true,
          percentage: coverage.percentage || 0,
          covered_lines: coverage.covered_lines || 0,
          total_lines: coverage.total_lines || 0,
          uncovered_modules: length(coverage.uncovered_files || []),
          coverage_rating: rate_coverage(coverage.percentage || 0),
          module_coverage: coverage.by_module || %{}
        }
      else
        %{enabled: false}
      end
    end
    
    defp analyze_trends(results, agent) do
      history = Enum.take(agent.state.test_history, 10)
      
      %{
        success_rate_trend: calculate_success_rate_trend(results, history),
        performance_trend: calculate_duration_trend(results, history),
        coverage_trend: calculate_coverage_trend(results, history),
        failure_pattern_trend: analyze_failure_patterns(results, history)
      }
    end
    
    defp generate_recommendations(results, agent) do
      recommendations = []
      
      # Coverage recommendations
      recommendations = if results.coverage && results.coverage.enabled do
        coverage_pct = results.coverage.percentage || 0
        target_pct = agent.state.coverage_data.target_percentage
        
        if coverage_pct < target_pct do
          [%{
            type: :coverage,
            priority: :high,
            message: "Coverage is below target (#{coverage_pct}% < #{target_pct}%)",
            action: "Add tests for uncovered code paths"
          } | recommendations]
        else
          recommendations
        end
      else
        recommendations
      end
      
      # Performance recommendations
      recommendations = if results.summary.duration_ms > 30_000 do
        [%{
          type: "performance",
          priority: :medium,
          message: "Test suite is running slowly (#{results.summary.duration_ms}ms)",
          action: "Consider parallel execution or test optimization"
        } | recommendations]
      else
        recommendations
      end
      
      # Failure recommendations
      recommendations = if results.summary.failed > 0 do
        [%{
          type: :failures,
          priority: :high,
          message: "#{results.summary.failed} tests are failing",
          action: "Review and fix failing tests to maintain code quality"
        } | recommendations]
      else
        recommendations
      end
      
      recommendations
    end
    
    # Helper functions with simplified implementations
    defp rate_performance(duration, test_count) do
      tests_per_second = if duration > 0, do: test_count / (duration / 1000), else: 0
      
      cond do
        tests_per_second > 10 -> :excellent
        tests_per_second > 5 -> :good
        tests_per_second > 1 -> :acceptable
        true -> :slow
      end
    end
    
    defp categorize_failures(failures) do
      failures
      |> Enum.group_by(fn failure -> failure.error.type end)
      |> Enum.map(fn {type, fails} -> 
        %{type: type, count: length(fails), percentage: length(fails) / length(failures) * 100}
      end)
    end
    
    defp find_common_error_types(failures) do
      failures
      |> Enum.map(fn failure -> failure.error.message end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_msg, count} -> -count end)
      |> Enum.take(5)
      |> Enum.map(fn {msg, count} -> %{message: msg, occurrences: count} end)
    end
    
    defp analyze_failure_distribution(failures) do
      by_module = failures
      |> Enum.group_by(fn failure -> failure.module end)
      |> Enum.map(fn {mod, fails} -> %{module: mod, failures: length(fails)} end)
      |> Enum.sort_by(fn %{failures: count} -> -count end)
      
      %{by_module: by_module}
    end
    
    defp calculate_performance_trend(current, average) do
      if average > 0 do
        change = (current - average) / average * 100
        cond do
          change < -10 -> :improving
          change > 10 -> :degrading
          true -> :stable
        end
      else
        :stable
      end
    end
    
    defp calculate_efficiency_score(duration, test_count) do
      if duration > 0 and test_count > 0 do
        # Simple efficiency score based on tests per second
        tests_per_second = test_count / (duration / 1000)
        min(100, tests_per_second * 10)
      else
        0
      end
    end
    
    defp rate_coverage(percentage) do
      cond do
        percentage >= 90 -> :excellent
        percentage >= 80 -> :good
        percentage >= 70 -> :acceptable
        percentage >= 50 -> :poor
        true -> :critical
      end
    end
    
    defp calculate_success_rate_trend(current, history) do
      current_rate = if current.summary.total > 0, do: current.summary.passed / current.summary.total * 100, else: 0
      
      if length(history) > 0 do
        avg_rate = history
        |> Enum.map(fn run -> if run.total > 0, do: run.passed / run.total * 100, else: 0 end)
        |> Enum.sum()
        |> Kernel./(length(history))
        
        %{current: current_rate, average: avg_rate, trend: if(current_rate >= avg_rate, do: :stable, else: :declining)}
      else
        %{current: current_rate, trend: :unknown}
      end
    end
    
    defp calculate_duration_trend(current, history) do
      current_duration = current.summary.duration_ms
      
      if length(history) > 0 do
        avg_duration = history
        |> Enum.map(fn run -> run.duration_ms || 0 end)
        |> Enum.sum()
        |> Kernel./(length(history))
        
        %{current: current_duration, average: avg_duration, trend: if(current_duration <= avg_duration, do: :stable, else: :slowing)}
      else
        %{current: current_duration, trend: :unknown}
      end
    end
    
    defp calculate_coverage_trend(current, history) do
      if current.coverage && current.coverage.enabled do
        current_pct = current.coverage.percentage || 0
        
        coverage_history = history
        |> Enum.map(fn run -> get_in(run, [:coverage, :percentage]) end)
        |> Enum.reject(&is_nil/1)
        
        if length(coverage_history) > 0 do
          avg_pct = Enum.sum(coverage_history) / length(coverage_history)
          %{current: current_pct, average: avg_pct, trend: if(current_pct >= avg_pct, do: :stable, else: :declining)}
        else
          %{current: current_pct, trend: :unknown}
        end
      else
        %{enabled: false}
      end
    end
    
    defp analyze_failure_patterns(current, history) do
      current_failures = current.failures || []
      current_modules = Enum.map(current_failures, & &1.module)
      
      # Find modules that frequently fail
      historical_failures = history
      |> Enum.flat_map(fn run -> get_in(run, [:failures]) || [] end)
      |> Enum.map(fn failure -> failure.module end)
      |> Enum.frequencies()
      
      frequent_failing_modules = historical_failures
      |> Enum.filter(fn {_mod, count} -> count > 1 end)
      |> Enum.sort_by(fn {_mod, count} -> -count end)
      |> Enum.take(5)
      
      %{
        current_failing_modules: current_modules,
        frequent_failing_modules: frequent_failing_modules,
        pattern_detected: length(frequent_failing_modules) > 0
      }
    end
  end
  
  defmodule MonitorHealthAction do
    @moduledoc false
    use Jido.Action,
      name: "monitor_health",
      description: "Monitor test health metrics and identify problematic patterns",
      schema: [
        time_window: [type: :integer, default: 86_400_000, doc: "Time window in milliseconds to analyze"],
        include_trends: [type: :boolean, default: true],
        detect_flaky_tests: [type: :boolean, default: true],
        performance_analysis: [type: :boolean, default: true]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      # Analyze recent test history within time window
      cutoff_time = DateTime.utc_now() |> DateTime.add(-params.time_window, :millisecond)
      recent_history = agent.state.test_history
      |> Enum.filter(fn run -> 
        DateTime.compare(run.timestamp || DateTime.utc_now(), cutoff_time) == :gt
      end)
      
      health_report = %{
        time_window: params.time_window,
        total_runs_analyzed: length(recent_history),
        stability_metrics: calculate_stability_metrics(recent_history),
        performance_metrics: if(params.performance_analysis, do: analyze_performance_health(recent_history), else: %{}),
        flaky_tests: if(params.detect_flaky_tests, do: detect_flaky_tests(recent_history), else: []),
        trends: if(params.include_trends, do: calculate_health_trends(recent_history), else: %{}),
        recommendations: generate_health_recommendations(recent_history, agent)
      }
      
      {:ok, health_report}
    end
    
    defp calculate_stability_metrics(history) do
      if length(history) == 0 do
        %{stability_score: 0, analysis: "No recent test runs to analyze"}
      else
        total_runs = length(history)
        successful_runs = Enum.count(history, fn run -> run.status == :passed end)
        stability_score = successful_runs / total_runs * 100
        
        %{
          stability_score: stability_score,
          total_runs: total_runs,
          successful_runs: successful_runs,
          failed_runs: total_runs - successful_runs,
          analysis: classify_stability(stability_score)
        }
      end
    end
    
    defp analyze_performance_health(history) do
      if length(history) == 0 do
        %{analysis: "No performance data available"}
      else
        durations = Enum.map(history, fn run -> run.duration_ms || 0 end)
        avg_duration = Enum.sum(durations) / length(durations)
        max_duration = Enum.max(durations)
        min_duration = Enum.min(durations)
        
        %{
          average_duration: avg_duration,
          max_duration: max_duration,
          min_duration: min_duration,
          performance_variance: calculate_variance(durations),
          performance_trend: analyze_duration_trend(durations)
        }
      end
    end
    
    defp detect_flaky_tests(history) do
      # Group failures by test name and look for intermittent failures
      all_failures = history
      |> Enum.flat_map(fn run -> run.failures || [] end)
      
      failure_counts = all_failures
      |> Enum.group_by(fn failure -> "#{failure.module}.#{failure.test}" end)
      |> Enum.map(fn {test_name, failures} -> 
        %{test: test_name, failure_count: length(failures)}
      end)
      |> Enum.filter(fn %{failure_count: count} -> count > 1 and count < length(history) end)
      |> Enum.sort_by(fn %{failure_count: count} -> -count end)
      
      %{
        flaky_tests_detected: length(failure_counts),
        flaky_tests: failure_counts,
        analysis: if(length(failure_counts) > 0, do: "Intermittent failures detected", else: "No flaky tests detected")
      }
    end
    
    defp calculate_health_trends(history) do
      if length(history) < 2 do
        %{analysis: "Insufficient data for trend analysis"}
      else
        # Split history in half to compare recent vs older
        mid_point = div(length(history), 2)
        {recent, older} = Enum.split(history, mid_point)
        
        recent_stability = calculate_stability_rate(recent)
        older_stability = calculate_stability_rate(older)
        
        %{
          stability_trend: compare_stability(recent_stability, older_stability),
          recent_stability: recent_stability,
          older_stability: older_stability
        }
      end
    end
    
    defp generate_health_recommendations(history, _agent) do
      recommendations = []
      
      # Check for stability issues
      stability = calculate_stability_rate(history)
      recommendations = if stability < 80 do
        [%{
          type: :stability,
          priority: :high,
          message: "Test stability is below acceptable threshold (#{stability}%)",
          action: "Investigate and fix frequently failing tests"
        } | recommendations]
      else
        recommendations
      end
      
      # Check for performance issues
      if length(history) > 0 do
        avg_duration = history
        |> Enum.map(fn run -> run.duration_ms || 0 end)
        |> Enum.sum()
        |> Kernel./(length(history))
        
        recommendations = if avg_duration > 60_000 do
          [%{
            type: "performance",
            priority: :medium,
            message: "Average test execution time is high (#{round(avg_duration)}ms)",
            action: "Consider test optimization or parallel execution"
          } | recommendations]
        else
          recommendations
        end
      else
        recommendations
      end
      
      recommendations
    end
    
    # Helper functions
    defp classify_stability(score) do
      cond do
        score >= 95 -> "Excellent stability"
        score >= 85 -> "Good stability"
        score >= 75 -> "Acceptable stability"
        score >= 60 -> "Poor stability"
        true -> "Critical stability issues"
      end
    end
    
    defp calculate_variance(values) do
      if length(values) <= 1 do
        0
      else
        mean = Enum.sum(values) / length(values)
        sum_of_squares = values
        |> Enum.map(fn x -> (x - mean) * (x - mean) end)
        |> Enum.sum()
        
        sum_of_squares / (length(values) - 1)
      end
    end
    
    defp analyze_duration_trend(durations) do
      if length(durations) < 2 do
        :unknown
      else
        # Simple trend: compare first half with second half
        mid = div(length(durations), 2)
        {first_half, second_half} = Enum.split(durations, mid)
        
        avg_first = Enum.sum(first_half) / length(first_half)
        avg_second = Enum.sum(second_half) / length(second_half)
        
        cond do
          avg_second > avg_first * 1.1 -> :slowing
          avg_second < avg_first * 0.9 -> :improving
          true -> :stable
        end
      end
    end
    
    defp calculate_stability_rate(runs) do
      if length(runs) == 0 do
        0
      else
        successful = Enum.count(runs, fn run -> run.status == :passed end)
        successful / length(runs) * 100
      end
    end
    
    defp compare_stability(recent, older) do
      cond do
        recent > older * 1.05 -> :improving
        recent < older * 0.95 -> :declining
        true -> :stable
      end
    end
  end
  
  defmodule OptimizeExecutionAction do
    @moduledoc false
    use Jido.Action,
      name: "optimize_execution",
      description: "Generate test execution optimization suggestions",
      schema: [
        focus_areas: [type: {:list, :atom}, default: ["performance", :coverage, :reliability]],
        current_settings: [type: :map, default: %{}],
        constraints: [type: :map, default: %{}]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      optimizations = []
      
      # Performance optimizations
      optimizations = if "performance" in params.focus_areas do
        optimizations ++ generate_performance_optimizations(agent, params.constraints)
      else
        optimizations
      end
      
      # Coverage optimizations
      optimizations = if :coverage in params.focus_areas do
        optimizations ++ generate_coverage_optimizations(agent, params.constraints)
      else
        optimizations
      end
      
      # Reliability optimizations
      optimizations = if :reliability in params.focus_areas do
        optimizations ++ generate_reliability_optimizations(agent, params.constraints)
      else
        optimizations
      end
      
      {:ok, %{
        total_suggestions: length(optimizations),
        focus_areas: params.focus_areas,
        optimizations: optimizations,
        generated_at: DateTime.utc_now()
      }}
    end
    
    defp generate_performance_optimizations(agent, _constraints) do
      suggestions = []
      
      # Check average test duration
      avg_duration = agent.state.execution_stats.average_duration
      suggestions = if avg_duration > 30_000 do
        [%{
          type: "performance",
          category: "execution_time",
          priority: :high,
          suggestion: "Enable parallel test execution to reduce overall run time",
          expected_improvement: "30-50% faster execution",
          implementation: %{
            setting: "parallel_execution",
            value: true,
            additional_config: %{max_concurrency: System.schedulers_online()}
          }
        } | suggestions]
      else
        suggestions
      end
      
      # Check for slow test patterns
      slow_tests = agent.state.test_health.slow_tests
      suggestions = if length(slow_tests) > 0 do
        [%{
          type: "performance",
          category: "slow_tests",
          priority: :medium,
          suggestion: "Optimize or isolate slow tests to separate suite",
          expected_improvement: "Faster feedback loop for quick tests",
          implementation: %{
            action: :create_suite,
            suite_name: "slow_tests",
            pattern: "test/**/*slow*_test.exs"
          }
        } | suggestions]
      else
        suggestions
      end
      
      suggestions
    end
    
    defp generate_coverage_optimizations(agent, _constraints) do
      suggestions = []
      
      current_coverage = agent.state.coverage_data.current_percentage
      target_coverage = agent.state.coverage_data.target_percentage
      
      suggestions = if current_coverage < target_coverage do
        gap = target_coverage - current_coverage
        [%{
          type: :coverage,
          category: "increase_coverage",
          priority: if(gap > 20, do: :high, else: :medium),
          suggestion: "Add tests for uncovered modules to reach target coverage",
          expected_improvement: "Increase coverage by #{gap}%",
          implementation: %{
            action: :generate_tests,
            target_modules: agent.state.coverage_data.uncovered_modules,
            priority_order: :by_complexity
          }
        } | suggestions]
      else
        suggestions
      end
      
      suggestions
    end
    
    defp generate_reliability_optimizations(agent, _constraints) do
      suggestions = []
      
      # Check for flaky tests
      flaky_tests = agent.state.test_health.flaky_tests
      suggestions = if length(flaky_tests) > 0 do
        [%{
          type: :reliability,
          category: "flaky_tests",
          priority: :high,
          suggestion: "Fix or isolate flaky tests to improve test reliability",
          expected_improvement: "More consistent test results",
          implementation: %{
            action: :isolate_flaky,
            affected_tests: flaky_tests,
            strategy: :retry_or_skip
          }
        } | suggestions]
      else
        suggestions
      end
      
      # Check stability score
      stability_score = agent.state.test_health.stability_score
      suggestions = if stability_score < 85 do
        [%{
          type: :reliability,
          category: "stability",
          priority: :high,
          suggestion: "Improve test stability by addressing frequent failures",
          expected_improvement: "Higher success rate and confidence",
          implementation: %{
            action: :analyze_failures,
            focus: :trending_failures,
            threshold: 3
          }
        } | suggestions]
      else
        suggestions
      end
      
      suggestions
    end
  end
  
  # Signal handlers
  
  def handle_signal(agent, %{"type" => "run_tests"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters
    params = %{
      test_pattern: data["test_pattern"] || "test/**/*_test.exs",
      filter: data["filter"],  
      tags: data["tags"] || [],
      max_failures: data["max_failures"],
      timeout: data["timeout"] || 60_000,
      coverage: data["coverage"] || true,
      formatter: data["formatter"] || "detailed",
      env: data["env"] || %{}
    }
    
    # Execute the test run
    {:ok, _ref} = Jido.Agent.cmd_async(agent, ExecuteToolAction, %{params: params})
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "run_test_suite"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = Jido.Agent.cmd_async(agent, RunTestSuiteAction, %{
      suite_name: data["suite_name"],
      include_coverage: data["include_coverage"] || true,
      parallel: data["parallel"] || true,
      timeout_override: data["timeout_override"],
      additional_tags: data["additional_tags"] || []
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "analyze_test_results"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = Jido.Agent.cmd_async(agent, AnalyzeResultsAction, %{
      test_results: data["test_results"],
      analysis_depth: String.to_atom(data["analysis_depth"] || "detailed"),
      compare_with_history: data["compare_with_history"] || true,
      generate_recommendations: data["generate_recommendations"] || true
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "monitor_test_health"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = Jido.Agent.cmd_async(agent, MonitorHealthAction, %{
      time_window: data["time_window"] || 86_400_000,
      include_trends: data["include_trends"] || true,
      detect_flaky_tests: data["detect_flaky_tests"] || true,
      performance_analysis: data["performance_analysis"] || true
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "optimize_test_execution"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = Jido.Agent.cmd_async(agent, OptimizeExecutionAction, %{
      focus_areas: Enum.map(data["focus_areas"] || ["performance", "coverage"], &String.to_atom/1),
      current_settings: data["current_settings"] || %{},
      constraints: data["constraints"] || %{}
    })
    
    {:ok, agent}
  end
  
  # Action result handlers
  
  def handle_action_result(agent, ExecuteToolAction, {:ok, result}, _metadata) do
    # Record test run
    test_record = %{
      total: result.summary.total,
      passed: result.summary.passed,
      failed: result.summary.failed,
      skipped: result.summary.skipped,
      duration_ms: result.summary.duration_ms,
      status: result.status,
      coverage: result.coverage,
      failures: result.failures,
      timestamp: DateTime.utc_now()
    }
    
    # Add to history
    agent = update_in(agent.state.test_history, fn history ->
      new_history = [test_record | history]
      if length(new_history) > agent.state.max_history_size do
        Enum.take(new_history, agent.state.max_history_size)
      else
        new_history
      end
    end)
    
    # Update statistics
    agent = update_in(agent.state.execution_stats, fn stats ->
      new_avg_duration = if stats.total_runs > 0 do
        (stats.average_duration * stats.total_runs + result.summary.duration_ms) / (stats.total_runs + 1)
      else
        result.summary.duration_ms
      end
      
      stats
      |> Map.update!(:total_runs, &(&1 + 1))
      |> Map.update!(:tests_executed, &(&1 + result.summary.total))
      |> Map.update!(:tests_passed, &(&1 + result.summary.passed))
      |> Map.update!(:tests_failed, &(&1 + result.summary.failed))
      |> Map.put(:average_duration, new_avg_duration)
      |> Map.update!(if(result.status == :passed, do: :successful_runs, else: :failed_runs), &(&1 + 1))
    end)
    
    # Update coverage data
    agent = if result.coverage && result.coverage.enabled do
      update_in(agent.state.coverage_data, fn coverage ->
        coverage
        |> Map.put(:current_percentage, result.coverage.percentage || 0)
        |> update_in([:trend], fn trend -> 
          new_trend = [result.coverage.percentage || 0 | trend]
          Enum.take(new_trend, 10)
        end)
      end)
    else
      agent
    end
    
    # Emit completion signal
    signal_type = if result.status == :passed, do: "tests_completed", else: "tests_failed"
    signal = Jido.Signal.new!(%{
      type: signal_type,
      source: "agent:#{agent.id}",
      data: %{
        total: result.summary.total,
        passed: result.summary.passed,
        failed: result.summary.failed,
        duration: result.summary.duration_ms,
        coverage_percentage: get_in(result, [:coverage, :percentage])
      }
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, ExecuteToolAction, {:error, reason}, metadata) do
    # Update failure statistics
    agent = update_in(agent.state.execution_stats.failed_runs, &(&1 + 1))
    
    # Emit error signal
    signal = Jido.Signal.new!(%{
      type: "test_execution_error",
      source: "agent:#{agent.id}",
      data: %{
        error: reason,
        metadata: metadata
      }
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:error, reason}
  end
  
  def handle_action_result(agent, AnalyzeResultsAction, {:ok, result}, _metadata) do
    # Emit analysis complete signal
    signal = Jido.Signal.new!(%{
      type: "test_results_analyzed",
      source: "agent:#{agent.id}",
      data: result
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, MonitorHealthAction, {:ok, result}, _metadata) do
    # Update health metrics
    agent = update_in(agent.state.test_health, fn health ->
      health
      |> Map.put(:stability_score, result.stability_metrics.stability_score || 0)
      |> Map.put(:flaky_tests, result.flaky_tests[:flaky_tests] || [])
    end)
    
    # Emit health report signal
    signal = Jido.Signal.new!(%{
      type: "test_health_report",
      source: "agent:#{agent.id}",
      data: result
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, OptimizeExecutionAction, {:ok, result}, _metadata) do
    # Store optimization suggestions
    agent = put_in(agent.state.optimization_suggestions, result.optimizations)
    
    # Emit optimization suggestions signal
    signal = Jido.Signal.new!(%{
      type: "test_optimization_suggestions",
      source: "agent:#{agent.id}",
      data: result
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
end