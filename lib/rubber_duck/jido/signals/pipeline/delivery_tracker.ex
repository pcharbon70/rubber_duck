defmodule RubberDuck.Jido.Signals.Pipeline.DeliveryTracker do
  @moduledoc """
  Tracks signal delivery status and confirmation.
  
  This monitor tracks whether signals are successfully delivered
  to their intended handlers, maintains delivery statistics,
  and provides insights into delivery failures.
  """
  
  use RubberDuck.Jido.Signals.Pipeline.SignalMonitor,
    name: :delivery_tracker,
    flush_interval: :timer.seconds(60)
  
  @ets_table :signal_delivery_tracking
  
  @impl true
  def observe(signal, metadata) do
    ensure_ets_table()
    
    signal_id = Map.get(signal, :id, generate_id())
    status = Map.get(metadata, :delivery_status, :pending)
    handler = Map.get(metadata, :handler)
    timestamp = DateTime.utc_now()
    
    entry = %{
      signal_id: signal_id,
      signal_type: Map.get(signal, :type),
      status: status,
      handler: handler,
      timestamp: timestamp,
      attempts: Map.get(metadata, :attempts, 1),
      latency: Map.get(metadata, :latency),
      error: Map.get(metadata, :error)
    }
    
    :ets.insert(@ets_table, {signal_id, entry})
    
    # Update aggregated metrics
    update_metrics(status, entry)
    
    :ok
  end
  
  @impl true
  def get_metrics do
    ensure_ets_table()
    
    all_entries = :ets.tab2list(@ets_table)
    now = DateTime.utc_now()
    
    # Calculate metrics
    total = length(all_entries)
    
    {delivered, pending, failed} = Enum.reduce(all_entries, {0, 0, 0}, fn {_, entry}, {d, p, f} ->
      case entry.status do
        :delivered -> {d + 1, p, f}
        :pending -> {d, p + 1, f}
        :failed -> {d, p, f + 1}
        _ -> {d, p, f}
      end
    end)
    
    # Calculate average latency for delivered signals
    latencies = all_entries
      |> Enum.filter(fn {_, e} -> e.status == :delivered && e.latency end)
      |> Enum.map(fn {_, e} -> e.latency end)
    
    avg_latency = if Enum.empty?(latencies) do
      0
    else
      Enum.sum(latencies) / length(latencies)
    end
    
    # Calculate delivery rate
    delivery_rate = if total > 0 do
      delivered / total * 100
    else
      0.0
    end
    
    # Group by signal type
    by_type = all_entries
      |> Enum.group_by(fn {_, e} -> e.signal_type end)
      |> Map.new(fn {type, entries} ->
        {type, %{
          total: length(entries),
          delivered: Enum.count(entries, fn {_, e} -> e.status == :delivered end),
          failed: Enum.count(entries, fn {_, e} -> e.status == :failed end)
        }}
      end)
    
    # Find stuck signals (pending for too long)
    stuck_threshold = :timer.minutes(5)
    stuck_signals = all_entries
      |> Enum.filter(fn {_, e} -> 
        e.status == :pending && 
        DateTime.diff(now, e.timestamp, :millisecond) > stuck_threshold
      end)
      |> length()
    
    %{
      total_signals: total,
      delivered: delivered,
      pending: pending,
      failed: failed,
      delivery_rate: Float.round(delivery_rate, 2),
      average_latency_ms: round(avg_latency),
      stuck_signals: stuck_signals,
      by_type: by_type,
      oldest_pending: find_oldest_pending(all_entries),
      most_retried: find_most_retried(all_entries)
    }
  end
  
  @impl true
  def reset_metrics do
    ensure_ets_table()
    :ets.delete_all_objects(@ets_table)
    :ok
  end
  
  @impl true
  def health_check do
    metrics = get_metrics()
    
    status = cond do
      metrics.delivery_rate < 50.0 -> :unhealthy
      metrics.delivery_rate < 80.0 -> :degraded
      metrics.stuck_signals > 10 -> :degraded
      metrics.stuck_signals > 50 -> :unhealthy
      true -> :healthy
    end
    
    {status, %{
      delivery_rate: metrics.delivery_rate,
      stuck_signals: metrics.stuck_signals,
      pending: metrics.pending,
      failed: metrics.failed
    }}
  end
  
  # Additional public functions
  
  def track_delivery(signal_id, handler, latency) do
    observe(%{id: signal_id}, %{
      delivery_status: :delivered,
      handler: handler,
      latency: latency
    })
  end
  
  def track_failure(signal_id, error, attempts) do
    observe(%{id: signal_id}, %{
      delivery_status: :failed,
      error: error,
      attempts: attempts
    })
  end
  
  def get_signal_status(signal_id) do
    ensure_ets_table()
    
    case :ets.lookup(@ets_table, signal_id) do
      [{_, entry}] -> {:ok, entry}
      [] -> {:error, :not_found}
    end
  end
  
  # Private functions
  
  defp ensure_ets_table do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:set, :public, :named_table])
      _ ->
        :ok
    end
  end
  
  defp generate_id do
    "sig_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
  
  defp update_metrics(status, entry) do
    # Emit telemetry for real-time monitoring
    :telemetry.execute(
      [:rubber_duck, :signal, :delivery],
      %{
        latency: entry.latency || 0,
        attempts: entry.attempts
      },
      %{
        signal_type: entry.signal_type,
        status: status,
        handler: entry.handler
      }
    )
  end
  
  defp find_oldest_pending(entries) do
    pending = entries
      |> Enum.filter(fn {_, e} -> e.status == :pending end)
      |> Enum.min_by(fn {_, e} -> e.timestamp end, DateTime, fn -> nil end)
    
    case pending do
      nil -> nil
      {id, entry} -> %{id: id, age_seconds: DateTime.diff(DateTime.utc_now(), entry.timestamp)}
    end
  end
  
  defp find_most_retried(entries) do
    case Enum.max_by(entries, fn {_, e} -> e.attempts end, fn -> nil end) do
      nil -> nil
      {id, entry} -> %{id: id, attempts: entry.attempts, status: entry.status}
    end
  end
end