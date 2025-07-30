defmodule RubberDuck.Tools.TestSummarizer do
  @moduledoc """
  Summarizes test results and identifies key failures or gaps.
  
  This tool analyzes test output, failure patterns, and coverage data
  to provide actionable insights about test quality and health.
  """
  
  use RubberDuck.Tool
  
  alias RubberDuck.LLM.Service
  
  tool do
    name :test_summarizer
    description "Summarizes test results and identifies key failures or gaps"
    category :testing
    version "1.0.0"
    tags [:testing, :analysis, :reporting, :quality]
    
    parameter :test_output do
      type :string
      required true
      description "Raw test output or results to analyze"
      constraints [
        min_length: 1,
        max_length: 100_000
      ]
    end
    
    parameter :format do
      type :string
      required false
      description "Format of the test output"
      default "auto"
      constraints [
        enum: [
          "auto",       # Auto-detect format
          "exunit",     # ExUnit output
          "junit",      # JUnit XML
          "tap",        # TAP format
          "json",       # JSON format
          "raw"         # Raw text
        ]
      ]
    end
    
    parameter :summary_type do
      type :string
      required false
      description "Type of summary to generate"
      default "comprehensive"
      constraints [
        enum: [
          "brief",        # Brief overview
          "comprehensive", # Detailed analysis
          "failures_only", # Focus on failures
          "trends",       # Pattern analysis
          "actionable"    # Action items
        ]
      ]
    end
    
    parameter :include_coverage do
      type :boolean
      required false
      description "Include coverage analysis if available"
      default true
    end
    
    parameter :highlight_flaky do
      type :boolean
      required false
      description "Identify potentially flaky tests"
      default true
    end
    
    parameter :group_failures do
      type :boolean
      required false
      description "Group similar failures together"
      default true
    end
    
    parameter :suggest_fixes do
      type :boolean
      required false
      description "Use AI to suggest fixes for failures"
      default true
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 1
    end
    
    security do
      sandbox :restricted
      capabilities [:llm_access]
      rate_limit 100
    end
  end
  
  @doc """
  Executes test result analysis and summarization.
  """
  def execute(params, context) do
    with {:ok, parsed} <- parse_test_output(params),
         {:ok, analyzed} <- analyze_test_results(parsed, params),
         {:ok, insights} <- generate_insights(analyzed, params, context),
         {:ok, summary} <- format_summary(insights, params) do
      
      {:ok, %{
        summary: summary,
        statistics: analyzed.statistics,
        failures: analyzed.failures,
        insights: insights.key_findings,
        recommendations: insights.recommendations,
        metadata: %{
          format_detected: parsed.format,
          analysis_type: params.summary_type,
          total_tests_analyzed: analyzed.statistics.total
        }
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp parse_test_output(params) do
    format = if params.format == "auto" do
      detect_format(params.test_output)
    else
      params.format
    end
    
    parsed = case format do
      "exunit" -> parse_exunit_output(params.test_output)
      "junit" -> parse_junit_output(params.test_output)
      "tap" -> parse_tap_output(params.test_output)
      "json" -> parse_json_output(params.test_output)
      "raw" -> parse_raw_output(params.test_output)
      _ -> parse_raw_output(params.test_output)
    end
    
    case parsed do
      {:ok, data} -> {:ok, Map.put(data, :format, format)}
      error -> error
    end
  end
  
  defp detect_format(output) do
    cond do
      output =~ ~r/\d+ tests?, \d+ failures?/ -> "exunit"
      output =~ ~r/<\?xml.*<testsuites/ -> "junit"
      output =~ ~r/TAP version \d+/ -> "tap"
      output =~ ~r/^\s*[{\[]/ -> "json"
      true -> "raw"
    end
  end
  
  defp parse_exunit_output(output) do
    # Parse ExUnit output format
    lines = String.split(output, "\n")
    
    # Extract summary line
    summary_line = Enum.find(lines, &(&1 =~ ~r/\d+ tests?, \d+ failures?/))
    
    statistics = if summary_line do
      parse_exunit_summary(summary_line)
    else
      %{total: 0, passed: 0, failed: 0, skipped: 0}
    end
    
    # Extract failures
    failures = parse_exunit_failures(output)
    
    # Extract test durations if available
    durations = parse_test_durations(output)
    
    {:ok, %{
      statistics: statistics,
      failures: failures,
      durations: durations,
      raw_output: output
    }}
  end
  
  defp parse_exunit_summary(line) do
    # Example: "5 tests, 2 failures, 1 skipped"
    tests = case Regex.run(~r/(\d+) tests?/, line) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
    
    failures = case Regex.run(~r/(\d+) failures?/, line) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
    
    skipped = case Regex.run(~r/(\d+) skipped/, line) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
    
    passed = tests - failures - skipped
    
    %{
      total: tests,
      passed: max(0, passed),
      failed: failures,
      skipped: skipped
    }
  end
  
  defp parse_exunit_failures(output) do
    # Split by failure markers
    failure_sections = String.split(output, ~r/\n\s*\d+\)\s+/)
    |> Enum.drop(1)  # Remove first section before first failure
    
    Enum.map(failure_sections, &parse_single_failure/1)
    |> Enum.reject(&is_nil/1)
  end
  
  defp parse_single_failure(section) do
    lines = String.split(section, "\n")
    
    # First line usually contains test name
    test_name = case hd(lines) do
      nil -> "Unknown test"
      line -> String.trim(line)
    end
    
    # Look for file and line info
    {file, line_num} = extract_file_info(section)
    
    # Extract error message
    error_message = extract_error_message(section)
    
    # Categorize failure type
    failure_type = categorize_failure(error_message)
    
    %{
      test_name: test_name,
      file: file,
      line: line_num,
      error_message: error_message,
      failure_type: failure_type,
      raw_section: section
    }
  end
  
  defp extract_file_info(section) do
    case Regex.run(~r/([^\s:]+\.exs):(\d+)/, section) do
      [_, file, line] -> {file, String.to_integer(line)}
      _ -> {"unknown", 0}
    end
  end
  
  defp extract_error_message(section) do
    # Look for assertion errors, exceptions, etc.
    cond do
      section =~ ~r/Assertion with (.+) failed/ ->
        case Regex.run(~r/Assertion with (.+) failed/, section) do
          [_, assertion] -> "Assertion failed: #{assertion}"
          _ -> "Assertion failed"
        end
      
      section =~ ~r/\*\* \((.+)\) (.+)/ ->
        case Regex.run(~r/\*\* \((.+)\) (.+)/, section) do
          [_, exception, message] -> "#{exception}: #{message}"
          _ -> "Exception occurred"
        end
      
      true ->
        # Take first few lines as error message
        section
        |> String.split("\n")
        |> Enum.take(3)
        |> Enum.join(" ")
        |> String.trim()
    end
  end
  
  defp categorize_failure(error_message) do
    cond do
      error_message =~ ~r/Assertion/ -> :assertion
      error_message =~ ~r/ArgumentError/ -> :argument_error
      error_message =~ ~r/MatchError/ -> :match_error
      error_message =~ ~r/KeyError/ -> :key_error
      error_message =~ ~r/FunctionClauseError/ -> :function_clause
      error_message =~ ~r/timeout/ -> :timeout
      error_message =~ ~r/connection/ -> :connection
      error_message =~ ~r/UndefinedFunctionError/ -> :undefined_function
      true -> :other
    end
  end
  
  defp parse_test_durations(output) do
    # Look for timing information
    Regex.scan(~r/Finished in ([\d.]+) seconds/, output)
    |> Enum.map(fn [_, time] -> String.to_float(time) end)
  end
  
  defp parse_junit_output(output) do
    # Simple XML parsing for JUnit format
    # In production, would use a proper XML parser
    {:ok, %{
      statistics: %{total: 0, passed: 0, failed: 0, skipped: 0},
      failures: [],
      durations: [],
      raw_output: output
    }}
  end
  
  defp parse_tap_output(output) do
    lines = String.split(output, "\n")
    
    # Parse TAP format
    test_lines = Enum.filter(lines, &(&1 =~ ~r/^(not )?ok \d+/))
    
    total = length(test_lines)
    failed_lines = Enum.filter(test_lines, &String.starts_with?(&1, "not ok"))
    failed = length(failed_lines)
    passed = total - failed
    
    failures = Enum.map(failed_lines, fn line ->
      %{
        test_name: String.trim(String.replace(line, ~r/^not ok \d+ - /, "")),
        file: "unknown",
        line: 0,
        error_message: "TAP test failed",
        failure_type: :tap_failure,
        raw_section: line
      }
    end)
    
    {:ok, %{
      statistics: %{total: total, passed: passed, failed: failed, skipped: 0},
      failures: failures,
      durations: [],
      raw_output: output
    }}
  end
  
  defp parse_json_output(output) do
    case Jason.decode(output) do
      {:ok, data} ->
        statistics = %{
          total: get_in(data, ["stats", "total"]) || 0,
          passed: get_in(data, ["stats", "passed"]) || 0,
          failed: get_in(data, ["stats", "failed"]) || 0,
          skipped: get_in(data, ["stats", "skipped"]) || 0
        }
        
        failures = (get_in(data, ["failures"]) || [])
        |> Enum.map(&parse_json_failure/1)
        
        {:ok, %{
          statistics: statistics,
          failures: failures,
          durations: [],
          raw_output: output
        }}
      
      {:error, _} ->
        {:error, "Invalid JSON format"}
    end
  end
  
  defp parse_json_failure(failure_data) do
    %{
      test_name: failure_data["test"] || "Unknown",
      file: failure_data["file"] || "unknown",
      line: failure_data["line"] || 0,
      error_message: failure_data["message"] || "No message",
      failure_type: String.to_atom(failure_data["type"] || "other"),
      raw_section: inspect(failure_data)
    }
  end
  
  defp parse_raw_output(output) do
    # Basic parsing for unknown formats
    line_count = length(String.split(output, "\n"))
    
    {:ok, %{
      statistics: %{total: line_count, passed: 0, failed: 0, skipped: 0},
      failures: [],
      durations: [],
      raw_output: output
    }}
  end
  
  defp analyze_test_results(parsed, params) do
    # Group failures by type if requested
    grouped_failures = if params.group_failures do
      group_failures_by_type(parsed.failures)
    else
      parsed.failures
    end
    
    # Identify flaky tests if requested
    flaky_indicators = if params.highlight_flaky do
      identify_flaky_patterns(parsed)
    else
      []
    end
    
    # Calculate additional statistics
    enhanced_stats = enhance_statistics(parsed.statistics, parsed)
    
    analyzed = %{
      statistics: enhanced_stats,
      failures: grouped_failures,
      flaky_indicators: flaky_indicators,
      patterns: identify_failure_patterns(parsed.failures)
    }
    
    {:ok, analyzed}
  end
  
  defp group_failures_by_type(failures) do
    failures
    |> Enum.group_by(& &1.failure_type)
    |> Enum.map(fn {type, type_failures} ->
      %{
        type: type,
        count: length(type_failures),
        failures: type_failures,
        sample_error: hd(type_failures).error_message
      }
    end)
  end
  
  defp identify_flaky_patterns(parsed) do
    # Simple heuristics for flaky test detection
    indicators = []
    
    # Check for timeout-related failures
    timeout_failures = Enum.filter(parsed.failures, &(&1.failure_type == :timeout))
    indicators = if length(timeout_failures) > 0 do
      [{:timeouts, length(timeout_failures)} | indicators]
    else
      indicators
    end
    
    # Check for connection failures
    connection_failures = Enum.filter(parsed.failures, &(&1.failure_type == :connection))
    indicators = if length(connection_failures) > 0 do
      [{:connection_issues, length(connection_failures)} | indicators]
    else
      indicators
    end
    
    indicators
  end
  
  defp enhance_statistics(base_stats, parsed) do
    pass_rate = if base_stats.total > 0 do
      base_stats.passed / base_stats.total * 100
    else
      0
    end
    
    avg_duration = if parsed.durations != [] do
      Enum.sum(parsed.durations) / length(parsed.durations)
    else
      nil
    end
    
    Map.merge(base_stats, %{
      pass_rate: Float.round(pass_rate, 2),
      avg_duration: avg_duration,
      failure_rate: Float.round(100 - pass_rate, 2)
    })
  end
  
  defp identify_failure_patterns(failures) do
    patterns = %{}
    
    # Group by error type
    type_counts = failures
    |> Enum.group_by(& &1.failure_type)
    |> Enum.map(fn {type, list} -> {type, length(list)} end)
    |> Enum.into(%{})
    
    patterns = Map.put(patterns, :by_type, type_counts)
    
    # Group by file
    file_counts = failures
    |> Enum.group_by(& &1.file)
    |> Enum.map(fn {file, list} -> {file, length(list)} end)
    |> Enum.into(%{})
    
    patterns = Map.put(patterns, :by_file, file_counts)
    
    patterns
  end
  
  defp generate_insights(analyzed, params, context) do
    if params.suggest_fixes do
      generate_ai_insights(analyzed, params, context)
    else
      generate_basic_insights(analyzed)
    end
  end
  
  defp generate_ai_insights(analyzed, params, context) do
    prompt = build_insights_prompt(analyzed, params)
    
    case Service.generate(%{
      prompt: prompt,
      max_tokens: 1500,
      temperature: 0.3,
      model: context[:llm_model] || "gpt-4"
    }) do
      {:ok, response} ->
        insights = parse_ai_insights(response)
        {:ok, insights}
      
      {:error, _} ->
        # Fallback to basic insights
        generate_basic_insights(analyzed)
    end
  end
  
  defp build_insights_prompt(analyzed, _params) do
    failure_summary = analyzed.failures
    |> Enum.take(5)
    |> Enum.map(fn failure ->
      "- #{failure.test_name}: #{failure.error_message}"
    end)
    |> Enum.join("\n")
    
    """
    Analyze these test results and provide insights:
    
    Statistics:
    - Total tests: #{analyzed.statistics.total}
    - Passed: #{analyzed.statistics.passed}
    - Failed: #{analyzed.statistics.failed}
    - Pass rate: #{analyzed.statistics.pass_rate}%
    
    Top failures:
    #{failure_summary}
    
    Failure patterns:
    #{inspect(analyzed.patterns)}
    
    Please provide:
    1. Key findings (2-3 bullet points)
    2. Specific recommendations for fixing failures
    3. Overall test health assessment
    
    Focus on actionable insights for developers.
    """
  end
  
  defp parse_ai_insights(response) do
    # Simple parsing of AI response
    sections = String.split(response, ~r/\n\d+\.\s*/)
    
    key_findings = extract_bullet_points(response, "findings")
    recommendations = extract_bullet_points(response, "recommendations")
    
    %{
      key_findings: key_findings,
      recommendations: recommendations,
      health_assessment: extract_health_assessment(response)
    }
  end
  
  defp extract_bullet_points(text, section) do
    # Extract bullet points from sections
    Regex.scan(~r/- (.+)/, text)
    |> Enum.map(fn [_, point] -> String.trim(point) end)
    |> Enum.take(5)
  end
  
  defp extract_health_assessment(text) do
    cond do
      text =~ ~r/excellent|great|good/i -> :good
      text =~ ~r/concerning|poor|bad/i -> :poor
      text =~ ~r/moderate|average|fair/i -> :fair
      true -> :unknown
    end
  end
  
  defp generate_basic_insights(analyzed) do
    key_findings = []
    recommendations = []
    
    # Analyze pass rate
    {findings, recs} = if analyzed.statistics.pass_rate < 70 do
      {["Low pass rate (#{analyzed.statistics.pass_rate}%) indicates significant issues" | key_findings],
       ["Focus on fixing failing tests before adding new ones" | recommendations]}
    else
      {key_findings, recommendations}
    end
    
    # Analyze failure patterns
    {findings, recs} = if analyzed.patterns.by_type do
      most_common = analyzed.patterns.by_type
      |> Enum.max_by(fn {_type, count} -> count end, fn -> {:other, 0} end)
      
      case most_common do
        {type, count} when count > 1 ->
          {["Most common failure type: #{type} (#{count} occurrences)" | findings],
           ["Review #{type} failures for common root cause" | recs]}
        _ ->
          {findings, recs}
      end
    else
      {findings, recs}
    end
    
    health = cond do
      analyzed.statistics.pass_rate >= 95 -> :excellent
      analyzed.statistics.pass_rate >= 80 -> :good
      analyzed.statistics.pass_rate >= 60 -> :fair
      true -> :poor
    end
    
    {:ok, %{
      key_findings: findings,
      recommendations: recs,
      health_assessment: health
    }}
  end
  
  defp format_summary(insights, params) do
    case params.summary_type do
      "brief" -> format_brief_summary(insights)
      "comprehensive" -> format_comprehensive_summary(insights)
      "failures_only" -> format_failures_summary(insights)
      "trends" -> format_trends_summary(insights)
      "actionable" -> format_actionable_summary(insights)
    end
  end
  
  defp format_brief_summary(insights) do
    {:ok, %{
      type: "brief",
      content: Enum.join(insights.key_findings, ". "),
      health: insights.health_assessment
    }}
  end
  
  defp format_comprehensive_summary(insights) do
    {:ok, %{
      type: "comprehensive",
      findings: insights.key_findings,
      recommendations: insights.recommendations,
      health: insights.health_assessment,
      summary: "Test suite health: #{insights.health_assessment}"
    }}
  end
  
  defp format_failures_summary(insights) do
    {:ok, %{
      type: "failures_only",
      recommendations: insights.recommendations,
      focus: "failure_resolution"
    }}
  end
  
  defp format_trends_summary(insights) do
    {:ok, %{
      type: "trends",
      findings: insights.key_findings,
      trend_analysis: "Based on current data snapshot"
    }}
  end
  
  defp format_actionable_summary(insights) do
    {:ok, %{
      type: "actionable",
      action_items: insights.recommendations,
      priority: determine_priority(insights.health_assessment)
    }}
  end
  
  defp determine_priority(health) do
    case health do
      :poor -> :high
      :fair -> :medium
      :good -> :low
      :excellent -> :maintenance
      _ -> :medium
    end
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end