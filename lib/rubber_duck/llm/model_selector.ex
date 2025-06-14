defmodule RubberDuck.LLM.ModelSelector do
  @moduledoc """
  Dynamic model selection based on task complexity and context.
  Implements sophisticated algorithms for choosing optimal models based on
  task characteristics, performance history, and contextual requirements.
  """
  use GenServer
  require Logger

  alias RubberDuck.LLM.{Coordinator, TaskRouter}

  defstruct [
    :selection_strategies,
    :complexity_analyzers,
    :context_evaluators,
    :model_profiles,
    :selection_history,
    :performance_weights,
    :selection_metrics
  ]

  @selection_strategies [:complexity_based, :context_aware, :performance_driven, :cost_efficient, :hybrid]
  @complexity_levels [:simple, :moderate, :complex, :highly_complex]
  @context_types [:code_generation, :analysis, :conversation, :translation, :reasoning]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Selects the optimal model for a given task and context.
  """
  def select_optimal_model(task, context \\ %{}, constraints \\ %{}) do
    GenServer.call(__MODULE__, {:select_optimal_model, task, context, constraints})
  end

  @doc """
  Analyzes task complexity and returns a complexity score.
  """
  def analyze_task_complexity(task, context \\ %{}) do
    GenServer.call(__MODULE__, {:analyze_complexity, task, context})
  end

  @doc """
  Evaluates context requirements for model selection.
  """
  def evaluate_context_requirements(context) do
    GenServer.call(__MODULE__, {:evaluate_context, context})
  end

  @doc """
  Updates model performance data for selection optimization.
  """
  def update_model_performance(model_id, task_type, performance_data) do
    GenServer.cast(__MODULE__, {:update_performance, model_id, task_type, performance_data})
  end

  @doc """
  Gets model selection recommendations with reasoning.
  """
  def get_model_recommendations(task, context, options \\ []) do
    GenServer.call(__MODULE__, {:get_recommendations, task, context, options})
  end

  @doc """
  Updates selection strategy configuration.
  """
  def update_selection_strategy(strategy, config \\ %{}) do
    GenServer.call(__MODULE__, {:update_strategy, strategy, config})
  end

  @doc """
  Gets model selection metrics and statistics.
  """
  def get_selection_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @impl true
  def init(opts) do
    Logger.info("Starting LLM Model Selector with dynamic selection algorithms")
    
    state = %__MODULE__{
      selection_strategies: initialize_selection_strategies(opts),
      complexity_analyzers: initialize_complexity_analyzers(opts),
      context_evaluators: initialize_context_evaluators(opts),
      model_profiles: initialize_model_profiles(opts),
      selection_history: [],
      performance_weights: initialize_performance_weights(opts),
      selection_metrics: initialize_selection_metrics()
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:select_optimal_model, task, context, constraints}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    case perform_model_selection(task, context, constraints, state) do
      {:ok, selection_result} ->
        end_time = System.monotonic_time(:microsecond)
        selection_time = end_time - start_time
        
        # Update metrics and history
        new_metrics = update_selection_metrics(state.selection_metrics, selection_result, selection_time)
        new_history = update_selection_history(state.selection_history, selection_result)
        new_state = %{state | selection_metrics: new_metrics, selection_history: new_history}
        
        {:reply, {:ok, selection_result}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:analyze_complexity, task, context}, _from, state) do
    complexity_analysis = perform_complexity_analysis(task, context, state)
    {:reply, {:ok, complexity_analysis}, state}
  end

  @impl true
  def handle_call({:evaluate_context, context}, _from, state) do
    context_evaluation = perform_context_evaluation(context, state)
    {:reply, {:ok, context_evaluation}, state}
  end

  @impl true
  def handle_call({:get_recommendations, task, context, options}, _from, state) do
    case generate_model_recommendations(task, context, options, state) do
      {:ok, recommendations} ->
        {:reply, {:ok, recommendations}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_strategy, strategy, config}, _from, state) do
    if strategy in @selection_strategies do
      new_strategies = Map.put(state.selection_strategies, strategy, config)
      new_state = %{state | selection_strategies: new_strategies}
      {:reply, {:ok, :strategy_updated}, new_state}
    else
      {:reply, {:error, :invalid_strategy}, state}
    end
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    enhanced_metrics = enhance_selection_metrics(state.selection_metrics, state)
    {:reply, enhanced_metrics, state}
  end

  @impl true
  def handle_cast({:update_performance, model_id, task_type, performance_data}, state) do
    current_profiles = state.model_profiles
    model_profile = Map.get(current_profiles, model_id, %{})
    
    updated_profile = update_model_profile(model_profile, task_type, performance_data)
    new_profiles = Map.put(current_profiles, model_id, updated_profile)
    
    new_state = %{state | model_profiles: new_profiles}
    {:noreply, new_state}
  end

  # Private functions

  defp perform_model_selection(task, context, constraints, state) do
    # Step 1: Analyze task complexity
    complexity_analysis = perform_complexity_analysis(task, context, state)
    
    # Step 2: Evaluate context requirements
    context_evaluation = perform_context_evaluation(context, state)
    
    # Step 3: Get available models with their capabilities
    case get_suitable_models(complexity_analysis, context_evaluation, constraints, state) do
      [] ->
        {:error, :no_suitable_models}
      
      suitable_models ->
        # Step 4: Apply selection strategy
        selection_strategy = determine_selection_strategy(complexity_analysis, context_evaluation, constraints, state)
        
        case apply_selection_strategy(suitable_models, complexity_analysis, context_evaluation, selection_strategy, state) do
          {:ok, selected_model} ->
            selection_result = enhance_selection_result(selected_model, complexity_analysis, context_evaluation, selection_strategy)
            {:ok, selection_result}
          
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp perform_complexity_analysis(task, context, state) do
    analyzers = state.complexity_analyzers
    
    # Basic complexity metrics
    content_complexity = analyze_content_complexity(task)
    context_complexity = analyze_context_complexity(context)
    structural_complexity = analyze_structural_complexity(task, context)
    
    # Advanced complexity analysis
    semantic_complexity = analyze_semantic_complexity(task, context, analyzers)
    computational_complexity = estimate_computational_requirements(task, context)
    
    complexity_score = calculate_overall_complexity(
      content_complexity,
      context_complexity,
      structural_complexity,
      semantic_complexity,
      computational_complexity
    )
    
    %{
      overall_score: complexity_score,
      level: classify_complexity_level(complexity_score),
      content_complexity: content_complexity,
      context_complexity: context_complexity,
      structural_complexity: structural_complexity,
      semantic_complexity: semantic_complexity,
      computational_complexity: computational_complexity,
      analysis_timestamp: System.monotonic_time(:millisecond)
    }
  end

  defp perform_context_evaluation(context, state) do
    evaluators = state.context_evaluators
    
    %{
      context_type: classify_context_type(context),
      context_size: calculate_context_size(context),
      quality_requirements: extract_quality_requirements(context),
      latency_requirements: extract_latency_requirements(context),
      cost_constraints: extract_cost_constraints(context),
      special_requirements: extract_special_requirements(context),
      domain_specificity: analyze_domain_specificity(context, evaluators),
      interaction_patterns: analyze_interaction_patterns(context)
    }
  end

  defp get_suitable_models(complexity_analysis, context_evaluation, constraints, state) do
    # Get all available models
    case Coordinator.get_available_models() do
      {:ok, available_models} ->
        # Filter models based on capability requirements
        suitable_models = Enum.filter(available_models, fn model ->
          meets_complexity_requirements?(model, complexity_analysis) and
          meets_context_requirements?(model, context_evaluation) and
          meets_constraints?(model, constraints)
        end)
        
        # Enrich with performance profiles
        Enum.map(suitable_models, fn model ->
          profile = Map.get(state.model_profiles, model.id, %{})
          Map.put(model, :profile, profile)
        end)
      
      {:error, _reason} ->
        []
    end
  end

  defp determine_selection_strategy(complexity_analysis, context_evaluation, constraints, state) do
    # Choose strategy based on task characteristics and constraints
    cond do
      Map.get(constraints, :prioritize_cost, false) -> :cost_efficient
      complexity_analysis.level in [:complex, :highly_complex] -> :performance_driven
      context_evaluation.latency_requirements < 1000 -> :performance_driven
      context_evaluation.quality_requirements == :high -> :hybrid
      true -> :complexity_based
    end
  end

  defp apply_selection_strategy(models, complexity_analysis, context_evaluation, strategy, state) do
    case strategy do
      :complexity_based ->
        select_by_complexity_matching(models, complexity_analysis, state)
      
      :context_aware ->
        select_by_context_optimization(models, context_evaluation, state)
      
      :performance_driven ->
        select_by_performance_optimization(models, complexity_analysis, context_evaluation, state)
      
      :cost_efficient ->
        select_by_cost_efficiency(models, complexity_analysis, context_evaluation, state)
      
      :hybrid ->
        select_by_hybrid_approach(models, complexity_analysis, context_evaluation, state)
    end
  end

  defp select_by_complexity_matching(models, complexity_analysis, state) do
    # Score models based on complexity handling capability
    scored_models = Enum.map(models, fn model ->
      complexity_score = calculate_complexity_handling_score(model, complexity_analysis, state)
      {model, complexity_score}
    end)
    
    case Enum.max_by(scored_models, fn {_model, score} -> score end, fn -> nil end) do
      nil -> {:error, :no_suitable_model}
      {selected_model, _score} -> {:ok, selected_model}
    end
  end

  defp select_by_context_optimization(models, context_evaluation, state) do
    # Score models based on context handling optimization
    scored_models = Enum.map(models, fn model ->
      context_score = calculate_context_handling_score(model, context_evaluation, state)
      {model, context_score}
    end)
    
    case Enum.max_by(scored_models, fn {_model, score} -> score end, fn -> nil end) do
      nil -> {:error, :no_suitable_model}
      {selected_model, _score} -> {:ok, selected_model}
    end
  end

  defp select_by_performance_optimization(models, complexity_analysis, context_evaluation, state) do
    # Score models based on expected performance
    scored_models = Enum.map(models, fn model ->
      performance_score = calculate_performance_score(model, complexity_analysis, context_evaluation, state)
      {model, performance_score}
    end)
    
    case Enum.max_by(scored_models, fn {_model, score} -> score end, fn -> nil end) do
      nil -> {:error, :no_suitable_model}
      {selected_model, _score} -> {:ok, selected_model}
    end
  end

  defp select_by_cost_efficiency(models, complexity_analysis, context_evaluation, state) do
    # Score models based on cost efficiency
    scored_models = Enum.map(models, fn model ->
      cost_efficiency_score = calculate_cost_efficiency_score(model, complexity_analysis, context_evaluation, state)
      {model, cost_efficiency_score}
    end)
    
    case Enum.max_by(scored_models, fn {_model, score} -> score end, fn -> nil end) do
      nil -> {:error, :no_suitable_model}
      {selected_model, _score} -> {:ok, selected_model}
    end
  end

  defp select_by_hybrid_approach(models, complexity_analysis, context_evaluation, state) do
    # Combine multiple scoring approaches with weights
    weights = state.performance_weights
    
    scored_models = Enum.map(models, fn model ->
      complexity_score = calculate_complexity_handling_score(model, complexity_analysis, state)
      context_score = calculate_context_handling_score(model, context_evaluation, state)
      performance_score = calculate_performance_score(model, complexity_analysis, context_evaluation, state)
      cost_score = calculate_cost_efficiency_score(model, complexity_analysis, context_evaluation, state)
      
      # Weighted combination
      hybrid_score = 
        complexity_score * weights.complexity +
        context_score * weights.context +
        performance_score * weights.performance +
        cost_score * weights.cost
      
      {model, hybrid_score}
    end)
    
    case Enum.max_by(scored_models, fn {_model, score} -> score end, fn -> nil end) do
      nil -> {:error, :no_suitable_model}
      {selected_model, _score} -> {:ok, selected_model}
    end
  end

  defp generate_model_recommendations(task, context, options, state) do
    # Analyze task and context
    complexity_analysis = perform_complexity_analysis(task, context, state)
    context_evaluation = perform_context_evaluation(context, state)
    
    # Get suitable models
    case get_suitable_models(complexity_analysis, context_evaluation, %{}, state) do
      [] ->
        {:error, :no_suitable_models}
      
      suitable_models ->
        # Generate recommendations for different strategies
        recommendations = Enum.map(@selection_strategies, fn strategy ->
          case apply_selection_strategy(suitable_models, complexity_analysis, context_evaluation, strategy, state) do
            {:ok, selected_model} ->
              %{
                strategy: strategy,
                recommended_model: selected_model.id,
                confidence: calculate_recommendation_confidence(selected_model, strategy, state),
                reasoning: generate_selection_reasoning(selected_model, strategy, complexity_analysis, context_evaluation)
              }
            
            {:error, _} ->
              nil
          end
        end)
        |> Enum.filter(&(&1 != nil))
        
        {:ok, recommendations}
    end
  end

  # Scoring and analysis functions

  defp calculate_complexity_handling_score(model, complexity_analysis, state) do
    model_capabilities = model.capabilities || %{}
    profile = model.profile || %{}
    
    # Base score from model capabilities
    base_score = get_model_capability_score(model_capabilities, complexity_analysis.level)
    
    # Performance history adjustment
    performance_adjustment = get_performance_adjustment(profile, complexity_analysis.level)
    
    # Context window consideration
    context_window_score = calculate_context_window_score(model, complexity_analysis)
    
    # Combine scores
    (base_score * 0.5 + performance_adjustment * 0.3 + context_window_score * 0.2)
  end

  defp calculate_context_handling_score(model, context_evaluation, state) do
    model_capabilities = model.capabilities || %{}
    
    # Context type compatibility
    type_score = calculate_type_compatibility_score(model_capabilities, context_evaluation.context_type)
    
    # Context size handling
    size_score = calculate_size_handling_score(model, context_evaluation.context_size)
    
    # Special requirements support
    requirements_score = calculate_requirements_support_score(model, context_evaluation.special_requirements)
    
    (type_score * 0.4 + size_score * 0.3 + requirements_score * 0.3)
  end

  defp calculate_performance_score(model, complexity_analysis, context_evaluation, state) do
    profile = model.profile || %{}
    
    # Historical performance for similar tasks
    task_type = context_evaluation.context_type
    historical_performance = get_in(profile, [task_type, :avg_performance]) || 0.5
    
    # Latency requirements compatibility
    latency_score = calculate_latency_compatibility(model, context_evaluation.latency_requirements)
    
    # Quality expectations alignment
    quality_score = calculate_quality_alignment(model, context_evaluation.quality_requirements)
    
    (historical_performance * 0.5 + latency_score * 0.3 + quality_score * 0.2)
  end

  defp calculate_cost_efficiency_score(model, complexity_analysis, context_evaluation, state) do
    cost_per_token = model.config[:cost_per_token] || 0.00001
    estimated_tokens = estimate_token_usage(complexity_analysis, context_evaluation)
    
    estimated_cost = cost_per_token * estimated_tokens
    performance_score = calculate_performance_score(model, complexity_analysis, context_evaluation, state)
    
    # Cost efficiency = performance per unit cost
    if estimated_cost > 0 do
      performance_score / estimated_cost
    else
      performance_score
    end
  end

  # Analysis helper functions

  defp analyze_content_complexity(task) do
    content = task[:content] || task[:prompt] || ""
    
    # Basic complexity indicators
    length_complexity = min(1.0, String.length(content) / 2000.0)
    word_complexity = min(1.0, length(String.split(content)) / 500.0)
    
    # Code-specific complexity
    code_complexity = analyze_code_complexity(content)
    
    # Technical terminology density
    technical_density = calculate_technical_density(content)
    
    (length_complexity + word_complexity + code_complexity + technical_density) / 4
  end

  defp analyze_context_complexity(context) do
    context_size = map_size(context)
    content_size = String.length(context[:content] || "")
    
    size_complexity = min(1.0, context_size / 20.0)
    content_complexity = min(1.0, content_size / 5000.0)
    
    (size_complexity + content_complexity) / 2
  end

  defp analyze_structural_complexity(task, context) do
    # Analyze structural patterns and relationships
    content = (task[:content] || "") <> (context[:content] || "")
    
    # Count structural elements
    code_blocks = length(Regex.scan(~r/```[\s\S]*?```/, content))
    lists = length(Regex.scan(~r/^\s*[-*+]\s/m, content))
    headers = length(Regex.scan(~r/^#+\s/m, content))
    
    structural_score = min(1.0, (code_blocks * 0.3 + lists * 0.1 + headers * 0.1) / 10)
    structural_score
  end

  defp analyze_semantic_complexity(task, context, analyzers) do
    # Simplified semantic complexity analysis
    content = (task[:content] || "") <> (context[:content] || "")
    
    # Domain-specific terms
    domain_terms = count_domain_specific_terms(content)
    
    # Abstract concepts
    abstract_concepts = count_abstract_concepts(content)
    
    # Reasoning requirements
    reasoning_indicators = count_reasoning_indicators(content)
    
    semantic_score = min(1.0, (domain_terms + abstract_concepts + reasoning_indicators) / 30.0)
    semantic_score
  end

  defp estimate_computational_requirements(task, context) do
    content = (task[:content] || "") <> (context[:content] || "")
    
    # Estimate based on task type and content
    base_requirement = String.length(content) / 1000.0
    
    # Adjust for task type
    task_multiplier = case determine_task_type(task) do
      :code_generation -> 1.5
      :analysis -> 1.3
      :reasoning -> 1.4
      :translation -> 1.1
      _ -> 1.0
    end
    
    min(1.0, base_requirement * task_multiplier)
  end

  defp calculate_overall_complexity(content, context, structural, semantic, computational) do
    weights = %{
      content: 0.25,
      context: 0.15,
      structural: 0.20,
      semantic: 0.25,
      computational: 0.15
    }
    
    content * weights.content +
    context * weights.context +
    structural * weights.structural +
    semantic * weights.semantic +
    computational * weights.computational
  end

  defp classify_complexity_level(complexity_score) do
    cond do
      complexity_score >= 0.8 -> :highly_complex
      complexity_score >= 0.6 -> :complex
      complexity_score >= 0.3 -> :moderate
      true -> :simple
    end
  end

  # Helper functions for context evaluation

  defp classify_context_type(context) do
    content = context[:content] || ""
    
    cond do
      String.contains?(String.downcase(content), ["code", "function", "class"]) -> :code_generation
      String.contains?(String.downcase(content), ["analyze", "analysis"]) -> :analysis
      String.contains?(String.downcase(content), ["chat", "conversation"]) -> :conversation
      String.contains?(String.downcase(content), ["translate", "translation"]) -> :translation
      String.contains?(String.downcase(content), ["reason", "think", "explain"]) -> :reasoning
      true -> :general
    end
  end

  defp calculate_context_size(context) do
    content_size = String.length(context[:content] || "")
    metadata_size = map_size(context)
    
    content_size + metadata_size * 100  # Weight metadata more heavily
  end

  defp extract_quality_requirements(context) do
    Map.get(context, :quality_requirements, :standard)
  end

  defp extract_latency_requirements(context) do
    Map.get(context, :max_latency_ms, 5000)
  end

  defp extract_cost_constraints(context) do
    Map.get(context, :max_cost, 1.0)
  end

  defp extract_special_requirements(context) do
    Map.get(context, :special_requirements, [])
  end

  defp analyze_domain_specificity(context, evaluators) do
    # Simplified domain analysis
    content = context[:content] || ""
    
    technical_terms = count_domain_specific_terms(content)
    
    cond do
      technical_terms > 10 -> :highly_specific
      technical_terms > 5 -> :moderately_specific
      technical_terms > 2 -> :somewhat_specific
      true -> :general
    end
  end

  defp analyze_interaction_patterns(context) do
    # Analyze expected interaction patterns
    %{
      expected_turns: Map.get(context, :expected_turns, 1),
      interaction_style: Map.get(context, :interaction_style, :single_shot),
      follow_up_likelihood: Map.get(context, :follow_up_likelihood, :low)
    }
  end

  # Model compatibility functions

  defp meets_complexity_requirements?(model, complexity_analysis) do
    model_capability = get_model_complexity_capability(model)
    required_capability = complexity_analysis.level
    
    capability_order = [:simple, :moderate, :complex, :highly_complex]
    model_index = Enum.find_index(capability_order, &(&1 == model_capability)) || 0
    required_index = Enum.find_index(capability_order, &(&1 == required_capability)) || 0
    
    model_index >= required_index
  end

  defp meets_context_requirements?(model, context_evaluation) do
    # Check context window
    context_window = model.config[:context_window] || 4096
    required_context = context_evaluation.context_size
    
    # Check capability support
    model_capabilities = model.capabilities || %{}
    supports_context_type = supports_context_type?(model_capabilities, context_evaluation.context_type)
    
    context_window >= required_context and supports_context_type
  end

  defp meets_constraints?(model, constraints) do
    # Check cost constraints
    cost_ok = check_cost_constraint(model, constraints)
    
    # Check latency constraints
    latency_ok = check_latency_constraint(model, constraints)
    
    # Check capability constraints
    capability_ok = check_capability_constraint(model, constraints)
    
    cost_ok and latency_ok and capability_ok
  end

  # Initialization functions

  defp initialize_selection_strategies(opts) do
    Enum.reduce(@selection_strategies, %{}, fn strategy, acc ->
      config = Keyword.get(opts, strategy, %{})
      Map.put(acc, strategy, config)
    end)
  end

  defp initialize_complexity_analyzers(_opts) do
    %{
      content_analyzer: %{enabled: true},
      structural_analyzer: %{enabled: true},
      semantic_analyzer: %{enabled: true}
    }
  end

  defp initialize_context_evaluators(_opts) do
    %{
      type_classifier: %{enabled: true},
      size_analyzer: %{enabled: true},
      requirements_extractor: %{enabled: true}
    }
  end

  defp initialize_model_profiles(_opts) do
    %{}
  end

  defp initialize_performance_weights(opts) do
    %{
      complexity: Keyword.get(opts, :complexity_weight, 0.3),
      context: Keyword.get(opts, :context_weight, 0.25),
      performance: Keyword.get(opts, :performance_weight, 0.25),
      cost: Keyword.get(opts, :cost_weight, 0.2)
    }
  end

  defp initialize_selection_metrics do
    %{
      total_selections: 0,
      selections_by_strategy: %{},
      selections_by_complexity: %{},
      avg_selection_time: 0,
      selection_accuracy: 0
    }
  end

  # Utility and helper functions (simplified implementations)

  defp enhance_selection_result(selected_model, complexity_analysis, context_evaluation, strategy) do
    %{
      selected_model: selected_model.id,
      model_config: selected_model.config,
      selection_strategy: strategy,
      complexity_analysis: complexity_analysis,
      context_evaluation: context_evaluation,
      selection_confidence: calculate_selection_confidence(selected_model, complexity_analysis, context_evaluation),
      estimated_performance: estimate_task_performance(selected_model, complexity_analysis, context_evaluation),
      selection_timestamp: System.monotonic_time(:millisecond)
    }
  end

  defp update_selection_metrics(metrics, selection_result, selection_time) do
    new_total = metrics.total_selections + 1
    new_avg_time = (metrics.avg_selection_time * metrics.total_selections + selection_time) / new_total
    
    strategy = selection_result.selection_strategy
    new_strategy_counts = Map.update(metrics.selections_by_strategy, strategy, 1, &(&1 + 1))
    
    complexity = selection_result.complexity_analysis.level
    new_complexity_counts = Map.update(metrics.selections_by_complexity, complexity, 1, &(&1 + 1))
    
    %{metrics |
      total_selections: new_total,
      avg_selection_time: new_avg_time,
      selections_by_strategy: new_strategy_counts,
      selections_by_complexity: new_complexity_counts
    }
  end

  defp update_selection_history(history, selection_result) do
    new_entry = %{
      timestamp: System.monotonic_time(:millisecond),
      selected_model: selection_result.selected_model,
      strategy: selection_result.selection_strategy,
      complexity_level: selection_result.complexity_analysis.level,
      context_type: selection_result.context_evaluation.context_type
    }
    
    [new_entry | Enum.take(history, 99)]  # Keep last 100 selections
  end

  defp update_model_profile(profile, task_type, performance_data) do
    current_task_data = Map.get(profile, task_type, %{})
    
    updated_task_data = %{
      avg_performance: average_performance(current_task_data[:avg_performance], performance_data[:performance]),
      avg_latency: average_performance(current_task_data[:avg_latency], performance_data[:latency]),
      success_rate: average_performance(current_task_data[:success_rate], performance_data[:success] && 1.0 || 0.0),
      total_requests: (current_task_data[:total_requests] || 0) + 1,
      last_updated: System.monotonic_time(:millisecond)
    }
    
    Map.put(profile, task_type, updated_task_data)
  end

  defp enhance_selection_metrics(metrics, state) do
    success_rate = if metrics.total_selections > 0 do
      # Simplified success rate calculation
      0.85
    else
      0.0
    end
    
    Map.merge(metrics, %{
      success_rate: success_rate,
      active_strategies: map_size(state.selection_strategies),
      model_profiles_count: map_size(state.model_profiles)
    })
  end

  # Simplified helper implementations
  defp analyze_code_complexity(content), do: min(1.0, length(Regex.scan(~r/def |class |if |for |while /, content)) / 20.0)
  defp calculate_technical_density(content), do: min(1.0, length(Regex.scan(~r/\b[A-Z][a-zA-Z]*[A-Z][a-zA-Z]*\b/, content)) / 50.0)
  defp count_domain_specific_terms(content), do: length(Regex.scan(~r/\b[a-z]+[A-Z][a-z]*\b/, content))
  defp count_abstract_concepts(content), do: length(Regex.scan(~r/\b(concept|abstract|theory|principle)\b/i, content))
  defp count_reasoning_indicators(content), do: length(Regex.scan(~r/\b(because|therefore|thus|hence|since)\b/i, content))
  defp determine_task_type(task), do: :general
  defp get_model_capability_score(_capabilities, level), do: case level do
    :simple -> 0.9
    :moderate -> 0.8
    :complex -> 0.7
    :highly_complex -> 0.6
  end
  defp get_performance_adjustment(_profile, _level), do: 0.8
  defp calculate_context_window_score(_model, _analysis), do: 0.8
  defp calculate_type_compatibility_score(_capabilities, _type), do: 0.8
  defp calculate_size_handling_score(_model, _size), do: 0.8
  defp calculate_requirements_support_score(_model, _requirements), do: 0.8
  defp calculate_latency_compatibility(_model, _requirements), do: 0.8
  defp calculate_quality_alignment(_model, _requirements), do: 0.8
  defp estimate_token_usage(_complexity, _context), do: 1000
  defp get_model_complexity_capability(_model), do: :complex
  defp supports_context_type?(_capabilities, _type), do: true
  defp check_cost_constraint(_model, _constraints), do: true
  defp check_latency_constraint(_model, _constraints), do: true
  defp check_capability_constraint(_model, _constraints), do: true
  defp calculate_selection_confidence(_model, _complexity, _context), do: 0.85
  defp estimate_task_performance(_model, _complexity, _context), do: 0.8
  defp calculate_recommendation_confidence(_model, _strategy, _state), do: 0.8
  defp generate_selection_reasoning(_model, strategy, _complexity, _context) do
    "Selected based on #{strategy} strategy for optimal performance"
  end
  defp average_performance(nil, new_value), do: new_value
  defp average_performance(current, new_value), do: (current + new_value) / 2
end