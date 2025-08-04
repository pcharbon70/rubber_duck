defmodule RubberDuck.Jido.Signals.Pipeline.MetricsCollector do
  @moduledoc """
  Collects performance metrics for signal processing.
  
  This monitor tracks latency, throughput, and other performance
  metrics to provide insights into pipeline efficiency and bottlenecks.
  """
  
  use RubberDuck.Jido.Signals.Pipeline.SignalMonitor,
    name: :metrics_collector,
    flush_interval: :timer.seconds(30)
  
  @impl true
  def init(opts) do
    state = %{
      opts: opts,
      counters: %{},
      latencies: %{},
      throughput_window: :queue.new(),
      window_size: Keyword.get(opts, :window_size, 100),
      percentiles: Keyword.get(opts, :percentiles, [50, 90, 95, 99])
    }
    
    schedule_flush()
    {:ok, state}
  end
  
  @impl true
  def observe(signal, metadata) do
    GenServer.cast(__MODULE__, {:record_metric, signal, metadata})
    :ok
  end
  
  @impl true
  def get_metrics do
    GenServer.call(__MODULE__, :calculate_metrics)
  end
  
  @impl GenServer
  def handle_cast({:record_metric, signal, metadata}, state) do
    signal_type = Map.get(signal, :type, "unknown")
    timestamp = System.monotonic_time(:microsecond)
    
    # Update counters
    new_counters = update_counters(state.counters, signal_type, metadata)
    
    # Update latencies
    new_latencies = if latency = Map.get(metadata, :processing_time) do
      update_latencies(state.latencies, signal_type, latency)
    else
      state.latencies
    end
    
    # Update throughput window
    new_window = update_throughput_window(
      state.throughput_window,
      {timestamp, signal_type},
      state.window_size
    )
    
    {:noreply, %{state | 
      counters: new_counters,
      latencies: new_latencies,
      throughput_window: new_window
    }}
  end
  
  @impl GenServer
  def handle_call(:calculate_metrics, _from, state) do
    metrics = calculate_all_metrics(state)
    {:reply, metrics, state}
  end
  
  # Private functions
  
  defp update_counters(counters, signal_type, metadata) do
    status = Map.get(metadata, :status, :processed)
    
    counters
    |> Map.update(:total, 1, &(&1 + 1))
    |> Map.update({:type, signal_type}, 1, &(&1 + 1))
    |> Map.update({:status, status}, 1, &(&1 + 1))
    |> Map.update({:type_status, {signal_type, status}}, 1, &(&1 + 1))
  end
  
  defp update_latencies(latencies, signal_type, latency) do
    latencies
    |> Map.update(:all, [latency], &([latency | &1] |> Enum.take(1000)))
    |> Map.update({:type, signal_type}, [latency], &([latency | &1] |> Enum.take(100)))
  end
  
  defp update_throughput_window(window, entry, max_size) do
    new_window = :queue.in(entry, window)
    
    if :queue.len(new_window) > max_size do
      {_, smaller} = :queue.out(new_window)
      smaller
    else
      new_window
    end
  end
  
  defp calculate_all_metrics(state) do
    now = System.monotonic_time(:microsecond)
    
    # Calculate throughput
    throughput = calculate_throughput(state.throughput_window, now)
    
    # Calculate latency percentiles
    latency_stats = calculate_latency_stats(state.latencies, state.percentiles)
    
    # Calculate error rate
    total = Map.get(state.counters, :total, 0)
    errors = Map.get(state.counters, {:status, :error}, 0)
    error_rate = if total > 0, do: errors / total * 100, else: 0.0
    
    # Get type breakdown
    type_breakdown = get_type_breakdown(state.counters)
    
    %{
      total_processed: total,
      error_rate: Float.round(error_rate, 2),
      throughput: throughput,
      latency: latency_stats,
      by_type: type_breakdown,
      window_size: :queue.len(state.throughput_window)
    }
  end
  
  defp calculate_throughput(window, now) do
    window_list = :queue.to_list(window)
    
    if Enum.empty?(window_list) do
      %{current: 0.0, average: 0.0}
    else
      # Get signals in last second
      one_second_ago = now - 1_000_000
      recent = Enum.filter(window_list, fn {ts, _} -> ts > one_second_ago end)
      
      # Calculate current throughput (signals/second)
      current_tps = length(recent)
      
      # Calculate average throughput over window
      {oldest_ts, _} = List.first(window_list)
      {newest_ts, _} = List.last(window_list)
      duration_seconds = max((newest_ts - oldest_ts) / 1_000_000, 1)
      avg_tps = length(window_list) / duration_seconds
      
      %{
        current_per_second: Float.round(current_tps, 2),
        average_per_second: Float.round(avg_tps, 2)
      }
    end
  end
  
  defp calculate_latency_stats(latencies, percentiles) do
    all_latencies = Map.get(latencies, :all, [])
    
    if Enum.empty?(all_latencies) do
      %{
        min: 0,
        max: 0,
        mean: 0,
        percentiles: Map.new(percentiles, fn p -> {p, 0} end)
      }
    else
      sorted = Enum.sort(all_latencies)
      count = length(sorted)
      
      percentile_values = Map.new(percentiles, fn p ->
        index = round(count * p / 100) - 1
        value = Enum.at(sorted, max(index, 0))
        {:"p#{p}", round(value)}
      end)
      
      Map.merge(%{
        min: List.first(sorted),
        max: List.last(sorted),
        mean: round(Enum.sum(sorted) / count)
      }, percentile_values)
    end
  end
  
  defp get_type_breakdown(counters) do
    counters
    |> Enum.filter(fn
      {{:type, _}, _} -> true
      _ -> false
    end)
    |> Map.new(fn {{:type, type}, count} ->
      errors = Map.get(counters, {:type_status, {type, :error}}, 0)
      error_rate = if count > 0, do: errors / count * 100, else: 0.0
      
      {type, %{
        count: count,
        errors: errors,
        error_rate: Float.round(error_rate, 2)
      }}
    end)
  end
  
  @impl true
  def health_check do
    metrics = get_metrics()
    
    status = cond do
      metrics.error_rate > 10.0 -> :unhealthy
      metrics.error_rate > 5.0 -> :degraded
      metrics.throughput.current_per_second == 0 -> :degraded
      true -> :healthy
    end
    
    {status, %{
      error_rate: metrics.error_rate,
      throughput: metrics.throughput.current_per_second,
      latency_p99: get_in(metrics, [:latency, :p99]) || 0
    }}
  end
end