defmodule RubberDuck.Jido.Actions.Conversation.Router.GetRoutingMetricsAction do
  @moduledoc """
  Action for retrieving routing metrics from the Conversation Router Agent.
  
  This action collects and returns comprehensive routing metrics including:
  - Request counts and route usage statistics
  - Circuit breaker states
  - Performance metrics (routing times)
  - Failure counts and types
  """
  
  use Jido.Action,
    name: "get_routing_metrics",
    description: "Retrieves comprehensive routing metrics and statistics",
    schema: [
      include_circuit_breakers: [type: :boolean, default: true, doc: "Whether to include circuit breaker status"],
      include_rules: [type: :boolean, default: false, doc: "Whether to include current routing rules"]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Build comprehensive metrics
    metrics_data = %{
      # Core metrics from agent state
      metrics: agent.state.metrics,
      
      # Circuit breaker information (if requested)
      circuit_breakers: if(params.include_circuit_breakers, do: agent.state.circuit_breakers, else: nil),
      
      # Routing rules (if requested)
      routing_rules: if(params.include_rules, do: agent.state.routing_rules, else: nil),
      
      # Routing table
      routing_table: agent.state.routing_table,
      default_route: agent.state.default_route,
      
      # Context cache info
      context_cache_size: map_size(agent.state.context_cache),
      context_ttl: agent.state.context_ttl,
      
      timestamp: DateTime.utc_now()
    }
    
    # Emit metrics signal
    with {:ok, _} <- emit_metrics_signal(agent, metrics_data) do
      {:ok, %{
        metrics_collected: true,
        total_requests: agent.state.metrics.total_requests,
        active_routes: map_size(agent.state.metrics.routes_used)
      }, %{agent: agent}}
    end
  end

  # Private functions

  defp emit_metrics_signal(agent, metrics_data) do
    signal_params = %{
      signal_type: "conversation.routing.metrics",
      data: Map.merge(metrics_data, %{
        agent_type: "conversation_router",
        collection_time: DateTime.utc_now()
      })
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end