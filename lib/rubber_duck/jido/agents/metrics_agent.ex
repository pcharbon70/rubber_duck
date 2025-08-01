defmodule RubberDuck.Jido.Agents.MetricsAgent do
  @moduledoc """
  Metrics aggregation and computation agent using the Jido pattern.
  
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
  
  ## Available Actions
  
  - `record_action` - Record agent action execution
  - `record_resources` - Record resource usage
  - `record_error` - Record error occurrence
  - `get_agent_metrics` - Get metrics for specific agent
  - `get_system_metrics` - Get system-wide metrics
  - `export_prometheus` - Export in Prometheus format
  - `export_statsd` - Export in StatsD format
  - `aggregate_metrics` - Process current window data
  """

  use Jido.Agent,
    name: "metrics",
    description: "Metrics aggregation and computation for the agent system",
    schema: [
      # Time-series data (ring buffers)
      action_latencies: [type: :map, default: %{}],     # agent_id => CircularBuffer of latencies
      throughput: [type: :map, default: %{}],           # agent_id => CircularBuffer of counts
      error_rates: [type: :map, default: %{}],          # agent_id => CircularBuffer of error counts
      resource_usage: [type: :map, default: %{}],       # agent_id => CircularBuffer of {memory, cpu}
      
      # Current window data
      current_window: [type: :map, default: %{
        actions: %{},            # agent_id => [{action, duration, status}]
        errors: %{},             # agent_id => [error_type]
        resources: %{}           # agent_id => {memory, queue, reductions}
      }],
      
      # Computed metrics
      metrics: [type: :map, default: %{
        agents: %{},             # agent_id => computed metrics
        system: %{}              # system-wide metrics
      }],
      
      # Configuration
      aggregation_interval: [type: :integer, default: 1000],  # 1 second
      metrics_window_size: [type: :integer, default: 300]     # 5 minutes
    ],
    actions: [
      RubberDuck.Jido.Actions.Metrics.RecordActionAction,
      RubberDuck.Jido.Actions.Metrics.RecordResourcesAction,
      RubberDuck.Jido.Actions.Metrics.RecordErrorAction,
      RubberDuck.Jido.Actions.Metrics.GetAgentMetricsAction,
      RubberDuck.Jido.Actions.Metrics.GetSystemMetricsAction,
      RubberDuck.Jido.Actions.Metrics.ExportPrometheusAction,
      RubberDuck.Jido.Actions.Metrics.ExportStatsdAction,
      RubberDuck.Jido.Actions.Metrics.AggregateMetricsAction
    ]

  require Logger

  def mount(agent) do
    # Attach telemetry handlers
    attach_telemetry_handlers(agent.id)
    
    # Schedule first aggregation
    schedule_aggregation(agent.state.aggregation_interval)
    
    Logger.info("Metrics Agent initialized", agent_id: agent.id)
    {:ok, agent}
  end

  def unmount(agent) do
    # Detach telemetry handlers
    :telemetry.detach("metrics-collector")
    
    Logger.info("Metrics Agent terminated", agent_id: agent.id)
    {:ok, agent}
  end

  # Helper functions

  defp attach_telemetry_handlers(agent_id) do
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
      %{agent_id: agent_id}
    )
  end

  defp handle_telemetry_event([:rubber_duck, :agent, :action, :stop], measurements, metadata, %{agent_id: metrics_agent_id}) do
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)
    agent_id = Map.get(metadata, :agent_id)
    action = Map.get(metadata, :action)
    
    if agent_id && action do
      # Send signal to record the action
      signal = Jido.Signal.new!(%{
        type: "metrics.record_action",
        source: "telemetry",
        data: %{
          agent_id: agent_id,
          action: action,
          duration_us: duration_us,
          status: :success
        }
      })
      
      Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
    end
  end

  defp handle_telemetry_event([:rubber_duck, :agent, :action, :exception], _measurements, metadata, %{agent_id: _metrics_agent_id}) do
    signal = Jido.Signal.new!(%{
      type: "metrics.record_error",
      source: "telemetry", 
      data: %{
        agent_id: metadata.agent_id,
        error_type: metadata.kind
      }
    })
    
    Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
  end

  defp handle_telemetry_event([:rubber_duck, :agent, :error], _measurements, metadata, %{agent_id: _metrics_agent_id}) do
    signal = Jido.Signal.new!(%{
      type: "metrics.record_error",
      source: "telemetry",
      data: %{
        agent_id: metadata.agent_id,
        error_type: metadata.error
      }
    })
    
    Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
  end

  defp handle_telemetry_event([:rubber_duck, :agent, resource_type], _measurements, _metadata, %{agent_id: _metrics_agent_id}) 
       when resource_type in [:memory, :cpu, :message_queue] do
    # Resource events are handled separately
    :ok
  end

  defp handle_telemetry_event(_, _, _, _), do: :ok

  defp schedule_aggregation(interval) do
    Process.send_after(self(), {:run_action, "aggregate_metrics", %{}}, interval)
  end
end