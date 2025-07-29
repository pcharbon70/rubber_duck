defmodule RubberDuck.Jido.Agents.Metrics do
  @moduledoc """
  Metrics aggregation and computation for the agent system.
  
  Provides:
  - Real-time metrics collection
  - Statistical aggregations
  - Time-series data management
  - Export formats for monitoring systems
  
  ## Metrics Categories
  
  - **Throughput**: Actions per second, messages processed
  - **Latency**: P50, P95, P99 response times
  - **Errors**: Error rates, error types
  - **Resources**: Memory, CPU, queue sizes
  - **Availability**: Uptime, health status
  """
  
  use GenServer
  require Logger
  
  @metrics_window_size 300  # 5 minutes of second-resolution data
  @aggregation_interval 1000  # 1 second
  
  # Client API
  
  @doc """
  Starts the metrics aggregator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Records an action execution.
  """
  def record_action(agent_id, action, duration_us, status) do
    GenServer.cast(__MODULE__, {:record_action, agent_id, action, duration_us, status})
  end
  
  @doc """
  Records resource usage.
  """
  def record_resources(agent_id, memory, queue_length, reductions) do
    GenServer.cast(__MODULE__, {:record_resources, agent_id, memory, queue_length, reductions})
  end
  
  @doc """
  Records an error occurrence.
  """
  def record_error(agent_id, error_type) do
    GenServer.cast(__MODULE__, {:record_error, agent_id, error_type})
  end
  
  @doc """
  Gets current metrics for an agent.
  """
  def get_agent_metrics(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_metrics, agent_id})
  end
  
  @doc """
  Gets system-wide metrics.
  """
  def get_system_metrics do
    GenServer.call(__MODULE__, :get_system_metrics)
  end
  
  @doc """
  Exports metrics in Prometheus format.
  """
  def export_prometheus do
    GenServer.call(__MODULE__, :export_prometheus)
  end
  
  @doc """
  Exports metrics in StatsD format.
  """
  def export_statsd do
    GenServer.call(__MODULE__, :export_statsd)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Start aggregation timer
    Process.send_after(self(), :aggregate, @aggregation_interval)
    
    # Attach telemetry handlers
    attach_telemetry_handlers()
    
    state = %{
      # Time-series data (ring buffers)
      action_latencies: %{},     # agent_id => CircularBuffer of latencies
      throughput: %{},           # agent_id => CircularBuffer of counts
      error_rates: %{},          # agent_id => CircularBuffer of error counts
      resource_usage: %{},       # agent_id => CircularBuffer of {memory, cpu}
      
      # Current window data
      current_window: %{
        actions: %{},            # agent_id => [{action, duration, status}]
        errors: %{},             # agent_id => [error_type]
        resources: %{}           # agent_id => {memory, queue, reductions}
      },
      
      # Computed metrics
      metrics: %{
        agents: %{},             # agent_id => computed metrics
        system: %{}              # system-wide metrics
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:record_action, agent_id, action, duration_us, status}, state) do
    actions = get_in(state.current_window.actions, [agent_id]) || []
    updated_actions = [{action, duration_us, status} | actions]
    
    new_state = put_in(state, [:current_window, :actions, agent_id], updated_actions)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:record_resources, agent_id, memory, queue_length, reductions}, state) do
    new_state = put_in(state, [:current_window, :resources, agent_id], 
                      {memory, queue_length, reductions})
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:record_error, agent_id, error_type}, state) do
    errors = get_in(state.current_window.errors, [agent_id]) || []
    updated_errors = [error_type | errors]
    
    new_state = put_in(state, [:current_window, :errors, agent_id], updated_errors)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call({:get_agent_metrics, agent_id}, _from, state) do
    metrics = get_in(state.metrics.agents, [agent_id]) || %{}
    {:reply, {:ok, metrics}, state}
  end
  
  @impl true
  def handle_call(:get_system_metrics, _from, state) do
    {:reply, {:ok, state.metrics.system}, state}
  end
  
  @impl true
  def handle_call(:export_prometheus, _from, state) do
    export = build_prometheus_export(state.metrics)
    {:reply, {:ok, export}, state}
  end
  
  @impl true
  def handle_call(:export_statsd, _from, state) do
    export = build_statsd_export(state.metrics)
    {:reply, {:ok, export}, state}
  end
  
  @impl true
  def handle_info(:aggregate, state) do
    # Compute metrics for current window
    new_state = state
    |> aggregate_window_data()
    |> update_time_series()
    |> compute_metrics()
    |> clear_current_window()
    
    # Schedule next aggregation
    Process.send_after(self(), :aggregate, @aggregation_interval)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({[:rubber_duck, :agent | _rest], _measurements, _metadata, _}, state) do
    # Handle telemetry events
    {:noreply, state}
  end
  
  # Private functions
  
  defp attach_telemetry_handlers do
    events = [
      [:rubber_duck, :agent, :action, :stop],
      [:rubber_duck, :agent, :action, :exception],
      [:rubber_duck, :agent, :error],
      [:rubber_duck, :agent, :memory],
      [:rubber_duck, :agent, :cpu],
      [:rubber_duck, :agent, :message_queue]
    ]
    
    :telemetry.attach_many(
      "metrics-collector",
      events,
      &handle_telemetry_event/4,
      %{metrics_pid: self()}
    )
  end
  
  defp handle_telemetry_event([:rubber_duck, :agent, :action, :stop], measurements, metadata, %{metrics_pid: pid}) do
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)
    # The metadata should be directly available, not nested
    agent_id = Map.get(metadata, :agent_id)
    action = Map.get(metadata, :action)
    
    if agent_id && action do
      send(pid, {:record_action, agent_id, action, duration_us, :success})
    end
  end
  
  defp handle_telemetry_event([:rubber_duck, :agent, :action, :exception], _measurements, metadata, %{metrics_pid: pid}) do
    send(pid, {:record_action, metadata.agent_id, metadata.action, 0, :error})
    send(pid, {:record_error, metadata.agent_id, metadata.kind})
  end
  
  defp handle_telemetry_event([:rubber_duck, :agent, :error], _measurements, metadata, %{metrics_pid: pid}) do
    send(pid, {:record_error, metadata.agent_id, metadata.error})
  end
  
  defp handle_telemetry_event([:rubber_duck, :agent, resource_type], _measurements, _metadata, %{metrics_pid: _pid})
       when resource_type in [:memory, :cpu, :message_queue] do
    # Resource events are handled separately
    :ok
  end
  
  defp handle_telemetry_event(_, _, _, _), do: :ok
  
  defp aggregate_window_data(state) do
    # Aggregate action data
    action_summaries = Enum.map(state.current_window.actions, fn {agent_id, actions} ->
      latencies = actions
      |> Enum.filter(fn {_, _, status} -> status == :success end)
      |> Enum.map(fn {_, duration, _} -> duration end)
      
      error_count = Enum.count(actions, fn {_, _, status} -> status == :error end)
      
      {agent_id, %{
        count: length(actions),
        latencies: latencies,
        error_count: error_count
      }}
    end)
    |> Map.new()
    
    # Also aggregate error data
    error_summaries = Enum.map(state.current_window.errors, fn {agent_id, errors} ->
      {agent_id, length(errors)}
    end)
    |> Map.new()
    
    put_in(state, [:current_window, :aggregated], Map.merge(action_summaries, %{errors: error_summaries}))
  end
  
  defp update_time_series(state) do
    aggregated = Map.delete(state.current_window.aggregated || %{}, :errors)
    
    # Update latency time series
    new_latencies = Enum.reduce(aggregated, state.action_latencies, 
      fn {agent_id, summary}, acc ->
        buffer = Map.get(acc, agent_id, CircularBuffer.new(@metrics_window_size))
        updated = CircularBuffer.push(buffer, summary.latencies)
        Map.put(acc, agent_id, updated)
      end)
    
    # Update throughput time series
    new_throughput = Enum.reduce(aggregated, state.throughput,
      fn {agent_id, summary}, acc ->
        buffer = Map.get(acc, agent_id, CircularBuffer.new(@metrics_window_size))
        updated = CircularBuffer.push(buffer, summary.count)
        Map.put(acc, agent_id, updated)
      end)
    
    # Update error rates time series
    new_error_rates = Enum.reduce(aggregated, state.error_rates,
      fn {agent_id, summary}, acc ->
        buffer = Map.get(acc, agent_id, CircularBuffer.new(@metrics_window_size))
        error_rate = if summary.count > 0, do: summary.error_count / summary.count, else: 0
        updated = CircularBuffer.push(buffer, error_rate)
        Map.put(acc, agent_id, updated)
      end)
    
    %{state | 
      action_latencies: new_latencies,
      throughput: new_throughput,
      error_rates: new_error_rates
    }
  end
  
  defp compute_metrics(state) do
    # Compute per-agent metrics
    agent_metrics = Enum.map(state.action_latencies, fn {agent_id, latency_buffer} ->
      all_latencies = CircularBuffer.to_list(latency_buffer) |> List.flatten()
      
      metrics = if length(all_latencies) > 0 do
        sorted = Enum.sort(all_latencies)
        %{
          latency_p50: percentile(sorted, 0.5),
          latency_p95: percentile(sorted, 0.95),
          latency_p99: percentile(sorted, 0.99),
          latency_mean: Enum.sum(sorted) / length(sorted),
          throughput: calculate_throughput(Map.get(state.throughput, agent_id)),
          error_rate: calculate_error_rate(Map.get(state.error_rates, agent_id))
        }
      else
        %{
          latency_p50: 0,
          latency_p95: 0,
          latency_p99: 0,
          latency_mean: 0,
          throughput: 0,
          error_rate: 0
        }
      end
      
      {agent_id, metrics}
    end)
    |> Map.new()
    
    # Compute system-wide metrics
    system_metrics = %{
      total_agents: map_size(agent_metrics),
      total_throughput: agent_metrics |> Map.values() |> Enum.map(& &1.throughput) |> Enum.sum(),
      avg_latency: calculate_system_avg_latency(agent_metrics),
      total_errors: calculate_total_errors(state.error_rates)
    }
    
    put_in(state, [:metrics], %{agents: agent_metrics, system: system_metrics})
  end
  
  defp clear_current_window(state) do
    put_in(state, [:current_window], %{
      actions: %{},
      errors: %{},
      resources: %{}
    })
  end
  
  defp percentile(sorted_list, p) do
    k = (length(sorted_list) - 1) * p
    f = :erlang.floor(k)
    c = :erlang.ceil(k)
    
    if f == c do
      Enum.at(sorted_list, trunc(k))
    else
      v0 = Enum.at(sorted_list, trunc(f))
      v1 = Enum.at(sorted_list, trunc(c))
      v0 + (k - f) * (v1 - v0)
    end
  end
  
  defp calculate_throughput(nil), do: 0
  defp calculate_throughput(throughput_buffer) do
    counts = CircularBuffer.to_list(throughput_buffer)
    if length(counts) > 0 do
      Enum.sum(counts) / length(counts)
    else
      0
    end
  end
  
  defp calculate_error_rate(nil), do: 0
  defp calculate_error_rate(error_rate_buffer) do
    rates = CircularBuffer.to_list(error_rate_buffer)
    if length(rates) > 0 do
      Enum.sum(rates) / length(rates)
    else
      0
    end
  end
  
  defp calculate_system_avg_latency(agent_metrics) do
    latencies = agent_metrics |> Map.values() |> Enum.map(& &1.latency_mean)
    if length(latencies) > 0 do
      Enum.sum(latencies) / length(latencies)
    else
      0
    end
  end
  
  defp calculate_total_errors(error_rates) do
    error_rates
    |> Map.values()
    |> Enum.map(&CircularBuffer.to_list/1)
    |> List.flatten()
    |> Enum.sum()
    |> round()
  end
  
  defp build_prometheus_export(metrics) do
    lines = []
    
    # Agent metrics
    lines = Enum.reduce(metrics.agents, lines, fn {agent_id, agent_metrics}, acc ->
      acc ++ [
        "# HELP agent_latency_microseconds Request latency in microseconds",
        "# TYPE agent_latency_microseconds summary",
        ~s(agent_latency_microseconds{agent_id="#{agent_id}",quantile="0.5"} #{agent_metrics.latency_p50}),
        ~s(agent_latency_microseconds{agent_id="#{agent_id}",quantile="0.95"} #{agent_metrics.latency_p95}),
        ~s(agent_latency_microseconds{agent_id="#{agent_id}",quantile="0.99"} #{agent_metrics.latency_p99}),
        "",
        "# HELP agent_throughput_ops Operations per second",
        "# TYPE agent_throughput_ops gauge",
        ~s(agent_throughput_ops{agent_id="#{agent_id}"} #{agent_metrics.throughput}),
        "",
        "# HELP agent_error_rate Error rate",
        "# TYPE agent_error_rate gauge", 
        ~s(agent_error_rate{agent_id="#{agent_id}"} #{agent_metrics.error_rate})
      ]
    end)
    
    # System metrics
    lines ++ [
      "",
      "# HELP system_total_agents Total number of agents",
      "# TYPE system_total_agents gauge",
      "system_total_agents #{metrics.system.total_agents}",
      "",
      "# HELP system_total_throughput Total system throughput",
      "# TYPE system_total_throughput gauge",
      "system_total_throughput #{metrics.system.total_throughput}"
    ]
    |> Enum.join("\n")
  end
  
  defp build_statsd_export(metrics) do
    lines = []
    
    # Agent metrics
    lines = Enum.reduce(metrics.agents, lines, fn {agent_id, agent_metrics}, acc ->
      acc ++ [
        "agent.latency.p50.#{agent_id}:#{agent_metrics.latency_p50}|ms",
        "agent.latency.p95.#{agent_id}:#{agent_metrics.latency_p95}|ms",
        "agent.latency.p99.#{agent_id}:#{agent_metrics.latency_p99}|ms",
        "agent.throughput.#{agent_id}:#{agent_metrics.throughput}|c",
        "agent.error_rate.#{agent_id}:#{agent_metrics.error_rate}|g"
      ]
    end)
    
    # System metrics
    lines ++ [
      "system.total_agents:#{metrics.system.total_agents}|g",
      "system.total_throughput:#{metrics.system.total_throughput}|c"
    ]
  end
end

# Simple circular buffer implementation
defmodule CircularBuffer do
  defstruct [:capacity, :buffer, :position, :full?]
  
  def new(capacity) do
    %__MODULE__{
      capacity: capacity,
      buffer: :array.new(capacity, default: nil),
      position: 0,
      full?: false
    }
  end
  
  def push(%__MODULE__{} = cb, item) do
    buffer = :array.set(cb.position, item, cb.buffer)
    position = rem(cb.position + 1, cb.capacity)
    full? = cb.full? or position == 0
    
    %{cb | buffer: buffer, position: position, full?: full?}
  end
  
  def to_list(%__MODULE__{} = cb) do
    if cb.full? do
      # Full buffer: read from position to end, then from start to position
      end_part = if cb.position <= cb.capacity - 1 do
        for i <- cb.position..(cb.capacity - 1), do: :array.get(i, cb.buffer)
      else
        []
      end
      
      start_part = if cb.position > 0 do
        for i <- 0..(cb.position - 1), do: :array.get(i, cb.buffer)
      else
        []
      end
      
      end_part ++ start_part
    else
      # Partial buffer: read from start to position
      if cb.position > 0 do
        for i <- 0..(cb.position - 1), do: :array.get(i, cb.buffer)
      else
        []
      end
    end
    |> Enum.reject(&is_nil/1)
  end
end