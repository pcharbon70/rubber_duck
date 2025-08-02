defmodule RubberDuck.Jido.Actions.RestartTracker.GetStatsAction do
  @moduledoc """
  Action for retrieving restart statistics for all agents or a specific agent.
  
  Returns comprehensive restart statistics including total restarts, recent activity,
  backoff status, and trend analysis.
  """
  
  use Jido.Action,
    name: "get_stats",
    description: "Retrieves restart statistics for agents",
    schema: [
      agent_id: [
        type: :string,
        default: nil,
        doc: "Specific agent ID to get stats for (nil for all agents)"
      ],
      include_detailed: [
        type: :boolean,
        default: false,
        doc: "Whether to include detailed analysis and trends"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{agent_id: agent_id, include_detailed: include_detailed} = params
    
    Logger.debug("Retrieving restart stats", agent_id: agent_id, detailed: include_detailed)
    
    stats = case agent_id do
      nil ->
        # Get stats for all agents
        get_all_agent_stats(agent.state.restart_data, include_detailed)
        
      specific_agent_id ->
        # Get stats for specific agent
        get_agent_stats(agent.state.restart_data, specific_agent_id, include_detailed)
    end
    
    # Emit stats response
    signal_params = %{
      signal_type: "restart_tracker.stats.response",
      data: %{
        agent_id: agent_id,
        stats: stats,
        timestamp: DateTime.utc_now()
      }
    }
    
    case EmitSignalAction.run(signal_params, %{agent: agent}) do
      {:ok, _} ->
        {:ok, %{stats: stats}, %{agent: agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end

  # Private functions
  
  defp get_all_agent_stats(restart_data, include_detailed) do
    stats = restart_data
    |> Enum.map(fn {agent_id, info} ->
      agent_stats = format_restart_info(info)
      
      formatted_stats = if include_detailed do
        Map.merge(agent_stats, %{
          detailed: build_detailed_stats(info),
          trends: analyze_restart_trends(info)
        })
      else
        agent_stats
      end
      
      {agent_id, formatted_stats}
    end)
    |> Map.new()
    
    # Add summary statistics
    Map.put(stats, :_summary, build_system_summary(restart_data, include_detailed))
  end
  
  defp get_agent_stats(restart_data, agent_id, include_detailed) do
    case Map.get(restart_data, agent_id) do
      nil -> 
        %{agent_id: agent_id, found: false}
        
      info -> 
        base_stats = format_restart_info(info)
        
        if include_detailed do
          Map.merge(base_stats, %{
            agent_id: agent_id,
            detailed: build_detailed_stats(info),
            trends: analyze_restart_trends(info),
            recommendations: generate_recommendations(info)
          })
        else
          Map.put(base_stats, :agent_id, agent_id)
        end
    end
  end
  
  defp format_restart_info(info) do
    now = DateTime.utc_now()
    
    %{
      total_restarts: info.count,
      last_restart: info.last_restart,
      backoff_until: info.backoff_until,
      recent_restart_count: length(info.history),
      in_backoff: info.backoff_until && DateTime.compare(now, info.backoff_until) == :lt,
      time_since_last_restart: if(info.last_restart, do: DateTime.diff(now, info.last_restart, :millisecond), else: nil)
    }
  end
  
  defp build_detailed_stats(info) do
    now = DateTime.utc_now()
    
    # Analyze restart intervals
    restart_intervals = calculate_restart_intervals(info.history)
    
    %{
      restart_frequency: %{
        last_hour: count_restarts_in_period(info.history, now, 3600),
        last_day: count_restarts_in_period(info.history, now, 86400),
        last_week: count_restarts_in_period(info.history, now, 604800)
      },
      intervals: %{
        min_seconds: if(length(restart_intervals) > 0, do: Enum.min(restart_intervals), else: nil),
        max_seconds: if(length(restart_intervals) > 0, do: Enum.max(restart_intervals), else: nil),
        avg_seconds: if(length(restart_intervals) > 0, do: Enum.sum(restart_intervals) / length(restart_intervals), else: nil)
      },
      backoff_history: analyze_backoff_history(info),
      health_score: calculate_health_score(info, now)
    }
  end
  
  defp analyze_restart_trends(info) do
    now = DateTime.utc_now()
    
    # Calculate trend over different periods
    recent_hour = count_restarts_in_period(info.history, now, 3600)
    recent_day = count_restarts_in_period(info.history, now, 86400)
    recent_week = count_restarts_in_period(info.history, now, 604800)
    
    %{
      trend: determine_trend(info.history, now),
      severity: classify_severity(recent_hour, recent_day, recent_week),
      stability: calculate_stability_score(info.history, now),
      prediction: predict_next_restart(info.history)
    }
  end
  
  defp build_system_summary(restart_data, include_detailed) do
    all_infos = Map.values(restart_data)
    now = DateTime.utc_now()
    
    total_agents = length(all_infos)
    agents_in_backoff = Enum.count(all_infos, fn info ->
      info.backoff_until && DateTime.compare(now, info.backoff_until) == :lt
    end)
    
    base_summary = %{
      total_agents_tracked: total_agents,
      agents_in_backoff: agents_in_backoff,
      total_restarts_today: count_all_restarts_in_period(all_infos, now, 86400),
      most_restarted_agent: find_most_restarted_agent(restart_data)
    }
    
    if include_detailed do
      Map.merge(base_summary, %{
        system_health: calculate_system_health(all_infos, now),
        restart_distribution: analyze_restart_distribution(all_infos),
        critical_agents: find_critical_agents(restart_data, now)
      })
    else
      base_summary
    end
  end
  
  # Analysis helper functions
  
  defp calculate_restart_intervals(history) do
    history
    |> Enum.sort(DateTime)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [earlier, later] ->
      DateTime.diff(later, earlier, :second)
    end)
  end
  
  defp count_restarts_in_period(history, now, seconds) do
    cutoff = DateTime.add(now, -seconds, :second)
    Enum.count(history, fn timestamp ->
      DateTime.compare(timestamp, cutoff) != :lt
    end)
  end
  
  defp count_all_restarts_in_period(all_infos, now, seconds) do
    all_infos
    |> Enum.map(fn info -> count_restarts_in_period(info.history, now, seconds) end)
    |> Enum.sum()
  end
  
  defp analyze_backoff_history(info) do
    # This is simplified - in practice would track backoff history
    %{
      times_in_backoff: if(info.backoff_until, do: 1, else: 0),
      longest_backoff_ms: nil,  # Would need to track this
      current_backoff_ms: if(info.backoff_until, do: DateTime.diff(info.backoff_until, DateTime.utc_now(), :millisecond), else: 0)
    }
  end
  
  defp calculate_health_score(info, now) do
    recent_restarts = count_restarts_in_period(info.history, now, 3600)
    
    cond do
      recent_restarts == 0 -> 1.0  # Perfect health
      recent_restarts <= 2 -> 0.8  # Good health
      recent_restarts <= 5 -> 0.5  # Fair health
      recent_restarts <= 10 -> 0.2 # Poor health
      true -> 0.0                  # Critical health
    end
  end
  
  defp determine_trend(history, now) do
    recent_hour = count_restarts_in_period(history, now, 3600)
    recent_day = count_restarts_in_period(history, now, 86400)
    
    cond do
      recent_hour > 3 -> :critical
      recent_hour > 1 -> :increasing
      recent_day == 0 -> :stable
      recent_day <= 2 -> :decreasing
      true -> :stable
    end
  end
  
  defp classify_severity(hour, day, week) do
    cond do
      hour > 5 -> :critical
      hour > 2 or day > 10 -> :high
      hour > 0 or day > 3 -> :medium
      week > 1 -> :low
      true -> :minimal
    end
  end
  
  defp calculate_stability_score(history, _now) do
    if Enum.empty?(history) do
      1.0  # No restarts = perfectly stable
    else
      intervals = calculate_restart_intervals(history)
      if length(intervals) < 2 do
        0.5
      else
        # More consistent intervals = higher stability
        mean = Enum.sum(intervals) / length(intervals)
        variance = Enum.reduce(intervals, 0, fn x, acc -> acc + :math.pow(x - mean, 2) end) / length(intervals)
        std_dev = :math.sqrt(variance)
        
        # Normalize to 0-1 scale (lower std_dev = higher stability)
        max(0.0, 1.0 - (std_dev / mean))
      end
    end
  end
  
  defp predict_next_restart(history) do
    if length(history) < 2 do
      nil
    else
      intervals = calculate_restart_intervals(history)
      avg_interval = Enum.sum(intervals) / length(intervals)
      
      last_restart = Enum.max(history, DateTime)
      predicted = DateTime.add(last_restart, round(avg_interval), :second)
      
      %{
        predicted_time: predicted,
        confidence: calculate_prediction_confidence(intervals)
      }
    end
  end
  
  defp calculate_prediction_confidence(intervals) do
    if length(intervals) < 3 do
      0.1
    else
      mean = Enum.sum(intervals) / length(intervals)
      variance = Enum.reduce(intervals, 0, fn x, acc -> acc + :math.pow(x - mean, 2) end) / length(intervals)
      coefficient_of_variation = :math.sqrt(variance) / mean
      
      # Lower coefficient of variation = higher confidence
      max(0.0, min(1.0, 1.0 - coefficient_of_variation))
    end
  end
  
  defp find_most_restarted_agent(restart_data) do
    restart_data
    |> Enum.max_by(fn {_agent_id, info} -> info.count end, fn -> nil end)
    |> case do
      nil -> nil
      {agent_id, info} -> %{agent_id: agent_id, restart_count: info.count}
    end
  end
  
  defp calculate_system_health(all_infos, now) do
    if Enum.empty?(all_infos) do
      1.0
    else
      health_scores = Enum.map(all_infos, &calculate_health_score(&1, now))
      Enum.sum(health_scores) / length(health_scores)
    end
  end
  
  defp analyze_restart_distribution(all_infos) do
    total_restarts = Enum.map(all_infos, & &1.count) |> Enum.sum()
    
    if total_restarts == 0 do
      %{distribution: "No restarts recorded"}
    else
      # Group by restart count ranges
      ranges = %{
        "0" => 0,
        "1-5" => 0,
        "6-10" => 0,
        "11-20" => 0,
        "21+" => 0
      }
      
      distribution = Enum.reduce(all_infos, ranges, fn info, acc ->
        case info.count do
          0 -> Map.update!(acc, "0", &(&1 + 1))
          n when n <= 5 -> Map.update!(acc, "1-5", &(&1 + 1))
          n when n <= 10 -> Map.update!(acc, "6-10", &(&1 + 1))
          n when n <= 20 -> Map.update!(acc, "11-20", &(&1 + 1))
          _ -> Map.update!(acc, "21+", &(&1 + 1))
        end
      end)
      
      distribution
    end
  end
  
  defp find_critical_agents(restart_data, now) do
    restart_data
    |> Enum.filter(fn {_agent_id, info} ->
      recent_restarts = count_restarts_in_period(info.history, now, 3600)
      recent_restarts > 3 or calculate_health_score(info, now) < 0.3
    end)
    |> Enum.map(fn {agent_id, info} ->
      %{
        agent_id: agent_id,
        recent_restarts: count_restarts_in_period(info.history, now, 3600),
        health_score: calculate_health_score(info, now),
        in_backoff: info.backoff_until && DateTime.compare(now, info.backoff_until) == :lt
      }
    end)
  end
  
  defp generate_recommendations(info) do
    now = DateTime.utc_now()
    recommendations = []
    
    recent_restarts = count_restarts_in_period(info.history, now, 3600)
    health_score = calculate_health_score(info, now)
    
    recommendations = if recent_restarts > 5 do
      ["Consider investigating root cause - high restart frequency detected" | recommendations]
    else
      recommendations
    end
    
    recommendations = if health_score < 0.3 do
      ["Agent health is critical - immediate attention required" | recommendations]
    else
      recommendations
    end
    
    recommendations = if info.backoff_until && DateTime.compare(now, info.backoff_until) == :lt do
      ["Agent is currently in backoff period - wait before manual restart" | recommendations]
    else
      recommendations
    end
    
    if Enum.empty?(recommendations) do
      ["Agent restart behavior is within normal parameters"]
    else
      recommendations
    end
  end
end