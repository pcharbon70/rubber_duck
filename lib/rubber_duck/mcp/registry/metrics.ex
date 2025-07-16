defmodule RubberDuck.MCP.Registry.Metrics do
  @moduledoc """
  Tracks and analyzes metrics for MCP tools.
  
  This module provides functionality for:
  - Recording execution metrics (success/failure, latency)
  - Calculating quality scores
  - Tracking usage patterns
  - Performance analysis
  """
  
  @type t :: %__MODULE__{
    total_executions: non_neg_integer(),
    successful_executions: non_neg_integer(),
    failed_executions: non_neg_integer(),
    total_latency_ms: non_neg_integer(),
    min_latency_ms: non_neg_integer() | nil,
    max_latency_ms: non_neg_integer() | nil,
    error_types: map(),
    last_execution: DateTime.t() | nil,
    hourly_executions: map(),
    daily_executions: map()
  }
  
  defstruct [
    total_executions: 0,
    successful_executions: 0,
    failed_executions: 0,
    total_latency_ms: 0,
    min_latency_ms: nil,
    max_latency_ms: nil,
    error_types: %{},
    last_execution: nil,
    hourly_executions: %{},
    daily_executions: %{}
  ]
  
  @doc """
  Creates a new metrics struct.
  """
  def new do
    %__MODULE__{}
  end
  
  @doc """
  Records a metric event.
  
  ## Metric Types
  - `{:execution, :success, latency_ms}` - Successful execution
  - `{:execution, :failure, error_type}` - Failed execution
  - `:execution_start` - Marks start of execution (for tracking concurrency)
  """
  def record(metrics, metric_type, value \\ nil)
  
  def record(metrics, {:execution, :success, latency_ms}, _value) when is_number(latency_ms) do
    now = DateTime.utc_now()
    hour_key = DateTime.to_date(now) |> Date.to_iso8601() <> "T" <> to_string(now.hour)
    day_key = DateTime.to_date(now) |> Date.to_iso8601()
    
    %{metrics |
      total_executions: metrics.total_executions + 1,
      successful_executions: metrics.successful_executions + 1,
      total_latency_ms: metrics.total_latency_ms + latency_ms,
      min_latency_ms: min_latency(metrics.min_latency_ms, latency_ms),
      max_latency_ms: max_latency(metrics.max_latency_ms, latency_ms),
      last_execution: now,
      hourly_executions: Map.update(metrics.hourly_executions, hour_key, 1, &(&1 + 1)),
      daily_executions: Map.update(metrics.daily_executions, day_key, 1, &(&1 + 1))
    }
  end
  
  def record(metrics, {:execution, :failure, error_type}, _value) do
    now = DateTime.utc_now()
    hour_key = DateTime.to_date(now) |> Date.to_iso8601() <> "T" <> to_string(now.hour)
    day_key = DateTime.to_date(now) |> Date.to_iso8601()
    
    %{metrics |
      total_executions: metrics.total_executions + 1,
      failed_executions: metrics.failed_executions + 1,
      error_types: Map.update(metrics.error_types, error_type, 1, &(&1 + 1)),
      last_execution: now,
      hourly_executions: Map.update(metrics.hourly_executions, hour_key, 1, &(&1 + 1)),
      daily_executions: Map.update(metrics.daily_executions, day_key, 1, &(&1 + 1))
    }
  end
  
  def record(metrics, :execution_start, _value) do
    # Could be used for tracking concurrent executions
    metrics
  end
  
  @doc """
  Calculates the success rate as a percentage.
  """
  def success_rate(%__MODULE__{total_executions: 0}), do: 100.0
  def success_rate(%__MODULE__{} = metrics) do
    (metrics.successful_executions / metrics.total_executions) * 100.0
  end
  
  @doc """
  Calculates the average latency in milliseconds.
  """
  def average_latency(%__MODULE__{successful_executions: 0}), do: nil
  def average_latency(%__MODULE__{} = metrics) do
    metrics.total_latency_ms / metrics.successful_executions
  end
  
  @doc """
  Calculates a quality score (0-100) based on various metrics.
  """
  def quality_score(%__MODULE__{} = metrics) do
    # Start with success rate (weighted 60%)
    success_score = success_rate(metrics) * 0.6
    
    # Latency score (weighted 30%)
    latency_score = calculate_latency_score(metrics) * 0.3
    
    # Usage score (weighted 10%)
    usage_score = calculate_usage_score(metrics) * 0.1
    
    success_score + latency_score + usage_score
  end
  
  @doc """
  Aggregates hourly/daily metrics and cleans up old data.
  """
  def aggregate(%__MODULE__{} = metrics) do
    now = DateTime.utc_now()
    cutoff_hour = DateTime.add(now, -24, :hour)
    cutoff_day = DateTime.add(now, -30, :day)
    
    %{metrics |
      hourly_executions: filter_old_entries(metrics.hourly_executions, cutoff_hour, :hour),
      daily_executions: filter_old_entries(metrics.daily_executions, cutoff_day, :day)
    }
  end
  
  @doc """
  Returns a summary of the metrics suitable for display.
  """
  def summary(%__MODULE__{} = metrics) do
    %{
      total_executions: metrics.total_executions,
      success_rate: Float.round(success_rate(metrics), 2),
      average_latency_ms: average_latency(metrics) && Float.round(average_latency(metrics), 2),
      min_latency_ms: metrics.min_latency_ms,
      max_latency_ms: metrics.max_latency_ms,
      quality_score: Float.round(quality_score(metrics), 2),
      last_execution: metrics.last_execution && DateTime.to_iso8601(metrics.last_execution),
      error_distribution: metrics.error_types
    }
  end
  
  @doc """
  Merges two metrics structs (useful for distributed systems).
  """
  def merge(%__MODULE__{} = m1, %__MODULE__{} = m2) do
    %__MODULE__{
      total_executions: m1.total_executions + m2.total_executions,
      successful_executions: m1.successful_executions + m2.successful_executions,
      failed_executions: m1.failed_executions + m2.failed_executions,
      total_latency_ms: m1.total_latency_ms + m2.total_latency_ms,
      min_latency_ms: min_latency(m1.min_latency_ms, m2.min_latency_ms),
      max_latency_ms: max_latency(m1.max_latency_ms, m2.max_latency_ms),
      error_types: merge_maps(m1.error_types, m2.error_types),
      last_execution: latest_datetime(m1.last_execution, m2.last_execution),
      hourly_executions: merge_maps(m1.hourly_executions, m2.hourly_executions),
      daily_executions: merge_maps(m1.daily_executions, m2.daily_executions)
    }
  end
  
  # Private functions
  
  defp min_latency(nil, new), do: new
  defp min_latency(current, new), do: min(current, new)
  
  defp max_latency(nil, new), do: new
  defp max_latency(current, new), do: max(current, new)
  
  defp calculate_latency_score(metrics) do
    avg = average_latency(metrics)
    
    cond do
      avg == nil -> 100.0
      avg <= 100 -> 100.0
      avg <= 500 -> 90.0
      avg <= 1000 -> 70.0
      avg <= 5000 -> 50.0
      true -> 25.0
    end
  end
  
  defp calculate_usage_score(metrics) do
    # Score based on recent usage
    case metrics.total_executions do
      0 -> 0.0
      n when n < 10 -> 50.0
      n when n < 100 -> 75.0
      _ -> 100.0
    end
  end
  
  defp filter_old_entries(map, cutoff, :hour) do
    Map.filter(map, fn {key, _value} ->
      case DateTime.from_iso8601(key <> ":00:00Z") do
        {:ok, datetime, _} -> DateTime.compare(datetime, cutoff) == :gt
        _ -> false
      end
    end)
  end
  
  defp filter_old_entries(map, cutoff, :day) do
    Map.filter(map, fn {key, _value} ->
      case Date.from_iso8601(key) do
        {:ok, date} ->
          date_time = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          DateTime.compare(date_time, cutoff) == :gt
        _ -> false
      end
    end)
  end
  
  defp merge_maps(map1, map2) do
    Map.merge(map1, map2, fn _k, v1, v2 -> v1 + v2 end)
  end
  
  defp latest_datetime(nil, dt2), do: dt2
  defp latest_datetime(dt1, nil), do: dt1
  defp latest_datetime(dt1, dt2) do
    if DateTime.compare(dt1, dt2) == :gt, do: dt1, else: dt2
  end
end