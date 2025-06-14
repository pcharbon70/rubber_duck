defmodule RubberDuck.LLM.CostOptimizer do
  @moduledoc """
  Cost optimization algorithms and budget management for LLM operations.
  Implements sophisticated cost tracking, budget enforcement, and optimization
  strategies to minimize costs while maintaining quality and performance targets.
  """
  use GenServer
  require Logger

  alias RubberDuck.LLM.{Coordinator, TaskRouter, ModelSelector}

  defstruct [
    :cost_tracking,
    :budget_limits,
    :optimization_strategies,
    :cost_models,
    :usage_analytics,
    :budget_alerts,
    :cost_metrics
  ]

  @optimization_strategies [:cost_first, :balanced, :quality_constrained, :adaptive, :budget_aware]
  @budget_periods [:hourly, :daily, :weekly, :monthly]
  @alert_thresholds [0.5, 0.75, 0.9, 0.95]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Optimizes model selection for cost while meeting quality constraints.
  """
  def optimize_model_selection(task, context, quality_threshold \\ 0.8) do
    GenServer.call(__MODULE__, {:optimize_selection, task, context, quality_threshold})
  end

  @doc """
  Tracks cost for a completed LLM operation.
  """
  def track_operation_cost(model_id, operation_data, cost_data) do
    GenServer.cast(__MODULE__, {:track_cost, model_id, operation_data, cost_data})
  end

  @doc """
  Checks if an operation is within budget constraints.
  """
  def check_budget_compliance(estimated_cost, operation_type \\ :general) do
    GenServer.call(__MODULE__, {:check_budget, estimated_cost, operation_type})
  end

  @doc """
  Gets cost optimization recommendations for a task.
  """
  def get_cost_recommendations(task, context, constraints \\ %{}) do
    GenServer.call(__MODULE__, {:get_recommendations, task, context, constraints})
  end

  @doc """
  Updates budget limits and thresholds.
  """
  def update_budget_limits(new_limits) do
    GenServer.call(__MODULE__, {:update_budget, new_limits})
  end

  @doc """
  Gets current cost metrics and budget status.
  """
  def get_cost_metrics do
    GenServer.call(__MODULE__, :get_cost_metrics)
  end

  @doc """
  Analyzes cost trends and provides optimization insights.
  """
  def analyze_cost_trends(period \\ :daily) do
    GenServer.call(__MODULE__, {:analyze_trends, period})
  end

  @doc """
  Sets up cost alerts and notifications.
  """
  def configure_cost_alerts(alert_config) do
    GenServer.call(__MODULE__, {:configure_alerts, alert_config})
  end

  @doc """
  Predicts cost for a planned operation.
  """
  def predict_operation_cost(task, context, model_id \\ nil) do
    GenServer.call(__MODULE__, {:predict_cost, task, context, model_id})
  end

  @impl true
  def init(opts) do
    Logger.info("Starting LLM Cost Optimizer with budget management")
    
    state = %__MODULE__{
      cost_tracking: initialize_cost_tracking(opts),
      budget_limits: initialize_budget_limits(opts),
      optimization_strategies: initialize_optimization_strategies(opts),
      cost_models: initialize_cost_models(opts),
      usage_analytics: initialize_usage_analytics(),
      budget_alerts: initialize_budget_alerts(opts),
      cost_metrics: initialize_cost_metrics()
    }
    
    # Start periodic budget checking
    schedule_budget_check()
    
    {:ok, state}
  end

  @impl true
  def handle_call({:optimize_selection, task, context, quality_threshold}, _from, state) do
    case perform_cost_optimization(task, context, quality_threshold, state) do
      {:ok, optimization_result} ->
        {:reply, {:ok, optimization_result}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:check_budget, estimated_cost, operation_type}, _from, state) do
    budget_check = perform_budget_check(estimated_cost, operation_type, state)
    {:reply, budget_check, state}
  end

  @impl true
  def handle_call({:get_recommendations, task, context, constraints}, _from, state) do
    case generate_cost_recommendations(task, context, constraints, state) do
      {:ok, recommendations} ->
        {:reply, {:ok, recommendations}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_budget, new_limits}, _from, state) do
    case validate_budget_limits(new_limits) do
      :ok ->
        updated_limits = Map.merge(state.budget_limits, new_limits)
        new_state = %{state | budget_limits: updated_limits}
        {:reply, {:ok, :budget_updated}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_cost_metrics, _from, state) do
    enhanced_metrics = enhance_cost_metrics(state.cost_metrics, state)
    {:reply, enhanced_metrics, state}
  end

  @impl true
  def handle_call({:analyze_trends, period}, _from, state) do
    trend_analysis = perform_trend_analysis(period, state)
    {:reply, {:ok, trend_analysis}, state}
  end

  @impl true
  def handle_call({:configure_alerts, alert_config}, _from, state) do
    case validate_alert_config(alert_config) do
      :ok ->
        new_alerts = Map.merge(state.budget_alerts, alert_config)
        new_state = %{state | budget_alerts: new_alerts}
        {:reply, {:ok, :alerts_configured}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:predict_cost, task, context, model_id}, _from, state) do
    case predict_operation_cost_internal(task, context, model_id, state) do
      {:ok, cost_prediction} ->
        {:reply, {:ok, cost_prediction}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:track_cost, model_id, operation_data, cost_data}, state) do
    new_state = update_cost_tracking(state, model_id, operation_data, cost_data)
    
    # Check for budget alerts
    check_budget_alerts(new_state)
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:budget_check, state) do
    # Perform periodic budget analysis
    perform_periodic_budget_analysis(state)
    
    # Schedule next check
    schedule_budget_check()
    
    {:noreply, state}
  end

  # Private functions

  defp perform_cost_optimization(task, context, quality_threshold, state) do
    # Get available models with cost and performance data
    case get_models_with_cost_data(state) do
      [] ->
        {:error, :no_models_available}
      
      models_with_costs ->
        # Analyze task requirements
        task_analysis = analyze_task_for_cost_optimization(task, context)
        
        # Apply cost optimization strategy
        strategy = determine_optimization_strategy(task_analysis, quality_threshold, state)
        
        case apply_cost_optimization_strategy(models_with_costs, task_analysis, quality_threshold, strategy, state) do
          {:ok, optimized_selection} ->
            optimization_result = enhance_optimization_result(optimized_selection, strategy, task_analysis)
            {:ok, optimization_result}
          
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp perform_budget_check(estimated_cost, operation_type, state) do
    current_usage = calculate_current_usage(state)
    budget_limits = state.budget_limits
    
    # Check against different budget periods
    budget_checks = Enum.map(@budget_periods, fn period ->
      period_limit = Map.get(budget_limits, period, %{})
      operation_limit = Map.get(period_limit, operation_type, Map.get(period_limit, :total, :unlimited))
      current_period_usage = Map.get(current_usage, period, 0.0)
      
      compliance = check_period_budget_compliance(estimated_cost, current_period_usage, operation_limit)
      
      %{
        period: period,
        limit: operation_limit,
        current_usage: current_period_usage,
        estimated_total: current_period_usage + estimated_cost,
        compliance: compliance,
        remaining_budget: calculate_remaining_budget(operation_limit, current_period_usage)
      }
    end)
    
    overall_compliance = Enum.all?(budget_checks, &(&1.compliance == :compliant))
    
    %{
      overall_compliance: overall_compliance,
      budget_checks: budget_checks,
      estimated_cost: estimated_cost,
      operation_type: operation_type
    }
  end

  defp generate_cost_recommendations(task, context, constraints, state) do
    # Analyze task for cost optimization opportunities
    task_analysis = analyze_task_for_cost_optimization(task, context)
    
    # Get models with cost-performance data
    case get_models_with_cost_data(state) do
      [] ->
        {:error, :no_cost_data_available}
      
      models_with_costs ->
        # Generate recommendations for different strategies
        recommendations = Enum.map(@optimization_strategies, fn strategy ->
          generate_strategy_recommendation(models_with_costs, task_analysis, constraints, strategy, state)
        end)
        |> Enum.filter(&(&1 != nil))
        
        # Add optimization insights
        insights = generate_optimization_insights(task_analysis, models_with_costs, state)
        
        {:ok, %{recommendations: recommendations, insights: insights}}
    end
  end

  defp get_models_with_cost_data(state) do
    case Coordinator.get_available_models() do
      {:ok, models} ->
        Enum.map(models, fn model ->
          cost_data = get_model_cost_data(model.id, state)
          performance_data = get_model_performance_data(model.id, state)
          
          Map.merge(model, %{
            cost_data: cost_data,
            performance_data: performance_data
          })
        end)
        |> Enum.filter(fn model -> model.cost_data != nil end)
      
      {:error, _} ->
        []
    end
  end

  defp analyze_task_for_cost_optimization(task, context) do
    %{
      estimated_tokens: estimate_token_requirements(task, context),
      complexity_level: assess_task_complexity(task, context),
      quality_requirements: extract_quality_requirements(context),
      latency_requirements: extract_latency_requirements(context),
      task_type: classify_task_type(task),
      context_size: calculate_context_size(context),
      optimization_opportunities: identify_optimization_opportunities(task, context)
    }
  end

  defp determine_optimization_strategy(task_analysis, quality_threshold, state) do
    current_budget_pressure = calculate_budget_pressure(state)
    
    cond do
      current_budget_pressure > 0.9 -> :cost_first
      quality_threshold >= 0.9 -> :quality_constrained
      task_analysis.complexity_level == :high -> :balanced
      current_budget_pressure > 0.7 -> :budget_aware
      true -> :adaptive
    end
  end

  defp apply_cost_optimization_strategy(models, task_analysis, quality_threshold, strategy, state) do
    case strategy do
      :cost_first ->
        optimize_for_minimum_cost(models, task_analysis, quality_threshold, state)
      
      :balanced ->
        optimize_for_cost_performance_balance(models, task_analysis, quality_threshold, state)
      
      :quality_constrained ->
        optimize_for_quality_constrained_cost(models, task_analysis, quality_threshold, state)
      
      :adaptive ->
        optimize_with_adaptive_strategy(models, task_analysis, quality_threshold, state)
      
      :budget_aware ->
        optimize_for_budget_compliance(models, task_analysis, quality_threshold, state)
    end
  end

  defp optimize_for_minimum_cost(models, task_analysis, quality_threshold, state) do
    # Score models primarily by cost efficiency
    scored_models = Enum.map(models, fn model ->
      cost_score = calculate_cost_efficiency_score(model, task_analysis, state)
      quality_score = estimate_quality_score(model, task_analysis, state)
      
      # Only consider models meeting minimum quality threshold
      if quality_score >= quality_threshold do
        {model, cost_score}
      else
        {model, 0.0}
      end
    end)
    
    case Enum.max_by(scored_models, fn {_model, score} -> score end, fn -> nil end) do
      nil -> {:error, :no_qualifying_models}
      {selected_model, _score} -> {:ok, selected_model}
    end
  end

  defp optimize_for_cost_performance_balance(models, task_analysis, quality_threshold, state) do
    # Balance cost and performance with equal weighting
    scored_models = Enum.map(models, fn model ->
      cost_score = calculate_cost_efficiency_score(model, task_analysis, state)
      performance_score = estimate_performance_score(model, task_analysis, state)
      quality_score = estimate_quality_score(model, task_analysis, state)
      
      if quality_score >= quality_threshold do
        balanced_score = (cost_score + performance_score) / 2
        {model, balanced_score}
      else
        {model, 0.0}
      end
    end)
    
    case Enum.max_by(scored_models, fn {_model, score} -> score end, fn -> nil end) do
      nil -> {:error, :no_qualifying_models}
      {selected_model, _score} -> {:ok, selected_model}
    end
  end

  defp optimize_for_quality_constrained_cost(models, task_analysis, quality_threshold, state) do
    # Prioritize quality, then optimize for cost among qualifying models
    qualifying_models = Enum.filter(models, fn model ->
      quality_score = estimate_quality_score(model, task_analysis, state)
      quality_score >= quality_threshold
    end)
    
    case qualifying_models do
      [] -> {:error, :no_qualifying_models}
      models_list ->
        # Among qualifying models, select the most cost-efficient
        optimize_for_minimum_cost(models_list, task_analysis, quality_threshold, state)
    end
  end

  defp optimize_with_adaptive_strategy(models, task_analysis, quality_threshold, state) do
    # Adapt strategy based on current conditions
    budget_pressure = calculate_budget_pressure(state)
    
    cond do
      budget_pressure > 0.8 ->
        optimize_for_minimum_cost(models, task_analysis, quality_threshold, state)
      
      task_analysis.complexity_level == :high ->
        optimize_for_quality_constrained_cost(models, task_analysis, quality_threshold, state)
      
      true ->
        optimize_for_cost_performance_balance(models, task_analysis, quality_threshold, state)
    end
  end

  defp optimize_for_budget_compliance(models, task_analysis, quality_threshold, state) do
    # Ensure operations stay within budget while meeting quality requirements
    remaining_budget = calculate_remaining_budget_amount(state)
    
    # Filter models by budget compliance
    budget_compliant_models = Enum.filter(models, fn model ->
      estimated_cost = estimate_operation_cost(model, task_analysis, state)
      estimated_cost <= remaining_budget
    end)
    
    case budget_compliant_models do
      [] -> {:error, :insufficient_budget}
      models_list ->
        optimize_for_quality_constrained_cost(models_list, task_analysis, quality_threshold, state)
    end
  end

  defp generate_strategy_recommendation(models, task_analysis, constraints, strategy, state) do
    case apply_cost_optimization_strategy(models, task_analysis, 0.7, strategy, state) do
      {:ok, recommended_model} ->
        estimated_cost = estimate_operation_cost(recommended_model, task_analysis, state)
        estimated_quality = estimate_quality_score(recommended_model, task_analysis, state)
        
        %{
          strategy: strategy,
          recommended_model: recommended_model.id,
          estimated_cost: estimated_cost,
          estimated_quality: estimated_quality,
          cost_efficiency: calculate_cost_efficiency_score(recommended_model, task_analysis, state),
          reasoning: generate_strategy_reasoning(strategy, recommended_model, task_analysis)
        }
      
      {:error, _} ->
        nil
    end
  end

  defp generate_optimization_insights(task_analysis, models, state) do
    cost_range = calculate_cost_range(models, task_analysis, state)
    quality_range = calculate_quality_range(models, task_analysis, state)
    
    %{
      cost_savings_potential: calculate_cost_savings_potential(cost_range),
      quality_trade_offs: analyze_quality_trade_offs(quality_range),
      budget_impact: assess_budget_impact(cost_range, state),
      optimization_opportunities: suggest_optimization_opportunities(task_analysis, models, state)
    }
  end

  # Cost calculation and analysis functions

  defp calculate_cost_efficiency_score(model, task_analysis, state) do
    estimated_cost = estimate_operation_cost(model, task_analysis, state)
    estimated_performance = estimate_performance_score(model, task_analysis, state)
    
    # Cost efficiency = performance per unit cost
    if estimated_cost > 0 do
      estimated_performance / estimated_cost
    else
      estimated_performance
    end
  end

  defp estimate_operation_cost(model, task_analysis, state) do
    cost_per_token = get_model_cost_per_token(model, state)
    estimated_tokens = task_analysis.estimated_tokens
    
    base_cost = cost_per_token * estimated_tokens
    
    # Apply complexity multiplier
    complexity_multiplier = case task_analysis.complexity_level do
      :high -> 1.3
      :medium -> 1.1
      :low -> 1.0
    end
    
    base_cost * complexity_multiplier
  end

  defp estimate_quality_score(model, task_analysis, state) do
    # Get historical quality data for the model
    performance_data = model.performance_data || %{}
    task_type = task_analysis.task_type
    
    historical_quality = get_in(performance_data, [task_type, :avg_quality]) || 0.7
    
    # Adjust for task complexity
    complexity_adjustment = case task_analysis.complexity_level do
      :high -> -0.1
      :medium -> 0.0
      :low -> 0.1
    end
    
    max(0.0, min(1.0, historical_quality + complexity_adjustment))
  end

  defp estimate_performance_score(model, task_analysis, state) do
    performance_data = model.performance_data || %{}
    task_type = task_analysis.task_type
    
    historical_performance = get_in(performance_data, [task_type, :avg_performance]) || 0.7
    
    # Consider latency requirements
    latency_adjustment = if task_analysis.latency_requirements < 2000 do
      get_model_latency_score(model, state)
    else
      0.0
    end
    
    max(0.0, min(1.0, historical_performance + latency_adjustment))
  end

  # Budget and tracking functions

  defp update_cost_tracking(state, model_id, operation_data, cost_data) do
    current_tracking = state.cost_tracking
    timestamp = System.monotonic_time(:millisecond)
    
    # Update model-specific tracking
    model_tracking = Map.get(current_tracking.by_model, model_id, %{})
    updated_model_tracking = update_model_cost_tracking(model_tracking, operation_data, cost_data, timestamp)
    
    # Update overall tracking
    new_tracking = %{current_tracking |
      total_cost: current_tracking.total_cost + cost_data.total_cost,
      total_operations: current_tracking.total_operations + 1,
      by_model: Map.put(current_tracking.by_model, model_id, updated_model_tracking),
      recent_operations: add_recent_operation(current_tracking.recent_operations, model_id, operation_data, cost_data, timestamp)
    }
    
    # Update usage analytics
    new_analytics = update_usage_analytics(state.usage_analytics, model_id, operation_data, cost_data, timestamp)
    
    # Update cost metrics
    new_metrics = update_cost_metrics(state.cost_metrics, cost_data, timestamp)
    
    %{state |
      cost_tracking: new_tracking,
      usage_analytics: new_analytics,
      cost_metrics: new_metrics
    }
  end

  defp calculate_current_usage(state) do
    current_time = System.monotonic_time(:millisecond)
    
    Enum.reduce(@budget_periods, %{}, fn period, acc ->
      period_start = calculate_period_start(period, current_time)
      period_usage = calculate_period_usage(state.cost_tracking, period_start, current_time)
      Map.put(acc, period, period_usage)
    end)
  end

  defp check_period_budget_compliance(estimated_cost, current_usage, limit) do
    case limit do
      :unlimited -> :compliant
      limit_amount when is_number(limit_amount) ->
        if current_usage + estimated_cost <= limit_amount do
          :compliant
        else
          :exceeds_budget
        end
      _ -> :compliant
    end
  end

  defp calculate_remaining_budget(limit, current_usage) do
    case limit do
      :unlimited -> :unlimited
      limit_amount when is_number(limit_amount) -> max(0, limit_amount - current_usage)
      _ -> :unlimited
    end
  end

  defp calculate_budget_pressure(state) do
    current_usage = calculate_current_usage(state)
    budget_limits = state.budget_limits
    
    # Calculate pressure for daily budget (most restrictive typically)
    daily_usage = Map.get(current_usage, :daily, 0.0)
    daily_limit = get_in(budget_limits, [:daily, :total])
    
    case daily_limit do
      nil -> 0.0
      :unlimited -> 0.0
      limit when is_number(limit) -> min(1.0, daily_usage / limit)
      _ -> 0.0
    end
  end

  defp check_budget_alerts(state) do
    current_usage = calculate_current_usage(state)
    budget_limits = state.budget_limits
    alert_config = state.budget_alerts
    
    Enum.each(@budget_periods, fn period ->
      usage = Map.get(current_usage, period, 0.0)
      limit = get_in(budget_limits, [period, :total])
      
      if is_number(limit) and limit > 0 do
        usage_percentage = usage / limit
        
        Enum.each(@alert_thresholds, fn threshold ->
          if usage_percentage >= threshold and should_send_alert?(period, threshold, alert_config) do
            send_budget_alert(period, threshold, usage, limit, alert_config)
          end
        end)
      end
    end)
  end

  # Trend analysis and prediction

  defp perform_trend_analysis(period, state) do
    usage_data = get_usage_data_for_period(state.usage_analytics, period)
    
    %{
      period: period,
      total_cost: calculate_total_cost_for_period(usage_data),
      operation_count: calculate_operation_count_for_period(usage_data),
      avg_cost_per_operation: calculate_avg_cost_per_operation(usage_data),
      cost_trend: calculate_cost_trend(usage_data),
      top_cost_models: identify_top_cost_models(usage_data),
      optimization_opportunities: identify_trend_optimization_opportunities(usage_data),
      projected_cost: project_future_cost(usage_data, period)
    }
  end

  defp predict_operation_cost_internal(task, context, model_id, state) do
    task_analysis = analyze_task_for_cost_optimization(task, context)
    
    case model_id do
      nil ->
        # Predict costs for all available models
        case get_models_with_cost_data(state) do
          [] -> {:error, :no_models_available}
          models ->
            predictions = Enum.map(models, fn model ->
              cost = estimate_operation_cost(model, task_analysis, state)
              %{model_id: model.id, estimated_cost: cost}
            end)
            {:ok, %{predictions: predictions, task_analysis: task_analysis}}
        end
      
      specific_model_id ->
        # Predict cost for specific model
        case get_model_by_id(specific_model_id, state) do
          nil -> {:error, :model_not_found}
          model ->
            cost = estimate_operation_cost(model, task_analysis, state)
            {:ok, %{model_id: specific_model_id, estimated_cost: cost, task_analysis: task_analysis}}
        end
    end
  end

  # Initialization functions

  defp initialize_cost_tracking(opts) do
    %{
      total_cost: 0.0,
      total_operations: 0,
      by_model: %{},
      by_task_type: %{},
      recent_operations: [],
      start_time: System.monotonic_time(:millisecond)
    }
  end

  defp initialize_budget_limits(opts) do
    %{
      daily: %{total: Keyword.get(opts, :daily_budget, 100.0)},
      weekly: %{total: Keyword.get(opts, :weekly_budget, 500.0)},
      monthly: %{total: Keyword.get(opts, :monthly_budget, 2000.0)}
    }
  end

  defp initialize_optimization_strategies(opts) do
    Enum.reduce(@optimization_strategies, %{}, fn strategy, acc ->
      config = Keyword.get(opts, strategy, %{})
      Map.put(acc, strategy, config)
    end)
  end

  defp initialize_cost_models(opts) do
    %{
      token_costs: Keyword.get(opts, :token_costs, %{}),
      operation_costs: Keyword.get(opts, :operation_costs, %{}),
      model_multipliers: Keyword.get(opts, :model_multipliers, %{})
    }
  end

  defp initialize_usage_analytics do
    %{
      hourly_usage: %{},
      daily_usage: %{},
      model_usage: %{},
      task_type_usage: %{}
    }
  end

  defp initialize_budget_alerts(opts) do
    %{
      enabled: Keyword.get(opts, :alerts_enabled, true),
      email_alerts: Keyword.get(opts, :email_alerts, false),
      webhook_url: Keyword.get(opts, :webhook_url, nil),
      alert_cooldown: Keyword.get(opts, :alert_cooldown, 3600000)  # 1 hour
    }
  end

  defp initialize_cost_metrics do
    %{
      total_cost_tracked: 0.0,
      operations_tracked: 0,
      avg_cost_per_operation: 0.0,
      cost_savings_achieved: 0.0,
      budget_adherence_rate: 1.0
    }
  end

  # Helper functions

  defp schedule_budget_check do
    Process.send_after(self(), :budget_check, 300_000)  # Every 5 minutes
  end

  defp perform_periodic_budget_analysis(state) do
    # Log budget status and trigger alerts if needed
    current_usage = calculate_current_usage(state)
    Logger.info("Periodic budget check: #{inspect(current_usage)}")
  end

  defp enhance_optimization_result(selected_model, strategy, task_analysis) do
    %{
      selected_model: selected_model.id,
      optimization_strategy: strategy,
      estimated_cost: selected_model.cost_data.estimated_cost,
      estimated_quality: selected_model.performance_data.estimated_quality,
      task_analysis: task_analysis,
      optimization_timestamp: System.monotonic_time(:millisecond)
    }
  end

  defp enhance_cost_metrics(metrics, state) do
    current_usage = calculate_current_usage(state)
    
    Map.merge(metrics, %{
      current_daily_usage: Map.get(current_usage, :daily, 0.0),
      current_monthly_usage: Map.get(current_usage, :monthly, 0.0),
      budget_pressure: calculate_budget_pressure(state),
      models_tracked: map_size(state.cost_tracking.by_model)
    })
  end

  # Simplified helper implementations
  defp estimate_token_requirements(task, context), do: (String.length((task[:content] || "") <> (context[:content] || "")) / 4) + 500
  defp assess_task_complexity(task, context), do: if String.length((task[:content] || "") <> (context[:content] || "")) > 1000, do: :high, else: :medium
  defp extract_quality_requirements(context), do: Map.get(context, :quality_requirements, :standard)
  defp extract_latency_requirements(context), do: Map.get(context, :max_latency_ms, 5000)
  defp classify_task_type(task), do: :general
  defp calculate_context_size(context), do: String.length(context[:content] || "")
  defp identify_optimization_opportunities(_task, _context), do: []
  defp get_model_cost_data(model_id, state), do: %{cost_per_token: 0.00001, base_cost: 0.001}
  defp get_model_performance_data(model_id, state), do: %{general: %{avg_quality: 0.8, avg_performance: 0.7}}
  defp validate_budget_limits(_limits), do: :ok
  defp validate_alert_config(_config), do: :ok
  defp get_model_cost_per_token(model, _state), do: model.cost_data.cost_per_token || 0.00001
  defp get_model_latency_score(_model, _state), do: 0.1
  defp update_model_cost_tracking(tracking, _operation, cost_data, timestamp), do: Map.merge(tracking, %{total_cost: (tracking[:total_cost] || 0.0) + cost_data.total_cost, last_updated: timestamp})
  defp add_recent_operation(recent, model_id, operation, cost, timestamp), do: [{model_id, operation, cost, timestamp} | Enum.take(recent, 99)]
  defp update_usage_analytics(analytics, _model_id, _operation, _cost, _timestamp), do: analytics
  defp update_cost_metrics(metrics, cost_data, _timestamp), do: %{metrics | total_cost_tracked: metrics.total_cost_tracked + cost_data.total_cost, operations_tracked: metrics.operations_tracked + 1}
  defp calculate_period_start(:daily, current), do: current - 86_400_000
  defp calculate_period_start(:weekly, current), do: current - 604_800_000
  defp calculate_period_start(:monthly, current), do: current - 2_592_000_000
  defp calculate_period_usage(_tracking, _start, _end), do: 0.0
  defp calculate_remaining_budget_amount(state), do: 100.0
  defp generate_strategy_reasoning(strategy, _model, _analysis), do: "Optimized using #{strategy} strategy"
  defp calculate_cost_range(_models, _analysis, _state), do: %{min: 0.01, max: 0.10}
  defp calculate_quality_range(_models, _analysis, _state), do: %{min: 0.7, max: 0.95}
  defp calculate_cost_savings_potential(_range), do: 0.3
  defp analyze_quality_trade_offs(_range), do: %{acceptable: true, impact: :minimal}
  defp assess_budget_impact(_range, _state), do: %{impact: :low, remaining_budget: 80.0}
  defp suggest_optimization_opportunities(_analysis, _models, _state), do: ["Consider using more cost-efficient models for simple tasks"]
  defp should_send_alert?(_period, _threshold, _config), do: false
  defp send_budget_alert(_period, _threshold, _usage, _limit, _config), do: :ok
  defp get_usage_data_for_period(_analytics, _period), do: []
  defp calculate_total_cost_for_period(_data), do: 0.0
  defp calculate_operation_count_for_period(_data), do: 0
  defp calculate_avg_cost_per_operation(_data), do: 0.0
  defp calculate_cost_trend(_data), do: :stable
  defp identify_top_cost_models(_data), do: []
  defp identify_trend_optimization_opportunities(_data), do: []
  defp project_future_cost(_data, _period), do: 0.0
  defp get_model_by_id(_model_id, _state), do: nil
end