defmodule RubberDuck.Jido.Actions.Metrics.ExportStatsdAction do
  @moduledoc """
  Action for exporting metrics in StatsD format.
  
  This action generates StatsD-compatible metrics output for
  integration with StatsD collectors and monitoring systems.
  """
  
  use Jido.Action,
    name: "export_statsd",
    description: "Exports metrics in StatsD format",
    schema: []

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    
    Logger.debug("Exporting StatsD metrics")
    
    # Build StatsD export
    statsd_export = build_statsd_export(agent.state.metrics)
    
    # Emit export response
    signal_params = %{
      signal_type: "metrics.statsd.export",
      data: %{
        export: statsd_export,
        format: "statsd",
        timestamp: DateTime.utc_now()
      }
    }
    
    case EmitSignalAction.run(signal_params, %{agent: agent}) do
      {:ok, _} ->
        {:ok, %{export: statsd_export}, %{agent: agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end

  # Private functions
  
  defp build_statsd_export(metrics) do
    lines = []
    
    # Agent metrics
    lines = if Map.has_key?(metrics, :agents) do
      Enum.reduce(metrics.agents, lines, fn {agent_id, agent_metrics}, acc ->
        acc ++ [
          "agent.latency.p50.#{agent_id}:#{Map.get(agent_metrics, :latency_p50, 0)}|ms",
          "agent.latency.p95.#{agent_id}:#{Map.get(agent_metrics, :latency_p95, 0)}|ms",
          "agent.latency.p99.#{agent_id}:#{Map.get(agent_metrics, :latency_p99, 0)}|ms",
          "agent.throughput.#{agent_id}:#{Map.get(agent_metrics, :throughput, 0)}|c",
          "agent.error_rate.#{agent_id}:#{Map.get(agent_metrics, :error_rate, 0)}|g"
        ]
      end)
    else
      lines
    end
    
    # System metrics
    system_metrics = Map.get(metrics, :system, %{})
    lines ++ [
      "system.total_agents:#{Map.get(system_metrics, :total_agents, 0)}|g",
      "system.total_throughput:#{Map.get(system_metrics, :total_throughput, 0)}|c",
      "system.avg_latency:#{Map.get(system_metrics, :avg_latency, 0)}|ms",
      "system.total_errors:#{Map.get(system_metrics, :total_errors, 0)}|c"
    ]
  end
end