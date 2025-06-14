defmodule RubberDuck.EventBroadcasting.MetricsCollector do
  @moduledoc """
  Distributed metrics collection and aggregation system.
  
  Collects performance metrics from providers, load balancers, and other 
  components across the cluster. Provides time-windowed aggregation,
  real-time metric streaming, and historical data analysis.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.EventBroadcasting.EventBroadcaster
  
  @type metric_type :: :counter | :gauge | :histogram | :summary
  @type metric_value :: number() | [number()]
  
  @type metric :: %{
    name: String.t(),
    type: metric_type(),
    value: metric_value(),
    timestamp: non_neg_integer(),
    node: node(),
    tags: map(),
    metadata: map()
  }
  
  @type aggregation_window :: %{
    start_time: non_neg_integer(),
    end_time: non_neg_integer(),
    metrics: [metric()],
    aggregated_values: map()
  }
  
  @default_window_size 60_000  # 1 minute
  @default_retention_windows 60  # Keep 1 hour of windows
  @aggregation_interval 10_000  # Aggregate every 10 seconds
  @cleanup_interval 300_000  # Cleanup every 5 minutes
  
  # Client API
  
  @doc """
  Start the MetricsCollector GenServer.
  
  ## Examples
  
      {:ok, pid} = MetricsCollector.start_link()
      {:ok, pid} = MetricsCollector.start_link(window_size: 30_000)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Record a metric value.
  
  ## Examples
  
      :ok = MetricsCollector.record(:counter, "provider.requests", 1, %{provider: "openai"})
      :ok = MetricsCollector.record(:gauge, "provider.health_score", 0.95, %{provider: "anthropic"})
      :ok = MetricsCollector.record(:histogram, "request.latency", 150, %{endpoint: "/chat"})
  """
  def record(type, name, value, tags \\ %{}, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record, type, name, value, tags, metadata})
  end
  
  @doc """
  Record multiple metrics at once.
  
  ## Examples
  
      metrics = [
        {:counter, "requests.total", 1, %{status: "success"}},
        {:gauge, "memory.usage", 0.75, %{node: node()}},
        {:histogram, "processing.time", 200, %{operation: "chat"}}
      ]
      :ok = MetricsCollector.record_batch(metrics)
  """
  def record_batch(metrics) when is_list(metrics) do
    GenServer.cast(__MODULE__, {:record_batch, metrics})
  end
  
  @doc """
  Get current metric values for a specific metric name.
  
  ## Examples
  
      values = MetricsCollector.get_current_metrics("provider.health_score")
      # [%{node: :node1, value: 0.95, tags: %{provider: "openai"}}, ...]
  """
  def get_current_metrics(metric_name) do
    GenServer.call(__MODULE__, {:get_current_metrics, metric_name})
  end
  
  @doc """
  Get aggregated metrics for a time range.
  
  ## Examples
  
      # Get last hour of aggregated data
      metrics = MetricsCollector.get_aggregated_metrics("provider.requests", minutes: 60)
      
      # Get specific time range
      start_time = System.monotonic_time(:millisecond) - 3600_000
      end_time = System.monotonic_time(:millisecond)
      metrics = MetricsCollector.get_aggregated_metrics("provider.requests", 
                                                       start_time: start_time, 
                                                       end_time: end_time)
  """
  def get_aggregated_metrics(metric_name, opts \\ []) do
    GenServer.call(__MODULE__, {:get_aggregated_metrics, metric_name, opts})
  end
  
  @doc """
  Get cluster-wide metrics summary.
  
  ## Examples
  
      summary = MetricsCollector.get_cluster_summary()
      # %{
      #   total_nodes: 4,
      #   total_metrics_collected: 15420,
      #   active_providers: 6,
      #   cluster_health_score: 0.94,
      #   top_metrics: [...]
      # }
  """
  def get_cluster_summary do
    GenServer.call(__MODULE__, :get_cluster_summary)
  end
  
  @doc """
  Get real-time metrics stream for a specific pattern.
  
  ## Examples
  
      # Subscribe to all provider metrics
      :ok = MetricsCollector.subscribe_to_metrics("provider.*")
      
      # Subscribe with filter
      filter_fn = fn metric -> metric.tags.severity == :critical end
      :ok = MetricsCollector.subscribe_to_metrics("alerts.*", filter_fn: filter_fn)
  """
  def subscribe_to_metrics(pattern, opts \\ []) do
    GenServer.call(__MODULE__, {:subscribe_to_metrics, self(), pattern, opts})
  end
  
  @doc """
  Unsubscribe from metrics stream.
  
  ## Examples
  
      :ok = MetricsCollector.unsubscribe_from_metrics("provider.*")
  """
  def unsubscribe_from_metrics(pattern) do
    GenServer.call(__MODULE__, {:unsubscribe_from_metrics, self(), pattern})
  end
  
  @doc """
  Get metrics collection statistics.
  
  ## Examples
  
      stats = MetricsCollector.get_stats()
      # %{
      #   metrics_per_second: 15.2,
      #   total_metrics_collected: 10540,
      #   active_windows: 12,
      #   memory_usage_mb: 45.2
      # }
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    window_size = Keyword.get(opts, :window_size, @default_window_size)
    retention_windows = Keyword.get(opts, :retention_windows, @default_retention_windows)
    
    # Subscribe to metric events from EventBroadcaster
    EventBroadcaster.subscribe("metrics.*")
    
    state = %{
      window_size: window_size,
      retention_windows: retention_windows,
      current_window: create_new_window(),
      completed_windows: :queue.new(),
      metric_subscriptions: %{},
      current_metrics: %{},
      stats: %{
        total_metrics_collected: 0,
        metrics_this_window: 0,
        last_aggregation_time: System.monotonic_time(:millisecond)
      },
      aggregation_timer: schedule_aggregation(),
      cleanup_timer: schedule_cleanup()
    }
    
    Logger.info("MetricsCollector started with window size: #{window_size}ms")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_current_metrics, metric_name}, _from, state) do
    metrics = Map.get(state.current_metrics, metric_name, [])
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_call({:get_aggregated_metrics, metric_name, opts}, _from, state) do
    time_range = calculate_time_range(opts)
    
    relevant_windows = filter_windows_by_time(state.completed_windows, time_range)
    aggregated_data = aggregate_metrics_from_windows(relevant_windows, metric_name)
    
    {:reply, aggregated_data, state}
  end
  
  @impl true
  def handle_call(:get_cluster_summary, _from, state) do
    summary = calculate_cluster_summary(state)
    {:reply, summary, state}
  end
  
  @impl true
  def handle_call({:subscribe_to_metrics, subscriber, pattern, opts}, _from, state) do
    monitor_ref = Process.monitor(subscriber)
    
    subscription = %{
      subscriber: subscriber,
      pattern: pattern,
      filter_fn: Keyword.get(opts, :filter_fn),
      monitor_ref: monitor_ref
    }
    
    subscription_key = {subscriber, pattern}
    updated_subscriptions = Map.put(state.metric_subscriptions, subscription_key, subscription)
    
    {:reply, :ok, %{state | metric_subscriptions: updated_subscriptions}}
  end
  
  @impl true
  def handle_call({:unsubscribe_from_metrics, subscriber, pattern}, _from, state) do
    subscription_key = {subscriber, pattern}
    
    case Map.get(state.metric_subscriptions, subscription_key) do
      nil ->
        {:reply, :ok, state}
      
      subscription ->
        Process.demonitor(subscription.monitor_ref)
        updated_subscriptions = Map.delete(state.metric_subscriptions, subscription_key)
        {:reply, :ok, %{state | metric_subscriptions: updated_subscriptions}}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = calculate_collection_stats(state)
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:record, type, name, value, tags, metadata}, state) do
    metric = create_metric(type, name, value, tags, metadata)
    updated_state = add_metric_to_window(state, metric)
    |> notify_metric_subscribers(metric)
    |> broadcast_metric_event(metric)
    
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_cast({:record_batch, metrics}, state) do
    updated_state = Enum.reduce(metrics, state, fn {type, name, value, tags, metadata}, acc_state ->
      metric = create_metric(type, name, value, tags || %{}, metadata || %{})
      add_metric_to_window(acc_state, metric)
      |> notify_metric_subscribers(metric)
    end)
    
    # Broadcast batch event
    batch_event = %{
      topic: "metrics.batch_recorded",
      payload: %{
        count: length(metrics),
        node: node(),
        timestamp: System.monotonic_time(:millisecond)
      }
    }
    EventBroadcaster.broadcast_async(batch_event)
    
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info({:event, event}, state) do
    # Handle events from EventBroadcaster
    case event.topic do
      "metrics." <> _metric_type ->
        # Process remote metric events
        remote_metric = event.payload
        updated_state = add_metric_to_window(state, remote_metric)
        {:noreply, updated_state}
      
      _ ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:aggregate_window, state) do
    # Complete current window and start new one
    completed_window = complete_current_window(state.current_window)
    new_window = create_new_window()
    
    # Add completed window to queue
    updated_completed_windows = :queue.in(completed_window, state.completed_windows)
    
    # Trim old windows if necessary
    final_completed_windows = if :queue.len(updated_completed_windows) > state.retention_windows do
      {_, trimmed_windows} = :queue.out(updated_completed_windows)
      trimmed_windows
    else
      updated_completed_windows
    end
    
    # Update current metrics cache
    updated_current_metrics = update_current_metrics_cache(state.current_metrics, completed_window)
    
    # Update stats
    updated_stats = %{state.stats |
      last_aggregation_time: System.monotonic_time(:millisecond),
      metrics_this_window: 0
    }
    
    updated_state = %{state |
      current_window: new_window,
      completed_windows: final_completed_windows,
      current_metrics: updated_current_metrics,
      stats: updated_stats
    }
    
    # Broadcast aggregation completed event
    aggregation_event = %{
      topic: "metrics.window_completed",
      payload: %{
        window_start: completed_window.start_time,
        window_end: completed_window.end_time,
        metric_count: length(completed_window.metrics),
        node: node()
      }
    }
    EventBroadcaster.broadcast_async(aggregation_event)
    
    # Schedule next aggregation
    timer = schedule_aggregation()
    
    {:noreply, %{updated_state | aggregation_timer: timer}}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Cleanup old metrics from current_metrics cache
    cutoff_time = System.monotonic_time(:millisecond) - (state.window_size * 2)
    
    cleaned_current_metrics = Map.new(state.current_metrics, fn {name, metrics} ->
      cleaned_metrics = Enum.filter(metrics, fn metric ->
        metric.timestamp > cutoff_time
      end)
      {name, cleaned_metrics}
    end)
    
    updated_state = %{state | current_metrics: cleaned_current_metrics}
    
    # Schedule next cleanup
    timer = schedule_cleanup()
    
    {:noreply, %{updated_state | cleanup_timer: timer}}
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove subscriptions for dead processes
    updated_subscriptions = state.metric_subscriptions
    |> Enum.reject(fn {{subscriber, _pattern}, _sub} -> subscriber == pid end)
    |> Map.new()
    
    {:noreply, %{state | metric_subscriptions: updated_subscriptions}}
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    if state.aggregation_timer do
      Process.cancel_timer(state.aggregation_timer)
    end
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end
    :ok
  end
  
  # Private Functions
  
  defp create_metric(type, name, value, tags, metadata) do
    %{
      name: name,
      type: type,
      value: value,
      timestamp: System.monotonic_time(:millisecond),
      node: node(),
      tags: tags,
      metadata: metadata
    }
  end
  
  defp create_new_window do
    current_time = System.monotonic_time(:millisecond)
    %{
      start_time: current_time,
      end_time: nil,
      metrics: [],
      aggregated_values: %{}
    }
  end
  
  defp add_metric_to_window(state, metric) do
    updated_window = %{state.current_window |
      metrics: [metric | state.current_window.metrics]
    }
    
    # Update current metrics cache
    metric_name = metric.name
    current_metric_list = Map.get(state.current_metrics, metric_name, [])
    updated_current_metrics = Map.put(state.current_metrics, metric_name, [metric | current_metric_list])
    
    # Update stats
    updated_stats = %{state.stats |
      total_metrics_collected: state.stats.total_metrics_collected + 1,
      metrics_this_window: state.stats.metrics_this_window + 1
    }
    
    %{state |
      current_window: updated_window,
      current_metrics: updated_current_metrics,
      stats: updated_stats
    }
  end
  
  defp complete_current_window(window) do
    end_time = System.monotonic_time(:millisecond)
    aggregated_values = aggregate_window_metrics(window.metrics)
    
    %{window |
      end_time: end_time,
      aggregated_values: aggregated_values
    }
  end
  
  defp aggregate_window_metrics(metrics) do
    metrics
    |> Enum.group_by(& &1.name)
    |> Map.new(fn {name, metric_list} ->
      aggregated = case metric_list do
        [] -> %{}
        [first_metric | _] ->
          case first_metric.type do
            :counter -> aggregate_counter_metrics(metric_list)
            :gauge -> aggregate_gauge_metrics(metric_list)
            :histogram -> aggregate_histogram_metrics(metric_list)
            :summary -> aggregate_summary_metrics(metric_list)
          end
      end
      {name, aggregated}
    end)
  end
  
  defp aggregate_counter_metrics(metrics) do
    total = Enum.sum(Enum.map(metrics, & &1.value))
    count = length(metrics)
    
    %{
      type: :counter,
      total: total,
      count: count,
      rate_per_second: if(count > 0, do: total / (count * 60), else: 0)
    }
  end
  
  defp aggregate_gauge_metrics(metrics) do
    values = Enum.map(metrics, & &1.value)
    
    %{
      type: :gauge,
      current: List.last(values),
      min: Enum.min(values),
      max: Enum.max(values),
      avg: Enum.sum(values) / length(values),
      count: length(values)
    }
  end
  
  defp aggregate_histogram_metrics(metrics) do
    values = Enum.flat_map(metrics, fn metric ->
      if is_list(metric.value), do: metric.value, else: [metric.value]
    end)
    
    sorted_values = Enum.sort(values)
    count = length(sorted_values)
    
    %{
      type: :histogram,
      count: count,
      min: if(count > 0, do: Enum.min(sorted_values), else: 0),
      max: if(count > 0, do: Enum.max(sorted_values), else: 0),
      avg: if(count > 0, do: Enum.sum(sorted_values) / count, else: 0),
      p50: percentile(sorted_values, 0.5),
      p95: percentile(sorted_values, 0.95),
      p99: percentile(sorted_values, 0.99)
    }
  end
  
  defp aggregate_summary_metrics(metrics) do
    # Similar to histogram but with predefined quantiles
    aggregate_histogram_metrics(metrics)
  end
  
  defp percentile([], _p), do: 0
  defp percentile(sorted_values, p) do
    index = trunc((length(sorted_values) - 1) * p)
    Enum.at(sorted_values, index, 0)
  end
  
  defp notify_metric_subscribers(state, metric) do
    matching_subscriptions = find_matching_metric_subscriptions(metric.name, state.metric_subscriptions)
    
    Enum.each(matching_subscriptions, fn subscription ->
      if should_deliver_metric?(metric, subscription) do
        send(subscription.subscriber, {:metric, metric})
      end
    end)
    
    state
  end
  
  defp find_matching_metric_subscriptions(metric_name, subscriptions) do
    Enum.filter(subscriptions, fn {_key, subscription} ->
      pattern_matches?(metric_name, subscription.pattern)
    end)
    |> Enum.map(fn {_key, subscription} -> subscription end)
  end
  
  defp pattern_matches?(name, pattern) do
    # Simple wildcard matching
    name_parts = String.split(name, ".")
    pattern_parts = String.split(pattern, ".")
    
    match_metric_parts?(name_parts, pattern_parts)
  end
  
  defp match_metric_parts?([], []), do: true
  defp match_metric_parts?([], ["*"]), do: true
  defp match_metric_parts?(_name, []), do: false
  defp match_metric_parts?([], _pattern), do: false
  
  defp match_metric_parts?([name_part | name_rest], ["*" | pattern_rest]) do
    match_metric_parts?(name_rest, pattern_rest)
  end
  
  defp match_metric_parts?([name_part | name_rest], [pattern_part | pattern_rest]) 
       when name_part == pattern_part do
    match_metric_parts?(name_rest, pattern_rest)
  end
  
  defp match_metric_parts?(_name, _pattern), do: false
  
  defp should_deliver_metric?(metric, subscription) do
    case subscription.filter_fn do
      nil -> true
      filter_fn when is_function(filter_fn, 1) ->
        try do
          filter_fn.(metric)
        rescue
          _ -> false
        end
      _ -> true
    end
  end
  
  defp broadcast_metric_event(state, metric) do
    event = %{
      topic: "metrics.recorded",
      payload: metric,
      metadata: %{
        collector_node: node(),
        window_metrics_count: state.stats.metrics_this_window
      }
    }
    
    EventBroadcaster.broadcast_async(event)
    state
  end
  
  defp calculate_time_range(opts) do
    current_time = System.monotonic_time(:millisecond)
    
    cond do
      Keyword.has_key?(opts, :start_time) and Keyword.has_key?(opts, :end_time) ->
        {Keyword.get(opts, :start_time), Keyword.get(opts, :end_time)}
      
      Keyword.has_key?(opts, :minutes) ->
        minutes = Keyword.get(opts, :minutes)
        start_time = current_time - (minutes * 60 * 1000)
        {start_time, current_time}
      
      Keyword.has_key?(opts, :hours) ->
        hours = Keyword.get(opts, :hours)
        start_time = current_time - (hours * 60 * 60 * 1000)
        {start_time, current_time}
      
      true ->
        # Default to last hour
        start_time = current_time - (60 * 60 * 1000)
        {start_time, current_time}
    end
  end
  
  defp filter_windows_by_time(windows_queue, {start_time, end_time}) do
    windows_queue
    |> :queue.to_list()
    |> Enum.filter(fn window ->
      window.end_time && window.start_time <= end_time && window.end_time >= start_time
    end)
  end
  
  defp aggregate_metrics_from_windows(windows, metric_name) do
    Enum.map(windows, fn window ->
      aggregated_metric = Map.get(window.aggregated_values, metric_name, %{})
      Map.put(aggregated_metric, :window_start, window.start_time)
      |> Map.put(:window_end, window.end_time)
    end)
    |> Enum.reject(&(map_size(&1) <= 2))  # Remove empty aggregations
  end
  
  defp calculate_cluster_summary(state) do
    current_time = System.monotonic_time(:millisecond)
    
    # Get metrics from current window and recent completed windows
    recent_windows = state.completed_windows
    |> :queue.to_list()
    |> Enum.take(-5)  # Last 5 windows
    
    provider_metrics = extract_provider_metrics(recent_windows, state.current_window)
    
    %{
      total_nodes: length(:pg.get_members(:event_broadcaster)),
      total_metrics_collected: state.stats.total_metrics_collected,
      active_providers: count_active_providers(provider_metrics),
      cluster_health_score: calculate_cluster_health(provider_metrics),
      metrics_per_minute: calculate_metrics_rate(recent_windows),
      top_metrics: get_top_metrics(state.current_metrics),
      collection_timestamp: current_time
    }
  end
  
  defp extract_provider_metrics(windows, current_window) do
    all_windows = windows ++ [current_window]
    
    Enum.flat_map(all_windows, fn window ->
      Enum.filter(window.metrics, fn metric ->
        String.starts_with?(metric.name, "provider.")
      end)
    end)
  end
  
  defp count_active_providers(provider_metrics) do
    provider_metrics
    |> Enum.map(fn metric -> Map.get(metric.tags, :provider, "unknown") end)
    |> Enum.uniq()
    |> length()
  end
  
  defp calculate_cluster_health(provider_metrics) do
    health_metrics = Enum.filter(provider_metrics, fn metric ->
      metric.name == "provider.health_score"
    end)
    
    if length(health_metrics) > 0 do
      health_values = Enum.map(health_metrics, & &1.value)
      Enum.sum(health_values) / length(health_values)
    else
      0.0
    end
  end
  
  defp calculate_metrics_rate(windows) do
    if length(windows) > 0 do
      total_metrics = Enum.sum(Enum.map(windows, fn window -> length(window.metrics) end))
      total_time_minutes = length(windows)  # Each window is roughly 1 minute
      total_metrics / max(total_time_minutes, 1)
    else
      0
    end
  end
  
  defp get_top_metrics(current_metrics) do
    current_metrics
    |> Enum.map(fn {name, metrics} -> {name, length(metrics)} end)
    |> Enum.sort_by(fn {_name, count} -> count end, :desc)
    |> Enum.take(10)
  end
  
  defp calculate_collection_stats(state) do
    memory_usage = :erlang.process_info(self(), :memory)[:memory] / 1024 / 1024
    
    current_time = System.monotonic_time(:millisecond)
    time_since_last_aggregation = current_time - state.stats.last_aggregation_time
    
    metrics_per_second = if time_since_last_aggregation > 0 do
      (state.stats.metrics_this_window * 1000) / time_since_last_aggregation
    else
      0
    end
    
    %{
      metrics_per_second: metrics_per_second,
      total_metrics_collected: state.stats.total_metrics_collected,
      active_windows: :queue.len(state.completed_windows) + 1,
      memory_usage_mb: memory_usage,
      current_window_metrics: state.stats.metrics_this_window,
      subscription_count: map_size(state.metric_subscriptions)
    }
  end
  
  defp update_current_metrics_cache(current_metrics, completed_window) do
    # Add completed window metrics to current cache for recent data access
    Enum.reduce(completed_window.metrics, current_metrics, fn metric, acc ->
      metric_name = metric.name
      current_list = Map.get(acc, metric_name, [])
      Map.put(acc, metric_name, [metric | current_list])
    end)
  end
  
  defp schedule_aggregation do
    Process.send_after(self(), :aggregate_window, @aggregation_interval)
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end