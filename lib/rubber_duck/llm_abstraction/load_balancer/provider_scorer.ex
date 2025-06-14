defmodule RubberDuck.LLMAbstraction.LoadBalancer.ProviderScorer do
  @moduledoc """
  Provider scoring algorithms for intelligent request routing.
  
  This module implements various scoring mechanisms to evaluate providers
  based on capabilities, performance, cost, and other criteria for optimal
  request routing and load balancing decisions.
  """

  alias RubberDuck.LLMAbstraction.{Capability, CapabilityMatcher}

  @doc """
  Score a provider based on request requirements and context.
  
  Returns a composite score (0.0 to 1.0) considering:
  - Capability match quality
  - Performance characteristics
  - Cost efficiency
  - Current load and health
  """
  def score_provider(provider_info, requirements, request_opts \\ []) do
    capability_score = capability_score(provider_info, requirements)
    performance_score = performance_score(provider_info, request_opts)
    cost_score = cost_score(provider_info, requirements)
    availability_score = availability_score(provider_info)
    
    # Weighted combination of scores
    weights = get_scoring_weights(request_opts)
    
    capability_score * weights.capability +
    performance_score * weights.performance +
    cost_score * weights.cost +
    availability_score * weights.availability
  end

  @doc """
  Score provider based on capability matching.
  
  Evaluates how well a provider's capabilities match the requirements.
  """
  def capability_score(provider_info, requirements) do
    provider_capabilities = Map.get(provider_info, :capabilities, [])
    
    if Enum.empty?(requirements) do
      0.5  # Neutral score when no specific requirements
    else
      match_quality = CapabilityMatcher.calculate_match_quality(
        requirements, 
        provider_capabilities
      )
      
      # Convert match quality to 0-1 score
      normalize_match_quality(match_quality)
    end
  end

  @doc """
  Score provider based on performance characteristics.
  
  Considers latency, throughput, and reliability metrics.
  """
  def performance_score(provider_info, request_opts \\ []) do
    latency_target = Keyword.get(request_opts, :latency_target)
    throughput_requirement = Keyword.get(request_opts, :throughput_requirement)
    
    metadata = Map.get(provider_info, :metadata, %{})
    
    latency_score = calculate_latency_score(metadata, latency_target)
    throughput_score = calculate_throughput_score(metadata, throughput_requirement)
    reliability_score = calculate_reliability_score(metadata)
    
    # Weighted average of performance metrics
    (latency_score * 0.4 + throughput_score * 0.3 + reliability_score * 0.3)
  end

  @doc """
  Score provider based on cost efficiency.
  
  Evaluates cost per token, rate limits, and pricing tiers.
  """
  def cost_score(provider_info, requirements) do
    metadata = Map.get(provider_info, :metadata, %{})
    pricing = Map.get(metadata, :pricing, %{})
    
    base_cost_score = calculate_base_cost_score(pricing)
    rate_limit_score = calculate_rate_limit_score(metadata)
    volume_discount_score = calculate_volume_discount_score(pricing, requirements)
    
    # Cost efficiency is combination of these factors
    (base_cost_score * 0.5 + rate_limit_score * 0.3 + volume_discount_score * 0.2)
  end

  @doc """
  Score provider based on current availability and health.
  
  Considers health status, current load, and rate limit headroom.
  """
  def availability_score(provider_info) do
    health = Map.get(provider_info, :health, :healthy)
    
    health_score = case health do
      :healthy -> 1.0
      :degraded -> 0.6
      :unhealthy -> 0.0
    end
    
    # Factor in current load if available
    load_score = calculate_load_score(provider_info)
    rate_limit_headroom = calculate_rate_limit_headroom(provider_info)
    
    health_score * 0.5 + load_score * 0.3 + rate_limit_headroom * 0.2
  end

  @doc """
  Calculate model-specific scoring for multi-model providers.
  
  Some providers support multiple models with different characteristics.
  """
  def model_score(provider_info, model_name, requirements) do
    models = Map.get(provider_info, :models, %{})
    model_info = Map.get(models, model_name, %{})
    
    if Enum.empty?(model_info) do
      0.5  # Neutral score for unknown models
    else
      model_capability_score = score_model_capabilities(model_info, requirements)
      model_performance_score = score_model_performance(model_info)
      model_cost_score = score_model_cost(model_info)
      
      # Model-specific weighted combination
      model_capability_score * 0.5 + 
      model_performance_score * 0.3 + 
      model_cost_score * 0.2
    end
  end

  @doc """
  Calculate time-based scoring adjustments.
  
  Some providers have time-based pricing or performance variations.
  """
  def temporal_score(provider_info, current_time \\ DateTime.utc_now()) do
    metadata = Map.get(provider_info, :metadata, %{})
    
    peak_hours_discount = calculate_peak_hours_score(metadata, current_time)
    maintenance_window_penalty = calculate_maintenance_penalty(metadata, current_time)
    
    base_score = 1.0
    adjusted_score = base_score * peak_hours_discount * maintenance_window_penalty
    
    max(0.0, min(1.0, adjusted_score))
  end

  # Private Helper Functions

  defp get_scoring_weights(request_opts) do
    default_weights = %{
      capability: 0.4,
      performance: 0.3,
      cost: 0.2,
      availability: 0.1
    }
    
    # Allow customization based on request options
    priority = Keyword.get(request_opts, :priority, :balanced)
    
    case priority do
      :performance ->
        %{capability: 0.3, performance: 0.5, cost: 0.1, availability: 0.1}
      :cost ->
        %{capability: 0.3, performance: 0.2, cost: 0.4, availability: 0.1}
      :reliability ->
        %{capability: 0.3, performance: 0.2, cost: 0.1, availability: 0.4}
      _ ->
        default_weights
    end
  end

  defp normalize_match_quality(match_quality) do
    case match_quality do
      :perfect -> 1.0
      :good -> 0.8
      :partial -> 0.6
      :minimal -> 0.3
      :none -> 0.0
      score when is_number(score) and score >= 0 and score <= 1 -> score
      _ -> 0.0
    end
  end

  defp calculate_latency_score(metadata, latency_target) do
    avg_latency = Map.get(metadata, :avg_latency_ms, 1000)
    
    if latency_target do
      # Score based on how well we meet the target
      if avg_latency <= latency_target do
        1.0
      else
        # Exponential decay for latencies beyond target
        max(0.0, :math.exp(-(avg_latency - latency_target) / latency_target))
      end
    else
      # General latency scoring (lower is better)
      max(0.0, 1.0 - (avg_latency / 5000.0))  # Normalize to 5-second max
    end
  end

  defp calculate_throughput_score(metadata, throughput_requirement) do
    max_throughput = Map.get(metadata, :max_throughput_rps, 10)
    
    if throughput_requirement do
      if max_throughput >= throughput_requirement do
        1.0
      else
        max_throughput / throughput_requirement
      end
    else
      # General throughput scoring
      min(1.0, max_throughput / 100.0)  # Normalize to 100 RPS max
    end
  end

  defp calculate_reliability_score(metadata) do
    uptime = Map.get(metadata, :uptime_percentage, 99.0)
    error_rate = Map.get(metadata, :error_rate, 0.01)
    
    uptime_score = uptime / 100.0
    error_score = max(0.0, 1.0 - (error_rate * 10))  # 10% error rate = 0 score
    
    (uptime_score + error_score) / 2
  end

  defp calculate_base_cost_score(pricing) do
    cost_per_1k_tokens = Map.get(pricing, :cost_per_1k_tokens, 0.01)
    
    # Lower cost = higher score (inverse relationship)
    max(0.0, 1.0 - (cost_per_1k_tokens / 0.1))  # Normalize to $0.10 per 1K tokens max
  end

  defp calculate_rate_limit_score(metadata) do
    rate_limit = Map.get(metadata, :rate_limit_rpm, 60)
    
    # Higher rate limit = higher score
    min(1.0, rate_limit / 1000.0)  # Normalize to 1000 RPM max
  end

  defp calculate_volume_discount_score(pricing, requirements) do
    volume_discounts = Map.get(pricing, :volume_discounts, [])
    expected_volume = estimate_request_volume(requirements)
    
    applicable_discount = volume_discounts
    |> Enum.filter(fn %{min_volume: min_vol} -> expected_volume >= min_vol end)
    |> Enum.map(fn %{discount: discount} -> discount end)
    |> Enum.max(fn -> 0 end)
    
    applicable_discount / 100.0  # Convert percentage to score
  end

  defp calculate_load_score(provider_info) do
    current_load = Map.get(provider_info, :current_load, 0.5)
    
    # Lower load = higher score
    max(0.0, 1.0 - current_load)
  end

  defp calculate_rate_limit_headroom(provider_info) do
    metadata = Map.get(provider_info, :metadata, %{})
    rate_limit = Map.get(metadata, :rate_limit_rpm, 60)
    current_usage = Map.get(provider_info, :current_usage_rpm, 0)
    
    if rate_limit > 0 do
      headroom = (rate_limit - current_usage) / rate_limit
      max(0.0, headroom)
    else
      0.5  # Neutral score when rate limit unknown
    end
  end

  defp score_model_capabilities(model_info, requirements) do
    model_capabilities = Map.get(model_info, :capabilities, [])
    
    if Enum.empty?(requirements) do
      0.5
    else
      match_quality = CapabilityMatcher.calculate_match_quality(
        requirements, 
        model_capabilities
      )
      normalize_match_quality(match_quality)
    end
  end

  defp score_model_performance(model_info) do
    context_window = Map.get(model_info, :context_window, 4096)
    max_tokens = Map.get(model_info, :max_tokens, 1024)
    speed_score = Map.get(model_info, :speed_score, 0.5)
    
    # Normalize and combine performance metrics
    context_score = min(1.0, context_window / 32768.0)  # Normalize to 32K context
    tokens_score = min(1.0, max_tokens / 4096.0)        # Normalize to 4K tokens
    
    (context_score * 0.4 + tokens_score * 0.3 + speed_score * 0.3)
  end

  defp score_model_cost(model_info) do
    cost_per_1k = Map.get(model_info, :cost_per_1k_tokens, 0.01)
    
    # Lower cost = higher score
    max(0.0, 1.0 - (cost_per_1k / 0.1))
  end

  defp calculate_peak_hours_score(metadata, current_time) do
    peak_hours = Map.get(metadata, :peak_hours, [])
    
    if Enum.empty?(peak_hours) do
      1.0  # No peak hour adjustments
    else
      current_hour = current_time.hour
      
      is_peak = Enum.any?(peak_hours, fn {start_hour, end_hour} ->
        if start_hour <= end_hour do
          current_hour >= start_hour and current_hour <= end_hour
        else
          # Handles overnight ranges like 22-6
          current_hour >= start_hour or current_hour <= end_hour
        end
      end)
      
      if is_peak do
        Map.get(metadata, :peak_hour_multiplier, 0.8)  # Slight penalty during peak
      else
        1.0
      end
    end
  end

  defp calculate_maintenance_penalty(metadata, current_time) do
    maintenance_windows = Map.get(metadata, :maintenance_windows, [])
    
    if Enum.empty?(maintenance_windows) do
      1.0  # No maintenance penalties
    else
      in_maintenance = Enum.any?(maintenance_windows, fn window ->
        DateTime.compare(current_time, window.start) != :lt and
        DateTime.compare(current_time, window.end) != :gt
      end)
      
      if in_maintenance do
        0.1  # Heavy penalty during maintenance
      else
        1.0
      end
    end
  end

  defp estimate_request_volume(requirements) do
    # Simple heuristic based on requirements
    # In a real implementation, this would use historical data
    base_volume = 100
    
    requirements
    |> Enum.reduce(base_volume, fn requirement, acc ->
      case requirement do
        %Capability{type: :streaming} -> acc * 2
        %Capability{type: :function_calling} -> acc * 1.5
        %Capability{type: :multimodal} -> acc * 1.3
        _ -> acc
      end
    end)
  end
end