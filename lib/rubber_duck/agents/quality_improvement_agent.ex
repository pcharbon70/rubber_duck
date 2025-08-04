defmodule RubberDuck.Agents.QualityImprovementAgent do
  @moduledoc """
  Quality Improvement Agent that analyzes and enhances code quality.
  
  This agent performs comprehensive quality analysis, applies improvement
  strategies, and tracks quality metrics over time. It focuses on
  maintainability, readability, performance, and adherence to best practices.
  
  ## Responsibilities
  
  - Analyze code quality metrics and patterns
  - Apply quality improvement strategies
  - Enforce coding standards and best practices
  - Track quality trends and improvements
  - Generate quality reports and recommendations
  """

  use Jido.Agent,
    name: "quality_improvement",
    description: "Analyzes and enhances code quality through metrics analysis and improvement strategies",
    category: "quality",
    tags: ["quality", "refactoring", "metrics", "best-practices"],
    vsn: "1.0.0",
    schema: [
      analysis_status: [
        type: :atom, 
        values: [:idle, :analyzing, :improving, :reporting], 
        default: :idle,
        doc: "Current status of quality analysis"
      ],
      active_analyses: [
        type: :map, 
        default: %{},
        doc: "Currently active quality analyses"
      ],
      improvement_history: [
        type: {:list, :map}, 
        default: [],
        doc: "History of completed improvements"
      ],
      quality_standards: [
        type: :map, 
        default: %{},
        doc: "Configured quality standards"
      ],
      best_practices: [
        type: :map, 
        default: %{},
        doc: "Best practice definitions"
      ],
      refactoring_patterns: [
        type: :map, 
        default: %{},
        doc: "Available refactoring patterns"
      ],
      metrics: [
        type: :map, 
        default: %{
          total_analyses: 0,
          quality_score: 0.0,
          improvements_applied: 0,
          avg_improvement_time: 0.0,
          quality_trends: %{}
        },
        doc: "Quality metrics and statistics"
      ]
    ]

  alias RubberDuck.Agents.ErrorHandling
  require Logger

  # Signal-to-Action Mappings
  # This replaces all handle_signal callbacks with Jido action routing
  
  @impl true
  def signal_mappings do
    %{
      "analyze_quality" => {AnalyzeQualityAction, &extract_analyze_params/1},
      "apply_improvements" => {ApplyImprovementAction, &extract_improvements_params/1},
      "enforce_standards" => {EnforceStandardsAction, &extract_standards_params/1},
      "track_metrics" => {TrackMetricsAction, &extract_metrics_params/1},
      "generate_report" => {GenerateQualityReportAction, &extract_report_params/1}
    }
  end
  
  # Parameter extraction functions for signal-to-action mapping
  
  defp extract_analyze_params(%{"payload" => payload}) do
    code = Map.get(payload, "code")
    language = Map.get(payload, "language", "elixir")
    depth = Map.get(payload, "depth", "standard")
    
    %{
      code: code,
      language: language,
      analysis_depth: depth,
      metrics_to_check: Map.get(payload, "metrics_to_check"),
      context: Map.get(payload, "context", %{})
    }
  end
  
  defp extract_improvements_params(%{"payload" => payload}) do
    %{
      improvements: Map.get(payload, "improvements", []),
      code: Map.get(payload, "code"),
      language: Map.get(payload, "language", "elixir"),
      apply_automatically: Map.get(payload, "apply_automatically", false),
      backup_original: Map.get(payload, "backup_original", true)
    }
  end
  
  defp extract_standards_params(%{"payload" => payload}) do
    %{
      standards: Map.get(payload, "standards", []),
      code: Map.get(payload, "code"),
      language: Map.get(payload, "language", "elixir"),
      enforcement_level: parse_enforcement_level(Map.get(payload, "enforcement_level", "standard")),
      auto_fix: Map.get(payload, "auto_fix", false)
    }
  end
  
  defp extract_metrics_params(%{"payload" => payload}) do
    %{
      metrics_type: parse_metrics_type(Map.get(payload, "metrics_type", "quality")),
      time_range: parse_time_range(Map.get(payload, "time_range", "recent")),
      include_trends: Map.get(payload, "include_trends", true),
      aggregation_level: parse_aggregation_level(Map.get(payload, "aggregation_level", "summary"))
    }
  end
  
  defp extract_report_params(%{"payload" => payload}) do
    %{
      report_type: parse_report_type(Map.get(payload, "report_type", "comprehensive")),
      include_recommendations: Map.get(payload, "include_recommendations", true),
      format: parse_report_format(Map.get(payload, "format", "markdown")),
      time_range: parse_time_range(Map.get(payload, "time_range", "recent")),
      include_metrics: Map.get(payload, "include_metrics", true)
    }
  end
  
  # Parsing helper functions
  
  defp parse_enforcement_level("strict"), do: :strict
  defp parse_enforcement_level("standard"), do: :standard
  defp parse_enforcement_level("lenient"), do: :lenient
  defp parse_enforcement_level(_), do: :standard
  
  defp parse_metrics_type("quality"), do: :quality
  defp parse_metrics_type("performance"), do: :performance
  defp parse_metrics_type("maintainability"), do: :maintainability
  defp parse_metrics_type("all"), do: :all
  defp parse_metrics_type(_), do: :quality
  
  defp parse_time_range("recent"), do: :recent
  defp parse_time_range("all"), do: :all
  defp parse_time_range("last_week"), do: :last_week
  defp parse_time_range("last_month"), do: :last_month
  defp parse_time_range(_), do: :recent
  
  defp parse_aggregation_level("summary"), do: :summary
  defp parse_aggregation_level("detailed"), do: :detailed
  defp parse_aggregation_level("raw"), do: :raw
  defp parse_aggregation_level(_), do: :summary
  
  defp parse_report_type("comprehensive"), do: :comprehensive
  defp parse_report_type("summary"), do: :summary
  defp parse_report_type("metrics_only"), do: :metrics_only
  defp parse_report_type(_), do: :comprehensive
  
  defp parse_report_format("markdown"), do: :markdown
  defp parse_report_format("json"), do: :json
  defp parse_report_format("html"), do: :html
  defp parse_report_format(_), do: :markdown

  # Action definitions

  defmodule AnalyzeQualityAction do
    @moduledoc """
    Analyzes code quality metrics and identifies improvement opportunities.
    """
    use Jido.Action,
      name: "analyze_quality",
      description: "Perform quality analysis on code",
      schema: [
        code: [type: :string, required: true, doc: "Code to analyze"],
        language: [type: :string, required: true, doc: "Programming language"],
        analysis_depth: [type: :string, default: "standard", doc: "Analysis depth: basic, standard, comprehensive"],
        metrics_to_check: [type: {:list, :string}, doc: "Specific metrics to evaluate"],
        context: [type: :map, doc: "Additional analysis context"]
      ]

    @impl true
    def run(params, _context) do
      metrics = analyze_code_quality(
        params.code,
        params.language,
        params.analysis_depth
      )
      
      improvements = identify_improvements(metrics, params.language)
      
      {:ok, %{
        metrics: metrics,
        improvements: improvements,
        quality_score: calculate_quality_score(metrics),
        analyzed_at: DateTime.utc_now()
      }}
    end

    defp analyze_code_quality(code, language, depth) do
      # Analyze various quality metrics
      %{
        complexity: calculate_complexity(code, language),
        maintainability: calculate_maintainability(code, language),
        readability: calculate_readability(code, language),
        testability: calculate_testability(code, language),
        documentation: analyze_documentation(code, language),
        duplication: detect_duplication(code),
        code_smells: detect_code_smells(code, language, depth),
        performance_issues: detect_performance_issues(code, language)
      }
    end

    defp calculate_complexity(code, _language) do
      # Simplified cyclomatic complexity calculation
      conditionals = Regex.scan(~r/\b(if|case|cond|when|unless)\b/, code) |> length()
      loops = Regex.scan(~r/\b(for|while|Enum\.\w+|Stream\.\w+)\b/, code) |> length()
      
      %{
        cyclomatic: conditionals + loops + 1,
        cognitive: conditionals * 2 + loops * 3,
        nesting_depth: calculate_nesting_depth(code)
      }
    end

    defp calculate_maintainability(code, _language) do
      lines = String.split(code, "\n")
      loc = length(lines)
      comments = Enum.count(lines, &String.contains?(&1, "#"))
      
      %{
        lines_of_code: loc,
        comment_ratio: if(loc > 0, do: comments / loc, else: 0),
        function_length: calculate_avg_function_length(code),
        module_cohesion: calculate_module_cohesion(code)
      }
    end

    defp calculate_readability(code, _language) do
      %{
        line_length: calculate_avg_line_length(code),
        naming_consistency: check_naming_consistency(code),
        formatting_score: check_formatting(code),
        clarity_score: calculate_clarity(code)
      }
    end

    defp calculate_testability(code, _language) do
      %{
        dependency_injection: check_dependency_injection(code),
        pure_functions: count_pure_functions(code),
        side_effects: detect_side_effects(code),
        mocking_difficulty: assess_mocking_difficulty(code)
      }
    end

    defp analyze_documentation(code, _language) do
      %{
        module_docs: check_module_docs(code),
        function_docs: check_function_docs(code),
        type_specs: check_type_specs(code),
        examples: check_examples(code)
      }
    end

    defp detect_duplication(code) do
      # Simple duplication detection
      lines = String.split(code, "\n")
      duplicates = lines
        |> Enum.frequencies()
        |> Enum.filter(fn {_line, count} -> count > 1 end)
        |> length()
      
      %{
        duplicate_lines: duplicates,
        duplication_ratio: if(length(lines) > 0, do: duplicates / length(lines), else: 0)
      }
    end

    defp detect_code_smells(code, _language, _depth) do
      [
        check_long_methods(code),
        check_large_modules(code),
        check_too_many_parameters(code),
        check_nested_conditions(code)
      ]
      |> Enum.filter(&(&1 != nil))
    end

    defp detect_performance_issues(code, _language) do
      [
        check_n_plus_one(code),
        check_inefficient_algorithms(code),
        check_memory_leaks(code)
      ]
      |> Enum.filter(&(&1 != nil))
    end

    defp identify_improvements(metrics, _language) do
      improvements = []
      
      improvements = if metrics.complexity.cyclomatic > 10 do
        [%{type: "reduce_complexity", priority: "high", description: "Reduce cyclomatic complexity"} | improvements]
      else
        improvements
      end
      
      improvements = if metrics.maintainability.comment_ratio < 0.1 do
        [%{type: "add_documentation", priority: "medium", description: "Add code documentation"} | improvements]
      else
        improvements
      end
      
      improvements
    end

    defp calculate_quality_score(metrics) do
      # Weighted quality score calculation
      complexity_score = max(0, 100 - metrics.complexity.cyclomatic * 5)
      maintainability_score = metrics.maintainability.comment_ratio * 100
      readability_score = 80  # Placeholder
      
      (complexity_score * 0.4 + maintainability_score * 0.3 + readability_score * 0.3)
    end

    # Helper functions (simplified implementations)
    defp calculate_nesting_depth(code) do
      # Count maximum indentation level
      String.split(code, "\n")
      |> Enum.map(fn line ->
        case Regex.run(~r/^(\s*)/, line) do
          [_, spaces] -> String.length(spaces) / 2
          _ -> 0
        end
      end)
      |> Enum.max(fn -> 0 end)
      |> round()
    end

    defp calculate_avg_function_length(code) do
      functions = Regex.scan(~r/def\s+\w+.*?(?=\n\s*def|\n\s*end|\z)/s, code)
      if length(functions) > 0 do
        total_lines = functions
          |> Enum.map(fn [func] -> length(String.split(func, "\n")) end)
          |> Enum.sum()
        total_lines / length(functions)
      else
        0
      end
    end

    defp calculate_module_cohesion(_code), do: 0.75
    defp calculate_avg_line_length(code) do
      lines = String.split(code, "\n")
      if length(lines) > 0 do
        total_length = lines |> Enum.map(&String.length/1) |> Enum.sum()
        total_length / length(lines)
      else
        0
      end
    end
    defp check_naming_consistency(_code), do: 0.8
    defp check_formatting(_code), do: 0.85
    defp calculate_clarity(_code), do: 0.7
    defp check_dependency_injection(_code), do: true
    defp count_pure_functions(_code), do: 5
    defp detect_side_effects(_code), do: 2
    defp assess_mocking_difficulty(_code), do: "low"
    defp check_module_docs(_code), do: true
    defp check_function_docs(_code), do: 0.6
    defp check_type_specs(_code), do: 0.4
    defp check_examples(_code), do: false
    defp check_long_methods(_code), do: nil
    defp check_large_modules(_code), do: nil
    defp check_too_many_parameters(_code), do: nil
    defp check_nested_conditions(_code), do: nil
    defp check_n_plus_one(_code), do: nil
    defp check_inefficient_algorithms(_code), do: nil
    defp check_memory_leaks(_code), do: nil
  end

  defmodule ApplyImprovementAction do
    @moduledoc """
    Applies quality improvement strategies to code.
    """
    use Jido.Action,
      name: "apply_improvement",
      description: "Apply quality improvements to code",
      schema: [
        code: [type: :string, required: true, doc: "Code to improve"],
        improvements: [type: {:list, :map}, required: true, doc: "Improvements to apply"],
        language: [type: :string, required: true, doc: "Programming language"],
        style_guide: [type: :map, doc: "Style guide to follow"],
        auto_fix: [type: :boolean, default: false, doc: "Automatically apply fixes"]
      ]

    @impl true
    def run(params, _context) do
      improved_code = params.improvements
        |> Enum.reduce(params.code, fn improvement, code ->
          apply_single_improvement(code, improvement, params.language)
        end)
      
      {:ok, %{
        original_code: params.code,
        improved_code: improved_code,
        improvements_applied: length(params.improvements),
        applied_at: DateTime.utc_now()
      }}
    end

    defp apply_single_improvement(code, %{type: "reduce_complexity"} = _improvement, _language) do
      # Simplified complexity reduction
      code
      |> extract_complex_conditions()
      |> extract_long_functions()
    end

    defp apply_single_improvement(code, %{type: "add_documentation"} = _improvement, _language) do
      # Add basic documentation
      add_module_documentation(code)
    end

    defp apply_single_improvement(code, _improvement, _language) do
      # Default: return unchanged
      code
    end

    defp extract_complex_conditions(code) do
      # Placeholder for extracting complex conditions into separate functions
      code
    end

    defp extract_long_functions(code) do
      # Placeholder for breaking up long functions
      code
    end

    defp add_module_documentation(code) do
      if !String.contains?(code, "@moduledoc") do
        String.replace(code, ~r/^defmodule/, "@moduledoc \"\"\"\nModule documentation\n\"\"\"\n\ndefmodule", global: false)
      else
        code
      end
    end
  end

  defmodule EnforceStandardsAction do
    @moduledoc """
    Enforces coding standards and best practices.
    """
    use Jido.Action,
      name: "enforce_standards",
      description: "Check and enforce coding standards",
      schema: [
        code: [type: :string, required: true, doc: "Code to check"],
        language: [type: :string, required: true, doc: "Programming language"],
        standards: [type: {:list, :string}, doc: "Standards to enforce"],
        auto_fix: [type: :boolean, default: false, doc: "Auto-fix violations"]
      ]

    @impl true
    def run(params, _context) do
      violations = check_standards(params.code, params.language, params.standards)
      
      fixed_code = if params.auto_fix do
        fix_violations(params.code, violations)
      else
        params.code
      end
      
      {:ok, %{
        violations: violations,
        violations_count: length(violations),
        fixed_code: fixed_code,
        compliant: length(violations) == 0,
        checked_at: DateTime.utc_now()
      }}
    end

    defp check_standards(code, _language, _standards) do
      violations = []
      
      # Check line length
      violations = violations ++ check_line_length(code)
      
      # Check naming conventions
      violations = violations ++ check_naming_conventions(code)
      
      # Check formatting
      violations = violations ++ check_formatting_standards(code)
      
      violations
    end

    defp check_line_length(code) do
      String.split(code, "\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _num} -> String.length(line) > 100 end)
      |> Enum.map(fn {_line, num} ->
        %{
          type: "line_too_long",
          line: num,
          severity: "warning",
          message: "Line exceeds 100 characters"
        }
      end)
    end

    defp check_naming_conventions(code) do
      # Check for non-snake_case functions
      Regex.scan(~r/def\s+([A-Z]\w*|[a-z]+[A-Z]\w*)/, code)
      |> Enum.map(fn [_match, name] ->
        %{
          type: "naming_convention",
          function: name,
          severity: "warning",
          message: "Function name should be snake_case"
        }
      end)
    end

    defp check_formatting_standards(_code) do
      # Placeholder for formatting checks
      []
    end

    defp fix_violations(code, violations) do
      Enum.reduce(violations, code, fn violation, acc ->
        fix_single_violation(acc, violation)
      end)
    end

    defp fix_single_violation(code, %{type: "line_too_long", line: line_num}) do
      lines = String.split(code, "\n")
      {before, [long_line | after_lines]} = Enum.split(lines, line_num - 1)
      
      # Simple line wrapping
      wrapped = wrap_line(long_line, 100)
      
      (before ++ [wrapped] ++ after_lines)
      |> Enum.join("\n")
    end

    defp fix_single_violation(code, _violation) do
      code
    end

    defp wrap_line(line, _max_length) do
      # Simplified line wrapping
      line
    end
  end

  defmodule TrackMetricsAction do
    @moduledoc """
    Tracks and updates quality metrics over time.
    """
    use Jido.Action,
      name: "track_metrics",
      description: "Track quality metrics and trends",
      schema: [
        metrics: [type: :map, required: true, doc: "Current metrics to track"],
        timestamp: [type: :string, doc: "Timestamp for metrics"],
        project_id: [type: :string, doc: "Project identifier"]
      ]

    @impl true
    def run(params, context) do
      # Get current state metrics
      current_metrics = context.agent.state.metrics
      
      # Update metrics with new data
      updated_metrics = update_metrics(current_metrics, params.metrics)
      
      # Calculate trends
      trends = calculate_trends(updated_metrics)
      
      {:ok, %{
        metrics: updated_metrics,
        trends: trends,
        tracked_at: DateTime.utc_now()
      }}
    end

    defp update_metrics(current, new_data) do
      %{
        total_analyses: current.total_analyses + 1,
        quality_score: calculate_avg_score(current.quality_score, new_data[:quality_score], current.total_analyses),
        improvements_applied: current.improvements_applied + Map.get(new_data, :improvements_count, 0),
        avg_improvement_time: current.avg_improvement_time,
        quality_trends: update_trends(current.quality_trends, new_data)
      }
    end

    defp calculate_avg_score(current_avg, new_score, count) when is_number(new_score) do
      (current_avg * count + new_score) / (count + 1)
    end
    defp calculate_avg_score(current_avg, _new_score, _count), do: current_avg

    defp update_trends(trends, new_data) do
      timestamp = DateTime.utc_now() |> DateTime.to_date() |> Date.to_string()
      
      Map.update(trends, timestamp, [new_data], fn existing ->
        [new_data | existing]
      end)
    end

    defp calculate_trends(metrics) do
      recent_scores = metrics.quality_trends
        |> Enum.sort_by(fn {date, _} -> date end, :desc)
        |> Enum.take(7)
        |> Enum.flat_map(fn {_, scores} -> scores end)
        |> Enum.map(fn data -> Map.get(data, :quality_score, 0) end)
      
      if length(recent_scores) >= 2 do
        trend = if List.first(recent_scores) > List.last(recent_scores) do
          :improving
        else
          :declining
        end
        
        %{direction: trend, change: List.first(recent_scores) - List.last(recent_scores)}
      else
        %{direction: :stable, change: 0}
      end
    end
  end

  defmodule GenerateQualityReportAction do
    @moduledoc """
    Generates comprehensive quality reports.
    """
    use Jido.Action,
      name: "generate_quality_report",
      description: "Generate quality analysis report",
      schema: [
        analysis_results: [type: :map, required: true, doc: "Analysis results to report"],
        report_format: [type: :string, default: "detailed", doc: "Format: summary, detailed, executive"],
        include_recommendations: [type: :boolean, default: true, doc: "Include improvement recommendations"],
        include_trends: [type: :boolean, default: true, doc: "Include historical trends"]
      ]

    @impl true
    def run(params, context) do
      report = generate_report(
        params.analysis_results,
        params.report_format,
        context.agent.state
      )
      
      {:ok, %{
        report: report,
        generated_at: DateTime.utc_now()
      }}
    end

    defp generate_report(results, "summary", state) do
      %{
        type: "summary",
        quality_score: results[:quality_score] || state.metrics.quality_score,
        key_findings: extract_key_findings(results),
        total_improvements: length(results[:improvements] || []),
        trend: state.metrics.quality_trends
      }
    end

    defp generate_report(results, "detailed", state) do
      %{
        type: "detailed",
        quality_score: results[:quality_score] || state.metrics.quality_score,
        metrics: results[:metrics],
        improvements: results[:improvements],
        violations: results[:violations],
        historical_data: state.improvement_history |> Enum.take(10),
        recommendations: generate_recommendations(results)
      }
    end

    defp generate_report(results, "executive", state) do
      %{
        type: "executive",
        overall_health: categorize_health(results[:quality_score] || state.metrics.quality_score),
        critical_issues: filter_critical_issues(results),
        strategic_recommendations: generate_strategic_recommendations(results),
        roi_estimate: estimate_improvement_roi(results)
      }
    end

    defp extract_key_findings(results) do
      findings = []
      
      findings = if results[:metrics][:complexity][:cyclomatic] > 10 do
        ["High code complexity detected" | findings]
      else
        findings
      end
      
      findings = if results[:metrics][:maintainability][:comment_ratio] < 0.1 do
        ["Low documentation coverage" | findings]
      else
        findings
      end
      
      findings
    end

    defp generate_recommendations(results) do
      results[:improvements]
      |> Enum.map(fn imp ->
        %{
          type: imp.type,
          priority: imp.priority,
          description: imp.description,
          estimated_effort: estimate_effort(imp.type)
        }
      end)
    end

    defp generate_strategic_recommendations(_results) do
      [
        "Implement automated quality gates in CI/CD",
        "Establish team coding standards",
        "Schedule regular refactoring sessions"
      ]
    end

    defp categorize_health(score) when score >= 80, do: "Excellent"
    defp categorize_health(score) when score >= 60, do: "Good"
    defp categorize_health(score) when score >= 40, do: "Fair"
    defp categorize_health(_score), do: "Needs Improvement"

    defp filter_critical_issues(results) do
      (results[:improvements] || [])
      |> Enum.filter(fn imp -> imp.priority == "high" end)
    end

    defp estimate_improvement_roi(_results) do
      %{
        time_saved: "2-4 hours/week",
        bug_reduction: "15-25%",
        maintenance_improvement: "30%"
      }
    end

    defp estimate_effort("reduce_complexity"), do: "2-4 hours"
    defp estimate_effort("add_documentation"), do: "1-2 hours"
    defp estimate_effort(_), do: "1 hour"
  end

  # Lifecycle hooks for Jido compliance
  
  @impl true
  def on_before_init(config) do
    # Initialize default quality standards if not provided
    standards = Map.get(config, :quality_standards) || default_quality_standards()
    best_practices = Map.get(config, :best_practices) || default_best_practices()
    refactoring_patterns = Map.get(config, :refactoring_patterns) || default_refactoring_patterns()
    
    config
    |> Map.put(:quality_standards, standards)
    |> Map.put(:best_practices, best_practices)
    |> Map.put(:refactoring_patterns, refactoring_patterns)
  end
  
  @impl true
  def on_after_start(agent) do
    Logger.info("Quality Improvement Agent started successfully",
      name: agent.name,
      standards: map_size(agent.state.quality_standards),
      patterns: map_size(agent.state.refactoring_patterns)
    )
    agent
  end
  
  @impl true
  def on_after_run(agent, action, result) do
    # Update metrics and state based on action results
    case action do
      AnalyzeQualityAction ->
        update_analysis_metrics(agent, result)
      ApplyImprovementAction ->
        update_improvement_metrics(agent, result)
      TrackMetricsAction ->
        update_tracking_metrics(agent, result)
      _ ->
        {:ok, agent}
    end
  end
  
  # Default configuration helpers
  
  defp default_quality_standards do
    %{
      complexity_threshold: 10,
      line_length_limit: 120,
      function_length_limit: 20,
      documentation_coverage: 0.8,
      test_coverage: 0.85
    }
  end
  
  defp default_best_practices do
    %{
      use_descriptive_names: true,
      avoid_deep_nesting: true,
      single_responsibility: true,
      dry_principle: true,
      error_handling: true
    }
  end
  
  defp default_refactoring_patterns do
    %{
      extract_function: "Break large functions into smaller ones",
      extract_variable: "Replace complex expressions with descriptive variables",
      rename_variable: "Use meaningful names for variables",
      eliminate_duplication: "Remove duplicate code blocks",
      simplify_conditionals: "Simplify complex conditional logic"
    }
  end
  
  # Metrics update helpers
  
  defp update_analysis_metrics(agent, result) do
    case result do
      {:ok, analysis_result} ->
        new_metrics = agent.state.metrics
        |> Map.update(:total_analyses, 1, &(&1 + 1))
        |> Map.put(:quality_score, Map.get(analysis_result, :quality_score, 0.0))
        
        new_state = %{agent.state | metrics: new_metrics}
        {:ok, %{agent | state: new_state}}
      _ ->
        {:ok, agent}
    end
  end
  
  defp update_improvement_metrics(agent, result) do
    case result do
      {:ok, improvement_result} ->
        improvements_count = Map.get(improvement_result, :improvements_applied, 0)
        
        new_metrics = agent.state.metrics
        |> Map.update(:improvements_applied, improvements_count, &(&1 + improvements_count))
        
        new_state = %{agent.state | metrics: new_metrics}
        {:ok, %{agent | state: new_state}}
      _ ->
        {:ok, agent}
    end
  end
  
  defp update_tracking_metrics(agent, _result) do
    # Update last tracking time
    new_metrics = Map.put(agent.state.metrics, :last_tracked, DateTime.utc_now())
    new_state = %{agent.state | metrics: new_metrics}
    {:ok, %{agent | state: new_state}}
  end
  
  # Health check implementation
  @impl true
  def health_check(agent) do
    issues = []
    
    # Check agent status
    issues = if agent.state.analysis_status == :idle do
      issues
    else
      ["Agent not in idle state" | issues]
    end
    
    # Check quality standards
    issues = if map_size(agent.state.quality_standards) > 0 do
      issues
    else
      ["Missing quality standards" | issues]
    end
    
    # Check best practices
    issues = if map_size(agent.state.best_practices) > 0 do
      issues
    else
      ["Missing best practices" | issues]
    end
    
    if length(issues) == 0 do
      {:healthy, %{
        status: "All systems operational",
        standards_count: map_size(agent.state.quality_standards),
        patterns_count: map_size(agent.state.refactoring_patterns),
        total_analyses: agent.state.metrics.total_analyses,
        quality_score: agent.state.metrics.quality_score,
        last_check: DateTime.utc_now()
      }}
    else
      {:unhealthy, %{issues: issues, last_check: DateTime.utc_now()}}
    end
  end

  # Helper module for UUID generation (if not available)
  defmodule UUID do
    def uuid4 do
      :crypto.strong_rand_bytes(16)
      |> Base.encode16(case: :lower)
    end
  end
end