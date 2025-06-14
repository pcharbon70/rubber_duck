defmodule RubberDuck.LLMAbstraction.LoadBalancer.RoutingStrategy do
  @moduledoc """
  Routing strategy implementations for load balancing.
  
  This module provides various algorithms for selecting providers
  based on different criteria like weights, performance, and cost.
  """

  @doc """
  Weighted random selection based on provider weights.
  
  Uses reservoir sampling for efficient O(n) weighted selection.
  """
  def weighted_selection(weighted_providers) when is_list(weighted_providers) do
    total_weight = weighted_providers
    |> Enum.map(fn {_provider, weight} -> weight end)
    |> Enum.sum()
    
    if total_weight <= 0 do
      # Fallback to uniform selection
      weighted_providers
      |> Enum.map(fn {provider, _weight} -> provider end)
      |> Enum.random()
    else
      random_value = :rand.uniform() * total_weight
      select_by_weight(weighted_providers, random_value, 0)
    end
  end

  @doc """
  Round-robin selection with state tracking.
  
  Returns the next provider in sequence and the updated state.
  """
  def round_robin_selection(providers, last_index \\ 0) do
    if Enum.empty?(providers) do
      {nil, 0}
    else
      provider_count = length(providers)
      next_index = rem(last_index + 1, provider_count)
      provider = Enum.at(providers, next_index)
      
      {provider, next_index}
    end
  end

  @doc """
  Least-connections selection based on active request counts.
  """
  def least_connections_selection(provider_connections) when is_map(provider_connections) do
    case Enum.min_by(provider_connections, fn {_provider, count} -> count end, fn -> nil end) do
      nil -> nil
      {provider, _count} -> provider
    end
  end

  @doc """
  Power of two choices selection for better load distribution.
  
  Randomly selects two providers and chooses the one with fewer connections.
  This provides better load distribution than pure random selection with
  minimal overhead.
  """
  def power_of_two_selection(provider_connections) when is_map(provider_connections) do
    providers = Map.keys(provider_connections)
    
    case length(providers) do
      0 -> nil
      1 -> List.first(providers)
      _ ->
        # Randomly select two different providers
        [provider1, provider2] = Enum.take_random(providers, 2)
        
        count1 = Map.get(provider_connections, provider1, 0)
        count2 = Map.get(provider_connections, provider2, 0)
        
        if count1 <= count2, do: provider1, else: provider2
    end
  end

  @doc """
  Latency-based selection with exponential decay for recent measurements.
  
  Gives more weight to recent latency measurements while considering
  historical performance.
  """
  def latency_based_selection(provider_latencies, decay_factor \\ 0.9) do
    if Enum.empty?(provider_latencies) do
      nil
    else
      # Calculate weighted average latency for each provider
      provider_scores = provider_latencies
      |> Enum.map(fn {provider, latency_history} ->
        weighted_latency = calculate_weighted_latency(latency_history, decay_factor)
        # Convert latency to score (lower latency = higher score)
        score = if weighted_latency > 0, do: 1.0 / weighted_latency, else: 0
        {provider, score}
      end)
      |> Enum.filter(fn {_provider, score} -> score > 0 end)
      
      # Use weighted selection based on latency scores
      weighted_selection(provider_scores)
    end
  end

  @doc """
  Hash-based selection for session affinity.
  
  Uses consistent hashing to ensure the same session/user always
  maps to the same provider (when available).
  """
  def hash_based_selection(providers, session_key) do
    if Enum.empty?(providers) do
      nil
    else
      hash_value = :crypto.hash(:sha256, to_string(session_key))
      |> :binary.decode_unsigned(:big)
      
      provider_index = rem(hash_value, length(providers))
      Enum.at(providers, provider_index)
    end
  end

  @doc """
  Multi-criteria selection combining multiple factors.
  
  Combines latency, load, cost, and capability scores with configurable weights.
  """
  def multi_criteria_selection(providers_data, criteria_weights \\ %{}) do
    default_weights = %{
      latency: 0.3,
      load: 0.25,
      cost: 0.25,
      capability: 0.2
    }
    
    weights = Map.merge(default_weights, criteria_weights)
    
    # Calculate composite scores
    scored_providers = providers_data
    |> Enum.map(fn {provider, data} ->
      score = calculate_composite_score(data, weights)
      {provider, score}
    end)
    |> Enum.filter(fn {_provider, score} -> score > 0 end)
    
    if Enum.empty?(scored_providers) do
      nil
    else
      # Select provider with highest composite score
      {provider, _score} = Enum.max_by(scored_providers, fn {_provider, score} -> score end)
      provider
    end
  end

  @doc """
  Adaptive selection that learns from request outcomes.
  
  Uses a simple reinforcement learning approach to improve
  selection based on success rates and performance.
  """
  def adaptive_selection(provider_history, exploration_rate \\ 0.1) do
    if Enum.empty?(provider_history) do
      nil
    else
      if :rand.uniform() < exploration_rate do
        # Exploration: randomly select a provider
        provider_history
        |> Map.keys()
        |> Enum.random()
      else
        # Exploitation: select based on learned performance
        provider_scores = provider_history
        |> Enum.map(fn {provider, history} ->
          score = calculate_adaptive_score(history)
          {provider, score}
        end)
        
        weighted_selection(provider_scores)
      end
    end
  end

  # Private Helper Functions

  defp select_by_weight([{provider, weight} | _rest], random_value, acc) 
       when random_value <= acc + weight do
    provider
  end

  defp select_by_weight([{_provider, weight} | rest], random_value, acc) do
    select_by_weight(rest, random_value, acc + weight)
  end

  defp select_by_weight([], _random_value, _acc) do
    # Fallback - should not happen with proper weights
    nil
  end

  defp calculate_weighted_latency(latency_history, decay_factor) do
    latency_history
    |> Enum.reverse()  # Most recent first
    |> Enum.with_index()
    |> Enum.reduce({0, 0}, fn {{latency, _timestamp}, index}, {sum, weight_sum} ->
      weight = :math.pow(decay_factor, index)
      {sum + latency * weight, weight_sum + weight}
    end)
    |> case do
      {_sum, 0} -> 0
      {sum, weight_sum} -> sum / weight_sum
    end
  end

  defp calculate_composite_score(data, weights) do
    latency_score = normalize_latency_score(Map.get(data, :latency, 1000))
    load_score = normalize_load_score(Map.get(data, :load, 0.5))
    cost_score = normalize_cost_score(Map.get(data, :cost, 1.0))
    capability_score = Map.get(data, :capability, 0.5)
    
    latency_score * weights.latency +
    load_score * weights.load +
    cost_score * weights.cost +
    capability_score * weights.capability
  end

  defp normalize_latency_score(latency_ms) when latency_ms > 0 do
    # Lower latency = higher score (inverse relationship)
    max(0, 1.0 - (latency_ms / 5000.0))  # Normalize to 0-5 second range
  end

  defp normalize_latency_score(_), do: 0

  defp normalize_load_score(load_percentage) when load_percentage >= 0 and load_percentage <= 1 do
    # Lower load = higher score
    1.0 - load_percentage
  end

  defp normalize_load_score(_), do: 0

  defp normalize_cost_score(cost_per_token) when cost_per_token > 0 do
    # Lower cost = higher score (inverse relationship)
    max(0, 1.0 - (cost_per_token / 0.01))  # Normalize to $0.01 per token max
  end

  defp normalize_cost_score(_), do: 0

  defp calculate_adaptive_score(history) do
    total_requests = length(history)
    
    if total_requests == 0 do
      0.5  # Neutral score for unknown providers
    else
      # Calculate success rate
      successful_requests = Enum.count(history, fn %{success: success} -> success end)
      success_rate = successful_requests / total_requests
      
      # Calculate average response time for successful requests
      successful_latencies = history
      |> Enum.filter(fn %{success: success} -> success end)
      |> Enum.map(fn %{latency_ms: latency} -> latency end)
      
      avg_latency = if Enum.empty?(successful_latencies) do
        5000  # Penalty for no successful requests
      else
        Enum.sum(successful_latencies) / length(successful_latencies)
      end
      
      # Combine success rate and latency into a single score
      latency_score = normalize_latency_score(avg_latency)
      success_rate * 0.7 + latency_score * 0.3
    end
  end
end