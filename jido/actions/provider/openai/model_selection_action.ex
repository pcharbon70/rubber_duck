defmodule RubberDuck.Jido.Actions.Provider.OpenAI.ModelSelectionAction do
  @moduledoc """
  Action for intelligent OpenAI model selection based on request characteristics.

  This action analyzes request parameters, content complexity, performance requirements,
  and cost constraints to automatically select the most appropriate OpenAI model
  for optimal performance and cost efficiency.

  ## Parameters

  - `operation` - Selection operation (required: :select, :analyze, :recommend, :compare)
  - `messages` - Conversation messages for analysis (required for :select)
  - `requirements` - Performance and cost requirements (default: %{})
  - `constraints` - Hard constraints for model selection (default: %{})
  - `optimization_goal` - Primary optimization target (default: :balanced)
  - `fallback_strategy` - How to handle unavailable models (default: :auto)
  - `models_to_consider` - Specific models to evaluate (default: :all)

  ## Returns

  - `{:ok, result}` - Model selection completed successfully
  - `{:error, reason}` - Model selection failed

  ## Example

      params = %{
        operation: :select,
        messages: conversation_messages,
        requirements: %{
          max_cost_per_request: 0.10,
          min_response_quality: :high,
          max_latency_ms: 5000
        },
        optimization_goal: :cost_efficiency,
        fallback_strategy: :performance_based
      }

      {:ok, result} = ModelSelectionAction.run(params, context)
  """

  use Jido.Action,
    name: "model_selection",
    description: "Intelligent OpenAI model selection based on request characteristics",
    schema: [
      operation: [
        type: :atom,
        required: true,
        doc: "Selection operation (select, analyze, recommend, compare, benchmark)"
      ],
      messages: [
        type: :list,
        default: [],
        doc: "Conversation messages for analysis"
      ],
      requirements: [
        type: :map,
        default: %{},
        doc: "Performance and cost requirements"
      ],
      constraints: [
        type: :map,
        default: %{},
        doc: "Hard constraints for model selection"
      ],
      optimization_goal: [
        type: :atom,
        default: :balanced,
        doc: "Primary optimization target (cost, performance, balanced, quality, speed)"
      ],
      fallback_strategy: [
        type: :atom,
        default: :auto,
        doc: "Fallback strategy (auto, performance_based, cost_based, none)"
      ],
      models_to_consider: [
        type: {:union, [:atom, {:list, :string}]},
        default: :all,
        doc: "Specific models to evaluate or :all"
      ],
      task_type: [
        type: :atom,
        default: :general,
        doc: "Type of task (general, coding, analysis, creative, reasoning)"
      ],
      context_size: [
        type: :integer,
        default: nil,
        doc: "Estimated context size if known"
      ]
    ]

  require Logger

  @model_specifications %{
    "gpt-4o" => %{
      context_length: 128_000,
      cost_per_input_token: 2.50 / 1_000_000,
      cost_per_output_token: 10.00 / 1_000_000,
      performance_tier: :premium,
      strengths: [:reasoning, :coding, :analysis, :multimodal],
      latency_tier: :fast,
      quality_score: 95,
      release_date: ~D[2024-05-13]
    },
    "gpt-4-turbo" => %{
      context_length: 128_000,
      cost_per_input_token: 10.00 / 1_000_000,
      cost_per_output_token: 30.00 / 1_000_000,
      performance_tier: :premium,
      strengths: [:reasoning, :coding, :analysis, :long_context],
      latency_tier: :medium,
      quality_score: 92,
      release_date: ~D[2024-04-09]
    },
    "gpt-4" => %{
      context_length: 8_192,
      cost_per_input_token: 30.00 / 1_000_000,
      cost_per_output_token: 60.00 / 1_000_000,
      performance_tier: :premium,
      strengths: [:reasoning, :complex_tasks, :accuracy],
      latency_tier: :slow,
      quality_score: 90,
      release_date: ~D[2023-03-14]
    },
    "gpt-3.5-turbo" => %{
      context_length: 16_385,
      cost_per_input_token: 0.50 / 1_000_000,
      cost_per_output_token: 1.50 / 1_000_000,
      performance_tier: :standard,
      strengths: [:speed, :cost_efficiency, :general_tasks],
      latency_tier: :fast,
      quality_score: 75,
      release_date: ~D[2023-03-01]
    },
    "gpt-3.5-turbo-16k" => %{
      context_length: 16_385,
      cost_per_input_token: 3.00 / 1_000_000,
      cost_per_output_token: 4.00 / 1_000_000,
      performance_tier: :standard,
      strengths: [:long_context, :cost_efficiency],
      latency_tier: :fast,
      quality_score: 75,
      release_date: ~D[2023-06-13]
    }
  }

  @valid_operations [:select, :analyze, :recommend, :compare, :benchmark]
  @valid_optimization_goals [:cost, :performance, :balanced, :quality, :speed, :context_length]
  @valid_fallback_strategies [:auto, :performance_based, :cost_based, :none]
  @valid_task_types [:general, :coding, :analysis, :creative, :reasoning, :summarization, :translation]

  @impl true
  def run(params, context) do
    Logger.info("Executing model selection: #{params.operation} with goal #{params.optimization_goal}")

    with {:ok, validated_params} <- validate_selection_parameters(params),
         {:ok, result} <- execute_selection_operation(validated_params, context) do
      
      emit_selection_completed_signal(params.operation, result)
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Model selection failed: #{inspect(reason)}")
        emit_selection_error_signal(params.operation, reason)
        {:error, reason}
    end
  end

  # Parameter validation

  defp validate_selection_parameters(params) do
    with {:ok, _} <- validate_operation(params.operation),
         {:ok, _} <- validate_optimization_goal(params.optimization_goal),
         {:ok, _} <- validate_fallback_strategy(params.fallback_strategy),
         {:ok, _} <- validate_task_type(params.task_type),
         {:ok, _} <- validate_models_to_consider(params.models_to_consider),
         {:ok, _} <- validate_messages_for_operation(params.messages, params.operation) do
      
      {:ok, params}
    else
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  defp validate_operation(operation) do
    if operation in @valid_operations do
      {:ok, operation}
    else
      {:error, {:invalid_operation, operation, @valid_operations}}
    end
  end

  defp validate_optimization_goal(goal) do
    if goal in @valid_optimization_goals do
      {:ok, goal}
    else
      {:error, {:invalid_optimization_goal, goal, @valid_optimization_goals}}
    end
  end

  defp validate_fallback_strategy(strategy) do
    if strategy in @valid_fallback_strategies do
      {:ok, strategy}
    else
      {:error, {:invalid_fallback_strategy, strategy, @valid_fallback_strategies}}
    end
  end

  defp validate_task_type(task_type) do
    if task_type in @valid_task_types do
      {:ok, task_type}
    else
      {:error, {:invalid_task_type, task_type, @valid_task_types}}
    end
  end

  defp validate_models_to_consider(:all), do: {:ok, :all}
  defp validate_models_to_consider(models) when is_list(models) do
    available_models = Map.keys(@model_specifications)
    invalid_models = models -- available_models
    
    if Enum.empty?(invalid_models) do
      {:ok, models}
    else
      {:error, {:invalid_models, invalid_models, available_models}}
    end
  end
  defp validate_models_to_consider(models), do: {:error, {:invalid_models_format, models}}

  defp validate_messages_for_operation(messages, operation) when operation in [:select, :analyze] do
    if is_list(messages) and length(messages) > 0 do
      {:ok, messages}
    else
      {:error, {:messages_required_for_operation, operation}}
    end
  end
  defp validate_messages_for_operation(_messages, _operation), do: {:ok, :not_required}

  # Operation execution

  defp execute_selection_operation(params, context) do
    case params.operation do
      :select -> select_optimal_model(params, context)
      :analyze -> analyze_request_characteristics(params, context)
      :recommend -> recommend_models(params, context)
      :compare -> compare_models(params, context)
      :benchmark -> benchmark_models(params, context)
    end
  end

  # Model selection

  defp select_optimal_model(params, context) do
    with {:ok, request_analysis} <- analyze_request_requirements(params),
         {:ok, candidate_models} <- get_candidate_models(params),
         {:ok, model_scores} <- score_models(candidate_models, request_analysis, params),
         {:ok, selected_model} <- apply_selection_strategy(model_scores, params) do
      
      result = %{
        operation: :select,
        selected_model: selected_model,
        selection_confidence: calculate_selection_confidence(model_scores, selected_model),
        request_analysis: request_analysis,
        model_scores: model_scores,
        selection_rationale: generate_selection_rationale(selected_model, model_scores, params),
        fallback_models: identify_fallback_models(model_scores, selected_model),
        estimated_cost: estimate_request_cost(selected_model, request_analysis),
        metadata: %{
          selection_timestamp: DateTime.utc_now(),
          optimization_goal: params.optimization_goal,
          models_evaluated: length(model_scores)
        }
      }
      
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp analyze_request_requirements(params) do
    messages = params.messages
    task_type = params.task_type
    context_size = params.context_size
    
    analysis = %{
      estimated_input_tokens: estimate_input_tokens(messages),
      estimated_output_tokens: estimate_output_tokens(messages, task_type),
      content_complexity: assess_content_complexity(messages),
      task_characteristics: analyze_task_characteristics(messages, task_type),
      context_requirements: determine_context_requirements(messages, context_size),
      performance_requirements: extract_performance_requirements(params.requirements),
      cost_constraints: extract_cost_constraints(params.constraints)
    }
    
    {:ok, analysis}
  end

  defp estimate_input_tokens(messages) do
    total_chars = Enum.reduce(messages, 0, fn message, acc ->
      content = message[:content] || message["content"] || ""
      acc + String.length(content)
    end)
    
    # Rough estimation: ~4 characters per token
    div(total_chars, 4)
  end

  defp estimate_output_tokens(messages, task_type) do
    input_tokens = estimate_input_tokens(messages)
    
    # Estimate based on task type
    multiplier = case task_type do
      :summarization -> 0.3
      :translation -> 1.2
      :coding -> 1.5
      :analysis -> 2.0
      :creative -> 3.0
      :reasoning -> 2.5
      :general -> 1.0
    end
    
    round(input_tokens * multiplier)
  end

  defp assess_content_complexity(messages) do
    if length(messages) == 0 do
      %{score: 0, factors: []}
    else
      total_content = Enum.map_join(messages, " ", fn message ->
        message[:content] || message["content"] || ""
      end)
      
      complexity_factors = []
      base_score = 1.0
      
      # Length complexity
      char_count = String.length(total_content)
      length_factor = min(char_count / 10000, 3.0)
      complexity_factors = [{:length, length_factor} | complexity_factors]
      
      # Technical content detection
      technical_keywords = ["algorithm", "function", "variable", "database", "API", "code", "syntax"]
      technical_count = Enum.count(technical_keywords, &String.contains?(String.downcase(total_content), &1))
      technical_factor = technical_count * 0.2
      complexity_factors = [{:technical, technical_factor} | complexity_factors]
      
      # Mathematical content
      math_patterns = ~r/\d+[\+\-\*\/]\d+|equation|formula|calculate|mathematics/i
      math_factor = if Regex.match?(math_patterns, total_content), do: 0.5, else: 0.0
      complexity_factors = [{:mathematical, math_factor} | complexity_factors]
      
      # Language complexity (sentence structure, vocabulary)
      sentences = String.split(total_content, ~r/[.!?]+/)
      avg_sentence_length = if length(sentences) > 0 do
        total_words = String.split(total_content) |> length()
        total_words / length(sentences)
      else
        0
      end
      
      language_factor = min(avg_sentence_length / 20, 1.0)
      complexity_factors = [{:language, language_factor} | complexity_factors]
      
      total_score = base_score + length_factor + technical_factor + math_factor + language_factor
      
      %{
        score: min(total_score, 10.0),
        factors: complexity_factors,
        content_length: char_count,
        average_sentence_length: avg_sentence_length,
        technical_content_detected: technical_count > 0
      }
    end
  end

  defp analyze_task_characteristics(messages, task_type) do
    content = Enum.map_join(messages, " ", fn message ->
      message[:content] || message["content"] || ""
    end)
    
    # Detect actual task characteristics from content
    detected_characteristics = []
    
    # Code-related patterns
    code_patterns = ~r/(def |function |class |import |from |SELECT |INSERT |UPDATE)/i
    if Regex.match?(code_patterns, content) do
      detected_characteristics = [:coding | detected_characteristics]
    end
    
    # Analysis patterns
    analysis_patterns = ~r/(analyze|analysis|compare|evaluate|assess|examine)/i
    if Regex.match?(analysis_patterns, content) do
      detected_characteristics = [:analysis | detected_characteristics]
    end
    
    # Creative patterns
    creative_patterns = ~r/(story|creative|imagine|write|compose|poem|novel)/i
    if Regex.match?(creative_patterns, content) do
      detected_characteristics = [:creative | detected_characteristics]
    end
    
    # Reasoning patterns
    reasoning_patterns = ~r/(because|therefore|logic|reasoning|solve|problem|think)/i
    if Regex.match?(reasoning_patterns, content) do
      detected_characteristics = [:reasoning | detected_characteristics]
    end
    
    %{
      declared_type: task_type,
      detected_characteristics: detected_characteristics,
      primary_characteristic: List.first(detected_characteristics) || task_type,
      confidence: calculate_task_confidence(task_type, detected_characteristics)
    }
  end

  defp calculate_task_confidence(declared_type, detected_characteristics) do
    if declared_type in detected_characteristics do
      1.0
    else
      case length(detected_characteristics) do
        0 -> 0.5  # No clear signals
        1 -> 0.7  # One clear signal
        _ -> 0.3  # Mixed signals
      end
    end
  end

  defp determine_context_requirements(messages, provided_context_size) do
    estimated_tokens = estimate_input_tokens(messages)
    
    # Use provided context size if available, otherwise estimate
    context_needed = provided_context_size || estimated_tokens
    
    # Add buffer for output and conversation history
    buffer_multiplier = 1.5
    total_context_needed = round(context_needed * buffer_multiplier)
    
    %{
      estimated_input_tokens: estimated_tokens,
      total_context_needed: total_context_needed,
      buffer_applied: buffer_multiplier,
      requires_long_context: total_context_needed > 16_000
    }
  end

  defp extract_performance_requirements(requirements) do
    %{
      max_latency_ms: requirements[:max_latency_ms],
      min_quality_score: requirements[:min_quality_score] || requirements[:min_response_quality],
      max_cost_per_request: requirements[:max_cost_per_request],
      required_capabilities: requirements[:required_capabilities] || []
    }
  end

  defp extract_cost_constraints(constraints) do
    %{
      hard_cost_limit: constraints[:max_cost],
      budget_tier: constraints[:budget_tier],
      cost_optimization_priority: constraints[:cost_optimization_priority] || :medium
    }
  end

  defp get_candidate_models(params) do
    candidate_models = case params.models_to_consider do
      :all -> Map.keys(@model_specifications)
      specific_models -> specific_models
    end
    
    # Filter based on hard constraints
    filtered_models = Enum.filter(candidate_models, fn model ->
      meets_hard_constraints?(model, params.constraints)
    end)
    
    if length(filtered_models) > 0 do
      {:ok, filtered_models}
    else
      {:error, :no_models_meet_constraints}
    end
  end

  defp meets_hard_constraints?(model, constraints) do
    spec = Map.get(@model_specifications, model)
    
    cond do
      constraints[:min_context_length] && spec.context_length < constraints[:min_context_length] ->
        false
      
      constraints[:max_cost_per_token] && 
      spec.cost_per_input_token > constraints[:max_cost_per_token] ->
        false
      
      constraints[:required_capabilities] &&
      not Enum.all?(constraints[:required_capabilities], &(&1 in spec.strengths)) ->
        false
      
      true ->
        true
    end
  end

  defp score_models(candidate_models, request_analysis, params) do
    model_scores = Enum.map(candidate_models, fn model ->
      score = calculate_model_score(model, request_analysis, params)
      %{
        model: model,
        total_score: score.total,
        component_scores: score.components,
        suitability_rating: categorize_suitability(score.total),
        estimated_cost: score.estimated_cost,
        performance_prediction: score.performance_prediction
      }
    end)
    
    # Sort by total score descending
    sorted_scores = Enum.sort_by(model_scores, & &1.total_score, :desc)
    
    {:ok, sorted_scores}
  end

  defp calculate_model_score(model, request_analysis, params) do
    spec = Map.get(@model_specifications, model)
    
    # Component scores (0-100 scale)
    cost_score = calculate_cost_score(spec, request_analysis, params)
    performance_score = calculate_performance_score(spec, request_analysis, params)
    capability_score = calculate_capability_score(spec, request_analysis, params)
    context_score = calculate_context_score(spec, request_analysis)
    quality_score = spec.quality_score
    
    # Weighted combination based on optimization goal
    weights = get_scoring_weights(params.optimization_goal)
    
    total_score = 
      cost_score * weights.cost +
      performance_score * weights.performance +
      capability_score * weights.capability +
      context_score * weights.context +
      quality_score * weights.quality
    
    %{
      total: total_score,
      components: %{
        cost: cost_score,
        performance: performance_score,
        capability: capability_score,
        context: context_score,
        quality: quality_score
      },
      estimated_cost: calculate_estimated_cost(spec, request_analysis),
      performance_prediction: predict_performance(spec, request_analysis)
    }
  end

  defp calculate_cost_score(spec, request_analysis, params) do
    estimated_cost = calculate_estimated_cost(spec, request_analysis)
    
    # Score based on cost efficiency
    baseline_cost = 0.01  # $0.01 as baseline
    
    cost_efficiency = baseline_cost / max(estimated_cost, 0.0001)
    
    # Apply constraints
    max_cost = params.requirements[:max_cost_per_request]
    
    if max_cost && estimated_cost > max_cost do
      0  # Eliminate models that exceed budget
    else
      min(cost_efficiency * 50, 100)  # Scale to 0-100
    end
  end

  defp calculate_estimated_cost(spec, request_analysis) do
    input_cost = request_analysis.estimated_input_tokens * spec.cost_per_input_token
    output_cost = request_analysis.estimated_output_tokens * spec.cost_per_output_token
    
    input_cost + output_cost
  end

  defp calculate_performance_score(spec, request_analysis, params) do
    base_score = case spec.performance_tier do
      :premium -> 90
      :standard -> 70
      :basic -> 50
    end
    
    # Adjust for latency requirements
    latency_score = case spec.latency_tier do
      :fast -> 100
      :medium -> 80
      :slow -> 60
    end
    
    # Check against requirements
    max_latency = params.requirements[:max_latency_ms]
    
    if max_latency do
      # Rough latency estimates
      estimated_latency = case spec.latency_tier do
        :fast -> 2000
        :medium -> 5000
        :slow -> 10000
      end
      
      if estimated_latency > max_latency do
        0  # Eliminate models that are too slow
      else
        (base_score + latency_score) / 2
      end
    else
      (base_score + latency_score) / 2
    end
  end

  defp calculate_capability_score(spec, request_analysis, params) do
    task_characteristics = request_analysis.task_characteristics
    primary_task = task_characteristics.primary_characteristic
    
    # Base capability match
    base_score = if primary_task in spec.strengths do
      90
    else
      # Check for related capabilities
      related_score = case primary_task do
        :coding -> if :reasoning in spec.strengths, do: 70, else: 50
        :analysis -> if :reasoning in spec.strengths, do: 80, else: 60
        :creative -> if :general_tasks in spec.strengths, do: 60, else: 40
        :reasoning -> if :complex_tasks in spec.strengths, do: 85, else: 50
        _ -> 60
      end
      
      related_score
    end
    
    # Adjust for complexity
    complexity_factor = min(request_analysis.content_complexity.score / 5.0, 1.5)
    
    # Higher complexity benefits from premium models
    if spec.performance_tier == :premium and complexity_factor > 1.0 do
      min(base_score * complexity_factor, 100)
    else
      base_score
    end
  end

  defp calculate_context_score(spec, request_analysis) do
    required_context = request_analysis.context_requirements.total_context_needed
    available_context = spec.context_length
    
    cond do
      required_context > available_context ->
        0  # Cannot handle the required context
      
      required_context < available_context * 0.5 ->
        100  # Plenty of context headroom
      
      required_context < available_context * 0.8 ->
        80  # Good context fit
      
      true ->
        60  # Tight but acceptable
    end
  end

  defp get_scoring_weights(optimization_goal) do
    case optimization_goal do
      :cost -> %{cost: 0.5, performance: 0.2, capability: 0.15, context: 0.1, quality: 0.05}
      :performance -> %{cost: 0.1, performance: 0.4, capability: 0.25, context: 0.15, quality: 0.1}
      :quality -> %{cost: 0.1, performance: 0.2, capability: 0.25, context: 0.15, quality: 0.3}
      :speed -> %{cost: 0.15, performance: 0.45, capability: 0.2, context: 0.1, quality: 0.1}
      :context_length -> %{cost: 0.1, performance: 0.2, capability: 0.2, context: 0.4, quality: 0.1}
      :balanced -> %{cost: 0.25, performance: 0.25, capability: 0.25, context: 0.15, quality: 0.1}
    end
  end

  defp categorize_suitability(score) do
    cond do
      score >= 80 -> :excellent
      score >= 65 -> :good
      score >= 50 -> :acceptable
      score >= 35 -> :poor
      true -> :unsuitable
    end
  end

  defp predict_performance(spec, request_analysis) do
    %{
      estimated_latency_ms: estimate_latency(spec, request_analysis),
      expected_quality: spec.quality_score,
      cost_efficiency_ratio: calculate_cost_efficiency_ratio(spec, request_analysis),
      context_utilization: calculate_context_utilization(spec, request_analysis)
    }
  end

  defp estimate_latency(spec, request_analysis) do
    base_latency = case spec.latency_tier do
      :fast -> 1500
      :medium -> 4000
      :slow -> 8000
    end
    
    # Adjust for token count
    token_factor = request_analysis.estimated_output_tokens / 1000
    
    round(base_latency + (token_factor * 500))
  end

  defp calculate_cost_efficiency_ratio(spec, request_analysis) do
    cost = calculate_estimated_cost(spec, request_analysis)
    quality = spec.quality_score
    
    if cost > 0 do
      quality / (cost * 1000)  # Quality per millidollar
    else
      0
    end
  end

  defp calculate_context_utilization(spec, request_analysis) do
    required = request_analysis.context_requirements.total_context_needed
    available = spec.context_length
    
    min(required / available, 1.0)
  end

  defp apply_selection_strategy(model_scores, params) do
    case params.fallback_strategy do
      :none ->
        # Strict selection - only top model
        top_model = List.first(model_scores)
        if top_model && top_model.suitability_rating != :unsuitable do
          {:ok, top_model}
        else
          {:error, :no_suitable_model_found}
        end
        
      :auto ->
        # Select first suitable model
        suitable_model = Enum.find(model_scores, fn score ->
          score.suitability_rating in [:excellent, :good, :acceptable]
        end)
        
        if suitable_model do
          {:ok, suitable_model}
        else
          {:error, :no_suitable_model_found}
        end
        
      :performance_based ->
        # Prefer performance over cost
        performance_sorted = Enum.sort_by(model_scores, fn score ->
          score.component_scores.performance + score.component_scores.quality
        end, :desc)
        
        {:ok, List.first(performance_sorted)}
        
      :cost_based ->
        # Prefer cost efficiency
        cost_sorted = Enum.sort_by(model_scores, & &1.component_scores.cost, :desc)
        {:ok, List.first(cost_sorted)}
    end
  end

  defp calculate_selection_confidence(model_scores, selected_model) do
    if length(model_scores) < 2 do
      1.0
    else
      scores = Enum.map(model_scores, & &1.total_score)
      top_score = selected_model.total_score
      second_score = Enum.at(Enum.sort(scores, :desc), 1)
      
      # Confidence based on score gap
      score_gap = top_score - second_score
      min(score_gap / 20, 1.0)
    end
  end

  defp generate_selection_rationale(selected_model, model_scores, params) do
    spec = Map.get(@model_specifications, selected_model.model)
    
    primary_reasons = []
    
    # Identify primary selection factors
    components = selected_model.component_scores
    max_component = Enum.max_by(components, &elem(&1, 1))
    
    primary_reasons = case elem(max_component, 0) do
      :cost -> ["Selected for optimal cost efficiency" | primary_reasons]
      :performance -> ["Selected for superior performance characteristics" | primary_reasons]
      :capability -> ["Selected for best task capability match" | primary_reasons]
      :context -> ["Selected for optimal context handling" | primary_reasons]
      :quality -> ["Selected for highest quality output" | primary_reasons]
    end
    
    # Add specific advantages
    if selected_model.suitability_rating == :excellent do
      primary_reasons = ["Excellent overall fit for requirements" | primary_reasons]
    end
    
    if spec.performance_tier == :premium and params.optimization_goal != :cost do
      primary_reasons = ["Premium model provides superior capabilities" | primary_reasons]
    end
    
    %{
      primary_reasons: Enum.reverse(primary_reasons),
      score_breakdown: components,
      model_strengths: spec.strengths,
      selection_confidence: calculate_selection_confidence(model_scores, selected_model),
      compared_models: length(model_scores)
    }
  end

  defp identify_fallback_models(model_scores, selected_model) do
    model_scores
    |> Enum.filter(fn score -> 
      score.model != selected_model.model and 
      score.suitability_rating in [:excellent, :good, :acceptable]
    end)
    |> Enum.take(3)
    |> Enum.map(fn score ->
      %{
        model: score.model,
        score: score.total_score,
        suitability: score.suitability_rating,
        reason: generate_fallback_reason(score, selected_model)
      }
    end)
  end

  defp generate_fallback_reason(fallback_score, selected_model) do
    if fallback_score.component_scores.cost > selected_model.component_scores.cost do
      "More cost-effective alternative"
    else
      "Alternative with different performance characteristics"
    end
  end

  defp estimate_request_cost(selected_model, request_analysis) do
    spec = Map.get(@model_specifications, selected_model.model)
    calculate_estimated_cost(spec, request_analysis)
  end

  # Request analysis operation

  defp analyze_request_characteristics(params, _context) do
    case analyze_request_requirements(params) do
      {:ok, analysis} ->
        result = %{
          operation: :analyze,
          request_analysis: analysis,
          recommendations: generate_analysis_recommendations(analysis),
          optimization_opportunities: identify_optimization_opportunities(analysis, params)
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_analysis_recommendations(analysis) do
    recommendations = []
    
    # Context recommendations
    recommendations = if analysis.context_requirements.requires_long_context do
      ["Consider using models with larger context windows (GPT-4 Turbo, GPT-4o)" | recommendations]
    else
      recommendations
    end
    
    # Complexity recommendations
    recommendations = if analysis.content_complexity.score > 7 do
      ["High complexity detected - premium models recommended for best results" | recommendations]
    else
      recommendations
    end
    
    # Cost optimization
    recommendations = if analysis.estimated_output_tokens < 500 do
      ["Short responses expected - consider cost-effective models" | recommendations]
    else
      recommendations
    end
    
    Enum.reverse(recommendations)
  end

  defp identify_optimization_opportunities(analysis, params) do
    opportunities = []
    
    # Model tier optimization
    if params.optimization_goal == :balanced and analysis.content_complexity.score < 5 do
      opportunities = ["Consider using a standard tier model for cost savings" | opportunities]
    end
    
    # Context optimization
    if analysis.context_requirements.total_context_needed < 8000 do
      opportunities = ["Request fits in smaller context windows - consider GPT-3.5 models" | opportunities]
    end
    
    # Task-specific optimization
    task_type = analysis.task_characteristics.primary_characteristic
    if task_type == :summarization and analysis.estimated_output_tokens < 200 do
      opportunities = ["Simple summarization - GPT-3.5 may be sufficient" | opportunities]
    end
    
    Enum.reverse(opportunities)
  end

  # Model recommendation operation

  defp recommend_models(params, context) do
    with {:ok, request_analysis} <- analyze_request_requirements(params),
         {:ok, candidate_models} <- get_candidate_models(params),
         {:ok, model_scores} <- score_models(candidate_models, request_analysis, params) do
      
      # Group recommendations by use case
      recommendations = %{
        optimal: get_optimal_recommendations(model_scores),
        cost_effective: get_cost_effective_recommendations(model_scores),
        high_performance: get_high_performance_recommendations(model_scores),
        balanced: get_balanced_recommendations(model_scores)
      }
      
      result = %{
        operation: :recommend,
        recommendations: recommendations,
        request_analysis: request_analysis,
        evaluation_summary: create_evaluation_summary(model_scores)
      }
      
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_optimal_recommendations(model_scores) do
    model_scores
    |> Enum.filter(&(&1.suitability_rating in [:excellent, :good]))
    |> Enum.take(3)
    |> Enum.map(&format_recommendation/1)
  end

  defp get_cost_effective_recommendations(model_scores) do
    model_scores
    |> Enum.sort_by(& &1.component_scores.cost, :desc)
    |> Enum.take(2)
    |> Enum.map(&format_recommendation/1)
  end

  defp get_high_performance_recommendations(model_scores) do
    model_scores
    |> Enum.sort_by(& &1.component_scores.performance, :desc)
    |> Enum.take(2)
    |> Enum.map(&format_recommendation/1)
  end

  defp get_balanced_recommendations(model_scores) do
    model_scores
    |> Enum.filter(fn score ->
      components = score.component_scores
      # Balanced means no single component dominates
      max_score = Enum.max(Map.values(components))
      min_score = Enum.min(Map.values(components))
      max_score - min_score < 30
    end)
    |> Enum.take(2)
    |> Enum.map(&format_recommendation/1)
  end

  defp format_recommendation(model_score) do
    spec = Map.get(@model_specifications, model_score.model)
    
    %{
      model: model_score.model,
      suitability: model_score.suitability_rating,
      total_score: model_score.total_score,
      estimated_cost: model_score.estimated_cost,
      key_strengths: spec.strengths,
      recommendation_reason: generate_recommendation_reason(model_score, spec)
    }
  end

  defp generate_recommendation_reason(model_score, spec) do
    components = model_score.component_scores
    top_component = Enum.max_by(components, &elem(&1, 1))
    
    case elem(top_component, 0) do
      :cost -> "Most cost-effective option for this request"
      :performance -> "Best performance characteristics"
      :capability -> "Optimal capabilities for the task type"
      :quality -> "Highest quality output expected"
      :context -> "Best context handling for request size"
    end
  end

  defp create_evaluation_summary(model_scores) do
    %{
      models_evaluated: length(model_scores),
      excellent_options: Enum.count(model_scores, &(&1.suitability_rating == :excellent)),
      good_options: Enum.count(model_scores, &(&1.suitability_rating == :good)),
      acceptable_options: Enum.count(model_scores, &(&1.suitability_rating == :acceptable)),
      average_score: if(length(model_scores) > 0, do: Enum.sum(Enum.map(model_scores, & &1.total_score)) / length(model_scores), else: 0),
      cost_range: calculate_cost_range(model_scores)
    }
  end

  defp calculate_cost_range(model_scores) do
    costs = Enum.map(model_scores, & &1.estimated_cost)
    
    %{
      min_cost: Enum.min(costs, fn -> 0 end),
      max_cost: Enum.max(costs, fn -> 0 end),
      average_cost: if(length(costs) > 0, do: Enum.sum(costs) / length(costs), else: 0)
    }
  end

  # Model comparison operation

  defp compare_models(params, context) do
    models_to_compare = case params.models_to_consider do
      :all -> Map.keys(@model_specifications)
      specific_models -> specific_models
    end
    
    comparisons = Enum.map(models_to_compare, fn model ->
      spec = Map.get(@model_specifications, model)
      
      %{
        model: model,
        specifications: spec,
        pros: generate_model_pros(spec),
        cons: generate_model_cons(spec),
        best_use_cases: determine_best_use_cases(spec),
        cost_analysis: analyze_model_costs(spec)
      }
    end)
    
    result = %{
      operation: :compare,
      model_comparisons: comparisons,
      comparison_matrix: create_comparison_matrix(comparisons),
      selection_guidance: generate_selection_guidance(comparisons)
    }
    
    {:ok, result}
  end

  defp generate_model_pros(spec) do
    pros = []
    
    pros = if spec.performance_tier == :premium do
      ["High quality output", "Advanced reasoning capabilities" | pros]
    else
      pros
    end
    
    pros = if spec.latency_tier == :fast do
      ["Fast response times" | pros]
    else
      pros
    end
    
    pros = if spec.context_length > 32000 do
      ["Large context window" | pros]
    else
      pros
    end
    
    pros = if spec.cost_per_input_token < 1.0 / 1_000_000 do
      ["Cost-effective" | pros]
    else
      pros
    end
    
    Enum.reverse(pros)
  end

  defp generate_model_cons(spec) do
    cons = []
    
    cons = if spec.cost_per_input_token > 10.0 / 1_000_000 do
      ["Higher cost per token" | cons]
    else
      cons
    end
    
    cons = if spec.latency_tier == :slow do
      ["Slower response times" | cons]
    else
      cons
    end
    
    cons = if spec.context_length < 16000 do
      ["Limited context window" | cons]
    else
      cons
    end
    
    Enum.reverse(cons)
  end

  defp determine_best_use_cases(spec) do
    use_cases = []
    
    use_cases = if :coding in spec.strengths do
      ["Software development", "Code analysis" | use_cases]
    else
      use_cases
    end
    
    use_cases = if :reasoning in spec.strengths do
      ["Complex problem solving", "Logical analysis" | use_cases]
    else
      use_cases
    end
    
    use_cases = if :creative in spec.strengths do
      ["Creative writing", "Content generation" | use_cases]
    else
      use_cases
    end
    
    use_cases = if spec.cost_per_input_token < 1.0 / 1_000_000 do
      ["High-volume applications", "Cost-sensitive use cases" | use_cases]
    else
      use_cases
    end
    
    Enum.reverse(use_cases)
  end

  defp analyze_model_costs(spec) do
    %{
      input_cost_per_1k_tokens: spec.cost_per_input_token * 1000,
      output_cost_per_1k_tokens: spec.cost_per_output_token * 1000,
      cost_tier: categorize_cost_tier(spec),
      cost_efficiency_rating: calculate_cost_efficiency_rating(spec)
    }
  end

  defp categorize_cost_tier(spec) do
    avg_cost = (spec.cost_per_input_token + spec.cost_per_output_token) / 2
    
    cond do
      avg_cost < 1.0 / 1_000_000 -> :budget
      avg_cost < 10.0 / 1_000_000 -> :standard
      avg_cost < 30.0 / 1_000_000 -> :premium
      true -> :enterprise
    end
  end

  defp calculate_cost_efficiency_rating(spec) do
    # Simple heuristic: quality per unit cost
    avg_cost = (spec.cost_per_input_token + spec.cost_per_output_token) / 2
    
    if avg_cost > 0 do
      efficiency = spec.quality_score / (avg_cost * 1_000_000)
      min(efficiency / 100, 10.0)
    else
      10.0
    end
  end

  defp create_comparison_matrix(comparisons) do
    models = Enum.map(comparisons, & &1.model)
    
    %{
      models: models,
      context_lengths: Enum.map(comparisons, &(&1.specifications.context_length)),
      quality_scores: Enum.map(comparisons, &(&1.specifications.quality_score)),
      cost_tiers: Enum.map(comparisons, &(&1.cost_analysis.cost_tier)),
      performance_tiers: Enum.map(comparisons, &(&1.specifications.performance_tier))
    }
  end

  defp generate_selection_guidance(comparisons) do
    guidance = []
    
    # Budget guidance
    budget_options = Enum.filter(comparisons, &(&1.cost_analysis.cost_tier == :budget))
    if length(budget_options) > 0 do
      budget_models = Enum.map(budget_options, & &1.model)
      guidance = ["For budget-conscious applications: #{Enum.join(budget_models, ", ")}" | guidance]
    end
    
    # Performance guidance
    premium_options = Enum.filter(comparisons, &(&1.specifications.performance_tier == :premium))
    if length(premium_options) > 0 do
      premium_models = Enum.map(premium_options, & &1.model)
      guidance = ["For high-performance requirements: #{Enum.join(premium_models, ", ")}" | guidance]
    end
    
    # Context guidance
    long_context_options = Enum.filter(comparisons, &(&1.specifications.context_length > 32000))
    if length(long_context_options) > 0 do
      long_context_models = Enum.map(long_context_options, & &1.model)
      guidance = ["For large context requirements: #{Enum.join(long_context_models, ", ")}" | guidance]
    end
    
    Enum.reverse(guidance)
  end

  # Benchmarking operation

  defp benchmark_models(params, _context) do
    models_to_benchmark = case params.models_to_consider do
      :all -> Map.keys(@model_specifications)
      specific_models -> specific_models
    end
    
    # Simulate benchmark results
    benchmark_results = Enum.map(models_to_benchmark, fn model ->
      generate_benchmark_result(model)
    end)
    
    result = %{
      operation: :benchmark,
      benchmark_results: benchmark_results,
      performance_rankings: create_performance_rankings(benchmark_results),
      benchmark_summary: create_benchmark_summary(benchmark_results)
    }
    
    {:ok, result}
  end

  defp generate_benchmark_result(model) do
    spec = Map.get(@model_specifications, model)
    
    # Simulate realistic benchmark scores
    base_performance = spec.quality_score
    
    %{
      model: model,
      overall_score: base_performance,
      benchmarks: %{
        reasoning_score: base_performance + :rand.uniform(10) - 5,
        creativity_score: base_performance + :rand.uniform(15) - 7,
        accuracy_score: base_performance + :rand.uniform(8) - 4,
        speed_score: case spec.latency_tier do
          :fast -> 85 + :rand.uniform(15)
          :medium -> 70 + :rand.uniform(15)
          :slow -> 50 + :rand.uniform(20)
        end,
        cost_efficiency_score: round(calculate_cost_efficiency_rating(spec) * 10)
      },
      test_scenarios: %{
        simple_tasks: base_performance + :rand.uniform(5),
        complex_tasks: base_performance - :rand.uniform(10),
        long_context: if(spec.context_length > 32000, do: base_performance, else: base_performance - 20)
      }
    }
  end

  defp create_performance_rankings(benchmark_results) do
    %{
      overall: Enum.sort_by(benchmark_results, & &1.overall_score, :desc),
      reasoning: Enum.sort_by(benchmark_results, &(&1.benchmarks.reasoning_score), :desc),
      creativity: Enum.sort_by(benchmark_results, &(&1.benchmarks.creativity_score), :desc),
      speed: Enum.sort_by(benchmark_results, &(&1.benchmarks.speed_score), :desc),
      cost_efficiency: Enum.sort_by(benchmark_results, &(&1.benchmarks.cost_efficiency_score), :desc)
    }
  end

  defp create_benchmark_summary(benchmark_results) do
    %{
      models_tested: length(benchmark_results),
      top_performer: List.first(Enum.sort_by(benchmark_results, & &1.overall_score, :desc)),
      most_cost_effective: List.first(Enum.sort_by(benchmark_results, &(&1.benchmarks.cost_efficiency_score), :desc)),
      fastest: List.first(Enum.sort_by(benchmark_results, &(&1.benchmarks.speed_score), :desc)),
      average_scores: calculate_average_benchmark_scores(benchmark_results)
    }
  end

  defp calculate_average_benchmark_scores(benchmark_results) do
    if length(benchmark_results) == 0 do
      %{}
    else
      count = length(benchmark_results)
      
      %{
        overall: Enum.sum(Enum.map(benchmark_results, & &1.overall_score)) / count,
        reasoning: Enum.sum(Enum.map(benchmark_results, &(&1.benchmarks.reasoning_score))) / count,
        creativity: Enum.sum(Enum.map(benchmark_results, &(&1.benchmarks.creativity_score))) / count,
        accuracy: Enum.sum(Enum.map(benchmark_results, &(&1.benchmarks.accuracy_score))) / count,
        speed: Enum.sum(Enum.map(benchmark_results, &(&1.benchmarks.speed_score))) / count
      }
    end
  end

  # Signal emission

  defp emit_selection_completed_signal(operation, result) do
    # TODO: Emit actual signal
    Logger.debug("Model selection #{operation} completed: #{inspect(Map.keys(result))}")
  end

  defp emit_selection_error_signal(operation, reason) do
    # TODO: Emit actual signal
    Logger.debug("Model selection #{operation} failed: #{inspect(reason)}")
  end
end