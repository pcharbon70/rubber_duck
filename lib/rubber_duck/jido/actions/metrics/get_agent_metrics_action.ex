defmodule RubberDuck.Jido.Actions.Metrics.GetAgentMetricsAction do
  @moduledoc """
  Action for retrieving computed metrics for a specific agent.
  
  This action returns the current performance metrics for an agent
  including latency percentiles, throughput, and error rates.
  """
  
  use Jido.Action,
    name: "get_agent_metrics",
    description: "Retrieves computed metrics for a specific agent",
    schema: [
      agent_id: [
        type: :string,
        required: true,
        doc: "ID of the agent to get metrics for"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{agent_id: agent_id} = params
    
    Logger.debug("Retrieving agent metrics", agent_id: agent_id)
    
    # Get metrics for the requested agent
    agent_metrics = get_in(agent.state.metrics, [:agents, agent_id]) || %{}
    
    # Emit metrics response
    signal_params = %{
      signal_type: "metrics.agent.response",
      data: %{
        agent_id: agent_id,
        metrics: agent_metrics,
        timestamp: DateTime.utc_now()
      }
    }
    
    case EmitSignalAction.run(signal_params, %{agent: agent}) do
      {:ok, _} ->
        {:ok, %{metrics: agent_metrics}, %{agent: agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end
end