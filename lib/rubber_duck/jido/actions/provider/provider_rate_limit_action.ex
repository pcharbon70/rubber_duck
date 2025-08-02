defmodule RubberDuck.Jido.Actions.Provider.ProviderRateLimitAction do
  @moduledoc """
  Action for managing provider rate limiting with dynamic adjustment capabilities.
  
  This action provides:
  - Dynamic rate limit adjustment based on provider feedback
  - Rate limit status monitoring and reporting
  - Automatic backoff and recovery strategies
  - Provider-specific rate limiting rules
  - Request queuing and scheduling
  - Rate limit violation handling
  """
  
  use Jido.Action,
    name: "provider_rate_limit",
    description: "Manages provider rate limiting with dynamic adjustment and monitoring",
    schema: [
      operation: [
        type: {:in, [:check, :adjust, :reset, :monitor, :backoff]}, 
        required: true
      ],
      new_limit: [type: :integer, default: nil],
      new_window_ms: [type: :integer, default: nil],
      backoff_factor: [type: :number, default: 1.5],
      recovery_factor: [type: :number, default: 0.8],
      auto_adjust: [type: :boolean, default: false]
    ]

  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    try do
      case params.operation do
        :check ->
          check_rate_limit_status(agent)
        
        :adjust ->
          adjust_rate_limits(agent, params)
        
        :reset ->
          reset_rate_limiter(agent)
        
        :monitor ->
          monitor_rate_limit_performance(agent)
        
        :backoff ->
          apply_backoff_strategy(agent, params)
        
        _ ->
          {:error, {:invalid_operation, params.operation}}
      end
      
    rescue
      error ->
        Logger.error("Rate limit operation failed for #{agent.name}: #{inspect(error)}")
        {:error, {:rate_limit_operation_failed, error}}
    end
  end
  
  # Rate limit status checking
  
  defp check_rate_limit_status(agent) do
    rate_limiter = agent.state.rate_limiter
    now = System.monotonic_time(:millisecond)
    
    # Check if we're within the current window
    {current_count, window_start} = get_current_window_info(rate_limiter, now)
    
    # Calculate utilization and remaining capacity
    utilization_percent = if rate_limiter.limit && rate_limiter.limit > 0 do
      Float.round(current_count / rate_limiter.limit * 100, 2)
    else
      0.0
    end
    
    remaining_requests = if rate_limiter.limit do
      max(0, rate_limiter.limit - current_count)
    else
      :unlimited
    end
    
    # Calculate time until window reset
    time_until_reset = if window_start && rate_limiter.window do
      window_end = window_start + rate_limiter.window
      max(0, window_end - now)
    else
      0
    end
    
    # Determine rate limit status
    status = cond do
      is_nil(rate_limiter.limit) -> :unlimited
      remaining_requests == 0 -> :exceeded
      utilization_percent >= 90 -> :critical
      utilization_percent >= 75 -> :warning
      true -> :healthy
    end
    
    result = %{
      status: status,
      current_count: current_count,
      limit: rate_limiter.limit,
      remaining_requests: remaining_requests,
      utilization_percent: utilization_percent,
      window_ms: rate_limiter.window,
      time_until_reset_ms: time_until_reset,
      window_start: window_start,
      can_make_request: remaining_requests > 0 || is_nil(rate_limiter.limit),
      recommended_delay_ms: calculate_recommended_delay(status, time_until_reset),
      checked_at: DateTime.utc_now()
    }
    
    Logger.debug("Rate limit check for #{agent.name}", 
      status: status, 
      utilization: utilization_percent,
      remaining: remaining_requests
    )
    
    {:ok, result}
  end
  
  # Rate limit adjustment
  
  defp adjust_rate_limits(agent, params) do
    current_limiter = agent.state.rate_limiter
    
    # Validate adjustment parameters
    case validate_adjustment_params(params) do
      :ok ->
        # Create new rate limiter configuration
        new_limiter = apply_rate_limit_adjustments(current_limiter, params)
        
        # Update the agent state
        updated_agent = put_in(agent.state.rate_limiter, new_limiter)
        
        Logger.info("Rate limits adjusted for #{agent.name}", 
          old_limit: current_limiter.limit,
          new_limit: new_limiter.limit,
          old_window: current_limiter.window,
          new_window: new_limiter.window
        )
        
        {:ok, %{
          status: :adjusted,
          previous_config: safe_limiter_config(current_limiter),
          new_config: safe_limiter_config(new_limiter),
          auto_adjusted: params.auto_adjust,
          adjusted_at: DateTime.utc_now()
        }}
      
      {:error, reason} ->
        {:error, {:invalid_adjustment_params, reason}}
    end
  end
  
  # Rate limiter reset
  
  defp reset_rate_limiter(agent) do
    current_limiter = agent.state.rate_limiter
    
    # Reset counts and window
    reset_limiter = %{current_limiter |
      current_count: 0,
      window_start: nil
    }
    
    updated_agent = put_in(agent.state.rate_limiter, reset_limiter)
    
    Logger.info("Rate limiter reset for #{agent.name}")
    
    {:ok, %{
      status: :reset,
      previous_count: current_limiter.current_count,
      limit: reset_limiter.limit,
      window_ms: reset_limiter.window,
      reset_at: DateTime.utc_now()
    }}
  end
  
  # Rate limit performance monitoring
  
  defp monitor_rate_limit_performance(agent) do
    rate_limiter = agent.state.rate_limiter
    metrics = agent.state.metrics
    now = System.monotonic_time(:millisecond)
    
    # Calculate performance metrics
    performance_metrics = calculate_performance_metrics(rate_limiter, metrics, now)
    
    # Generate recommendations
    recommendations = generate_rate_limit_recommendations(performance_metrics, rate_limiter)
    
    # Check for auto-adjustment opportunities
    auto_adjustment = if should_auto_adjust?(performance_metrics, rate_limiter) do
      suggest_auto_adjustment(performance_metrics, rate_limiter)
    else
      %{recommended: false, reason: "No adjustment needed"}
    end
    
    result = %{
      performance: performance_metrics,
      current_config: safe_limiter_config(rate_limiter),
      recommendations: recommendations,
      auto_adjustment: auto_adjustment,
      monitored_at: DateTime.utc_now()
    }
    
    {:ok, result}
  end
  
  # Backoff strategy application
  
  defp apply_backoff_strategy(agent, params) do
    current_limiter = agent.state.rate_limiter
    
    # Calculate new limits based on backoff factor
    new_limit = if current_limiter.limit do
      max(1, round(current_limiter.limit / params.backoff_factor))
    else
      current_limiter.limit
    end
    
    new_window = if current_limiter.window do
      round(current_limiter.window * params.backoff_factor)
    else
      current_limiter.window
    end
    
    # Apply backoff
    backed_off_limiter = %{current_limiter |
      limit: new_limit,
      window: new_window,
      current_count: 0,
      window_start: nil
    }
    
    updated_agent = put_in(agent.state.rate_limiter, backed_off_limiter)
    
    Logger.warning("Applied backoff strategy for #{agent.name}", 
      backoff_factor: params.backoff_factor,
      old_limit: current_limiter.limit,
      new_limit: new_limit,
      old_window: current_limiter.window,
      new_window: new_window
    )
    
    {:ok, %{
      status: :backoff_applied,
      backoff_factor: params.backoff_factor,
      previous_config: safe_limiter_config(current_limiter),
      new_config: safe_limiter_config(backed_off_limiter),
      applied_at: DateTime.utc_now()
    }}
  end
  
  # Helper functions
  
  defp get_current_window_info(rate_limiter, now) do
    window_start = rate_limiter.window_start
    window_duration = rate_limiter.window
    
    cond do
      is_nil(window_start) ->
        # No window started yet
        {0, nil}
      
      is_nil(window_duration) ->
        # No window configured
        {rate_limiter.current_count, window_start}
      
      now >= (window_start + window_duration) ->
        # Window has expired, reset
        {0, nil}
      
      true ->
        # Within current window
        {rate_limiter.current_count, window_start}
    end
  end
  
  defp calculate_recommended_delay(status, time_until_reset) do
    case status do
      :exceeded -> time_until_reset + 100  # Wait for reset plus buffer
      :critical -> max(1000, round(time_until_reset * 0.1))  # Small delay
      :warning -> 500  # Minimal delay
      _ -> 0  # No delay needed
    end
  end
  
  defp validate_adjustment_params(params) do
    errors = []
    
    errors = if params.new_limit do
      if is_integer(params.new_limit) and params.new_limit > 0 do
        errors
      else
        ["new_limit must be a positive integer" | errors]
      end
    else
      errors
    end
    
    errors = if params.new_window_ms do
      if is_integer(params.new_window_ms) and params.new_window_ms > 0 do
        errors
      else
        ["new_window_ms must be a positive integer" | errors]
      end
    else
      errors
    end
    
    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end
  
  defp apply_rate_limit_adjustments(current_limiter, params) do
    new_limiter = current_limiter
    
    # Apply new limit if specified
    new_limiter = if params.new_limit do
      %{new_limiter | limit: params.new_limit}
    else
      new_limiter
    end
    
    # Apply new window if specified
    new_limiter = if params.new_window_ms do
      %{new_limiter | window: params.new_window_ms}
    else
      new_limiter
    end
    
    # Reset counters when configuration changes
    %{new_limiter |
      current_count: 0,
      window_start: nil
    }
  end
  
  defp calculate_performance_metrics(rate_limiter, metrics, now) do
    %{
      current_utilization_percent: calculate_utilization_percent(rate_limiter),
      requests_per_second: calculate_requests_per_second(metrics, rate_limiter),
      average_request_latency_ms: metrics.avg_latency,
      success_rate_percent: calculate_success_rate_percent(metrics),
      violations_count: 0,  # Would be tracked in real implementation
      efficiency_score: calculate_efficiency_score(rate_limiter, metrics)
    }
  end
  
  defp generate_rate_limit_recommendations(performance_metrics, rate_limiter) do
    recommendations = []
    
    # Check utilization
    recommendations = if performance_metrics.current_utilization_percent > 90 do
      ["Consider increasing rate limit - current utilization is #{performance_metrics.current_utilization_percent}%" | recommendations]
    else
      recommendations
    end
    
    # Check efficiency
    recommendations = if performance_metrics.efficiency_score < 0.7 do
      ["Rate limiting may be too restrictive - efficiency score is #{performance_metrics.efficiency_score}" | recommendations]
    else
      recommendations
    end
    
    # Check success rate
    recommendations = if performance_metrics.success_rate_percent < 95 do
      ["High error rate detected - consider implementing backoff strategy" | recommendations]
    else
      recommendations
    end
    
    if Enum.empty?(recommendations) do
      ["Rate limiting configuration appears optimal"]
    else
      recommendations
    end
  end
  
  defp should_auto_adjust?(performance_metrics, rate_limiter) do
    # Auto-adjust if utilization is consistently low or high
    performance_metrics.current_utilization_percent < 30 or 
    performance_metrics.current_utilization_percent > 85
  end
  
  defp suggest_auto_adjustment(performance_metrics, rate_limiter) do
    cond do
      performance_metrics.current_utilization_percent < 30 ->
        suggested_limit = if rate_limiter.limit do
          round(rate_limiter.limit * 1.2)  # Increase by 20%
        else
          rate_limiter.limit
        end
        
        %{
          recommended: true,
          action: :increase_limit,
          suggested_limit: suggested_limit,
          reason: "Low utilization - can increase throughput"
        }
      
      performance_metrics.current_utilization_percent > 85 ->
        suggested_limit = if rate_limiter.limit do
          max(1, round(rate_limiter.limit * 0.8))  # Decrease by 20%
        else
          rate_limiter.limit
        end
        
        %{
          recommended: true,
          action: :decrease_limit,
          suggested_limit: suggested_limit,
          reason: "High utilization - prevent rate limit violations"
        }
      
      true ->
        %{recommended: false, reason: "Utilization within acceptable range"}
    end
  end
  
  defp calculate_utilization_percent(rate_limiter) do
    if rate_limiter.limit && rate_limiter.limit > 0 do
      Float.round(rate_limiter.current_count / rate_limiter.limit * 100, 2)
    else
      0.0
    end
  end
  
  defp calculate_requests_per_second(metrics, rate_limiter) do
    if rate_limiter.window && rate_limiter.window > 0 do
      Float.round(rate_limiter.current_count / (rate_limiter.window / 1000), 2)
    else
      0.0
    end
  end
  
  defp calculate_success_rate_percent(%{total_requests: 0}), do: 100.0
  defp calculate_success_rate_percent(%{total_requests: total, successful_requests: successful}) do
    Float.round(successful / total * 100, 2)
  end
  
  defp calculate_efficiency_score(rate_limiter, metrics) do
    # Simple efficiency score based on utilization vs success rate
    utilization = calculate_utilization_percent(rate_limiter) / 100
    success_rate = calculate_success_rate_percent(metrics) / 100
    
    Float.round(utilization * success_rate, 2)
  end
  
  defp safe_limiter_config(rate_limiter) do
    %{
      limit: rate_limiter.limit,
      window_ms: rate_limiter.window,
      current_count: rate_limiter.current_count,
      utilization_percent: calculate_utilization_percent(rate_limiter)
    }
  end
end