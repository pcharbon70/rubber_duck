defmodule RubberDuck.Jido.Actions.Metrics.ExportPrometheusAction do
  @moduledoc """
  Action for exporting metrics in Prometheus format.
  
  This action generates Prometheus-compatible metrics output for
  integration with monitoring and alerting systems.
  """
  
  use Jido.Action,
    name: "export_prometheus",
    description: "Exports metrics in Prometheus format",
    schema: []

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    
    Logger.debug("Exporting Prometheus metrics")
    
    # Build Prometheus export
    prometheus_export = build_prometheus_export(agent.state.metrics)
    
    # Emit export response
    signal_params = %{
      signal_type: "metrics.prometheus.export",
      data: %{
        export: prometheus_export,
        format: "text/plain",
        timestamp: DateTime.utc_now()
      }
    }
    
    case EmitSignalAction.run(signal_params, %{agent: agent}) do
      {:ok, _} ->
        {:ok, %{export: prometheus_export}, %{agent: agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end

  # Private functions
  
  defp build_prometheus_export(metrics) do
    lines = []
    
    # Agent metrics
    lines = if Map.has_key?(metrics, :agents) do
      Enum.reduce(metrics.agents, lines, fn {agent_id, agent_metrics}, acc ->
        acc ++ [
          "# HELP agent_latency_microseconds Request latency in microseconds",
          "# TYPE agent_latency_microseconds summary",
          ~s(agent_latency_microseconds{agent_id="#{agent_id}",quantile="0.5"} #{Map.get(agent_metrics, :latency_p50, 0)}),
          ~s(agent_latency_microseconds{agent_id="#{agent_id}",quantile="0.95"} #{Map.get(agent_metrics, :latency_p95, 0)}),
          ~s(agent_latency_microseconds{agent_id="#{agent_id}",quantile="0.99"} #{Map.get(agent_metrics, :latency_p99, 0)}),
          "",
          "# HELP agent_throughput_ops Operations per second",
          "# TYPE agent_throughput_ops gauge",
          ~s(agent_throughput_ops{agent_id="#{agent_id}"} #{Map.get(agent_metrics, :throughput, 0)}),
          "",
          "# HELP agent_error_rate Error rate",
          "# TYPE agent_error_rate gauge", 
          ~s(agent_error_rate{agent_id="#{agent_id}"} #{Map.get(agent_metrics, :error_rate, 0)})
        ]
      end)
    else
      lines
    end
    
    # System metrics
    system_metrics = Map.get(metrics, :system, %{})
    lines = lines ++ [
      "",
      "# HELP system_total_agents Total number of agents",
      "# TYPE system_total_agents gauge",
      "system_total_agents #{Map.get(system_metrics, :total_agents, 0)}",
      "",
      "# HELP system_total_throughput Total system throughput",
      "# TYPE system_total_throughput gauge",
      "system_total_throughput #{Map.get(system_metrics, :total_throughput, 0)}",
      "",
      "# HELP system_avg_latency Average system latency",
      "# TYPE system_avg_latency gauge",
      "system_avg_latency #{Map.get(system_metrics, :avg_latency, 0)}",
      "",
      "# HELP system_total_errors Total system errors",
      "# TYPE system_total_errors counter",
      "system_total_errors #{Map.get(system_metrics, :total_errors, 0)}"
    ]
    
    # Metadata
    lines ++ [
      "",
      "# HELP metrics_last_updated_timestamp Unix timestamp of last metrics update",
      "# TYPE metrics_last_updated_timestamp gauge",
      "metrics_last_updated_timestamp #{DateTime.utc_now() |> DateTime.to_unix()}"
    ]
    |> Enum.join("\n")
  end
end