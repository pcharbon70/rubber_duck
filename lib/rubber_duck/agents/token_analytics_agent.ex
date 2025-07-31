defmodule RubberDuck.Agents.TokenAnalyticsAgent do
  @moduledoc """
  Agent responsible for real-time token analytics and reporting.
  
  Provides analytics capabilities including:
  - Real-time usage tracking
  - Cost analysis
  - Trend detection
  - Usage patterns
  - Model performance comparison
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "token_analytics_agent",
    description: "Provides real-time token usage analytics",
    schema: [
      cache_ttl: [type: :integer, default: 300_000], # 5 minutes
      analytics_cache: [type: :map, default: %{}],
      trend_window: [type: :integer, default: 86_400_000], # 24 hours
      alert_thresholds: [type: :map, default: %{
        cost_spike: 2.0,  # 2x normal
        usage_spike: 3.0, # 3x normal
        error_rate: 0.1   # 10% errors
      }]
    ]
  
  require Logger
  alias RubberDuck.Tokens
  
  @doc """
  Handles analytics requests and signals.
  """
  def handle_signal(agent, %{"type" => "analytics_request", "data" => request}) do
    case request["query_type"] do
      "user_summary" ->
        handle_user_summary(agent, request)
        
      "project_costs" ->
        handle_project_costs(agent, request)
        
      "model_comparison" ->
        handle_model_comparison(agent, request)
        
      "usage_trends" ->
        handle_usage_trends(agent, request)
        
      "cost_breakdown" ->
        handle_cost_breakdown(agent, request)
        
      _ ->
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "token_usage_flush", "data" => usage_records}) do
    # Update real-time analytics with new data
    agent = update_analytics_cache(agent, usage_records)
    
    # Check for anomalies
    check_for_anomalies(agent, usage_records)
  end
  
  def handle_signal(agent, _signal) do
    {:ok, agent}
  end
  
  # Analytics handlers
  
  defp handle_user_summary(agent, request) do
    user_id = request["user_id"]
    start_date = parse_date(request["start_date"])
    end_date = parse_date(request["end_date"])
    
    cache_key = {:user_summary, user_id, start_date, end_date}
    
    case get_cached_result(agent, cache_key) do
      {:ok, cached_result} ->
        emit_analytics_result(agent, "user_summary", cached_result)
        {:ok, agent}
        
      :miss ->
        case fetch_user_summary(user_id, start_date, end_date) do
          {:ok, summary} ->
            agent = cache_result(agent, cache_key, summary)
            emit_analytics_result(agent, "user_summary", summary)
            {:ok, agent}
            
          {:error, reason} ->
            Logger.error("Failed to fetch user summary: #{inspect(reason)}")
            {:ok, agent}
        end
    end
  end
  
  defp handle_project_costs(agent, request) do
    project_id = request["project_id"]
    start_date = parse_date(request["start_date"])
    end_date = parse_date(request["end_date"])
    
    cache_key = {:project_costs, project_id, start_date, end_date}
    
    case get_cached_result(agent, cache_key) do
      {:ok, cached_result} ->
        emit_analytics_result(agent, "project_costs", cached_result)
        {:ok, agent}
        
      :miss ->
        case fetch_project_costs(project_id, start_date, end_date) do
          {:ok, costs} ->
            agent = cache_result(agent, cache_key, costs)
            emit_analytics_result(agent, "project_costs", costs)
            {:ok, agent}
            
          {:error, reason} ->
            Logger.error("Failed to fetch project costs: #{inspect(reason)}")
            {:ok, agent}
        end
    end
  end
  
  defp handle_model_comparison(agent, request) do
    models = request["models"] || []
    period = request["period"] || "day"
    
    cache_key = {:model_comparison, models, period}
    
    case get_cached_result(agent, cache_key) do
      {:ok, cached_result} ->
        emit_analytics_result(agent, "model_comparison", cached_result)
        {:ok, agent}
        
      :miss ->
        comparison = compare_models(models, period)
        agent = cache_result(agent, cache_key, comparison)
        emit_analytics_result(agent, "model_comparison", comparison)
        {:ok, agent}
    end
  end
  
  defp handle_usage_trends(agent, request) do
    entity_type = request["entity_type"] || "global"
    entity_id = request["entity_id"]
    period = request["period"] || "hour"
    
    trends = calculate_usage_trends(agent, entity_type, entity_id, period)
    emit_analytics_result(agent, "usage_trends", trends)
    {:ok, agent}
  end
  
  defp handle_cost_breakdown(agent, request) do
    entity_type = request["entity_type"] || "global"
    entity_id = request["entity_id"]
    group_by = request["group_by"] || ["provider", "model"]
    
    breakdown = calculate_cost_breakdown(entity_type, entity_id, group_by)
    emit_analytics_result(agent, "cost_breakdown", breakdown)
    {:ok, agent}
  end
  
  # Data fetching functions
  
  defp fetch_user_summary(user_id, start_date, end_date) do
    with {:ok, usage_data} <- Tokens.sum_user_tokens(user_id, start_date, end_date) do
      summary = %{
        user_id: user_id,
        period: %{start: start_date, end: end_date},
        total_tokens: get_aggregate_value(usage_data, :total_tokens, 0),
        total_cost: get_aggregate_value(usage_data, :total_cost, Decimal.new("0")),
        request_count: get_aggregate_value(usage_data, :request_count, 0),
        average_tokens_per_request: calculate_average(usage_data),
        timestamp: DateTime.utc_now()
      }
      
      {:ok, summary}
    end
  end
  
  defp fetch_project_costs(project_id, start_date, end_date) do
    with {:ok, cost_data} <- Tokens.sum_project_cost(project_id, start_date, end_date) do
      costs = %{
        project_id: project_id,
        period: %{start: start_date, end: end_date},
        total_cost: get_aggregate_value(cost_data, :total_cost, Decimal.new("0")),
        total_tokens: get_aggregate_value(cost_data, :total_tokens, 0),
        request_count: get_aggregate_value(cost_data, :request_count, 0),
        by_model: format_model_breakdown(cost_data),
        timestamp: DateTime.utc_now()
      }
      
      {:ok, costs}
    end
  end
  
  defp compare_models(models, period) do
    # This would fetch and compare model performance
    # For now, return a placeholder
    %{
      models: models,
      period: period,
      comparison: %{
        cost_efficiency: %{},
        speed: %{},
        token_usage: %{}
      },
      timestamp: DateTime.utc_now()
    }
  end
  
  defp calculate_usage_trends(agent, entity_type, entity_id, period) do
    # Calculate trends from cached data
    recent_data = get_recent_analytics(agent, entity_type, entity_id)
    
    %{
      entity_type: entity_type,
      entity_id: entity_id,
      period: period,
      trends: %{
        usage_change: calculate_trend_percentage(recent_data, :tokens),
        cost_change: calculate_trend_percentage(recent_data, :cost),
        request_change: calculate_trend_percentage(recent_data, :requests)
      },
      timestamp: DateTime.utc_now()
    }
  end
  
  defp calculate_cost_breakdown(entity_type, entity_id, group_by) do
    # This would fetch and group cost data
    %{
      entity_type: entity_type,
      entity_id: entity_id,
      grouped_by: group_by,
      breakdown: %{},
      timestamp: DateTime.utc_now()
    }
  end
  
  # Analytics cache management
  
  defp update_analytics_cache(agent, usage_records) do
    # Update real-time analytics cache with new records
    new_cache = Enum.reduce(usage_records, agent.state.analytics_cache, fn record, cache ->
      update_cache_with_record(cache, record)
    end)
    
    new_state = Map.put(agent.state, :analytics_cache, new_cache)
    %{agent | state: new_state}
  end
  
  defp update_cache_with_record(cache, record) do
    # Update various cache entries with the new record
    cache
    |> update_user_cache(record)
    |> update_model_cache(record)
    |> update_global_cache(record)
  end
  
  defp update_user_cache(cache, record) do
    user_key = {:user_stats, record["user_id"] || record[:user_id]}
    user_stats = Map.get(cache, user_key, %{tokens: 0, cost: Decimal.new("0"), requests: 0})
    
    updated_stats = %{
      tokens: user_stats.tokens + (record["total_tokens"] || record[:total_tokens] || 0),
      cost: Decimal.add(user_stats.cost, Decimal.new(to_string(record["cost"] || record[:cost] || "0"))),
      requests: user_stats.requests + 1,
      last_updated: DateTime.utc_now()
    }
    
    Map.put(cache, user_key, updated_stats)
  end
  
  defp update_model_cache(cache, record) do
    model = record["model"] || record[:model]
    model_key = {:model_stats, model}
    model_stats = Map.get(cache, model_key, %{tokens: 0, cost: Decimal.new("0"), requests: 0})
    
    updated_stats = %{
      tokens: model_stats.tokens + (record["total_tokens"] || record[:total_tokens] || 0),
      cost: Decimal.add(model_stats.cost, Decimal.new(to_string(record["cost"] || record[:cost] || "0"))),
      requests: model_stats.requests + 1,
      last_updated: DateTime.utc_now()
    }
    
    Map.put(cache, model_key, updated_stats)
  end
  
  defp update_global_cache(cache, record) do
    global_key = :global_stats
    global_stats = Map.get(cache, global_key, %{tokens: 0, cost: Decimal.new("0"), requests: 0})
    
    updated_stats = %{
      tokens: global_stats.tokens + (record["total_tokens"] || record[:total_tokens] || 0),
      cost: Decimal.add(global_stats.cost, Decimal.new(to_string(record["cost"] || record[:cost] || "0"))),
      requests: global_stats.requests + 1,
      last_updated: DateTime.utc_now()
    }
    
    Map.put(cache, global_key, updated_stats)
  end
  
  # Anomaly detection
  
  defp check_for_anomalies(agent, usage_records) do
    # Check for cost spikes
    check_cost_spike(agent, usage_records)
    
    # Check for usage spikes
    check_usage_spike(agent, usage_records)
    
    {:ok, agent}
  end
  
  defp check_cost_spike(agent, records) do
    total_cost = Enum.reduce(records, Decimal.new("0"), fn record, acc ->
      Decimal.add(acc, Decimal.new(to_string(record["cost"] || record[:cost] || "0")))
    end)
    
    # Compare with historical average
    if should_alert_cost_spike?(agent, total_cost) do
      signal = Jido.Signal.new!(%{
        type: "token.analytics.alert",
        source: "agent:#{agent.id}",
        data: %{
          alert_type: "cost_spike",
          current_cost: total_cost,
          threshold: agent.state.alert_thresholds.cost_spike,
          timestamp: DateTime.utc_now()
        }
      })
      emit_signal(agent, signal)
    end
  end
  
  defp check_usage_spike(agent, records) do
    total_tokens = Enum.reduce(records, 0, fn record, acc ->
      acc + (record["total_tokens"] || record[:total_tokens] || 0)
    end)
    
    if should_alert_usage_spike?(agent, total_tokens) do
      signal = Jido.Signal.new!(%{
        type: "token.analytics.alert",
        source: "agent:#{agent.id}",
        data: %{
          alert_type: "usage_spike",
          current_usage: total_tokens,
          threshold: agent.state.alert_thresholds.usage_spike,
          timestamp: DateTime.utc_now()
        }
      })
      emit_signal(agent, signal)
    end
  end
  
  # Helper functions
  
  defp get_cached_result(agent, cache_key) do
    case Map.get(agent.state.analytics_cache, cache_key) do
      nil -> 
        :miss
        
      %{data: data, cached_at: cached_at} ->
        age = DateTime.diff(DateTime.utc_now(), cached_at, :millisecond)
        if age < agent.state.cache_ttl do
          {:ok, data}
        else
          :miss
        end
        
      _ ->
        :miss
    end
  end
  
  defp cache_result(agent, cache_key, data) do
    cache_entry = %{
      data: data,
      cached_at: DateTime.utc_now()
    }
    
    new_cache = Map.put(agent.state.analytics_cache, cache_key, cache_entry)
    new_state = Map.put(agent.state, :analytics_cache, new_cache)
    %{agent | state: new_state}
  end
  
  defp emit_analytics_result(agent, query_type, result) do
    signal = Jido.Signal.new!(%{
      type: "token.analytics.result",
      source: "agent:#{agent.id}",
      data: %{
        query_type: query_type,
        result: result,
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
  end
  
  defp parse_date(nil), do: nil
  defp parse_date(date) when is_binary(date) do
    case DateTime.from_iso8601(date) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end
  defp parse_date(date), do: date
  
  defp get_aggregate_value(data, key, default) do
    case data do
      %{^key => value} -> value
      _ -> default
    end
  end
  
  defp calculate_average(%{total_tokens: tokens, request_count: count}) when count > 0 do
    div(tokens, count)
  end
  defp calculate_average(_), do: 0
  
  defp format_model_breakdown(data) when is_list(data) do
    Enum.map(data, fn entry ->
      %{
        provider: entry.provider,
        model: entry.model,
        cost: entry.total_cost,
        tokens: entry.total_tokens,
        requests: entry.request_count
      }
    end)
  end
  defp format_model_breakdown(_), do: []
  
  defp get_recent_analytics(agent, _entity_type, _entity_id) do
    # Would fetch recent analytics from cache
    %{tokens: 0, cost: Decimal.new("0"), requests: 0}
  end
  
  defp calculate_trend_percentage(_data, _metric) do
    # Would calculate trend percentage
    0.0
  end
  
  defp should_alert_cost_spike?(_agent, _cost) do
    # Would check against historical averages
    false
  end
  
  defp should_alert_usage_spike?(_agent, _tokens) do
    # Would check against historical averages
    false
  end
  
  @doc """
  Health check for the analytics agent.
  """
  @impl true
  def health_check(agent) do
    cache_size = map_size(agent.state.analytics_cache)
    
    if cache_size < 10000 do
      {:healthy, %{
        cache_size: cache_size,
        cache_hit_rate: 0.0 # Would track this in production
      }}
    else
      {:unhealthy, %{
        cache_size: cache_size,
        message: "Cache size too large"
      }}
    end
  end
end