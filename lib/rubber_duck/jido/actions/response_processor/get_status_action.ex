defmodule RubberDuck.Jido.Actions.ResponseProcessor.GetStatusAction do
  @moduledoc """
  Action for retrieving agent health and status information.
  
  This action builds and returns a comprehensive status report including
  agent health, configuration, and operational statistics.
  """
  
  use Jido.Action,
    name: "get_status",
    description: "Retrieves agent health status and operational information",
    schema: []

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    status = build_status_report(agent)
    
    signal_data = Map.merge(status, %{
      timestamp: DateTime.utc_now()
    })
    
    case EmitSignalAction.run(
      %{signal_type: "response.status", data: signal_data},
      %{agent: agent}
    ) do
      {:ok, _result, %{agent: updated_agent}} ->
        {:ok, signal_data, %{agent: updated_agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end

  # Private functions

  defp build_status_report(agent) do
    %{
      "status" => "healthy",
      "cache_size" => map_size(agent.state.cache),
      "total_processed" => agent.state.metrics.total_processed,
      "uptime" => get_uptime(),
      "parsers_available" => Map.keys(agent.state.parsers),
      "enhancers_enabled" => agent.state.enhancers,
      "validators_active" => agent.state.validators,
      "configuration" => agent.state.config,
      "memory_usage" => calculate_memory_usage(agent)
    }
  end

  defp calculate_memory_usage(agent) do
    # Simplified memory calculation
    cache_size = map_size(agent.state.cache) * 2048  # rough estimate per entry
    metrics_size = 1024  # rough estimate for metrics
    
    %{
      "cache_bytes" => cache_size,
      "metrics_bytes" => metrics_size,
      "total_bytes" => cache_size + metrics_size
    }
  end

  defp get_uptime do
    # Simple uptime calculation
    System.monotonic_time(:second)
  end
end