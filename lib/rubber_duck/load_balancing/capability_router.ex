defmodule RubberDuck.LoadBalancing.CapabilityRouter do
  @moduledoc """
  Advanced capability-based routing for LLM providers with multi-criteria scoring.
  
  This module implements sophisticated provider selection algorithms that consider
  multiple factors including provider capabilities, performance metrics, cost,
  and real-time health status to make optimal routing decisions.
  """
  
  require Logger
  
  @type provider_info :: %{
    id: term(),
    capabilities: map(),
    performance_metrics: map(),
    cost_metrics: map(),
    health_score: float(),
    weight: non_neg_integer(),
    active_connections: non_neg_integer()
  }
  
  @type request_requirements :: %{
    model: String.t() | nil,
    type: atom(),
    priority: :low | :normal | :high | :critical,
    max_cost: float() | nil,
    min_performance: float() | nil,
    required_features: [atom()],
    user_tier: :free | :premium | :enterprise | nil,
    session_affinity: String.t() | nil
  }
  
  @type scoring_weights :: %{
    capability_match: float(),
    performance: float(),
    cost: float(),
    health: float(),
    load: float(),
    affinity: float()
  }
  
  @default_weights %{
    capability_match: 0.4,
    performance: 0.2,
    cost: 0.2,
    health: 0.1,
    load: 0.05,
    affinity: 0.05
  }
  
  @doc """
  Select the best provider for a given request using multi-criteria scoring.
  
  ## Examples
  
      providers = %{
        openai: %{id: :openai, capabilities: %{models: ["gpt-4"], ...}, ...},
        anthropic: %{id: :anthropic, capabilities: %{models: ["claude-3"], ...}, ...}
      }
      
      requirements = %{
        model: "gpt-4",
        type: :chat,
        priority: :high,
        required_features: [:streaming]
      }
      
      {:ok, :openai} = CapabilityRouter.select_provider(providers, requirements)
  """
  def select_provider(providers, requirements, opts \\ []) do
    weights = Keyword.get(opts, :weights, @default_weights)
    
    case score_all_providers(providers, requirements, weights) do
      [] -> {:error, :no_suitable_providers}
      scored_providers ->
        {best_provider_id, score} = Enum.max_by(scored_providers, fn {_id, score} -> score end)
        
        Logger.debug("Selected provider #{best_provider_id} with score #{score}")
        {:ok, best_provider_id}
    end
  end
  
  @doc """
  Score all providers for a given request and return sorted results.
  
  ## Examples
  
      scores = CapabilityRouter.score_providers(providers, requirements)
      # [{:openai, 85.2}, {:anthropic, 72.1}, {:cohere, 45.3}]
  """
  def score_providers(providers, requirements, opts \\ []) do
    weights = Keyword.get(opts, :weights, @default_weights)
    
    providers
    |> score_all_providers(requirements, weights)
    |> Enum.sort_by(fn {_id, score} -> score end, :desc)
  end
  
  @doc """
  Get multiple providers ranked by suitability for request.
  
  Useful for failover scenarios where you want backup providers.
  
  ## Examples
  
      {:ok, [:openai, :anthropic]} = CapabilityRouter.select_providers(providers, requirements, count: 2)
  """
  def select_providers(providers, requirements, opts \\ []) do
    count = Keyword.get(opts, :count, 1)
    min_score = Keyword.get(opts, :min_score, 0.0)
    
    case score_providers(providers, requirements, opts) do
      [] -> {:error, :no_suitable_providers}
      scored_providers ->
        selected = scored_providers
        |> Enum.filter(fn {_id, score} -> score >= min_score end)
        |> Enum.take(count)
        |> Enum.map(fn {provider_id, _score} -> provider_id end)
        
        {:ok, selected}
    end
  end
  
  @doc """
  Check if a provider can handle a specific request.
  
  ## Examples
  
      true = CapabilityRouter.can_handle?(provider, %{model: "gpt-4", type: :chat})
      false = CapabilityRouter.can_handle?(provider, %{model: "unknown", type: :chat})
  """
  def can_handle?(provider_info, requirements) do
    score_capability_match(provider_info, requirements) > 0
  end
  
  @doc """
  Get detailed scoring breakdown for a provider and request.
  
  Useful for debugging and optimization.
  
  ## Examples
  
      breakdown = CapabilityRouter.score_breakdown(provider, requirements)
      # %{capability_match: 90, performance: 85, cost: 70, ...}
  """
  def score_breakdown(provider_info, requirements, weights \\ @default_weights) do
    %{
      capability_match: score_capability_match(provider_info, requirements),
      performance: score_performance(provider_info, requirements),
      cost: score_cost(provider_info, requirements),
      health: score_health(provider_info, requirements),
      load: score_load(provider_info, requirements),
      affinity: score_affinity(provider_info, requirements),
      weighted_total: calculate_total_score(provider_info, requirements, weights)
    }
  end
  
  # Private Functions
  
  defp score_all_providers(providers, requirements, weights) do
    Enum.map(providers, fn {provider_id, provider_info} ->
      score = calculate_total_score(provider_info, requirements, weights)
      {provider_id, score}
    end)
    |> Enum.filter(fn {_id, score} -> score > 0 end)
  end
  
  defp calculate_total_score(provider_info, requirements, weights) do
    capability_score = score_capability_match(provider_info, requirements)
    
    # If provider can't handle the request at all, return 0
    if capability_score == 0 do
      0
    else
      performance_score = score_performance(provider_info, requirements)
      cost_score = score_cost(provider_info, requirements)
      health_score = score_health(provider_info, requirements)
      load_score = score_load(provider_info, requirements)
      affinity_score = score_affinity(provider_info, requirements)
      
      # If cost constraint is violated, return 0
      if cost_score == 0 do
        0
      else
        weighted_score = 
          capability_score * weights.capability_match +
          performance_score * weights.performance +
          cost_score * weights.cost +
          health_score * weights.health +
          load_score * weights.load +
          affinity_score * weights.affinity
        
        # Apply provider weight multiplier
        provider_weight = Map.get(provider_info, :weight, 100) / 100
        weighted_score * provider_weight
      end
    end
  end
  
  defp score_capability_match(provider_info, requirements) do
    capabilities = Map.get(provider_info, :capabilities, %{})
    
    model_score = score_model_support(capabilities, requirements)
    type_score = score_request_type_support(capabilities, requirements)
    feature_score = score_feature_support(capabilities, requirements)
    tier_score = score_user_tier_support(capabilities, requirements)
    
    # All capabilities must be met for a non-zero score
    if model_score > 0 and type_score > 0 and feature_score > 0 and tier_score > 0 do
      (model_score + type_score + feature_score + tier_score) / 4
    else
      0
    end
  end
  
  defp score_model_support(capabilities, %{model: nil}), do: 100
  defp score_model_support(capabilities, %{model: required_model}) do
    supported_models = Map.get(capabilities, :models, [])
    
    cond do
      required_model in supported_models -> 100
      Enum.any?(supported_models, &model_family_match?(required_model, &1)) -> 80
      Enum.any?(supported_models, &String.contains?(required_model, &1)) -> 60
      true -> 0
    end
  end
  defp score_model_support(_capabilities, _requirements), do: 100
  
  defp score_request_type_support(capabilities, %{type: required_type}) do
    supported_types = Map.get(capabilities, :request_types, [:chat, :completion])
    
    if required_type in supported_types do
      100
    else
      0
    end
  end
  defp score_request_type_support(_capabilities, _requirements), do: 100
  
  defp score_feature_support(capabilities, %{required_features: features}) when is_list(features) do
    supported_features = Map.get(capabilities, :features, [])
    
    if Enum.all?(features, &(&1 in supported_features)) do
      100
    else
      0  # Must have all required features
    end
  end
  defp score_feature_support(_capabilities, _requirements), do: 100
  
  defp score_user_tier_support(capabilities, %{user_tier: tier}) when tier != nil do
    supported_tiers = Map.get(capabilities, :user_tiers, [:free, :premium, :enterprise])
    
    if tier in supported_tiers do
      100
    else
      0
    end
  end
  defp score_user_tier_support(_capabilities, _requirements), do: 100
  
  defp score_performance(provider_info, requirements) do
    metrics = Map.get(provider_info, :performance_metrics, %{})
    min_performance = Map.get(requirements, :min_performance, 0.0)
    
    latency_score = score_latency(metrics)
    throughput_score = score_throughput(metrics)
    reliability_score = score_reliability(metrics)
    
    base_score = (latency_score + throughput_score + reliability_score) / 3
    
    # Check minimum performance requirement
    current_performance = Map.get(metrics, :performance_index, 0.7)
    if current_performance >= min_performance do
      base_score
    else
      base_score * 0.5  # Penalty for not meeting minimum
    end
  end
  
  defp score_latency(metrics) do
    avg_latency_ms = Map.get(metrics, :avg_latency_ms, 1000)
    
    cond do
      avg_latency_ms <= 100 -> 100
      avg_latency_ms <= 500 -> 80
      avg_latency_ms <= 1000 -> 60
      avg_latency_ms <= 2000 -> 40
      avg_latency_ms <= 5000 -> 20
      true -> 0
    end
  end
  
  defp score_throughput(metrics) do
    requests_per_second = Map.get(metrics, :requests_per_second, 1.0)
    
    cond do
      requests_per_second >= 10 -> 100
      requests_per_second >= 5 -> 80
      requests_per_second >= 2 -> 60
      requests_per_second >= 1 -> 40
      requests_per_second >= 0.5 -> 20
      true -> 0
    end
  end
  
  defp score_reliability(metrics) do
    success_rate = Map.get(metrics, :success_rate, 0.95)
    trunc(success_rate * 100)
  end
  
  defp score_cost(provider_info, requirements) do
    cost_metrics = Map.get(provider_info, :cost_metrics, %{})
    max_cost = Map.get(requirements, :max_cost)
    priority = Map.get(requirements, :priority, :normal)
    
    cost_per_request = Map.get(cost_metrics, :cost_per_request, 0.01)
    
    # Base cost score (lower cost = higher score)
    base_score = case cost_per_request do
      c when c <= 0.001 -> 100
      c when c <= 0.005 -> 80
      c when c <= 0.01 -> 60
      c when c <= 0.05 -> 40
      c when c <= 0.1 -> 20
      _ -> 0
    end
    
    # Adjust for maximum cost constraint
    cost_score = if max_cost && cost_per_request > max_cost do
      0  # Exceeds budget
    else
      base_score
    end
    
    # Adjust for priority (higher priority cares less about cost)
    case priority do
      :critical -> min(100, cost_score * 1.5)  # Boost for critical requests
      :high -> min(100, cost_score * 1.2)
      :normal -> cost_score
      :low -> cost_score * 0.8  # Cost is more important for low priority
    end
  end
  
  defp score_health(provider_info, _requirements) do
    health_score = Map.get(provider_info, :health_score, 1.0)
    trunc(health_score * 100)
  end
  
  defp score_load(provider_info, _requirements) do
    active_connections = Map.get(provider_info, :active_connections, 0)
    
    # Prefer providers with fewer active connections
    cond do
      active_connections == 0 -> 100
      active_connections <= 5 -> 80
      active_connections <= 20 -> 60
      active_connections <= 50 -> 40
      active_connections <= 100 -> 20
      true -> 0
    end
  end
  
  defp score_affinity(provider_info, requirements) do
    session_affinity = Map.get(requirements, :session_affinity)
    provider_id = Map.get(provider_info, :id)
    
    if session_affinity && String.contains?(to_string(session_affinity), to_string(provider_id)) do
      500  # Very strong preference for session affinity
    else
      50   # Neutral score when no affinity
    end
  end
  
  defp model_family_match?(required_model, supported_model) do
    # Check if models are from the same family (e.g., "gpt-4" matches "gpt-4-turbo")
    required_base = required_model |> String.split("-") |> Enum.take(2) |> Enum.join("-")
    supported_base = supported_model |> String.split("-") |> Enum.take(2) |> Enum.join("-")
    
    required_base == supported_base
  end
end