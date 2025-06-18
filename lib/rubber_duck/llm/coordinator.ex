defmodule RubberDuck.LLM.Coordinator do
  @moduledoc """
  Multi-LLM coordination with capability-based model selection.
  Orchestrates task routing, model ensemble processing, and intelligent
  model selection across different LLM providers for optimal performance.
  """
  use GenServer
  require Logger

  alias RubberDuck.LLM.{TaskRouter, Ensemble, ModelSelector}

  defstruct [
    :available_models,
    :model_capabilities,
    :performance_metrics,
    :cost_tracker,
    :routing_strategy,
    :ensemble_config,
    :fallback_chains,
    :coordination_metrics
  ]

  @routing_strategies [:performance_first, :cost_optimized, :balanced, :quality_first, :ensemble]
  @model_types [:completion, :chat, :embedding, :code_generation, :reasoning, :multimodal]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Routes a task to the most appropriate LLM based on capabilities and context.
  """
  def route_task(task, context \\ %{}, opts \\ []) do
    GenServer.call(__MODULE__, {:route_task, task, context, opts})
  end

  @doc """
  Processes a task using ensemble of multiple LLMs.
  """
  def ensemble_process(task, context \\ %{}, opts \\ []) do
    GenServer.call(__MODULE__, {:ensemble_process, task, context, opts})
  end

  @doc """
  Selects the best model for a given task type and complexity.
  """
  def select_model(task_type, complexity_score, context \\ %{}) do
    GenServer.call(__MODULE__, {:select_model, task_type, complexity_score, context})
  end

  @doc """
  Updates model performance metrics based on execution results.
  """
  def update_performance_metrics(model_id, task_type, metrics) do
    GenServer.cast(__MODULE__, {:update_metrics, model_id, task_type, metrics})
  end

  @doc """
  Gets available models and their capabilities.
  """
  def get_available_models do
    GenServer.call(__MODULE__, :get_available_models)
  end

  @doc """
  Updates routing strategy and configuration.
  """
  def update_routing_strategy(strategy, config \\ %{}) do
    GenServer.call(__MODULE__, {:update_strategy, strategy, config})
  end

  @doc """
  Gets coordination metrics and performance statistics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Registers a new LLM model with its capabilities.
  """
  def register_model(model_config) do
    GenServer.call(__MODULE__, {:register_model, model_config})
  end

  @doc """
  Removes a model from available models (maintenance, failures, etc.).
  """
  def deregister_model(model_id) do
    GenServer.call(__MODULE__, {:deregister_model, model_id})
  end

  @impl true
  def init(opts) do
    Logger.info("Starting LLM Coordinator with capability-based routing")
    
    state = %__MODULE__{
      available_models: initialize_models(opts),
      model_capabilities: %{},
      performance_metrics: %{},
      cost_tracker: initialize_cost_tracker(),
      routing_strategy: Keyword.get(opts, :routing_strategy, :balanced),
      ensemble_config: initialize_ensemble_config(opts),
      fallback_chains: initialize_fallback_chains(opts),
      coordination_metrics: initialize_coordination_metrics()
    }
    
    # Initialize model capabilities
    initial_state = populate_model_capabilities(state)
    
    {:ok, initial_state}
  end

  @impl true
  def handle_call({:route_task, task, context, opts}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    case perform_task_routing(task, context, opts, state) do
      {:ok, routing_result} ->
        end_time = System.monotonic_time(:microsecond)
        routing_time = end_time - start_time
        
        new_metrics = update_routing_metrics(state.coordination_metrics, routing_time, :success)
        new_state = %{state | coordination_metrics: new_metrics}
        
        {:reply, {:ok, routing_result}, new_state}
      
      {:error, reason} ->
        new_metrics = update_routing_metrics(state.coordination_metrics, 0, :error)
        new_state = %{state | coordination_metrics: new_metrics}
        
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call({:ensemble_process, task, context, opts}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    case perform_ensemble_processing(task, context, opts, state) do
      {:ok, ensemble_result} ->
        end_time = System.monotonic_time(:microsecond)
        processing_time = end_time - start_time
        
        new_metrics = update_ensemble_metrics(state.coordination_metrics, processing_time, :success)
        new_state = %{state | coordination_metrics: new_metrics}
        
        {:reply, {:ok, ensemble_result}, new_state}
      
      {:error, reason} ->
        new_metrics = update_ensemble_metrics(state.coordination_metrics, 0, :error)
        new_state = %{state | coordination_metrics: new_metrics}
        
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call({:select_model, task_type, complexity_score, context}, _from, state) do
    case perform_model_selection(task_type, complexity_score, context, state) do
      {:ok, selected_model} ->
        {:reply, {:ok, selected_model}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_available_models, _from, state) do
    models_info = Enum.map(state.available_models, fn {model_id, model_config} ->
      capabilities = Map.get(state.model_capabilities, model_id, %{})
      performance = Map.get(state.performance_metrics, model_id, %{})
      
      %{
        id: model_id,
        config: model_config,
        capabilities: capabilities,
        performance: performance,
        status: determine_model_status(model_id, state)
      }
    end)
    
    {:reply, {:ok, models_info}, state}
  end

  @impl true
  def handle_call({:update_strategy, strategy, config}, _from, state) do
    if strategy in @routing_strategies do
      new_ensemble_config = Map.merge(state.ensemble_config, config)
      new_state = %{state | 
        routing_strategy: strategy,
        ensemble_config: new_ensemble_config
      }
      
      {:reply, {:ok, :strategy_updated}, new_state}
    else
      {:reply, {:error, :invalid_strategy}, state}
    end
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    enhanced_metrics = enhance_coordination_metrics(state.coordination_metrics, state)
    {:reply, enhanced_metrics, state}
  end

  @impl true
  def handle_call({:register_model, model_config}, _from, state) do
    model_id = model_config.id
    
    case validate_model_config(model_config) do
      :ok ->
        new_available_models = Map.put(state.available_models, model_id, model_config)
        new_capabilities = Map.put(state.model_capabilities, model_id, 
          extract_model_capabilities(model_config))
        
        new_state = %{state |
          available_models: new_available_models,
          model_capabilities: new_capabilities
        }
        
        Logger.info("Registered LLM model: #{model_id}")
        {:reply, {:ok, :model_registered}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:deregister_model, model_id}, _from, state) do
    new_available_models = Map.delete(state.available_models, model_id)
    new_capabilities = Map.delete(state.model_capabilities, model_id)
    new_performance_metrics = Map.delete(state.performance_metrics, model_id)
    
    new_state = %{state |
      available_models: new_available_models,
      model_capabilities: new_capabilities,
      performance_metrics: new_performance_metrics
    }
    
    Logger.info("Deregistered LLM model: #{model_id}")
    {:reply, {:ok, :model_deregistered}, new_state}
  end

  @impl true
  def handle_cast({:update_metrics, model_id, task_type, metrics}, state) do
    current_metrics = Map.get(state.performance_metrics, model_id, %{})
    task_metrics = Map.get(current_metrics, task_type, %{})
    
    updated_task_metrics = merge_performance_metrics(task_metrics, metrics)
    updated_model_metrics = Map.put(current_metrics, task_type, updated_task_metrics)
    new_performance_metrics = Map.put(state.performance_metrics, model_id, updated_model_metrics)
    
    # Update cost tracking
    new_cost_tracker = update_cost_tracking(state.cost_tracker, model_id, metrics)
    
    new_state = %{state |
      performance_metrics: new_performance_metrics,
      cost_tracker: new_cost_tracker
    }
    
    {:noreply, new_state}
  end

  # Private functions

  defp perform_task_routing(task, context, opts, state) do
    # Analyze task requirements
    task_analysis = analyze_task_requirements(task, context)
    
    # Apply routing strategy
    case state.routing_strategy do
      :performance_first ->
        route_by_performance(task_analysis, state)
      
      :cost_optimized ->
        route_by_cost(task_analysis, state)
      
      :balanced ->
        route_by_balanced_score(task_analysis, state)
      
      :quality_first ->
        route_by_quality(task_analysis, state)
      
      :ensemble ->
        route_to_ensemble(task_analysis, state)
    end
  end

  defp perform_ensemble_processing(task, context, opts, state) do
    # Select ensemble models based on task requirements
    task_analysis = analyze_task_requirements(task, context)
    ensemble_models = select_ensemble_models(task_analysis, state)
    
    case ensemble_models do
      [] ->
        {:error, :no_suitable_models}
      
      models ->
        # Process with ensemble
        ensemble_config = Map.merge(state.ensemble_config, Map.new(opts))
        Ensemble.process_with_models(task, models, ensemble_config)
    end
  end

  defp perform_model_selection(task_type, complexity_score, context, state) do
    # Filter models by task type capability
    suitable_models = filter_models_by_capability(state.available_models, 
      state.model_capabilities, task_type)
    
    case suitable_models do
      [] ->
        {:error, :no_suitable_models}
      
      models ->
        # Score models based on complexity and context
        scored_models = score_models_for_task(models, task_type, complexity_score, 
          context, state)
        
        # Select best model
        best_model = select_best_model(scored_models, state.routing_strategy)
        {:ok, best_model}
    end
  end

  defp analyze_task_requirements(task, context) do
    %{
      task_type: determine_task_type(task),
      complexity_score: calculate_complexity_score(task, context),
      context_size: calculate_context_size(context),
      quality_requirements: extract_quality_requirements(context),
      latency_requirements: extract_latency_requirements(context),
      cost_constraints: extract_cost_constraints(context),
      special_capabilities: extract_special_capabilities(task, context)
    }
  end

  defp route_by_performance(task_analysis, state) do
    suitable_models = filter_models_by_capability(state.available_models,
      state.model_capabilities, task_analysis.task_type)
    
    # Score by performance metrics
    scored_models = Enum.map(suitable_models, fn {model_id, model_config} ->
      performance = get_model_performance(model_id, task_analysis.task_type, state)
      score = calculate_performance_score(performance, task_analysis)
      {model_id, model_config, score}
    end)
    
    case Enum.max_by(scored_models, fn {_id, _config, score} -> score end, fn -> nil end) do
      nil -> {:error, :no_suitable_models}
      {model_id, model_config, _score} ->
        {:ok, %{
          selected_model: model_id,
          model_config: model_config,
          routing_reason: :performance_optimized,
          task_analysis: task_analysis
        }}
    end
  end

  defp route_by_cost(task_analysis, state) do
    suitable_models = filter_models_by_capability(state.available_models,
      state.model_capabilities, task_analysis.task_type)
    
    # Score by cost efficiency
    scored_models = Enum.map(suitable_models, fn {model_id, model_config} ->
      cost_metrics = get_model_cost_metrics(model_id, state)
      score = calculate_cost_efficiency_score(cost_metrics, task_analysis)
      {model_id, model_config, score}
    end)
    
    case Enum.max_by(scored_models, fn {_id, _config, score} -> score end, fn -> nil end) do
      nil -> {:error, :no_suitable_models}
      {model_id, model_config, _score} ->
        {:ok, %{
          selected_model: model_id,
          model_config: model_config,
          routing_reason: :cost_optimized,
          task_analysis: task_analysis
        }}
    end
  end

  defp route_by_balanced_score(task_analysis, state) do
    suitable_models = filter_models_by_capability(state.available_models,
      state.model_capabilities, task_analysis.task_type)
    
    # Calculate balanced score (performance + cost + quality)
    scored_models = Enum.map(suitable_models, fn {model_id, model_config} ->
      performance = get_model_performance(model_id, task_analysis.task_type, state)
      cost_metrics = get_model_cost_metrics(model_id, state)
      quality_metrics = get_model_quality_metrics(model_id, task_analysis.task_type, state)
      
      score = calculate_balanced_score(performance, cost_metrics, quality_metrics, task_analysis)
      {model_id, model_config, score}
    end)
    
    case Enum.max_by(scored_models, fn {_id, _config, score} -> score end, fn -> nil end) do
      nil -> {:error, :no_suitable_models}
      {model_id, model_config, _score} ->
        {:ok, %{
          selected_model: model_id,
          model_config: model_config,
          routing_reason: :balanced_optimization,
          task_analysis: task_analysis
        }}
    end
  end

  defp route_by_quality(task_analysis, state) do
    suitable_models = filter_models_by_capability(state.available_models,
      state.model_capabilities, task_analysis.task_type)
    
    # Score by quality metrics
    scored_models = Enum.map(suitable_models, fn {model_id, model_config} ->
      quality_metrics = get_model_quality_metrics(model_id, task_analysis.task_type, state)
      score = calculate_quality_score(quality_metrics, task_analysis)
      {model_id, model_config, score}
    end)
    
    case Enum.max_by(scored_models, fn {_id, _config, score} -> score end, fn -> nil end) do
      nil -> {:error, :no_suitable_models}
      {model_id, model_config, _score} ->
        {:ok, %{
          selected_model: model_id,
          model_config: model_config,
          routing_reason: :quality_optimized,
          task_analysis: task_analysis
        }}
    end
  end

  defp route_to_ensemble(task_analysis, state) do
    ensemble_models = select_ensemble_models(task_analysis, state)
    
    case ensemble_models do
      [] -> {:error, :no_suitable_models}
      models ->
        {:ok, %{
          ensemble_models: models,
          routing_reason: :ensemble_processing,
          task_analysis: task_analysis
        }}
    end
  end

  defp select_ensemble_models(task_analysis, state) do
    suitable_models = filter_models_by_capability(state.available_models,
      state.model_capabilities, task_analysis.task_type)
    
    # Select diverse models for ensemble
    ensemble_size = min(3, length(suitable_models))
    
    suitable_models
    |> Enum.map(fn {model_id, model_config} ->
      diversity_score = calculate_model_diversity_score(model_id, model_config, state)
      performance = get_model_performance(model_id, task_analysis.task_type, state)
      {model_id, model_config, diversity_score + performance[:avg_score] || 0.5}
    end)
    |> Enum.sort_by(fn {_id, _config, score} -> score end, :desc)
    |> Enum.take(ensemble_size)
    |> Enum.map(fn {model_id, model_config, _score} -> {model_id, model_config} end)
  end

  defp filter_models_by_capability(available_models, model_capabilities, task_type) do
    Enum.filter(available_models, fn {model_id, _model_config} ->
      capabilities = Map.get(model_capabilities, model_id, %{})
      supports_task_type?(capabilities, task_type)
    end)
  end

  defp supports_task_type?(capabilities, task_type) do
    supported_types = Map.get(capabilities, :supported_task_types, [])
    task_type in supported_types
  end

  defp score_models_for_task(models, task_type, complexity_score, context, state) do
    Enum.map(models, fn {model_id, model_config} ->
      performance = get_model_performance(model_id, task_type, state)
      cost_metrics = get_model_cost_metrics(model_id, state)
      
      # Calculate composite score
      performance_score = calculate_performance_score(performance, 
        %{complexity_score: complexity_score})
      cost_score = calculate_cost_efficiency_score(cost_metrics, 
        %{complexity_score: complexity_score})
      
      composite_score = performance_score * 0.6 + cost_score * 0.4
      
      {model_id, model_config, composite_score}
    end)
  end

  defp select_best_model(scored_models, routing_strategy) do
    case routing_strategy do
      :performance_first ->
        Enum.max_by(scored_models, fn {_id, _config, score} -> score end)
      
      :cost_optimized ->
        # Prefer cost efficiency in scoring
        Enum.max_by(scored_models, fn {_id, _config, score} -> score end)
      
      _ ->
        Enum.max_by(scored_models, fn {_id, _config, score} -> score end)
    end
  end

  # Helper functions for initialization and utilities

  defp initialize_models(opts) do
    default_models = %{
      "gpt-4" => %{
        id: "gpt-4",
        provider: :openai,
        model_type: :chat,
        context_window: 8192,
        cost_per_token: 0.00003,
        capabilities: [:reasoning, :code_generation, :general_knowledge]
      },
      "gpt-3.5-turbo" => %{
        id: "gpt-3.5-turbo", 
        provider: :openai,
        model_type: :chat,
        context_window: 4096,
        cost_per_token: 0.000002,
        capabilities: [:general_knowledge, :code_generation]
      },
      "claude-3-opus" => %{
        id: "claude-3-opus",
        provider: :anthropic,
        model_type: :chat,
        context_window: 200000,
        cost_per_token: 0.000015,
        capabilities: [:reasoning, :analysis, :code_generation]
      }
    }
    
    custom_models = Keyword.get(opts, :models, %{})
    Map.merge(default_models, custom_models)
  end

  defp initialize_cost_tracker do
    %{
      total_cost: 0.0,
      costs_by_model: %{},
      costs_by_task_type: %{},
      daily_costs: %{},
      budget_limits: %{
        daily: 100.0,
        monthly: 2000.0
      }
    }
  end

  defp initialize_ensemble_config(opts) do
    %{
      voting_strategy: Keyword.get(opts, :voting_strategy, :majority),
      confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.7),
      max_ensemble_size: Keyword.get(opts, :max_ensemble_size, 3),
      disagreement_resolution: Keyword.get(opts, :disagreement_resolution, :weighted_average)
    }
  end

  defp initialize_fallback_chains(_opts) do
    %{
      "gpt-4" => ["claude-3-opus", "gpt-3.5-turbo"],
      "claude-3-opus" => ["gpt-4", "gpt-3.5-turbo"],
      "gpt-3.5-turbo" => ["gpt-4", "claude-3-opus"]
    }
  end

  defp initialize_coordination_metrics do
    %{
      total_tasks_routed: 0,
      ensemble_tasks_processed: 0,
      avg_routing_time: 0,
      avg_ensemble_time: 0,
      routing_successes: 0,
      routing_failures: 0,
      strategy_effectiveness: %{}
    }
  end

  defp populate_model_capabilities(state) do
    capabilities = Enum.reduce(state.available_models, %{}, fn {model_id, model_config}, acc ->
      model_capabilities = extract_model_capabilities(model_config)
      Map.put(acc, model_id, model_capabilities)
    end)
    
    %{state | model_capabilities: capabilities}
  end

  defp extract_model_capabilities(model_config) do
    %{
      supported_task_types: determine_supported_task_types(model_config),
      context_window: Map.get(model_config, :context_window, 4096),
      max_tokens: Map.get(model_config, :max_tokens, 2048),
      supports_streaming: Map.get(model_config, :supports_streaming, false),
      supports_function_calling: Map.get(model_config, :supports_function_calling, false),
      multimodal: Map.get(model_config, :multimodal, false),
      languages: Map.get(model_config, :languages, ["en"])
    }
  end

  defp determine_supported_task_types(model_config) do
    capabilities = Map.get(model_config, :capabilities, [])
    
    base_types = [:completion, :chat]
    
    additional_types = Enum.flat_map(capabilities, fn capability ->
      case capability do
        :code_generation -> [:code_generation]
        :reasoning -> [:reasoning]
        :analysis -> [:analysis]
        :summarization -> [:summarization]
        :translation -> [:translation]
        :embedding -> [:embedding]
        _ -> []
      end
    end)
    
    base_types ++ additional_types
  end

  # Helper functions for task analysis and scoring

  defp determine_task_type(task) do
    content = task[:content] || task[:prompt] || ""
    
    cond do
      String.contains?(content, ["code", "function", "class", "programming"]) -> :code_generation
      String.contains?(content, ["analyze", "analysis", "examine"]) -> :analysis
      String.contains?(content, ["summarize", "summary"]) -> :summarization
      String.contains?(content, ["translate", "translation"]) -> :translation
      String.contains?(content, ["reason", "think", "explain"]) -> :reasoning
      true -> :general
    end
  end

  defp calculate_complexity_score(task, context) do
    content = task[:content] || task[:prompt] || ""
    context_size = map_size(context)
    
    base_score = String.length(content) / 1000.0
    context_score = context_size / 10.0
    
    min(1.0, base_score + context_score)
  end

  defp calculate_context_size(context) do
    content = context[:content] || ""
    String.length(content)
  end

  defp extract_quality_requirements(context) do
    Map.get(context, :quality_requirements, :standard)
  end

  defp extract_latency_requirements(context) do
    Map.get(context, :max_latency_ms, 30000)
  end

  defp extract_cost_constraints(context) do
    Map.get(context, :max_cost, 1.0)
  end

  defp extract_special_capabilities(task, context) do
    []  # Simplified - would analyze for special requirements
  end

  defp get_model_performance(model_id, task_type, state) do
    metrics = get_in(state.performance_metrics, [model_id, task_type])
    metrics || %{avg_score: 0.5, avg_latency: 5000, success_rate: 0.9}
  end

  defp get_model_cost_metrics(model_id, state) do
    Map.get(state.cost_tracker.costs_by_model, model_id, %{avg_cost: 0.01, cost_per_token: 0.00001})
  end

  defp get_model_quality_metrics(model_id, task_type, state) do
    performance = get_model_performance(model_id, task_type, state)
    %{quality_score: performance[:avg_score] || 0.5}
  end

  defp calculate_performance_score(performance, task_analysis) do
    base_score = performance[:avg_score] || 0.5
    latency_penalty = min(0.2, (performance[:avg_latency] || 5000) / 25000)
    success_bonus = (performance[:success_rate] || 0.9) * 0.2
    
    base_score - latency_penalty + success_bonus
  end

  defp calculate_cost_efficiency_score(cost_metrics, task_analysis) do
    cost_per_token = cost_metrics[:cost_per_token] || 0.00001
    complexity_factor = task_analysis[:complexity_score] || 0.5
    
    # Lower cost = higher score
    efficiency = 1.0 / (cost_per_token * 100000 * complexity_factor + 1)
    min(1.0, efficiency)
  end

  defp calculate_balanced_score(performance, cost_metrics, quality_metrics, task_analysis) do
    performance_score = calculate_performance_score(performance, task_analysis)
    cost_score = calculate_cost_efficiency_score(cost_metrics, task_analysis)
    quality_score = quality_metrics[:quality_score] || 0.5
    
    # Weighted combination
    performance_score * 0.4 + cost_score * 0.3 + quality_score * 0.3
  end

  defp calculate_quality_score(quality_metrics, _task_analysis) do
    quality_metrics[:quality_score] || 0.5
  end

  defp calculate_model_diversity_score(_model_id, _model_config, _state) do
    # Simplified diversity calculation
    :rand.uniform()
  end

  defp determine_model_status(_model_id, _state) do
    :available  # Simplified - would check actual model health
  end

  defp validate_model_config(model_config) do
    required_fields = [:id, :provider, :model_type]
    
    case Enum.all?(required_fields, &Map.has_key?(model_config, &1)) do
      true -> :ok
      false -> {:error, :invalid_model_config}
    end
  end

  defp merge_performance_metrics(current_metrics, new_metrics) do
    %{
      avg_score: average_metric(current_metrics[:avg_score], new_metrics[:score]),
      avg_latency: average_metric(current_metrics[:avg_latency], new_metrics[:latency]),
      success_rate: average_metric(current_metrics[:success_rate], new_metrics[:success] && 1.0 || 0.0),
      total_requests: (current_metrics[:total_requests] || 0) + 1,
      last_updated: System.monotonic_time(:millisecond)
    }
  end

  defp average_metric(nil, new_value), do: new_value
  defp average_metric(current, new_value), do: (current + new_value) / 2

  defp update_cost_tracking(cost_tracker, model_id, metrics) do
    cost = metrics[:cost] || 0.0
    
    new_total = cost_tracker.total_cost + cost
    new_model_costs = Map.update(cost_tracker.costs_by_model, model_id, cost, &(&1 + cost))
    
    %{cost_tracker |
      total_cost: new_total,
      costs_by_model: new_model_costs
    }
  end

  defp update_routing_metrics(metrics, routing_time, result) do
    new_total = metrics.total_tasks_routed + 1
    new_avg_time = (metrics.avg_routing_time * metrics.total_tasks_routed + routing_time) / new_total
    
    case result do
      :success ->
        %{metrics |
          total_tasks_routed: new_total,
          avg_routing_time: new_avg_time,
          routing_successes: metrics.routing_successes + 1
        }
      
      :error ->
        %{metrics |
          total_tasks_routed: new_total,
          avg_routing_time: new_avg_time,
          routing_failures: metrics.routing_failures + 1
        }
    end
  end

  defp update_ensemble_metrics(metrics, processing_time, result) do
    case result do
      :success ->
        new_total = metrics.ensemble_tasks_processed + 1
        new_avg_time = (metrics.avg_ensemble_time * (new_total - 1) + processing_time) / new_total
        
        %{metrics |
          ensemble_tasks_processed: new_total,
          avg_ensemble_time: new_avg_time
        }
      
      :error ->
        metrics
    end
  end

  defp enhance_coordination_metrics(metrics, state) do
    success_rate = if metrics.total_tasks_routed > 0 do
      metrics.routing_successes / metrics.total_tasks_routed
    else
      0.0
    end
    
    Map.merge(metrics, %{
      success_rate: success_rate,
      available_models_count: map_size(state.available_models),
      total_cost: state.cost_tracker.total_cost,
      current_strategy: state.routing_strategy
    })
  end
end