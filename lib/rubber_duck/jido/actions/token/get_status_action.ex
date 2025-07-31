defmodule RubberDuck.Jido.Actions.Token.GetStatusAction do
  @moduledoc """
  Action for retrieving the current status and health metrics of the Token Manager Agent.
  
  This action provides comprehensive status information including buffer states,
  active requests, metrics, and overall health indicators.
  """
  
  use Jido.Action,
    name: "get_status",
    description: "Retrieves Token Manager Agent status and health metrics",
    schema: []

  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    
    status = build_status_report(agent)
    
    {:ok, status, %{agent: agent}}
  end

  # Private functions

  defp build_status_report(agent) do
    %{
      "healthy" => true,
      "budgets_active" => map_size(agent.state.budgets),
      "active_requests" => map_size(agent.state.active_requests),
      "buffer_size" => length(agent.state.usage_buffer),
      "provenance_buffer_size" => length(agent.state.provenance_buffer),
      "relationships_tracked" => length(agent.state.provenance_graph),
      "total_tracked" => agent.state.metrics.requests_tracked,
      "total_tokens" => agent.state.metrics.total_tokens,
      "total_cost" => Decimal.to_string(agent.state.metrics.total_cost),
      "last_flush" => agent.state.metrics.last_flush,
      "config" => agent.state.config,
      "pricing_models_loaded" => count_pricing_models(agent.state.pricing_models),
      "timestamp" => DateTime.utc_now()
    }
  end

  defp count_pricing_models(pricing_models) do
    pricing_models
    |> Enum.map(fn {_provider, models} -> map_size(models) end)
    |> Enum.sum()
  end
end