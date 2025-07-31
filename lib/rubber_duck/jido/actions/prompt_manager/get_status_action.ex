defmodule RubberDuck.Jido.Actions.PromptManager.GetStatusAction do
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

  @impl true
  def run(_params, context) do
    agent = context.agent
    status = build_status_report(agent)
    
    signal_data = Map.merge(status, %{
      timestamp: DateTime.utc_now()
    })
    
    case EmitSignalAction.run(
      %{signal_type: "prompt.status.report", data: signal_data},
      %{agent: agent}
    ) do
      {:ok, _result, %{agent: updated_agent}} ->
        {:ok, signal_data, %{agent: updated_agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end

  # Private helper functions

  defp build_status_report(agent) do
    %{
      "templates_count" => map_size(agent.state.templates),
      "experiments_count" => map_size(agent.state.experiments),
      "cache_size" => map_size(agent.state.cache),
      "memory_usage" => calculate_memory_usage(agent),
      "uptime" => get_uptime(),
      "health" => "healthy"
    }
  end

  defp calculate_memory_usage(agent) do
    # Simplified memory calculation
    template_size = map_size(agent.state.templates) * 1024  # rough estimate
    cache_size = map_size(agent.state.cache) * 512
    
    %{
      "templates_bytes" => template_size,
      "cache_bytes" => cache_size,
      "total_bytes" => template_size + cache_size
    }
  end

  defp get_uptime do
    # Simple uptime calculation
    # In production, would track actual start time
    System.monotonic_time(:second)
  end
end