defmodule RubberDuck.Agents.ReviewAgent do
  @moduledoc """
  Review Agent specialized in code review, quality assessment, and improvement suggestions.

  The Review Agent is responsible for:
  - Reviewing code changes and providing feedback
  - Assessing code quality across multiple dimensions
  - Suggesting improvements for readability and maintainability
  - Verifying correctness and identifying potential issues
  - Reviewing documentation completeness and accuracy
  - Detecting breaking changes and compatibility issues

  ## Capabilities

  - `:change_review` - Review code changes and modifications
  - `:quality_assessment` - Assess overall code quality
  - `:improvement_suggestions` - Suggest code improvements
  - `:correctness_verification` - Verify code correctness
  - `:documentation_review` - Review documentation quality

  ## Task Types

  - `:review_changes` - Review code changes between versions
  - `:quality_review` - Comprehensive quality assessment
  - `:suggest_improvements` - Generate improvement suggestions
  - `:verify_correctness` - Verify code correctness and behavior
  - `:review_documentation` - Review docs and comments

  ## Example Usage

      # Review code changes
      task = %{
        id: "review_1",
        type: :review_changes,
        payload: %{
          original_code: old_code,
          modified_code: new_code,
          change_type: :enhancement
        }
      }

      {:ok, result} = Agent.assign_task(agent_pid, task, context)
  """

  use RubberDuck.Agents.Behavior

  alias RubberDuck.Analysis.{Semantic, Style, Security}
  alias RubberDuck.SelfCorrection.Engine, as: SelfCorrection
  alias RubberDuck.LLM.Service, as: LLMService
  # alias RubberDuck.Engines.Generation, as: GenerationEngine

  require Logger

  @capabilities [
    :change_review,
    :quality_assessment,
    :improvement_suggestions,
    :correctness_verification,
    :documentation_review
  ]

  # Helper functions first

  defp initialize_metrics do
    %{
      tasks_completed: 0,
      review_changes: 0,
      quality_review: 0,
      suggest_improvements: 0,
      verify_correctness: 0,
      review_documentation: 0,
      total_reviews: 0,
      avg_review_time: 0.0,
      breaking_changes_detected: 0,
      improvements_suggested: 0
    }
  end

  defp initialize_review_standards(config) do
    Map.get(config, :review_standards, %{
      readability_weight: 0.3,
      maintainability_weight: 0.3,
      performance_weight: 0.2,
      security_weight: 0.2,
      breaking_change_threshold: 0.7,
      approval_threshold: 0.8
    })
  end

  defp update_task_metrics(metrics, task_type) do
    metrics
    |> Map.update(:tasks_completed, 1, &(&1 + 1))
    |> Map.update(task_type, 1, &(&1 + 1))
    |> Map.update(:total_reviews, 1, &(&1 + 1))
  end

  defp determine_status(state) do
    if Map.has_key?(state, :current_task) do
      :busy
    else
      :idle
    end
  end

  defp send_response(from, message) do
    if is_pid(from) do
      send(from, message)
    end
  end

  # Behavior Implementation

  @impl true
  def init(config) do
    state = %{
      config: config,
      review_cache: %{},
      review_history: [],
      review_standards: initialize_review_standards(config),
      metrics: initialize_metrics(),
      llm_config: configure_llm(config),
      analysis_engines: initialize_analysis_engines(config),
      last_activity: DateTime.utc_now()
    }

    Logger.info("Review Agent initialized with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_task(task, context, state) do
    Logger.info("Review Agent handling task: #{task.type}")

    case task.type do
      :review_changes ->
        handle_review_changes(task, context, state)

      :quality_review ->
        handle_quality_review(task, context, state)

      :suggest_improvements ->
        handle_suggest_improvements(task, context, state)

      :verify_correctness ->
        handle_verify_correctness(task, context, state)

      :review_documentation ->
        handle_review_documentation(task, context, state)

      _ ->
        {:error, {:unsupported_task_type, task.type}, state}
    end
  end

  @impl true
  def handle_message(message, from, state) do
    case message do
      {:quick_review, code, review_type} ->
        result = perform_quick_review(code, review_type, state)
        send_response(from, {:review_result, result})
        {:ok, state}

      {:review_standards_update, new_standards} ->
        new_review_standards = Map.merge(state.review_standards, new_standards)
        new_state = %{state | review_standards: new_review_standards}
        send_response(from, :standards_updated)
        {:ok, new_state}

      {:review_history} ->
        history = Enum.take(state.review_history, 10)
        send_response(from, {:review_history, history})
        {:ok, state}

      _ ->
        Logger.debug("Review Agent received unknown message: #{inspect(message)}")
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
        cache_size: map_size(state.review_cache),
        history_size: length(state.review_history),
        engines_loaded: map_size(state.analysis_engines)
      },
      review_standards: state.review_standards,
      last_activity: state.last_activity,
      capabilities: @capabilities
    }
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Review Agent terminating")
    :ok
  end

  # Task Handlers

  defp handle_review_changes(%{payload: payload} = task, context, state) do
    original_code = payload.original_code
    modified_code = payload.modified_code
    change_type = Map.get(payload, :change_type, :unknown)
    file_path = Map.get(payload, :file_path)

    # Analyze changes
    change_analysis = analyze_code_changes(original_code, modified_code, file_path, state)

    # Check for breaking changes
    breaking_changes = detect_breaking_changes(original_code, modified_code, state)

    # Generate feedback
    feedback = generate_change_feedback(change_analysis, breaking_changes, change_type, state)

    # Calculate approval score
    approval_score = calculate_approval_score(change_analysis, breaking_changes, state)

    # Apply self-correction if enabled
    final_feedback =
      if Map.get(state.config, :enable_self_correction, true) do
        apply_self_correction_to_feedback(feedback, context, state)
      else
        feedback
      end

    result = %{
      task_id: task.id,
      review_status: determine_review_status(approval_score, state),
      feedback: final_feedback,
      suggestions: change_analysis.suggestions,
      approval_score: approval_score,
      breaking_changes_detected: breaking_changes.detected,
      breaking_changes: breaking_changes.changes,
      change_metrics: %{
        lines_added: count_lines(modified_code) - count_lines(original_code),
        complexity_change: change_analysis.complexity_delta
      },
      timestamp: DateTime.utc_now()
    }

    # Update cache and history
    cache_key = {original_code, modified_code, change_type}
    new_cache = Map.put(state.review_cache, cache_key, result)
    new_history = [{task.id, :review_changes, result} | Enum.take(state.review_history, 99)]

    new_state = %{
      state
      | review_cache: new_cache,
        review_history: new_history,
        metrics: update_task_metrics(state.metrics, :review_changes),
        last_activity: DateTime.utc_now()
    }

    {:ok, result, new_state}
  end

  defp handle_quality_review(%{payload: payload} = task, context, state) do
    code = payload.code
    quality_aspects = Map.get(payload, :quality_aspects, [:readability, :maintainability, :performance])

    # Run comprehensive quality analysis
    quality_analysis = perform_quality_analysis(code, quality_aspects, context, state)

    # Calculate quality scores
    quality_scores = calculate_quality_scores(quality_analysis, state)

    # Generate improvements
    improvements = generate_quality_improvements(quality_analysis, quality_scores, state)

    result = %{
      task_id: task.id,
      quality_scores: quality_scores,
      improvements: improvements,
      analysis_details: quality_analysis,
      overall_score: calculate_overall_quality_score(quality_scores, state),
      recommendations: prioritize_recommendations(improvements),
      confidence: 0.85,
      timestamp: DateTime.utc_now()
    }

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :quality_review),
        last_activity: DateTime.utc_now()
    }

    {:ok, result, new_state}
  end

  defp handle_suggest_improvements(%{payload: payload} = task, context, state) do
    code = payload.code
    improvement_focus = Map.get(payload, :improvement_focus, [:all])

    # Analyze code for improvement opportunities
    improvement_analysis = analyze_for_improvements(code, improvement_focus, context, state)

    # Generate concrete suggestions
    suggestions = generate_improvement_suggestions(improvement_analysis, state)

    # Rank suggestions by impact
    ranked_suggestions = rank_suggestions_by_impact(suggestions, state)

    result = %{
      task_id: task.id,
      suggestions: ranked_suggestions,
      improvement_areas: Map.keys(improvement_analysis),
      estimated_impact: calculate_improvement_impact(ranked_suggestions),
      confidence: 0.8,
      timestamp: DateTime.utc_now()
    }

    new_state = %{
      state
      | metrics:
          state.metrics
          |> update_task_metrics(:suggest_improvements)
          |> Map.update(:improvements_suggested, length(ranked_suggestions), &(&1 + length(ranked_suggestions))),
        last_activity: DateTime.utc_now()
    }

    {:ok, result, new_state}
  end

  defp handle_verify_correctness(%{payload: payload} = task, context, state) do
    code = payload.code
    expected_behavior = Map.get(payload, :expected_behavior, "")
    test_cases = Map.get(payload, :test_cases, [])

    # Analyze code for correctness
    correctness_analysis = analyze_correctness(code, expected_behavior, context, state)

    # Run test cases if provided
    test_results =
      if Enum.any?(test_cases) do
        verify_with_test_cases(code, test_cases, state)
      else
        %{passed: true, results: [], message: "No test cases provided"}
      end

    # Check edge cases
    edge_cases = identify_edge_cases(code, expected_behavior, state)

    result = %{
      task_id: task.id,
      correctness_verified: correctness_analysis.verified and test_results.passed,
      correctness_issues: correctness_analysis.issues,
      test_results: test_results,
      edge_cases_covered: evaluate_edge_case_coverage(code, edge_cases),
      potential_bugs: correctness_analysis.potential_bugs,
      confidence: correctness_analysis.confidence,
      timestamp: DateTime.utc_now()
    }

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :verify_correctness),
        last_activity: DateTime.utc_now()
    }

    {:ok, result, new_state}
  end

  defp handle_review_documentation(%{payload: payload} = task, _context, state) do
    code = payload.code
    doc_type = Map.get(payload, :doc_type, :all)

    # Extract existing documentation
    existing_docs = extract_documentation(code)

    # Analyze documentation quality
    doc_analysis = analyze_documentation_quality(existing_docs, code, doc_type, state)

    # Generate documentation suggestions
    doc_suggestions = generate_documentation_suggestions(doc_analysis, code, state)

    result = %{
      task_id: task.id,
      documentation_coverage: doc_analysis.coverage,
      documentation_quality: doc_analysis.quality_score,
      missing_documentation: doc_analysis.missing,
      suggestions: doc_suggestions,
      examples_needed: doc_analysis.examples_needed,
      confidence: 0.9,
      timestamp: DateTime.utc_now()
    }

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :review_documentation),
        last_activity: DateTime.utc_now()
    }

    {:ok, result, new_state}
  end

  # Helper Functions

  defp configure_llm(config) do
    %{
      provider: Map.get(config, :llm_provider, :openai),
      model: Map.get(config, :model, "gpt-4"),
      temperature: Map.get(config, :temperature, 0.3),
      max_tokens: Map.get(config, :max_tokens, 1024)
    }
  end

  defp initialize_analysis_engines(config) do
    %{
      semantic: %{module: Semantic, config: Map.get(config, :semantic_config, %{})},
      style: %{module: Style, config: Map.get(config, :style_config, %{})},
      security: %{module: Security, config: Map.get(config, :security_config, %{})}
    }
  end

  defp analyze_code_changes(original_code, modified_code, file_path, state) do
    # Use semantic analysis to understand changes
    original_analysis = analyze_code_semantics(original_code, state)
    modified_analysis = analyze_code_semantics(modified_code, state)

    %{
      semantic_changes: compare_semantic_analysis(original_analysis, modified_analysis),
      style_changes: analyze_style_changes(original_code, modified_code, state),
      complexity_delta: modified_analysis.complexity - original_analysis.complexity,
      suggestions: generate_change_suggestions(original_analysis, modified_analysis, file_path)
    }
  end

  defp analyze_code_semantics(code, state) do
    {:ok, result} = Semantic.analyze(code, state.analysis_engines.semantic.config)

    %{
      functions: Map.get(result, :functions, []),
      complexity: Map.get(result.metrics, :cyclomatic_complexity, 0),
      dependencies: Map.get(result, :dependencies, [])
    }
  end

  defp compare_semantic_analysis(original, modified) do
    %{
      functions_added: modified.functions -- original.functions,
      functions_removed: original.functions -- modified.functions,
      functions_modified: detect_modified_functions(original.functions, modified.functions),
      dependencies_added: modified.dependencies -- original.dependencies,
      dependencies_removed: original.dependencies -- modified.dependencies
    }
  end

  defp detect_modified_functions(original_funcs, modified_funcs) do
    # Simplified - would do deeper comparison in production
    common_names =
      MapSet.intersection(
        MapSet.new(original_funcs, & &1.name),
        MapSet.new(modified_funcs, & &1.name)
      )

    Enum.map(common_names, &%{name: &1, change_type: :modified})
  end

  defp analyze_style_changes(original_code, modified_code, state) do
    original_style = Style.analyze(original_code, state.analysis_engines.style.config)
    modified_style = Style.analyze(modified_code, state.analysis_engines.style.config)

    case {original_style, modified_style} do
      {{:ok, orig}, {:ok, mod}} ->
        %{
          style_improved: mod.metrics.naming_consistency_score > orig.metrics.naming_consistency_score,
          formatting_changes: mod.metrics != orig.metrics
        }

      _ ->
        %{style_improved: false, formatting_changes: false}
    end
  end

  defp generate_change_suggestions(original_analysis, modified_analysis, _file_path) do
    suggestions = []

    # Check for increased complexity
    complexity_increase = modified_analysis.complexity - original_analysis.complexity

    suggestions =
      if complexity_increase > 5 do
        ["Consider breaking down the function to reduce complexity"] ++ suggestions
      else
        suggestions
      end

    # Check for removed error handling
    suggestions =
      if Enum.any?(original_analysis.functions, &String.contains?(&1.name, "rescue")) and
           not Enum.any?(modified_analysis.functions, &String.contains?(&1.name, "rescue")) do
        ["Ensure error handling is preserved or improved"] ++ suggestions
      else
        suggestions
      end

    suggestions
  end

  defp detect_breaking_changes(original_code, modified_code, _state) do
    # Parse function signatures
    original_sigs = extract_function_signatures(original_code)
    modified_sigs = extract_function_signatures(modified_code)

    breaking_changes = []

    # Check for removed functions
    removed_functions = original_sigs -- modified_sigs

    breaking_changes =
      if Enum.any?(removed_functions) do
        [%{type: :function_removed, functions: removed_functions}] ++ breaking_changes
      else
        breaking_changes
      end

    # Check for signature changes
    signature_changes = detect_signature_changes(original_sigs, modified_sigs)

    breaking_changes =
      if Enum.any?(signature_changes) do
        [%{type: :signature_changed, changes: signature_changes}] ++ breaking_changes
      else
        breaking_changes
      end

    %{
      detected: Enum.any?(breaking_changes),
      changes: breaking_changes,
      severity: calculate_breaking_change_severity(breaking_changes)
    }
  end

  defp extract_function_signatures(code) do
    # Simplified - extracts function names and arities
    ~r/def\s+(\w+)\((.*?)\)/
    |> Regex.scan(code)
    |> Enum.map(fn [_, name, args] ->
      arity = if args == "", do: 0, else: length(String.split(args, ","))
      {name, arity}
    end)
  end

  defp detect_signature_changes(original_sigs, modified_sigs) do
    original_map = Map.new(original_sigs)
    modified_map = Map.new(modified_sigs)

    original_map
    |> Enum.filter(fn {name, arity} ->
      case Map.get(modified_map, name) do
        # Function removed, handled elsewhere
        nil -> false
        # Same arity
        ^arity -> false
        # Arity changed
        _different_arity -> true
      end
    end)
    |> Enum.map(fn {name, original_arity} ->
      %{
        function: name,
        original_arity: original_arity,
        new_arity: Map.get(modified_map, name)
      }
    end)
  end

  defp calculate_breaking_change_severity(breaking_changes) do
    if Enum.any?(breaking_changes, &(&1.type == :signature_changed)) do
      :high
    else
      :medium
    end
  end

  defp generate_change_feedback(change_analysis, breaking_changes, change_type, state) do
    feedback_prompt = build_feedback_prompt(change_analysis, breaking_changes, change_type)

    case LLMService.completion(%{
           model: state.llm_config.model,
           messages: [%{role: "user", content: feedback_prompt}],
           temperature: state.llm_config.temperature
         }) do
      {:ok, %{choices: [%{message: %{content: feedback}} | _]}} ->
        %{
          summary: extract_feedback_summary(feedback),
          details: feedback,
          tone: :constructive
        }

      {:error, _} ->
        %{
          summary: "Review completed with analysis",
          details: format_analysis_as_feedback(change_analysis),
          tone: :neutral
        }
    end
  end

  defp build_feedback_prompt(change_analysis, breaking_changes, change_type) do
    """
    Review the following code changes and provide constructive feedback.

    Change Type: #{change_type}
    Breaking Changes Detected: #{breaking_changes.detected}
    Complexity Change: #{change_analysis.complexity_delta}

    Semantic Changes:
    - Functions added: #{length(change_analysis.semantic_changes.functions_added)}
    - Functions removed: #{length(change_analysis.semantic_changes.functions_removed)}
    - Functions modified: #{length(change_analysis.semantic_changes.functions_modified)}

    Provide:
    1. A brief summary of the changes
    2. Positive aspects of the changes
    3. Areas for improvement
    4. Any concerns about breaking changes
    """
  end

  defp extract_feedback_summary(feedback) do
    # Extract first paragraph or first 2 sentences
    feedback
    |> String.split("\n\n")
    |> List.first()
    |> String.slice(0, 200)
  end

  defp format_analysis_as_feedback(change_analysis) do
    """
    Changes detected:
    - Complexity delta: #{change_analysis.complexity_delta}
    - Style changes: #{inspect(change_analysis.style_changes)}

    Suggestions:
    #{Enum.join(change_analysis.suggestions, "\n- ")}
    """
  end

  defp calculate_approval_score(change_analysis, breaking_changes, state) do
    base_score = 1.0

    # Deduct for breaking changes
    score =
      if breaking_changes.detected do
        base_score - state.review_standards.breaking_change_threshold * 0.5
      else
        base_score
      end

    # Deduct for complexity increase
    score =
      if change_analysis.complexity_delta > 10 do
        score - 0.2
      else
        score
      end

    # Boost for style improvements
    score =
      if change_analysis.style_changes[:style_improved] do
        score + 0.1
      else
        score
      end

    max(0.0, min(1.0, score))
  end

  defp determine_review_status(approval_score, state) do
    cond do
      approval_score >= state.review_standards.approval_threshold -> :approved
      approval_score >= 0.6 -> :needs_revision
      true -> :rejected
    end
  end

  defp apply_self_correction_to_feedback(feedback, context, _state) do
    case SelfCorrection.correct(%{
           input: feedback,
           strategies: [:consistency_check, :tone_adjustment],
           context: context
         }) do
      {:ok, corrected} ->
        Map.merge(feedback, %{
          details: corrected.output,
          self_corrected: true
        })

      {:error, _} ->
        feedback
    end
  end

  defp perform_quality_analysis(code, quality_aspects, _context, state) do
    analysis = %{}

    analysis =
      if :readability in quality_aspects do
        Map.put(analysis, :readability, analyze_readability(code, state))
      else
        analysis
      end

    analysis =
      if :maintainability in quality_aspects do
        Map.put(analysis, :maintainability, analyze_maintainability(code, state))
      else
        analysis
      end

    analysis =
      if :performance in quality_aspects do
        Map.put(analysis, :performance, analyze_performance(code, state))
      else
        analysis
      end

    analysis =
      if :security in quality_aspects do
        Map.put(analysis, :security, analyze_security(code, state))
      else
        analysis
      end

    analysis
  end

  defp analyze_readability(code, state) do
    {:ok, result} = Style.analyze(code, state.analysis_engines.style.config)

    %{
      score: result.metrics.naming_consistency_score,
      issues: filter_readability_issues(result.issues),
      line_length_avg: calculate_avg_line_length(code)
    }
  end

  defp filter_readability_issues(issues) do
    Enum.filter(issues, &(&1.category == :readability))
  end

  defp calculate_avg_line_length(code) do
    lines = String.split(code, "\n")

    if Enum.empty?(lines) do
      0
    else
      total_length = Enum.reduce(lines, 0, &(String.length(&1) + &2))
      div(total_length, length(lines))
    end
  end

  defp analyze_maintainability(code, _state) do
    # For now, return a simple maintainability assessment
    # In production, would parse AST and use Semantic.analyze
    %{
      score: 0.7,
      complexity: estimate_complexity(code),
      coupling: 0.5
    }
  end

  defp estimate_complexity(code) do
    # Simple heuristic based on code structure
    lines = String.split(code, "\n")
    line_count = length(lines)

    # Count control flow keywords
    control_flow_count =
      Enum.count(lines, fn line ->
        String.contains?(line, ["if ", "case ", "cond ", "with ", "for ", "while "])
      end)

    # Simple complexity estimate
    base_complexity = div(line_count, 50)
    base_complexity + control_flow_count
  end

  defp analyze_performance(_code, _state) do
    # Simplified - would do deeper analysis
    %{
      score: 0.7,
      potential_bottlenecks: [],
      optimization_opportunities: []
    }
  end

  defp analyze_security(code, state) do
    {:ok, result} = Security.analyze(code, state.analysis_engines.security.config)

    %{
      score: result.metrics.security_score,
      vulnerabilities: result.issues,
      high_risk_patterns: length(Enum.filter(result.issues, &(&1.severity == :high)))
    }
  end

  defp calculate_quality_scores(quality_analysis, _state) do
    scores = %{}

    scores =
      if Map.has_key?(quality_analysis, :readability) do
        Map.put(scores, :readability, quality_analysis.readability.score)
      else
        scores
      end

    scores =
      if Map.has_key?(quality_analysis, :maintainability) do
        Map.put(scores, :maintainability, quality_analysis.maintainability.score)
      else
        scores
      end

    scores =
      if Map.has_key?(quality_analysis, :performance) do
        Map.put(scores, :performance, quality_analysis.performance.score)
      else
        scores
      end

    scores =
      if Map.has_key?(quality_analysis, :security) do
        Map.put(scores, :security, quality_analysis.security.score)
      else
        scores
      end

    scores
  end

  defp generate_quality_improvements(quality_analysis, quality_scores, _state) do
    improvements = []

    # Readability improvements
    improvements =
      if Map.get(quality_scores, :readability, 1.0) < 0.7 do
        readability_improvements =
          quality_analysis.readability.issues
          |> Enum.map(
            &%{
              type: :readability,
              description: &1.message,
              location: &1.location,
              priority: :medium
            }
          )

        improvements ++ readability_improvements
      else
        improvements
      end

    # Maintainability improvements
    improvements =
      if Map.get(quality_scores, :maintainability, 1.0) < 0.7 do
        maint_improvements = [
          %{
            type: :maintainability,
            description: "Reduce complexity (current: #{quality_analysis.maintainability.complexity})",
            priority: :high
          }
        ]

        improvements ++ maint_improvements
      else
        improvements
      end

    # Security improvements
    improvements =
      if Map.get(quality_scores, :security, 1.0) < 0.8 do
        sec_improvements =
          quality_analysis.security.vulnerabilities
          |> Enum.map(
            &%{
              type: :security,
              description: &1.description,
              location: &1.location,
              priority: :critical
            }
          )

        improvements ++ sec_improvements
      else
        improvements
      end

    improvements
  end

  defp calculate_overall_quality_score(quality_scores, state) do
    weights = state.review_standards

    weighted_sum =
      quality_scores
      |> Enum.reduce(0.0, fn {aspect, score}, acc ->
        weight = Map.get(weights, :"#{aspect}_weight", 0.25)
        acc + score * weight
      end)

    total_weight =
      [:readability, :maintainability, :performance, :security]
      |> Enum.reduce(0.0, fn aspect, acc ->
        if Map.has_key?(quality_scores, aspect) do
          acc + Map.get(weights, :"#{aspect}_weight", 0.25)
        else
          acc
        end
      end)

    if total_weight > 0 do
      weighted_sum / total_weight
    else
      0.0
    end
  end

  defp prioritize_recommendations(improvements) do
    priority_order = [:critical, :high, :medium, :low]

    improvements
    |> Enum.sort_by(&Enum.find_index(priority_order, fn p -> p == &1.priority end))
    # Top 10 recommendations
    |> Enum.take(10)
  end

  defp analyze_for_improvements(code, improvement_focus, _context, state) do
    analysis = %{}

    focus_areas =
      if improvement_focus == [:all] do
        [:naming, :structure, :documentation, :error_handling, :performance]
      else
        improvement_focus
      end

    Enum.reduce(focus_areas, analysis, fn area, acc ->
      Map.put(acc, area, analyze_improvement_area(code, area, state))
    end)
  end

  defp analyze_improvement_area(code, :naming, state) do
    {:ok, result} = Style.analyze(code, state.analysis_engines.style.config)

    %{
      score: result.metrics.naming_consistency_score,
      issues: Enum.filter(result.issues, &(&1.category == :naming))
    }
  end

  defp analyze_improvement_area(code, :structure, _state) do
    # Simplified structure analysis
    %{
      complexity: estimate_complexity(code),
      coupling: 0.5,
      suggestions: ["Consider breaking down large functions", "Reduce module dependencies"]
    }
  end

  defp analyze_improvement_area(code, :documentation, _state) do
    %{
      has_moduledoc: String.contains?(code, "@moduledoc"),
      has_fundocs: Regex.match?(~r/@doc\s+/, code),
      missing_docs: identify_undocumented_functions(code)
    }
  end

  defp analyze_improvement_area(code, :error_handling, _state) do
    %{
      uses_with: String.contains?(code, "with "),
      has_rescue: String.contains?(code, "rescue"),
      has_catch: String.contains?(code, "catch"),
      unhandled_cases: identify_unhandled_cases(code)
    }
  end

  defp analyze_improvement_area(_code, :performance, _state) do
    %{
      potential_bottlenecks: [],
      optimization_opportunities: []
    }
  end

  defp identify_undocumented_functions(code) do
    # Find functions without preceding @doc
    function_regex = ~r/^\s*def\s+(\w+)/m
    doc_regex = ~r/@doc\s+/

    functions =
      Regex.scan(function_regex, code)
      |> Enum.map(fn [_, name] -> name end)

    # Simplified - check if any @doc exists
    if Regex.match?(doc_regex, code) do
      []
    else
      functions
    end
  end

  defp identify_unhandled_cases(code) do
    # Simplified - look for case statements without catch-all
    case_blocks = Regex.scan(~r/case .+? do(.+?)end/s, code)

    case_blocks
    |> Enum.filter(fn [_, block] ->
      not String.contains?(block, "_ ->")
    end)
    |> length()
  end

  defp generate_improvement_suggestions(improvement_analysis, _state) do
    suggestions = []

    # Naming suggestions
    suggestions =
      if Map.has_key?(improvement_analysis, :naming) do
        naming_suggestions =
          improvement_analysis.naming.issues
          |> Enum.map(
            &%{
              type: :naming,
              description: &1.message,
              code_change: suggest_naming_fix(&1),
              impact: :medium
            }
          )

        suggestions ++ naming_suggestions
      else
        suggestions
      end

    # Structure suggestions
    suggestions =
      if Map.has_key?(improvement_analysis, :structure) and
           improvement_analysis.structure.complexity > 10 do
        struct_suggestion = %{
          type: :structure,
          description: "Consider breaking down complex functions",
          code_change: "Extract helper functions for better readability",
          impact: :high
        }

        [struct_suggestion | suggestions]
      else
        suggestions
      end

    # Documentation suggestions
    suggestions =
      if Map.has_key?(improvement_analysis, :documentation) and
           not improvement_analysis.documentation.has_moduledoc do
        doc_suggestion = %{
          type: :documentation,
          description: "Add module documentation",
          code_change: "@moduledoc \"\"\"\nDescribe module purpose here\n\"\"\"",
          impact: :medium
        }

        [doc_suggestion | suggestions]
      else
        suggestions
      end

    # Error handling suggestions
    suggestions =
      if Map.has_key?(improvement_analysis, :error_handling) and
           improvement_analysis.error_handling.unhandled_cases > 0 do
        error_suggestion = %{
          type: :error_handling,
          description: "Add catch-all clauses to case statements",
          code_change: "_ -> {:error, :unexpected_case}",
          impact: :high
        }

        [error_suggestion | suggestions]
      else
        suggestions
      end

    suggestions
  end

  defp suggest_naming_fix(_issue) do
    # Simplified suggestion
    "Use more descriptive names following Elixir conventions"
  end

  defp rank_suggestions_by_impact(suggestions, _state) do
    impact_order = [:critical, :high, :medium, :low]

    suggestions
    |> Enum.sort_by(&Enum.find_index(impact_order, fn i -> i == &1.impact end))
  end

  defp calculate_improvement_impact(suggestions) do
    high_impact_count = Enum.count(suggestions, &(&1.impact == :high))
    medium_impact_count = Enum.count(suggestions, &(&1.impact == :medium))

    %{
      high_impact: high_impact_count,
      medium_impact: medium_impact_count,
      total_score: high_impact_count * 3 + medium_impact_count * 1
    }
  end

  defp analyze_correctness(code, expected_behavior, _context, state) do
    # Use LLM to analyze correctness
    correctness_prompt = build_correctness_prompt(code, expected_behavior)

    case LLMService.completion(%{
           model: state.llm_config.model,
           messages: [%{role: "user", content: correctness_prompt}],
           # Lower temperature for accuracy
           temperature: 0.2
         }) do
      {:ok, %{choices: [%{message: %{content: analysis}} | _]}} ->
        parse_correctness_analysis(analysis)

      {:error, _} ->
        %{
          verified: false,
          issues: ["Unable to verify correctness"],
          potential_bugs: [],
          confidence: 0.0
        }
    end
  end

  defp build_correctness_prompt(code, expected_behavior) do
    """
    Analyze the following code for correctness:

    Expected Behavior: #{expected_behavior}

    Code:
    ```elixir
    #{code}
    ```

    Check for:
    1. Logic errors
    2. Edge case handling
    3. Potential runtime errors
    4. Behavior matching expected description

    Format response as:
    VERIFIED: true/false
    ISSUES: [list any issues]
    BUGS: [list potential bugs]
    CONFIDENCE: 0.0-1.0
    """
  end

  defp parse_correctness_analysis(analysis) do
    verified = String.contains?(analysis, "VERIFIED: true")

    issues =
      case Regex.run(~r/ISSUES:\s*\[(.*?)\]/s, analysis) do
        [_, issues_str] -> String.split(issues_str, ",") |> Enum.map(&String.trim/1)
        _ -> []
      end

    bugs =
      case Regex.run(~r/BUGS:\s*\[(.*?)\]/s, analysis) do
        [_, bugs_str] -> String.split(bugs_str, ",") |> Enum.map(&String.trim/1)
        _ -> []
      end

    confidence =
      case Regex.run(~r/CONFIDENCE:\s*([\d.]+)/, analysis) do
        [_, conf] -> String.to_float(conf)
        _ -> 0.5
      end

    %{
      verified: verified,
      issues: issues,
      potential_bugs: bugs,
      confidence: confidence
    }
  end

  defp verify_with_test_cases(_code, test_cases, _state) do
    # Simplified - would actually execute in sandboxed environment
    results =
      Enum.map(test_cases, fn test_case ->
        %{
          input: test_case.input,
          expected: test_case.expected,
          # Simplified
          passed: true,
          actual: test_case.expected
        }
      end)

    %{
      passed: Enum.all?(results, & &1.passed),
      results: results,
      message: "#{Enum.count(results, & &1.passed)}/#{length(results)} tests passed"
    }
  end

  defp identify_edge_cases(code, expected_behavior, _state) do
    # Identify potential edge cases based on code patterns
    edge_cases = []

    # Check for nil handling
    edge_cases =
      if not String.contains?(code, "nil") do
        ["nil input handling"] ++ edge_cases
      else
        edge_cases
      end

    # Check for empty collection handling
    edge_cases =
      if String.contains?(code, "Enum.") and not String.contains?(code, "[]") do
        ["empty list/map handling"] ++ edge_cases
      else
        edge_cases
      end

    # Check for zero/negative number handling
    edge_cases =
      if String.contains?(expected_behavior, "number") and not String.contains?(code, "<= 0") do
        ["zero/negative number handling"] ++ edge_cases
      else
        edge_cases
      end

    edge_cases
  end

  defp evaluate_edge_case_coverage(code, edge_cases) do
    covered =
      Enum.count(edge_cases, fn edge_case ->
        case edge_case do
          "nil input handling" -> String.contains?(code, "nil")
          "empty list/map handling" -> String.contains?(code, "[]") or String.contains?(code, "%{}")
          "zero/negative number handling" -> String.contains?(code, "<= 0") or String.contains?(code, "< 0")
          _ -> false
        end
      end)

    total = length(edge_cases)

    %{
      covered: covered,
      total: total,
      percentage: if(total > 0, do: covered / total, else: 1.0),
      missing:
        Enum.filter(edge_cases, fn ec ->
          not evaluate_single_edge_case(code, ec)
        end)
    }
  end

  defp evaluate_single_edge_case(code, edge_case) do
    case edge_case do
      "nil input handling" -> String.contains?(code, "nil")
      "empty list/map handling" -> String.contains?(code, "[]") or String.contains?(code, "%{}")
      "zero/negative number handling" -> String.contains?(code, "<= 0") or String.contains?(code, "< 0")
      _ -> false
    end
  end

  defp extract_documentation(code) do
    moduledoc =
      case Regex.run(~r/@moduledoc\s+"""(.*?)"""/s, code) do
        [_, doc] -> String.trim(doc)
        _ -> nil
      end

    fundocs =
      Regex.scan(~r/@doc\s+"""(.*?)"""/s, code)
      |> Enum.map(fn [_, doc] -> String.trim(doc) end)

    %{
      moduledoc: moduledoc,
      function_docs: fundocs,
      total_docs: if(moduledoc, do: 1, else: 0) + length(fundocs)
    }
  end

  defp analyze_documentation_quality(existing_docs, code, _doc_type, _state) do
    functions = extract_function_names(code)
    documented_functions = length(existing_docs.function_docs)
    total_functions = length(functions)

    coverage =
      if total_functions > 0 do
        documented_functions / total_functions
      else
        1.0
      end

    %{
      coverage: coverage,
      quality_score: calculate_doc_quality_score(existing_docs),
      missing: functions -- documented_function_names(existing_docs, code),
      examples_needed: identify_functions_needing_examples(existing_docs, functions)
    }
  end

  defp extract_function_names(code) do
    Regex.scan(~r/def\s+(\w+)/, code)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
  end

  defp documented_function_names(_existing_docs, code) do
    # Find functions with @doc before them
    Regex.scan(~r/@doc\s+.*?\n\s*def\s+(\w+)/, code)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp calculate_doc_quality_score(existing_docs) do
    base_score = 0.0

    # Has moduledoc
    score =
      if existing_docs.moduledoc do
        base_score + 0.3
      else
        base_score
      end

    # Function docs exist
    score =
      if length(existing_docs.function_docs) > 0 do
        score + 0.3
      else
        score
      end

    # Docs have good length (not too short)
    avg_doc_length =
      if length(existing_docs.function_docs) > 0 do
        total = Enum.reduce(existing_docs.function_docs, 0, &(String.length(&1) + &2))
        div(total, length(existing_docs.function_docs))
      else
        0
      end

    score =
      if avg_doc_length > 50 do
        score + 0.4
      else
        score + 0.2
      end

    min(1.0, score)
  end

  defp identify_functions_needing_examples(existing_docs, functions) do
    # Functions that would benefit from examples
    complex_functions = Enum.filter(functions, &String.contains?(&1, "_"))

    # Check which docs lack examples
    docs_without_examples =
      existing_docs.function_docs
      |> Enum.filter(&(not String.contains?(&1, "##") and not String.contains?(&1, "iex>")))
      |> length()

    if docs_without_examples > 0 or length(complex_functions) > 2 do
      complex_functions
    else
      []
    end
  end

  defp generate_documentation_suggestions(doc_analysis, _code, _state) do
    suggestions = []

    # Missing moduledoc
    suggestions =
      if doc_analysis.coverage < 0.3 do
        [
          %{
            type: :missing_moduledoc,
            description: "Add module documentation",
            template: """
            @moduledoc \"\"\"
            Brief description of module purpose.

            ## Examples

                iex> # example usage
            \"\"\"
            """,
            priority: :high
          }
        ] ++ suggestions
      else
        suggestions
      end

    # Missing function docs
    suggestions =
      if length(doc_analysis.missing) > 0 do
        missing_suggestions =
          Enum.map(doc_analysis.missing, fn func_name ->
            %{
              type: :missing_function_doc,
              description: "Add documentation for #{func_name}/N",
              function: func_name,
              template: """
              @doc \"\"\"
              Brief description of #{func_name}.

              ## Parameters

              - param1 - description

              ## Examples

                  iex> #{func_name}(...)
                  :result
              \"\"\"
              """,
              priority: :medium
            }
          end)

        suggestions ++ missing_suggestions
      else
        suggestions
      end

    # Examples needed
    suggestions =
      if length(doc_analysis.examples_needed) > 0 do
        example_suggestion = %{
          type: :add_examples,
          description: "Add examples to function documentation",
          functions: doc_analysis.examples_needed,
          priority: :low
        }

        [example_suggestion | suggestions]
      else
        suggestions
      end

    suggestions
  end

  defp perform_quick_review(code, review_type, state) do
    case review_type do
      :basic ->
        quality_scores = %{
          readability: analyze_readability(code, state).score,
          maintainability: analyze_maintainability(code, state).score
        }

        %{
          overall_score: (quality_scores.readability + quality_scores.maintainability) / 2,
          feedback: "Basic review completed",
          quality_scores: quality_scores
        }

      :security ->
        security_analysis = analyze_security(code, state)

        %{
          vulnerabilities: security_analysis.vulnerabilities,
          security_score: security_analysis.score,
          high_risk_count: security_analysis.high_risk_patterns
        }

      _ ->
        %{error: "Unknown review type"}
    end
  end

  defp count_lines(code) do
    code
    |> String.split("\n")
    |> length()
  end
end
