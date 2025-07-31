defmodule RubberDuck.Jido.Actions.LLMRouter.ProviderHealthAction do
  @moduledoc """
  Action for updating provider health status in the LLM Router Agent.
  
  This action processes health check results, updates provider state,
  tracks consecutive failures, and updates latency metrics for healthy providers.
  """
  
  use Jido.Action,
    name: "provider_health",
    description: "Updates provider health status and metrics",
    schema: [
      provider: [type: :string, required: true],
      status: [type: :string, required: true],
      latency_ms: [type: :integer, default: nil]
    ]

  alias RubberDuck.Jido.Actions.Base.UpdateStateAction
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    provider_name = String.to_atom(params.provider)
    health_status = parse_health_status(params.status)
    
    case agent.state.provider_states[provider_name] do
      nil ->
        Logger.warning("Received health update for unknown provider: #{params.provider}")
        {:ok, %{
          "updated" => false,
          "provider" => params.provider,
          "reason" => "Provider not found"
        }, %{agent: agent}}
      
      current_state ->
        with {:ok, updated_agent} <- update_provider_health(
               agent, 
               provider_name, 
               current_state, 
               health_status, 
               params.latency_ms
             ) do
          {:ok, %{
            "updated" => true,
            "provider" => params.provider,
            "status" => params.status,
            "consecutive_failures" => get_consecutive_failures(updated_agent, provider_name)
          }, %{agent: updated_agent}}
        end
    end
  end

  # Private functions

  defp parse_health_status("healthy"), do: :healthy
  defp parse_health_status(_), do: :unhealthy

  defp update_provider_health(agent, provider_name, current_state, health_status, latency_ms) do
    # Update provider state
    updated_state = current_state
    |> Map.put(:status, health_status)
    |> Map.put(:last_health_check, System.monotonic_time(:millisecond))
    |> Map.update(:consecutive_failures, 0, fn failures ->
      if health_status == :healthy, do: 0, else: failures + 1
    end)
    
    # Prepare state updates
    state_updates = %{
      provider_states: Map.put(agent.state.provider_states, provider_name, updated_state)
    }
    
    # Update latency metrics if provider is healthy and latency is provided
    state_updates = if health_status == :healthy && latency_ms do
      metrics_update = update_latency_metrics(agent.state.metrics, provider_name, latency_ms)
      Map.put(state_updates, :metrics, metrics_update)
    else
      state_updates
    end
    
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end

  defp update_latency_metrics(metrics, provider_name, latency_ms) do
    current_latency = metrics.avg_latency_by_provider[provider_name]
    
    new_avg_latency = if current_latency do
      # Simple moving average (90% old, 10% new)
      (current_latency * 0.9) + (latency_ms * 0.1)
    else
      latency_ms
    end
    
    put_in(metrics.avg_latency_by_provider[provider_name], new_avg_latency)
  end

  defp get_consecutive_failures(agent, provider_name) do
    case agent.state.provider_states[provider_name] do
      nil -> 0
      state -> state.consecutive_failures || 0
    end
  end
end