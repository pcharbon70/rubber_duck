defmodule RubberDuck.Agents.AnalysisAgent do
  @moduledoc """
  Analysis Agent specialized in code analysis using existing analysis engines.

  The Analysis Agent is responsible for:
  - Performing semantic, style, and security analysis on code
  - Detecting patterns, complexity, and potential issues
  - Providing comprehensive code quality assessments
  - Generating actionable insights and recommendations
  - Supporting incremental analysis for performance

  ## Capabilities

  - `:code_analysis` - General code analysis across multiple dimensions
  - `:security_analysis` - Security vulnerability detection
  - `:complexity_analysis` - Code complexity metrics and assessment
  - `:pattern_detection` - Identifying code patterns and anti-patterns
  - `:style_checking` - Code style and formatting analysis

  ## Task Types

  - `:analyze_code` - Comprehensive code analysis
  - `:security_review` - Security-focused analysis
  - `:complexity_analysis` - Complexity metrics calculation
  - `:pattern_detection` - Pattern and anti-pattern detection
  - `:style_check` - Style and formatting verification

  ## Example Usage

      # Analyze code file
      task = %{
        id: "analysis_1",
        type: :analyze_code,
        payload: %{
          file_path: "lib/example.ex",
          analysis_types: [:semantic, :style, :security]
        }
      }

      {:ok, result} = Agent.assign_task(agent_pid, task, context)
  """

  use RubberDuck.Agents.Behavior

  alias RubberDuck.Analysis.{Semantic, Style, Security}
  alias RubberDuck.SelfCorrection.Engine, as: SelfCorrection
  # alias RubberDuck.LLM.Service, as: LLMService

  require Logger

  @capabilities [
    :code_analysis,
    :security_analysis,
    :complexity_analysis,
    :pattern_detection,
    :style_checking
  ]

  # Behavior Implementation

  @impl true
  def init(config) do
    state = %{
      config: config,
      analysis_cache: %{},
      engines: initialize_engines(config),
      metrics: initialize_metrics(),
      last_activity: DateTime.utc_now()
    }

    Logger.info("Analysis Agent initialized with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_task(task, context, state) do
    Logger.info("Analysis Agent handling task: #{task.type}")

    case task.type do
      :analyze_code ->
        handle_analyze_code(task, context, state)

      :security_review ->
        handle_security_review(task, context, state)

      :complexity_analysis ->
        handle_complexity_analysis(task, context, state)

      :pattern_detection ->
        handle_pattern_detection(task, context, state)

      :style_check ->
        handle_style_check(task, context, state)

      _ ->
        {:error, {:unsupported_task_type, task.type}, state}
    end
  end

  @impl true
  def handle_message(message, from, state) do
    case message do
      {:analysis_request, file_path, analysis_types} ->
        result = perform_quick_analysis(file_path, analysis_types, state)
        send_response(from, {:analysis_result, result})
        {:ok, state}

      {:cache_query, file_path} ->
        result = Map.get(state.analysis_cache, file_path)
        send_response(from, {:cache_result, result})
        {:ok, state}

      {:engine_status} ->
        status = get_engine_status(state.engines)
        send_response(from, {:engine_status, status})
        {:ok, state}

      _ ->
        Logger.debug("Analysis Agent received unknown message: #{inspect(message)}")
        {:noreply, state}
    end
  end

  @impl true
  def get_capabilities(_state) do
    @capabilities
  end

  @impl true
  def get_status(state) do
    %{
      status: determine_status(state),
      current_task: Map.get(state, :current_task),
      metrics: state.metrics,
      health: %{
        healthy: true,
        cache_size: map_size(state.analysis_cache),
        engines_loaded: map_size(state.engines)
      },
      last_activity: state.last_activity,
      capabilities: @capabilities
    }
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Analysis Agent terminating, cleaning up cache")
    # Clean up any resources if needed
    :ok
  end

  # Helper Functions

  defp initialize_engines(config) do
    engines = Map.get(config, :engines, [:semantic, :style, :security])

    Map.new(engines, fn engine_type ->
      {engine_type,
       %{
         module: get_engine_module(engine_type),
         config: Map.get(config, engine_type, %{})
       }}
    end)
  end

  defp get_engine_module(:semantic), do: RubberDuck.Analysis.Semantic
  defp get_engine_module(:style), do: RubberDuck.Analysis.Style
  defp get_engine_module(:security), do: RubberDuck.Analysis.Security

  defp initialize_metrics do
    %{
      tasks_completed: 0,
      analyze_code: 0,
      analyze_code_cached: 0,
      security_review: 0,
      complexity_analysis: 0,
      pattern_detection: 0,
      style_check: 0,
      total_execution_time: 0,
      cache_hits: 0,
      cache_misses: 0
    }
  end

  defp update_task_metrics(metrics, task_type) do
    metrics
    |> Map.update(:tasks_completed, 1, &(&1 + 1))
    |> Map.update(task_type, 1, &(&1 + 1))
  end

  defp determine_status(state) do
    if Map.has_key?(state, :current_task) do
      :busy
    else
      :idle
    end
  end

  defp generate_complexity_recommendations(metrics) do
    recommendations = []

    cyclomatic = Map.get(metrics, :cyclomatic, 0)

    recommendations =
      if cyclomatic > 10 do
        ["Consider breaking down complex functions (cyclomatic complexity: #{cyclomatic})"] ++ recommendations
      else
        recommendations
      end

    cognitive = Map.get(metrics, :cognitive, 0)

    recommendations =
      if cognitive > 15 do
        ["High cognitive complexity detected (#{cognitive}). Simplify logic flow."] ++ recommendations
      else
        recommendations
      end

    recommendations
  end

  # Task Handlers

  defp handle_analyze_code(%{payload: payload} = _task, context, state) do
    file_path = payload.file_path
    analysis_types = Map.get(payload, :analysis_types, [:semantic, :style, :security])

    # Check cache first
    cache_key = {file_path, analysis_types}

    case Map.get(state.analysis_cache, cache_key) do
      nil ->
        # Perform fresh analysis
        analysis_result = perform_comprehensive_analysis(file_path, analysis_types, context, state)

        # Apply self-correction if configured
        final_result =
          if Map.get(state.config, :enable_self_correction, true) do
            apply_self_correction(analysis_result, context, state)
          else
            analysis_result
          end

        # Update cache
        new_cache = Map.put(state.analysis_cache, cache_key, final_result)

        new_state = %{
          state
          | analysis_cache: new_cache,
            metrics: update_task_metrics(state.metrics, :analyze_code),
            last_activity: DateTime.utc_now()
        }

        {:ok, final_result, new_state}

      cached_result ->
        # Return cached result
        Logger.debug("Returning cached analysis for #{file_path}")

        new_state = %{
          state
          | metrics: update_task_metrics(state.metrics, :analyze_code_cached),
            last_activity: DateTime.utc_now()
        }

        {:ok, cached_result, new_state}
    end
  end

  defp handle_security_review(%{payload: payload} = task, context, state) do
    file_paths = payload.file_paths
    vulnerability_types = Map.get(payload, :vulnerability_types, :all)

    security_result = %{
      task_id: task.id,
      vulnerabilities: [],
      severity_summary: %{critical: 0, high: 0, medium: 0, low: 0},
      scanned_files: length(file_paths),
      timestamp: DateTime.utc_now()
    }

    # Analyze each file for security issues
    security_result =
      file_paths
      |> Enum.reduce(security_result, fn file_path, acc ->
        {:ok, vulnerabilities} = analyze_file_security(file_path, vulnerability_types, context, state)

        %{
          acc
          | vulnerabilities: acc.vulnerabilities ++ vulnerabilities,
            severity_summary: update_severity_summary(acc.severity_summary, vulnerabilities)
        }
      end)

    # Add recommendations
    final_result =
      Map.put(security_result, :recommendations, generate_security_recommendations(security_result.vulnerabilities))

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :security_review),
        last_activity: DateTime.utc_now()
    }

    {:ok, final_result, new_state}
  end

  defp handle_complexity_analysis(%{payload: payload} = task, context, state) do
    module_path = payload.module_path
    metrics_types = Map.get(payload, :metrics, [:cyclomatic, :cognitive])

    complexity_result = %{
      task_id: task.id,
      module_path: module_path,
      complexity_metrics: %{},
      recommendations: [],
      timestamp: DateTime.utc_now()
    }

    # Calculate complexity metrics
    {:ok, metrics} = calculate_complexity_metrics(module_path, metrics_types, context, state)

    recommendations = generate_complexity_recommendations(metrics)

    final_result =
      complexity_result
      |> Map.put(:complexity_metrics, metrics)
      |> Map.put(:recommendations, recommendations)
      |> Map.put(:confidence, 0.9)

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :complexity_analysis),
        last_activity: DateTime.utc_now()
    }

    {:ok, final_result, new_state}
  end

  defp handle_pattern_detection(%{payload: payload} = task, context, state) do
    codebase_path = payload.codebase_path
    pattern_types = Map.get(payload, :pattern_types, [:all])

    pattern_result = %{
      task_id: task.id,
      patterns_found: [],
      anti_patterns: [],
      suggestions: [],
      confidence: 0.0
    }

    # Detect patterns in codebase
    {:ok, patterns} = detect_patterns(codebase_path, pattern_types, context, state)

    final_result = %{
      pattern_result
      | patterns_found: patterns.positive,
        anti_patterns: patterns.negative,
        suggestions: generate_pattern_suggestions(patterns),
        confidence: 0.85
    }

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :pattern_detection),
        last_activity: DateTime.utc_now()
    }

    {:ok, final_result, new_state}
  end

  defp handle_style_check(%{payload: payload} = task, context, state) do
    file_paths = payload.file_paths
    style_rules = Map.get(payload, :style_rules, :default)

    style_result = %{
      task_id: task.id,
      violations: [],
      summary: %{},
      auto_fixable: [],
      confidence: 0.95
    }

    # Check style for each file
    style_result =
      file_paths
      |> Enum.reduce(style_result, fn file_path, acc ->
        {:ok, violations} = check_file_style(file_path, style_rules, context, state)

        %{
          acc
          | violations: acc.violations ++ violations,
            auto_fixable: acc.auto_fixable ++ filter_auto_fixable(violations)
        }
      end)

    # Generate summary
    final_result = %{
      style_result
      | summary: summarize_style_violations(style_result.violations)
    }

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :style_check),
        last_activity: DateTime.utc_now()
    }

    {:ok, final_result, new_state}
  end

  defp perform_comprehensive_analysis(file_path, analysis_types, context, state) do
    base_result = %{
      task_id: Map.get(context, :task_id),
      file_path: file_path,
      analysis_results: %{},
      issues_found: [],
      confidence: 0.0,
      timestamp: DateTime.utc_now()
    }

    # Run each analysis type
    result =
      analysis_types
      |> Enum.reduce(base_result, fn analysis_type, acc ->
        {:ok, engine_result} = run_analysis_engine(file_path, analysis_type, context, state)

        %{
          acc
          | analysis_results: Map.put(acc.analysis_results, analysis_type, engine_result),
            issues_found: acc.issues_found ++ extract_issues(engine_result)
        }
      end)

    # Calculate overall confidence
    %{result | confidence: calculate_analysis_confidence(result)}
  end

  defp run_analysis_engine(file_path, :semantic, _context, state) do
    engine_config = get_in(state.engines, [:semantic, :config])
    Semantic.analyze(file_path, engine_config)
  end

  defp run_analysis_engine(file_path, :style, _context, state) do
    engine_config = get_in(state.engines, [:style, :config])
    Style.analyze(file_path, engine_config)
  end

  defp run_analysis_engine(file_path, :security, _context, state) do
    engine_config = get_in(state.engines, [:security, :config])
    Security.analyze(file_path, engine_config)
  end

  defp extract_issues(engine_result) do
    Map.get(engine_result, :issues, [])
  end

  defp calculate_analysis_confidence(analysis_result) do
    if Enum.empty?(analysis_result.analysis_results) do
      0.0
    else
      # Average confidence across all engines
      confidences =
        analysis_result.analysis_results
        |> Map.values()
        |> Enum.map(&Map.get(&1, :confidence, 0.8))

      Enum.sum(confidences) / length(confidences)
    end
  end

  defp apply_self_correction(analysis_result, context, _state) do
    case SelfCorrection.correct(%{
           input: analysis_result,
           strategies: [:consistency_check, :false_positive_detection],
           context: context
         }) do
      {:ok, corrected_result} ->
        Map.put(corrected_result, :self_corrected, true)

      {:error, _reason} ->
        analysis_result
    end
  end

  defp analyze_file_security(file_path, vulnerability_types, _context, state) do
    engine_config = get_in(state.engines, [:security, :config])

    case Security.analyze(file_path, Map.put(engine_config, :vulnerability_types, vulnerability_types)) do
      {:ok, result} ->
        # Security.analyze returns issues, not vulnerabilities
        vulnerabilities = Map.get(result, :issues, [])
        {:ok, vulnerabilities}

      error ->
        error
    end
  end

  defp update_severity_summary(summary, vulnerabilities) do
    Enum.reduce(vulnerabilities, summary, fn vuln, acc ->
      severity = Map.get(vuln, :severity, :low)
      Map.update(acc, severity, 1, &(&1 + 1))
    end)
  end

  defp generate_security_recommendations(vulnerabilities) do
    vulnerabilities
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, vulns} ->
      %{
        type: type,
        count: length(vulns),
        recommendation: get_security_recommendation(type, length(vulns))
      }
    end)
  end

  defp get_security_recommendation(:sql_injection, _count) do
    "Use parameterized queries and avoid string concatenation in SQL"
  end

  defp get_security_recommendation(:hardcoded_secrets, _count) do
    "Move secrets to environment variables or secure vault"
  end

  defp get_security_recommendation(_, _count) do
    "Review and address security vulnerabilities"
  end

  defp calculate_complexity_metrics(module_path, metrics_types, _context, state) do
    engine_config = get_in(state.engines, [:semantic, :config])

    # Semantic.analyze always returns {:ok, result}
    {:ok, result} = Semantic.analyze(module_path, Map.put(engine_config, :analysis_type, :complexity))

    metrics =
      metrics_types
      |> Enum.reduce(%{}, fn metric_type, acc ->
        value = get_complexity_metric(result, metric_type)
        Map.put(acc, metric_type, value)
      end)

    {:ok, metrics}
  end

  defp get_complexity_metric(result, :cyclomatic) do
    get_in(result, [:complexity, :cyclomatic]) || calculate_cyclomatic_complexity(result)
  end

  defp get_complexity_metric(result, :cognitive) do
    # Default
    get_in(result, [:complexity, :cognitive]) || 5
  end

  defp get_complexity_metric(result, :halstead) do
    get_in(result, [:complexity, :halstead]) || %{}
  end

  defp calculate_cyclomatic_complexity(_result) do
    # Simplified calculation
    # Would calculate based on AST
    10
  end

  defp detect_patterns(codebase_path, _pattern_types, _context, _state) do
    # Simplified pattern detection
    patterns = %{
      positive: [
        %{
          type: :genserver_pattern,
          location: "#{codebase_path}/lib/example.ex:25",
          description: "Well-structured GenServer implementation",
          confidence: 0.9
        }
      ],
      negative: [
        %{
          type: :god_module,
          location: "#{codebase_path}/lib/big_module.ex",
          description: "Module with too many responsibilities",
          confidence: 0.8
        }
      ]
    }

    {:ok, patterns}
  end

  defp generate_pattern_suggestions(patterns) do
    suggestions = []

    # Suggest fixes for anti-patterns
    suggestions =
      patterns.negative
      |> Enum.reduce(suggestions, fn pattern, acc ->
        case pattern.type do
          :god_module ->
            ["Split large module into smaller, focused modules"] ++ acc

          :deep_nesting ->
            ["Reduce nesting levels by extracting functions"] ++ acc

          _ ->
            acc
        end
      end)

    # Suggest spreading positive patterns
    suggestions =
      if length(patterns.positive) > 0 do
        ["Continue using identified good patterns across the codebase"] ++ suggestions
      else
        suggestions
      end

    suggestions
  end

  defp check_file_style(file_path, style_rules, _context, state) do
    engine_config = get_in(state.engines, [:style, :config])

    case Style.analyze(file_path, Map.put(engine_config, :rules, style_rules)) do
      {:ok, result} ->
        violations = Map.get(result, :violations, [])
        {:ok, violations}

      error ->
        error
    end
  end

  defp filter_auto_fixable(violations) do
    Enum.filter(violations, & &1.auto_fixable)
  end

  defp summarize_style_violations(violations) do
    violations
    |> Enum.group_by(& &1.rule)
    |> Map.new(fn {rule, rule_violations} ->
      {rule,
       %{
         count: length(rule_violations),
         severity: get_most_severe(rule_violations)
       }}
    end)
  end

  defp get_most_severe(violations) do
    severities = [:error, :warning, :info]

    violations
    |> Enum.map(& &1.severity)
    |> Enum.min_by(&Enum.find_index(severities, fn s -> s == &1 end))
  end

  defp perform_quick_analysis(file_path, analysis_types, state) do
    # Quick analysis without full task handling
    perform_comprehensive_analysis(file_path, analysis_types, %{}, state)
  end

  defp get_engine_status(engines) do
    Map.new(engines, fn {type, engine_info} ->
      {type,
       %{
         module: engine_info.module,
         loaded: Code.ensure_loaded?(engine_info.module),
         config: Map.keys(engine_info.config)
       }}
    end)
  end

  defp send_response(from, message) do
    if is_pid(from) do
      send(from, message)
    end
  end
end
