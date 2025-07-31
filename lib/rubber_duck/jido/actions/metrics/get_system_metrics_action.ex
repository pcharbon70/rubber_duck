defmodule RubberDuck.Jido.Actions.Metrics.GetSystemMetricsAction do
  @moduledoc """
  Action for retrieving system-wide metrics aggregation.
  
  This action returns overall system performance metrics including
  total throughput, average latency, and system health indicators.
  """
  
  use Jido.Action,
    name: "get_system_metrics",
    description: "Retrieves system-wide performance metrics",
    schema: []

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    
    Logger.debug("Retrieving system metrics")
    
    # Get system-wide metrics
    system_metrics = agent.state.metrics.system || %{}
    
    # Emit metrics response
    signal_params = %{
      signal_type: "metrics.system.response",
      data: %{
        metrics: system_metrics,
        timestamp: DateTime.utc_now()
      }
    }
    
    case EmitSignalAction.run(signal_params, %{agent: agent}) do
      {:ok, _} ->
        {:ok, %{metrics: system_metrics}, %{agent: agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end
end