defmodule RubberDuck.Tools.Agents.TestSummarizerAgent do
  @moduledoc """
  Agent that orchestrates test result analysis and summarization.
  
  This agent manages the analysis of test outputs, identifies failure patterns,
  tracks test health metrics over time, and provides actionable insights for
  improving test quality and reliability.
  """
  
  use Jido.Agent,
    name: "test_summarizer_agent",
    description: "Orchestrates test result analysis and provides actionable insights",
    category: "testing",
    tags: ["testing", "analysis", "reporting", "quality", "metrics"],
    vsn: "1.0.0",
    schema: [
      analysis_config: [
        type: :map,
        doc: "Configuration for test analysis",
        default: %{
          default_format: "auto",
          default_summary_type: "comprehensive",
          group_failures: true,
          highlight_flaky: true,
          suggest_fixes: true,
          failure_threshold: 0.3
        }
      ],
      test_history: [
        type: {:list, :map},
        doc: "Historical test results for trend analysis",
        default: []
      ],
      failure_patterns: [
        type: :map,
        doc: "Tracked failure patterns across test runs",
        default: %{
          by_type: %{},
          by_test: %{},
          by_file: %{}
        }
      ],
      flaky_tests: [
        type: :map,
        doc: "Tests identified as potentially flaky",
        default: %{}
      ],
      test_metrics: [
        type: :map,
        doc: "Overall test suite metrics",
        default: %{
          average_pass_rate: 0.0,
          average_duration: 0.0,
          total_runs_analyzed: 0,
          health_trend: :stable
        }
      ],
      coverage_data: [
        type: :map,
        doc: "Code coverage data if available",
        default: %{
          line_coverage: 0.0,
          branch_coverage: 0.0,
          uncovered_files: []
        }
      ],
      active_analyses: [
        type: :map,
        doc: "Currently active test analyses",
        default: %{}
      ],
      recommendations_cache: [
        type: :map,
        doc: "Cached recommendations for similar failures",
        default: %{}
      ]
    ]
  
  alias RubberDuck.Tools.TestSummarizer
  
  # Action to execute the test summarizer tool
  defmodule ExecuteToolAction do
    use Jido.Action,
      name: "execute_test_summarizer_tool",
      description: "Execute the test summarizer tool with given parameters",
      schema: [
        params: [type: :map, required: true]
      ]
    
    def run(%{params: params}, context) do
      case TestSummarizer.execute(params, context) do
        {:ok, result} ->
          {:ok, result}
        error ->
          error
      end
    end
  end
  
  # Action to analyze test trends over time
  defmodule AnalyzeTrendsAction do
    use Jido.Action,
      name: "analyze_test_trends",
      description: "Analyze test trends across multiple runs",
      schema: [
        time_window: [type: :atom, default: :last_week],
        metrics: [type: {:list, :atom}, default: [:pass_rate, :duration, :failures]],
        group_by: [type: :atom, default: :day]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      history = agent_state.test_history
      
      # Filter history by time window
      filtered_history = filter_by_time_window(history, params.time_window)
      
      if filtered_history == [] do
        {:ok, %{
          message: "No test data available for the specified time window",
          trends: %{}
        }}
      else
        # Calculate trends for each metric
        trends = Enum.reduce(params.metrics, %{}, fn metric, acc ->
          trend_data = calculate_trend(filtered_history, metric, params.group_by)
          Map.put(acc, metric, trend_data)
        end)
        
        # Identify significant changes
        insights = analyze_trend_insights(trends)
        
        {:ok, %{
          time_window: params.time_window,
          data_points: length(filtered_history),
          trends: trends,
          insights: insights,
          health_trend: determine_health_trend(trends)
        }}
      end
    end
    
    defp filter_by_time_window(history, :all), do: history
    defp filter_by_time_window(history, window) do
      cutoff = calculate_cutoff_time(window)
      Enum.filter(history, fn entry ->
        DateTime.compare(entry.timestamp, cutoff) == :gt
      end)
    end
    
    defp calculate_cutoff_time(:last_day), do: DateTime.add(DateTime.utc_now(), -86400, :second)
    defp calculate_cutoff_time(:last_week), do: DateTime.add(DateTime.utc_now(), -604800, :second)
    defp calculate_cutoff_time(:last_month), do: DateTime.add(DateTime.utc_now(), -2592000, :second)
    defp calculate_cutoff_time(_), do: DateTime.add(DateTime.utc_now(), -604800, :second)
    
    defp calculate_trend(history, :pass_rate, group_by) do
      grouped = group_history_by(history, group_by)
      
      Enum.map(grouped, fn {period, entries} ->
        avg_pass_rate = entries
        |> Enum.map(& &1.statistics.pass_rate)
        |> average()
        
        %{
          period: period,
          value: avg_pass_rate,
          sample_size: length(entries)
        }
      end)
    end
    
    defp calculate_trend(history, :duration, group_by) do
      grouped = group_history_by(history, group_by)
      
      Enum.map(grouped, fn {period, entries} ->
        avg_duration = entries
        |> Enum.map(& &1.statistics[:avg_duration] || 0)
        |> Enum.reject(&(&1 == 0))
        |> average()
        
        %{
          period: period,
          value: avg_duration,
          sample_size: length(entries)
        }
      end)
    end
    
    defp calculate_trend(history, :failures, group_by) do
      grouped = group_history_by(history, group_by)
      
      Enum.map(grouped, fn {period, entries} ->
        total_failures = entries
        |> Enum.map(& &1.statistics.failed)
        |> Enum.sum()
        
        %{
          period: period,
          value: total_failures,
          sample_size: length(entries)
        }
      end)
    end
    
    defp group_history_by(history, :day) do
      history
      |> Enum.group_by(fn entry ->
        Date.to_string(DateTime.to_date(entry.timestamp))
      end)
    end
    
    defp group_history_by(history, :hour) do
      history
      |> Enum.group_by(fn entry ->
        "#{Date.to_string(DateTime.to_date(entry.timestamp))} #{entry.timestamp.hour}:00"
      end)
    end
    
    defp average([]), do: 0.0
    defp average(numbers), do: Enum.sum(numbers) / length(numbers)
    
    defp analyze_trend_insights(trends) do
      insights = []
      
      # Check pass rate trend
      insights = if pass_trend = trends[:pass_rate] do
        recent = Enum.take(pass_trend, -3)
        older = Enum.take(pass_trend, 3)
        
        if length(recent) >= 2 and length(older) >= 2 do
          recent_avg = average(Enum.map(recent, & &1.value))
          older_avg = average(Enum.map(older, & &1.value))
          
          change = recent_avg - older_avg
          
          insight = cond do
            change > 10 -> "Test pass rate improved by #{Float.round(change, 1)}%"
            change < -10 -> "Test pass rate declined by #{Float.round(abs(change), 1)}%"
            true -> nil
          end
          
          if insight, do: [insight | insights], else: insights
        else
          insights
        end
      else
        insights
      end
      
      insights
    end
    
    defp determine_health_trend(trends) do
      pass_trend = trends[:pass_rate] || []
      
      if length(pass_trend) >= 2 do
        recent_values = pass_trend
        |> Enum.take(-3)
        |> Enum.map(& &1.value)
        
        slope = calculate_simple_slope(recent_values)
        
        cond do
          slope > 2 -> :improving
          slope < -2 -> :declining
          true -> :stable
        end
      else
        :stable
      end
    end
    
    defp calculate_simple_slope([]), do: 0
    defp calculate_simple_slope([_]), do: 0
    defp calculate_simple_slope(values) do
      first = hd(values)
      last = List.last(values)
      (last - first) / length(values)
    end
  end
  
  # Action to identify flaky tests
  defmodule IdentifyFlakyTestsAction do
    use Jido.Action,
      name: "identify_flaky_tests",
      description: "Identify tests that show inconsistent behavior",
      schema: [
        min_runs: [type: :integer, default: 5],
        flakiness_threshold: [type: :float, default: 0.2],
        time_window: [type: :atom, default: :last_week]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      history = agent_state.test_history
      
      # Filter by time window
      filtered = filter_by_time_window(history, params.time_window)
      
      # Analyze test results for flakiness
      test_results = aggregate_test_results(filtered)
      
      flaky_tests = test_results
      |> Enum.filter(fn {_test, data} ->
        data.total_runs >= params.min_runs and
        data.failure_rate > 0 and
        data.failure_rate < 1.0 and
        (data.failure_rate > params.flakiness_threshold and
         data.failure_rate < (1 - params.flakiness_threshold))
      end)
      |> Enum.map(fn {test_name, data} ->
        %{
          test_name: test_name,
          failure_rate: Float.round(data.failure_rate, 3),
          total_runs: data.total_runs,
          failures: data.failures,
          flakiness_score: calculate_flakiness_score(data),
          failure_reasons: data.failure_reasons
        }
      end)
      |> Enum.sort_by(& &1.flakiness_score, :desc)
      
      {:ok, %{
        total_tests_analyzed: map_size(test_results),
        flaky_tests_found: length(flaky_tests),
        flaky_tests: flaky_tests,
        recommendations: generate_flaky_test_recommendations(flaky_tests)
      }}
    end
    
    defp filter_by_time_window(history, window) do
      cutoff = case window do
        :last_day -> DateTime.add(DateTime.utc_now(), -86400, :second)
        :last_week -> DateTime.add(DateTime.utc_now(), -604800, :second)
        :last_month -> DateTime.add(DateTime.utc_now(), -2592000, :second)
        _ -> DateTime.add(DateTime.utc_now(), -604800, :second)
      end
      
      Enum.filter(history, fn entry ->
        DateTime.compare(entry.timestamp, cutoff) == :gt
      end)
    end
    
    defp aggregate_test_results(history) do
      history
      |> Enum.flat_map(fn run ->
        # Get all test results from this run
        all_tests = extract_all_tests(run)
        failed_tests = run.failures || []
        
        Enum.map(all_tests, fn test ->
          failed = Enum.any?(failed_tests, &(&1.test_name == test))
          failure_reason = if failed do
            failure = Enum.find(failed_tests, &(&1.test_name == test))
            failure && failure.failure_type
          end
          
          {test, %{passed: not failed, failure_reason: failure_reason}}
        end)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {test, results} ->
        failures = Enum.count(results, &(not &1.passed))
        failure_reasons = results
        |> Enum.filter(&(not &1.passed))
        |> Enum.map(& &1.failure_reason)
        |> Enum.frequencies()
        
        {test, %{
          total_runs: length(results),
          failures: failures,
          failure_rate: failures / length(results),
          failure_reasons: failure_reasons
        }}
      end)
      |> Enum.into(%{})
    end
    
    defp extract_all_tests(run) do
      # Extract all test names from the run
      # This is simplified - in reality would parse the output more thoroughly
      failed_names = Enum.map(run.failures || [], & &1.test_name)
      
      # Estimate total tests (would need better parsing in production)
      _total_count = run.statistics.total
      _passed_count = run.statistics.passed
      
      # For now, just return the failed test names
      # In production, would extract all test names from the output
      failed_names
    end
    
    defp calculate_flakiness_score(data) do
      # Score based on failure rate variance from 0.5 (most flaky)
      base_score = 1.0 - abs(data.failure_rate - 0.5) * 2
      
      # Adjust for number of runs (more runs = more confidence)
      confidence_factor = :math.log(data.total_runs + 1) / 10
      
      # Adjust for failure reason diversity
      reason_diversity = map_size(data.failure_reasons) / data.failures
      
      (base_score * 0.6 + confidence_factor * 0.2 + reason_diversity * 0.2)
      |> Float.round(3)
    end
    
    defp generate_flaky_test_recommendations(flaky_tests) do
      recommendations = []
      
      # Check for timeout-related flakiness
      timeout_flaky = Enum.filter(flaky_tests, fn test ->
        Map.get(test.failure_reasons, :timeout, 0) > 0
      end)
      
      recommendations = if length(timeout_flaky) > 0 do
        ["Consider increasing timeout values for #{length(timeout_flaky)} tests" | recommendations]
      else
        recommendations
      end
      
      # Check for connection-related flakiness
      connection_flaky = Enum.filter(flaky_tests, fn test ->
        Map.get(test.failure_reasons, :connection, 0) > 0
      end)
      
      recommendations = if length(connection_flaky) > 0 do
        ["Add retry logic or mocking for #{length(connection_flaky)} tests with connection issues" | recommendations]
      else
        recommendations
      end
      
      # General recommendation
      if length(flaky_tests) > 5 do
        ["Consider implementing a test retry mechanism for flaky tests" | recommendations]
      else
        recommendations
      end
    end
  end
  
  # Action to generate test improvement plan
  defmodule GenerateImprovementPlanAction do
    use Jido.Action,
      name: "generate_test_improvement_plan",
      description: "Generate actionable plan for improving test suite",
      schema: [
        focus_areas: [type: {:list, :atom}, default: [:failures, :coverage, "performance", :flakiness]],
        max_recommendations: [type: :integer, default: 10],
        priority_threshold: [type: :atom, default: :medium]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      
      recommendations = []
      
      # Analyze each focus area
      recommendations = if :failures in params.focus_areas do
        failure_recs = analyze_failure_improvements(agent_state)
        recommendations ++ failure_recs
      else
        recommendations
      end
      
      recommendations = if :coverage in params.focus_areas do
        coverage_recs = analyze_coverage_improvements(agent_state)
        recommendations ++ coverage_recs
      else
        recommendations
      end
      
      recommendations = if "performance" in params.focus_areas do
        perf_recs = analyze_performance_improvements(agent_state)
        recommendations ++ perf_recs
      else
        recommendations
      end
      
      recommendations = if :flakiness in params.focus_areas do
        flaky_recs = analyze_flakiness_improvements(agent_state)
        recommendations ++ flaky_recs
      else
        recommendations
      end
      
      # Prioritize and limit recommendations
      prioritized = recommendations
      |> Enum.sort_by(& &1.priority_score, :desc)
      |> filter_by_priority(params.priority_threshold)
      |> Enum.take(params.max_recommendations)
      
      # Group by category
      grouped = Enum.group_by(prioritized, & &1.category)
      
      {:ok, %{
        total_recommendations: length(prioritized),
        plan: grouped,
        summary: generate_plan_summary(grouped, agent_state),
        estimated_impact: estimate_improvement_impact(prioritized, agent_state)
      }}
    end
    
    defp analyze_failure_improvements(state) do
      _recent_failures = get_recent_failures(state)
      failure_patterns = state.failure_patterns
      
      recommendations = []
      
      # Check for systematic failures
      systematic = failure_patterns.by_type
      |> Enum.filter(fn {_type, count} -> count > 3 end)
      |> Enum.map(fn {type, count} ->
        %{
          category: "failures",
          title: "Fix systematic #{type} errors",
          description: "#{count} tests are failing with #{type} errors",
          priority_score: min(count * 10, 100),
          effort: :medium,
          impact: :high
        }
      end)
      
      recommendations ++ systematic
    end
    
    defp analyze_coverage_improvements(state) do
      coverage = state.coverage_data
      recommendations = []
      
      recommendations = if coverage.line_coverage < 80 do
        [%{
          category: "coverage",
          title: "Increase test coverage",
          description: "Current line coverage is #{coverage.line_coverage}%, target is 80%",
          priority_score: 80 - coverage.line_coverage,
          effort: :high,
          impact: :high
        } | recommendations]
      else
        recommendations
      end
      
      recommendations = if length(coverage.uncovered_files) > 0 do
        [%{
          category: "coverage",
          title: "Add tests for uncovered files",
          description: "#{length(coverage.uncovered_files)} files have no test coverage",
          priority_score: min(length(coverage.uncovered_files) * 15, 90),
          effort: :medium,
          impact: :medium
        } | recommendations]
      else
        recommendations
      end
      
      recommendations
    end
    
    defp analyze_performance_improvements(state) do
      metrics = state.test_metrics
      recommendations = []
      
      recommendations = if metrics.average_duration > 60 do
        [%{
          category: "performance",
          title: "Optimize slow tests",
          description: "Average test duration is #{Float.round(metrics.average_duration, 1)}s",
          priority_score: min(metrics.average_duration, 100),
          effort: :medium,
          impact: :medium
        } | recommendations]
      else
        recommendations
      end
      
      recommendations
    end
    
    defp analyze_flakiness_improvements(state) do
      flaky_count = map_size(state.flaky_tests)
      
      if flaky_count > 0 do
        [%{
          category: "flakiness",
          title: "Fix flaky tests",
          description: "#{flaky_count} tests show inconsistent behavior",
          priority_score: min(flaky_count * 20, 95),
          effort: :high,
          impact: :high
        }]
      else
        []
      end
    end
    
    defp get_recent_failures(state) do
      state.test_history
      |> Enum.take(10)
      |> Enum.flat_map(& &1.failures)
    end
    
    defp filter_by_priority(recommendations, :low), do: recommendations
    defp filter_by_priority(recommendations, :medium) do
      Enum.filter(recommendations, &(&1.priority_score >= 30))
    end
    defp filter_by_priority(recommendations, :high) do
      Enum.filter(recommendations, &(&1.priority_score >= 60))
    end
    
    defp generate_plan_summary(grouped, state) do
      categories = Map.keys(grouped)
      total_items = grouped
      |> Map.values()
      |> Enum.map(&length/1)
      |> Enum.sum()
      
      %{
        focus_areas: categories,
        total_action_items: total_items,
        current_health: state.test_metrics.health_trend,
        estimated_time: estimate_total_effort(grouped)
      }
    end
    
    defp estimate_total_effort(grouped) do
      total_points = grouped
      |> Map.values()
      |> List.flatten()
      |> Enum.map(fn rec ->
        case rec.effort do
          :low -> 1
          :medium -> 3
          :high -> 8
        end
      end)
      |> Enum.sum()
      
      "#{total_points} story points"
    end
    
    defp estimate_improvement_impact(recommendations, state) do
      current_pass_rate = state.test_metrics.average_pass_rate
      
      # Estimate impact based on recommendation types
      failure_impact = recommendations
      |> Enum.filter(&(&1.category == :failures))
      |> length()
      |> Kernel.*(5)
      
      coverage_impact = recommendations
      |> Enum.filter(&(&1.category == :coverage))
      |> length()
      |> Kernel.*(3)
      
      flakiness_impact = recommendations
      |> Enum.filter(&(&1.category == :flakiness))
      |> length()
      |> Kernel.*(4)
      
      estimated_improvement = min(failure_impact + coverage_impact + flakiness_impact, 100 - current_pass_rate)
      
      %{
        current_pass_rate: current_pass_rate,
        estimated_pass_rate: current_pass_rate + estimated_improvement,
        improvement_percentage: estimated_improvement
      }
    end
  end
  
  # Action to compare test results
  defmodule CompareTestRunsAction do
    use Jido.Action,
      name: "compare_test_runs",
      description: "Compare test results between different runs",
      schema: [
        run_ids: [type: {:list, :string}, required: false],
        compare_latest: [type: :integer, default: 2],
        focus: [type: :atom, default: :all]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      
      # Get runs to compare
      runs = if params[:run_ids] do
        get_runs_by_ids(agent_state.test_history, params.run_ids)
      else
        Enum.take(agent_state.test_history, params.compare_latest)
      end
      
      if length(runs) < 2 do
        {:ok, %{
          message: "Not enough test runs to compare",
          comparison: %{}
        }}
      else
        [newer, older | _] = runs
        
        comparison = case params.focus do
          :failures -> compare_failures(newer, older)
          "performance" -> compare_performance(newer, older)
          :coverage -> compare_coverage(newer, older)
          _ -> compare_all_aspects(newer, older)
        end
        
        {:ok, %{
          newer_run: summarize_run(newer),
          older_run: summarize_run(older),
          comparison: comparison,
          improvements: identify_improvements(comparison),
          regressions: identify_regressions(comparison)
        }}
      end
    end
    
    defp get_runs_by_ids(history, ids) do
      Enum.filter(history, &(&1.id in ids))
    end
    
    defp compare_failures(newer, older) do
      newer_failures = MapSet.new(newer.failures || [], & &1.test_name)
      older_failures = MapSet.new(older.failures || [], & &1.test_name)
      
      %{
        fixed_tests: MapSet.difference(older_failures, newer_failures) |> MapSet.to_list(),
        new_failures: MapSet.difference(newer_failures, older_failures) |> MapSet.to_list(),
        persistent_failures: MapSet.intersection(newer_failures, older_failures) |> MapSet.to_list(),
        failure_rate_change: newer.statistics.failure_rate - older.statistics.failure_rate
      }
    end
    
    defp compare_performance(newer, older) do
      %{
        duration_change: (newer.statistics[:avg_duration] || 0) - (older.statistics[:avg_duration] || 0),
        duration_change_percent: calculate_percent_change(
          older.statistics[:avg_duration] || 1,
          newer.statistics[:avg_duration] || 1
        )
      }
    end
    
    defp compare_coverage(newer, older) do
      %{
        coverage_change: (newer.coverage[:line_coverage] || 0) - (older.coverage[:line_coverage] || 0),
        new_covered_files: [],  # Would need more detailed data
        newly_uncovered_files: []
      }
    end
    
    defp compare_all_aspects(newer, older) do
      %{
        failures: compare_failures(newer, older),
        performance: compare_performance(newer, older),
        coverage: compare_coverage(newer, older),
        overall: %{
          pass_rate_change: newer.statistics.pass_rate - older.statistics.pass_rate,
          total_tests_change: newer.statistics.total - older.statistics.total
        }
      }
    end
    
    defp calculate_percent_change(old, _new) when old == 0, do: 0
    defp calculate_percent_change(old, new) do
      ((new - old) / old * 100) |> Float.round(2)
    end
    
    defp summarize_run(run) do
      %{
        id: run[:id] || generate_id(),
        timestamp: run.timestamp,
        total_tests: run.statistics.total,
        pass_rate: run.statistics.pass_rate,
        duration: run.statistics[:avg_duration]
      }
    end
    
    defp identify_improvements(comparison) do
      improvements = []
      
      improvements = if get_in(comparison, [:overall, :pass_rate_change]) > 0 do
        ["Pass rate improved by #{get_in(comparison, [:overall, :pass_rate_change])}%" | improvements]
      else
        improvements
      end
      
      improvements = if get_in(comparison, [:failures, :fixed_tests]) != [] do
        fixed_count = length(get_in(comparison, [:failures, :fixed_tests]))
        ["#{fixed_count} previously failing tests now pass" | improvements]
      else
        improvements
      end
      
      improvements
    end
    
    defp identify_regressions(comparison) do
      regressions = []
      
      regressions = if get_in(comparison, [:overall, :pass_rate_change]) < 0 do
        ["Pass rate decreased by #{abs(get_in(comparison, [:overall, :pass_rate_change]))}%" | regressions]
      else
        regressions
      end
      
      regressions = if get_in(comparison, [:failures, :new_failures]) != [] do
        new_count = length(get_in(comparison, [:failures, :new_failures]))
        ["#{new_count} new test failures introduced" | regressions]
      else
        regressions
      end
      
      regressions
    end
    
    defp generate_id do
      :crypto.strong_rand_bytes(16) |> Base.encode16()
    end
  end
  
  # Action to generate test report
  defmodule GenerateReportAction do
    use Jido.Action,
      name: "generate_test_report",
      description: "Generate comprehensive test report",
      schema: [
        format: [type: :atom, default: :markdown],
        sections: [type: {:list, :atom}, default: [:summary, :failures, :trends, :recommendations]],
        include_raw_data: [type: :boolean, default: false]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      
      sections = Enum.reduce(params.sections, %{}, fn section, acc ->
        content = generate_section(section, agent_state, params)
        Map.put(acc, section, content)
      end)
      
      report = case params.format do
        :markdown -> format_markdown_report(sections, agent_state)
        :json -> format_json_report(sections, agent_state)
        :html -> format_html_report(sections, agent_state)
        _ -> format_text_report(sections, agent_state)
      end
      
      {:ok, %{
        format: params.format,
        report: report,
        metadata: %{
          generated_at: DateTime.utc_now(),
          data_points: length(agent_state.test_history),
          health_status: agent_state.test_metrics.health_trend
        }
      }}
    end
    
    defp generate_section(:summary, state, _params) do
      metrics = state.test_metrics
      recent_run = List.first(state.test_history)
      
      %{
        overall_health: metrics.health_trend,
        average_pass_rate: metrics.average_pass_rate,
        total_runs_analyzed: metrics.total_runs_analyzed,
        recent_results: if(recent_run, do: summarize_recent_run(recent_run), else: nil)
      }
    end
    
    defp generate_section(:failures, state, _params) do
      patterns = state.failure_patterns
      
      %{
        common_failure_types: patterns.by_type |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.take(5),
        failing_files: patterns.by_file |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.take(5),
        persistent_failures: identify_persistent_failures(state)
      }
    end
    
    defp generate_section(:trends, state, _params) do
      history = Enum.take(state.test_history, 10)
      
      %{
        pass_rate_trend: extract_trend(history, :pass_rate),
        duration_trend: extract_trend(history, :duration),
        failure_count_trend: extract_trend(history, :failures)
      }
    end
    
    defp generate_section(:recommendations, state, _params) do
      cache = state.recommendations_cache
      recent_recs = Map.values(cache) |> Enum.take(5)
      
      %{
        priority_actions: recent_recs,
        health_assessment: assess_overall_health(state)
      }
    end
    
    defp summarize_recent_run(run) do
      %{
        timestamp: run.timestamp,
        total_tests: run.statistics.total,
        passed: run.statistics.passed,
        failed: run.statistics.failed,
        pass_rate: run.statistics.pass_rate
      }
    end
    
    defp identify_persistent_failures(state) do
      # Find tests that fail frequently
      state.failure_patterns.by_test
      |> Enum.filter(fn {_test, count} -> count > 3 end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(10)
      |> Enum.map(fn {test, count} -> %{test: test, failure_count: count} end)
    end
    
    defp extract_trend(history, metric) do
      history
      |> Enum.map(fn run ->
        value = case metric do
          :pass_rate -> run.statistics.pass_rate
          :duration -> run.statistics[:avg_duration] || 0
          :failures -> run.statistics.failed
        end
        
        %{timestamp: run.timestamp, value: value}
      end)
    end
    
    defp assess_overall_health(state) do
      score = calculate_health_score(state)
      
      %{
        score: score,
        rating: determine_rating(score),
        key_issues: identify_key_issues(state)
      }
    end
    
    defp calculate_health_score(state) do
      metrics = state.test_metrics
      
      # Weight different factors
      pass_rate_score = metrics.average_pass_rate
      flaky_penalty = min(map_size(state.flaky_tests) * 5, 20)
      trend_bonus = case metrics.health_trend do
        :improving -> 10
        :stable -> 0
        :declining -> -10
      end
      
      max(0, min(100, pass_rate_score - flaky_penalty + trend_bonus))
    end
    
    defp determine_rating(score) do
      cond do
        score >= 90 -> :excellent
        score >= 75 -> :good
        score >= 60 -> :fair
        score >= 40 -> :poor
        true -> :critical
      end
    end
    
    defp identify_key_issues(state) do
      issues = []
      
      issues = if state.test_metrics.average_pass_rate < 80 do
        ["Low average pass rate (#{state.test_metrics.average_pass_rate}%)" | issues]
      else
        issues
      end
      
      issues = if map_size(state.flaky_tests) > 5 do
        ["High number of flaky tests (#{map_size(state.flaky_tests)})" | issues]
      else
        issues
      end
      
      issues
    end
    
    defp format_markdown_report(sections, _state) do
      """
      # Test Suite Report
      
      Generated: #{DateTime.utc_now() |> DateTime.to_string()}
      
      ## Summary
      #{format_markdown_section(sections[:summary])}
      
      ## Failure Analysis
      #{format_markdown_section(sections[:failures])}
      
      ## Trends
      #{format_markdown_section(sections[:trends])}
      
      ## Recommendations
      #{format_markdown_section(sections[:recommendations])}
      """
    end
    
    defp format_markdown_section(nil), do: "No data available"
    defp format_markdown_section(data) when is_map(data) do
      data
      |> Enum.map(fn {key, value} ->
        "**#{humanize(key)}**: #{format_value(value)}"
      end)
      |> Enum.join("\n")
    end
    
    defp format_json_report(sections, state) do
      Map.merge(sections, %{
        metadata: %{
          generated_at: DateTime.utc_now(),
          agent_version: "1.0.0",
          total_history: length(state.test_history)
        }
      })
    end
    
    defp format_html_report(_sections, _state) do
      # Simplified HTML report
      "<html><body><h1>Test Report</h1><p>HTML report generation not implemented</p></body></html>"
    end
    
    defp format_text_report(sections, _state) do
      sections
      |> Enum.map(fn {section, content} ->
        "=== #{humanize(section)} ===\n#{inspect(content, pretty: true)}"
      end)
      |> Enum.join("\n\n")
    end
    
    defp humanize(atom) do
      atom
      |> to_string()
      |> String.replace("_", " ")
      |> String.capitalize()
    end
    
    defp format_value(value) when is_list(value), do: "#{length(value)} items"
    defp format_value(value) when is_map(value), do: "#{map_size(value)} entries"
    defp format_value(value), do: to_string(value)
  end
  
  def additional_actions do
    [
      ExecuteToolAction,
      AnalyzeTrendsAction,
      IdentifyFlakyTestsAction,
      GenerateImprovementPlanAction,
      CompareTestRunsAction,
      GenerateReportAction
    ]
  end
  
  @impl true
  def handle_signal(state, %{"type" => "analyze_test_results"} = signal) do
    params = Map.get(signal, "data", %{})
    context = %{agent: %{state: state}}
    
    case ExecuteToolAction.run(%{params: params}, context) do
      {:ok, result} -> 
        {:ok, update_state_after_analysis(state, result)}
      {:error, reason} -> 
        {:error, reason}
    end
  end
  
  @impl true
  def handle_signal(state, %{"type" => "analyze_trends"} = signal) do
    params = Map.get(signal, "data", %{})
    context = %{agent: %{state: state}}
    
    case AnalyzeTrendsAction.run(params, context) do
      {:ok, result} -> 
        {:ok, put_in(state.test_metrics.health_trend, result.health_trend)}
      {:error, reason} -> 
        {:error, reason}
    end
  end
  
  @impl true
  def handle_signal(state, %{"type" => "identify_flaky"} = signal) do
    params = Map.get(signal, "data", %{})
    context = %{agent: %{state: state}}
    
    case IdentifyFlakyTestsAction.run(params, context) do
      {:ok, result} -> 
        {:ok, update_flaky_tests(state, result)}
      {:error, reason} -> 
        {:error, reason}
    end
  end
  
  @impl true
  def handle_signal(state, _signal) do
    {:ok, state}
  end
  
  def handle_action_result(state, ExecuteToolAction, {:ok, result}, _params) do
    # Add to test history
    history_entry = %{
      id: generate_id(),
      timestamp: DateTime.utc_now(),
      statistics: result.statistics,
      failures: result.failures,
      insights: result.insights,
      coverage: extract_coverage(result)
    }
    
    state = update_in(state.test_history, &([history_entry | &1] |> Enum.take(100)))
    
    # Update failure patterns
    state = update_failure_patterns(state, result.failures)
    
    # Update metrics
    state = update_test_metrics(state, result)
    
    # Cache recommendations
    if result[:recommendations] do
      update_recommendations_cache(state, result.recommendations)
    else
      state
    end
    
    {:ok, state}
  end
  
  def handle_action_result(state, IdentifyFlakyTestsAction, {:ok, result}, _params) do
    # Update flaky tests tracking
    new_flaky = Enum.reduce(result.flaky_tests, state.flaky_tests, fn test, acc ->
      Map.update(acc, test.test_name, test, fn existing ->
        %{existing | 
          failure_rate: test.failure_rate,
          total_runs: test.total_runs,
          last_updated: DateTime.utc_now()
        }
      end)
    end)
    
    {:ok, put_in(state.flaky_tests, new_flaky)}
  end
  
  def handle_action_result(state, _action, _result, _params) do
    {:ok, state}
  end
  
  defp update_state_after_analysis(state, result) do
    history_entry = %{
      id: generate_id(),
      timestamp: DateTime.utc_now(),
      statistics: result.statistics,
      failures: result.failures,
      insights: result.insights
    }
    
    state
    |> update_in([:test_history], &([history_entry | &1] |> Enum.take(100)))
    |> update_failure_patterns(result.failures)
    |> update_test_metrics(result)
  end
  
  defp update_failure_patterns(state, failures) do
    Enum.reduce(failures, state, fn failure, acc ->
      acc
      |> update_in([:failure_patterns, :by_type, failure.failure_type], &((&1 || 0) + 1))
      |> update_in([:failure_patterns, :by_test, failure.test_name], &((&1 || 0) + 1))
      |> update_in([:failure_patterns, :by_file, failure.file], &((&1 || 0) + 1))
    end)
  end
  
  defp update_test_metrics(state, result) do
    current_metrics = state.test_metrics
    history_count = current_metrics.total_runs_analyzed
    
    # Update running averages
    new_avg_pass_rate = 
      (current_metrics.average_pass_rate * history_count + result.statistics.pass_rate) / 
      (history_count + 1)
    
    new_avg_duration = if result.statistics[:avg_duration] do
      (current_metrics.average_duration * history_count + result.statistics.avg_duration) / 
      (history_count + 1)
    else
      current_metrics.average_duration
    end
    
    put_in(state.test_metrics, %{current_metrics |
      average_pass_rate: Float.round(new_avg_pass_rate, 2),
      average_duration: Float.round(new_avg_duration, 2),
      total_runs_analyzed: history_count + 1
    })
  end
  
  defp update_recommendations_cache(state, recommendations) do
    cache_entries = Enum.map(recommendations, fn rec ->
      {generate_cache_key(rec), %{
        recommendation: rec,
        created_at: DateTime.utc_now()
      }}
    end)
    
    new_cache = Enum.into(cache_entries, state.recommendations_cache)
    
    # Keep only recent recommendations
    cleaned_cache = new_cache
    |> Enum.sort_by(fn {_k, v} -> v.created_at end, {:desc, DateTime})
    |> Enum.take(50)
    |> Enum.into(%{})
    
    put_in(state.recommendations_cache, cleaned_cache)
  end
  
  defp update_flaky_tests(state, result) do
    new_flaky = Enum.reduce(result.flaky_tests, %{}, fn test, acc ->
      Map.put(acc, test.test_name, %{
        failure_rate: test.failure_rate,
        flakiness_score: test.flakiness_score,
        total_runs: test.total_runs,
        last_updated: DateTime.utc_now()
      })
    end)
    
    put_in(state.flaky_tests, Map.merge(state.flaky_tests, new_flaky))
  end
  
  defp extract_coverage(result) do
    # Extract coverage data if present in results
    %{
      line_coverage: result[:coverage][:line] || 0,
      branch_coverage: result[:coverage][:branch] || 0
    }
  end
  
  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
  
  defp generate_cache_key(recommendation) do
    :crypto.hash(:sha256, recommendation)
    |> Base.encode16()
    |> String.slice(0..15)
  end
end