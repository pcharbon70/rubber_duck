defmodule RubberDuck.Jido.Actions.LLMRouter.UpdateMetricsAction do
  @moduledoc """
  Internal action for updating LLM Router metrics.
  
  This action handles metrics updates including request completion tracking,
  provider load management, latency metrics, and error rate calculations.
  """
  
  use Jido.Action,
    name: "update_metrics",
    description: "Updates internal routing metrics",
    schema: [
      request_id: [type: :string, required: true],
      provider: [type: :atom, required: true],
      model: [type: :string, default: nil],
      status: [type: :atom, required: true],
      latency: [type: :integer, required: true]
    ]

  alias RubberDuck.Jido.Actions.Base.UpdateStateAction

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Remove from active requests
    updated_active_requests = Map.delete(agent.state.active_requests, params.request_id)
    
    # Update provider load
    updated_provider_states = update_in(
      agent.state.provider_states,
      [params.provider, :current_load],
      fn load -> max((load || 0) - 1, 0) end
    )
    
    # Update metrics
    updated_metrics = agent.state.metrics
    |> Map.update!(:total_requests, &(&1 + 1))
    |> update_in([:requests_by_provider, params.provider], &((&1 || 0) + 1))
    |> update_model_metrics(params.model)
    |> update_latency_metrics(params.provider, params.status, params.latency)
    |> update_error_metrics(params.provider, params.status)
    
    state_updates = %{
      active_requests: updated_active_requests,
      provider_states: updated_provider_states,
      metrics: updated_metrics
    }
    
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end

  # Private helper functions

  defp update_model_metrics(metrics, nil), do: metrics
  defp update_model_metrics(metrics, model) do
    update_in(metrics, [:requests_by_model, model], &((&1 || 0) + 1))
  end

  defp update_latency_metrics(metrics, provider, :success, latency) when latency > 0 do
    update_in(metrics, [:avg_latency_by_provider, provider], fn current ->
      if current do
        # Weighted average
        (current * 0.95) + (latency * 0.05)
      else
        latency
      end
    end)
  end
  defp update_latency_metrics(metrics, _provider, _status, _latency), do: metrics

  defp update_error_metrics(metrics, provider, :failure) do
    update_in(metrics, [:error_rates, provider], fn current ->
      total = get_in(metrics, [:requests_by_provider, provider]) || 1
      ((current || 0.0) * (total - 1) + 1.0) / total
    end)
  end
  defp update_error_metrics(metrics, _provider, _status), do: metrics
end