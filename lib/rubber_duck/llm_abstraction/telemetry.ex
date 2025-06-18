defmodule RubberDuck.LLMAbstraction.Telemetry do
  @moduledoc """
  Telemetry and metrics collection for LLM provider operations.
  
  This module provides comprehensive telemetry for LLM operations including
  performance metrics, error tracking, cost monitoring, and usage analytics.
  """

  @doc """
  Execute telemetry event for LLM operations.
  """
  def execute(event_name, measurements \\ %{}, metadata \\ %{}) do
    full_event_name = [:rubber_duck, :llm] ++ List.wrap(event_name)
    :telemetry.execute(full_event_name, measurements, metadata)
  rescue
    _ -> :ok  # Telemetry failures shouldn't crash the system
  end

  @doc """
  Track LLM request start.
  """
  def track_request_start(provider_id, operation, metadata \\ %{}) do
    measurements = %{
      start_time: System.monotonic_time(:millisecond),
      count: 1
    }
    
    metadata = Map.merge(metadata, %{
      provider_id: provider_id,
      operation: operation,
      request_id: generate_request_id()
    })
    
    execute([:request, :start], measurements, metadata)
    metadata.request_id
  end

  @doc """
  Track LLM request completion.
  """
  def track_request_stop(request_id, provider_id, operation, result, metadata \\ %{}) do
    end_time = System.monotonic_time(:millisecond)
    start_time = Map.get(metadata, :start_time, end_time)
    duration = end_time - start_time
    
    measurements = %{
      duration: duration,
      count: 1,
      tokens_used: Map.get(metadata, :tokens_used, 0),
      cost: Map.get(metadata, :cost, 0.0)
    }
    
    metadata = Map.merge(metadata, %{
      provider_id: provider_id,
      operation: operation,
      result: result,
      request_id: request_id
    })
    
    execute([:request, :stop], measurements, metadata)
  end

  @doc """
  Track LLM request error.
  """
  def track_request_error(request_id, provider_id, operation, error, metadata \\ %{}) do
    measurements = %{
      count: 1,
      duration: System.monotonic_time(:millisecond) - Map.get(metadata, :start_time, 0)
    }
    
    metadata = Map.merge(metadata, %{
      provider_id: provider_id,
      operation: operation,
      error_type: classify_error(error),
      error_message: extract_error_message(error),
      request_id: request_id
    })
    
    execute([:request, :error], measurements, metadata)
  end

  @doc """
  Track provider health changes.
  """
  def track_provider_health(provider_id, health_status, metadata \\ %{}) do
    measurements = %{count: 1}
    
    metadata = Map.merge(metadata, %{
      provider_id: provider_id,
      health_status: health_status,
      timestamp: System.system_time(:second)
    })
    
    execute([:provider, :health], measurements, metadata)
  end

  @doc """
  Track streaming operations.
  """
  def track_stream_event(request_id, provider_id, event_type, metadata \\ %{}) do
    measurements = %{count: 1}
    
    metadata = Map.merge(metadata, %{
      provider_id: provider_id,
      event_type: event_type,
      request_id: request_id,
      timestamp: System.monotonic_time(:millisecond)
    })
    
    execute([:stream, event_type], measurements, metadata)
  end

  @doc """
  Track rate limiting events.
  """
  def track_rate_limit(provider_id, limit_type, metadata \\ %{}) do
    measurements = %{count: 1}
    
    metadata = Map.merge(metadata, %{
      provider_id: provider_id,
      limit_type: limit_type,
      timestamp: System.system_time(:second)
    })
    
    execute([:rate_limit, :hit], measurements, metadata)
  end

  @doc """
  Track cost information.
  """
  def track_cost(provider_id, operation, cost_data, metadata \\ %{}) do
    measurements = %{
      input_tokens: Map.get(cost_data, :input_tokens, 0),
      output_tokens: Map.get(cost_data, :output_tokens, 0),
      total_tokens: Map.get(cost_data, :total_tokens, 0),
      cost: Map.get(cost_data, :cost, 0.0)
    }
    
    metadata = Map.merge(metadata, %{
      provider_id: provider_id,
      operation: operation,
      model: Map.get(cost_data, :model),
      timestamp: System.system_time(:second)
    })
    
    execute([:cost, :tracked], measurements, metadata)
  end

  @doc """
  Track capability usage.
  """
  def track_capability_usage(provider_id, capability, success, metadata \\ %{}) do
    measurements = %{count: 1}
    
    metadata = Map.merge(metadata, %{
      provider_id: provider_id,
      capability: capability,
      success: success,
      timestamp: System.system_time(:second)
    })
    
    execute([:capability, :used], measurements, metadata)
  end

  # Private Functions

  defp generate_request_id do
    "req_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp classify_error({:http_error, _}), do: :http_error
  defp classify_error({:client_error, status, _}), do: "client_error_#{status}"
  defp classify_error({:server_error, status, _}), do: "server_error_#{status}"
  defp classify_error({:timeout, _}), do: :timeout
  defp classify_error({:rate_limited, _}), do: :rate_limited
  defp classify_error({:auth_error, _}), do: :auth_error
  defp classify_error({:config_error, _}), do: :config_error
  defp classify_error({:provider_error, _}), do: :provider_error
  defp classify_error(_), do: :unknown_error

  defp extract_error_message({_type, message}) when is_binary(message), do: message
  defp extract_error_message({_type, reason}) when is_atom(reason), do: to_string(reason)
  defp extract_error_message({_type, %{message: message}}) when is_binary(message), do: message
  defp extract_error_message(error) when is_binary(error), do: error
  defp extract_error_message(error) when is_atom(error), do: to_string(error)
  defp extract_error_message(_), do: "unknown_error"
end

defmodule RubberDuck.LLMAbstraction.MetricsCollector do
  @moduledoc """
  Centralized metrics collection and aggregation for LLM operations.
  
  This module collects, aggregates, and provides access to LLM operation
  metrics for monitoring, alerting, and performance optimization.
  """

  use GenServer
  require Logger

  alias RubberDuck.LLMAbstraction.Telemetry

  defstruct [
    :metrics,
    :aggregates,
    :config,
    :start_time
  ]

  @metrics_table :llm_metrics
  @aggregation_interval 60_000  # 1 minute
  @retention_period 86_400_000   # 24 hours

  ## Public API

  @doc """
  Start the metrics collector.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current metrics for a provider.
  """
  def get_provider_metrics(provider_id) do
    GenServer.call(__MODULE__, {:get_provider_metrics, provider_id})
  end

  @doc """
  Get aggregated metrics across all providers.
  """
  def get_aggregate_metrics do
    GenServer.call(__MODULE__, :get_aggregate_metrics)
  end

  @doc """
  Get metrics for a specific time range.
  """
  def get_metrics_for_range(start_time, end_time, filters \\ %{}) do
    GenServer.call(__MODULE__, {:get_metrics_range, start_time, end_time, filters})
  end

  @doc """
  Get real-time performance statistics.
  """
  def get_performance_stats do
    GenServer.call(__MODULE__, :get_performance_stats)
  end

  @doc """
  Record a custom metric.
  """
  def record_metric(metric_name, value, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_metric, metric_name, value, metadata})
  end

  ## GenServer Implementation

  @impl GenServer
  def init(opts) do
    # Create ETS table for fast metric storage
    :ets.new(@metrics_table, [:set, :public, :named_table, {:write_concurrency, true}])
    
    # Attach telemetry handlers
    attach_telemetry_handlers()
    
    # Schedule aggregation
    schedule_aggregation()
    
    state = %__MODULE__{
      metrics: %{},
      aggregates: %{},
      config: Keyword.get(opts, :config, %{}),
      start_time: System.system_time(:second)
    }
    
    Logger.info("LLM Metrics Collector started")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get_provider_metrics, provider_id}, _from, state) do
    metrics = get_provider_metrics_internal(provider_id)
    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call(:get_aggregate_metrics, _from, state) do
    {:reply, state.aggregates, state}
  end

  @impl GenServer
  def handle_call({:get_metrics_range, start_time, end_time, filters}, _from, state) do
    metrics = get_metrics_for_range_internal(start_time, end_time, filters)
    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call(:get_performance_stats, _from, state) do
    stats = calculate_performance_stats(state)
    {:reply, stats, state}
  end

  @impl GenServer
  def handle_cast({:record_metric, metric_name, value, metadata}, state) do
    record_metric_internal(metric_name, value, metadata)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:aggregate_metrics, state) do
    new_state = perform_aggregation(state)
    schedule_aggregation()
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({[:rubber_duck, :llm | _] = event, measurements, metadata}, state) do
    handle_telemetry_event(event, measurements, metadata)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Telemetry Handlers

  defp attach_telemetry_handlers do
    events = [
      [:rubber_duck, :llm, :request, :start],
      [:rubber_duck, :llm, :request, :stop],
      [:rubber_duck, :llm, :request, :error],
      [:rubber_duck, :llm, :provider, :health],
      [:rubber_duck, :llm, :stream, :start],
      [:rubber_duck, :llm, :stream, :chunk],
      [:rubber_duck, :llm, :stream, :complete],
      [:rubber_duck, :llm, :rate_limit, :hit],
      [:rubber_duck, :llm, :cost, :tracked],
      [:rubber_duck, :llm, :capability, :used]
    ]
    
    :telemetry.attach_many(
      "llm-metrics-collector",
      events,
      &__MODULE__.handle_telemetry_event/4,
      nil
    )
  end

  def handle_telemetry_event(event, measurements, metadata, _config) do
    send(__MODULE__, {event, measurements, metadata})
  end

  defp handle_telemetry_event([:rubber_duck, :llm, :request, :start], measurements, metadata) do
    record_request_start(measurements, metadata)
  end

  defp handle_telemetry_event([:rubber_duck, :llm, :request, :stop], measurements, metadata) do
    record_request_stop(measurements, metadata)
  end

  defp handle_telemetry_event([:rubber_duck, :llm, :request, :error], measurements, metadata) do
    record_request_error(measurements, metadata)
  end

  defp handle_telemetry_event([:rubber_duck, :llm, :provider, :health], measurements, metadata) do
    record_provider_health(measurements, metadata)
  end

  defp handle_telemetry_event([:rubber_duck, :llm, :cost, :tracked], measurements, metadata) do
    record_cost_data(measurements, metadata)
  end

  defp handle_telemetry_event(_event, _measurements, _metadata) do
    :ok
  end

  ## Metric Recording Functions

  defp record_request_start(measurements, metadata) do
    key = {:request_start, metadata.provider_id, metadata.request_id}
    value = %{
      timestamp: measurements.start_time,
      operation: metadata.operation,
      metadata: metadata
    }
    :ets.insert(@metrics_table, {key, value})
  end

  defp record_request_stop(measurements, metadata) do
    provider_id = metadata.provider_id
    operation = metadata.operation
    
    # Record completion metrics
    key = {:request_complete, provider_id, metadata.request_id}
    value = %{
      timestamp: System.monotonic_time(:millisecond),
      duration: measurements.duration,
      tokens_used: measurements.tokens_used,
      cost: measurements.cost,
      operation: operation,
      result: metadata.result
    }
    :ets.insert(@metrics_table, {key, value})
    
    # Update provider aggregates
    update_provider_aggregates(provider_id, operation, :success, measurements)
  end

  defp record_request_error(measurements, metadata) do
    provider_id = metadata.provider_id
    operation = metadata.operation
    
    # Record error metrics
    key = {:request_error, provider_id, metadata.request_id}
    value = %{
      timestamp: System.monotonic_time(:millisecond),
      duration: measurements.duration,
      error_type: metadata.error_type,
      error_message: metadata.error_message,
      operation: operation
    }
    :ets.insert(@metrics_table, {key, value})
    
    # Update provider aggregates
    update_provider_aggregates(provider_id, operation, :error, measurements)
  end

  defp record_provider_health(measurements, metadata) do
    key = {:provider_health, metadata.provider_id, metadata.timestamp}
    value = %{
      health_status: metadata.health_status,
      timestamp: metadata.timestamp
    }
    :ets.insert(@metrics_table, {key, value})
  end

  defp record_cost_data(measurements, metadata) do
    key = {:cost, metadata.provider_id, metadata.timestamp}
    value = %{
      input_tokens: measurements.input_tokens,
      output_tokens: measurements.output_tokens,
      total_tokens: measurements.total_tokens,
      cost: measurements.cost,
      model: metadata.model,
      operation: metadata.operation,
      timestamp: metadata.timestamp
    }
    :ets.insert(@metrics_table, {key, value})
  end

  defp record_metric_internal(metric_name, value, metadata) do
    key = {:custom, metric_name, System.system_time(:millisecond)}
    metric_value = %{
      value: value,
      metadata: metadata,
      timestamp: System.system_time(:millisecond)
    }
    :ets.insert(@metrics_table, {key, metric_value})
  end

  ## Aggregation Functions

  defp update_provider_aggregates(provider_id, operation, result, measurements) do
    key = {:provider_aggregate, provider_id}
    
    case :ets.lookup(@metrics_table, key) do
      [] ->
        aggregate = initialize_provider_aggregate(provider_id)
        updated_aggregate = update_aggregate(aggregate, operation, result, measurements)
        :ets.insert(@metrics_table, {key, updated_aggregate})
      
      [{^key, aggregate}] ->
        updated_aggregate = update_aggregate(aggregate, operation, result, measurements)
        :ets.insert(@metrics_table, {key, updated_aggregate})
    end
  end

  defp initialize_provider_aggregate(provider_id) do
    %{
      provider_id: provider_id,
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      total_duration: 0,
      total_tokens: 0,
      total_cost: 0.0,
      average_duration: 0.0,
      error_rate: 0.0,
      operations: %{},
      last_updated: System.monotonic_time(:millisecond)
    }
  end

  defp update_aggregate(aggregate, operation, result, measurements) do
    total_requests = aggregate.total_requests + 1
    successful_requests = if result == :success, do: aggregate.successful_requests + 1, else: aggregate.successful_requests
    failed_requests = if result == :error, do: aggregate.failed_requests + 1, else: aggregate.failed_requests
    
    total_duration = aggregate.total_duration + Map.get(measurements, :duration, 0)
    total_tokens = aggregate.total_tokens + Map.get(measurements, :tokens_used, 0)
    total_cost = aggregate.total_cost + Map.get(measurements, :cost, 0.0)
    
    average_duration = if total_requests > 0, do: total_duration / total_requests, else: 0.0
    error_rate = if total_requests > 0, do: failed_requests / total_requests, else: 0.0
    
    # Update operation-specific metrics
    operation_stats = Map.get(aggregate.operations, operation, %{total: 0, successful: 0, failed: 0})
    updated_operation_stats = %{
      total: operation_stats.total + 1,
      successful: if(result == :success, do: operation_stats.successful + 1, else: operation_stats.successful),
      failed: if(result == :error, do: operation_stats.failed + 1, else: operation_stats.failed)
    }
    
    %{aggregate |
      total_requests: total_requests,
      successful_requests: successful_requests,
      failed_requests: failed_requests,
      total_duration: total_duration,
      total_tokens: total_tokens,
      total_cost: total_cost,
      average_duration: average_duration,
      error_rate: error_rate,
      operations: Map.put(aggregate.operations, operation, updated_operation_stats),
      last_updated: System.monotonic_time(:millisecond)
    }
  end

  defp perform_aggregation(state) do
    # Perform time-based aggregations and cleanup old data
    current_time = System.system_time(:millisecond)
    cutoff_time = current_time - @retention_period
    
    # Clean up old metrics
    cleanup_old_metrics(cutoff_time)
    
    # Calculate global aggregates
    global_aggregates = calculate_global_aggregates()
    
    %{state | aggregates: global_aggregates}
  end

  defp cleanup_old_metrics(cutoff_time) do
    # This is a simplified cleanup - in production you'd want more sophisticated cleanup
    :ets.select_delete(@metrics_table, [
      {{:request_start, :_, :_}, [], [true]},
      {{:request_complete, :_, :_}, [], [true]},
      {{:request_error, :_, :_}, [], [true]}
    ])
  end

  defp calculate_global_aggregates do
    # Calculate aggregates across all providers
    provider_aggregates = :ets.select(@metrics_table, [
      {{{:provider_aggregate, :"$1"}, :"$2"}, [], [:"$2"]}
    ])
    
    %{
      total_providers: length(provider_aggregates),
      total_requests: Enum.sum(Enum.map(provider_aggregates, & &1.total_requests)),
      total_cost: Enum.sum(Enum.map(provider_aggregates, & &1.total_cost)),
      average_error_rate: calculate_average_error_rate(provider_aggregates),
      timestamp: System.system_time(:second)
    }
  end

  defp calculate_average_error_rate([]), do: 0.0
  defp calculate_average_error_rate(aggregates) do
    total_error_rate = Enum.sum(Enum.map(aggregates, & &1.error_rate))
    total_error_rate / length(aggregates)
  end

  ## Query Functions

  defp get_provider_metrics_internal(provider_id) do
    case :ets.lookup(@metrics_table, {:provider_aggregate, provider_id}) do
      [] -> %{provider_id: provider_id, total_requests: 0}
      [{_, aggregate}] -> aggregate
    end
  end

  defp get_metrics_for_range_internal(start_time, end_time, filters) do
    # This is a simplified implementation
    # In production, you'd want more sophisticated querying
    provider_filter = Map.get(filters, :provider_id)
    
    all_metrics = :ets.tab2list(@metrics_table)
    
    Enum.filter(all_metrics, fn {key, value} ->
      timestamp = case key do
        {_, _, timestamp} when is_integer(timestamp) -> timestamp
        _ -> Map.get(value, :timestamp, 0)
      end
      
      timestamp >= start_time and timestamp <= end_time and
      (provider_filter == nil or match_provider_filter(key, provider_filter))
    end)
  end

  defp match_provider_filter({_, provider_id, _}, filter_provider_id) do
    provider_id == filter_provider_id
  end

  defp match_provider_filter(_, _), do: true

  defp calculate_performance_stats(state) do
    current_time = System.system_time(:second)
    uptime = current_time - state.start_time
    
    global_aggregates = Map.get(state.aggregates, :global, %{})
    
    %{
      uptime_seconds: uptime,
      total_requests: Map.get(global_aggregates, :total_requests, 0),
      requests_per_second: Map.get(global_aggregates, :total_requests, 0) / max(uptime, 1),
      average_error_rate: Map.get(global_aggregates, :average_error_rate, 0.0),
      total_cost: Map.get(global_aggregates, :total_cost, 0.0),
      timestamp: current_time
    }
  end

  defp schedule_aggregation do
    Process.send_after(self(), :aggregate_metrics, @aggregation_interval)
  end
end