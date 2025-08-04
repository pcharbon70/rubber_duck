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
  alias RubberDuck.Agents.{ErrorHandling, ActionErrorPatterns}
  require Logger

  @impl true
  def run(params, context) do
    ErrorHandling.safe_execute(fn ->
      # Validate parameters and context
      with :ok <- validate_metrics_params(params),
           :ok <- validate_metrics_context(context) do
        
        agent = context.agent
        
        # Safely update metrics with error handling
        case update_all_metrics(agent, params) do
          {:ok, state_updates} ->
            case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
              {:ok, result, context} ->
                {:ok, result, context}
              {:error, reason} ->
                ErrorHandling.system_error("Failed to update state: #{inspect(reason)}", %{reason: reason})
              error ->
                ErrorHandling.categorize_error(error)
            end
            
          error -> error
        end
      end
    end)
  end
  
  defp validate_metrics_params(%{request_id: id, provider: provider, status: status, latency: latency}) 
       when is_binary(id) and byte_size(id) > 0 and is_atom(provider) and is_atom(status) and is_integer(latency) and latency >= 0, do: :ok
  defp validate_metrics_params(params), do: ErrorHandling.validation_error("Invalid parameters for metrics update", %{params: params})
  
  defp validate_metrics_context(%{agent: %{state: %{active_requests: requests, provider_states: states, metrics: metrics}}}) 
       when is_map(requests) and is_map(states) and is_map(metrics), do: :ok
  defp validate_metrics_context(_), do: ErrorHandling.validation_error("Invalid context: missing required agent state", %{})
  
  defp update_all_metrics(agent, params) do
    try do
      # Remove from active requests
      updated_active_requests = Map.delete(agent.state.active_requests, params.request_id)
      
      # Update provider load
      updated_provider_states = safe_update_provider_load(agent.state.provider_states, params.provider)
      
      # Update metrics
      updated_metrics = safe_update_metrics(agent.state.metrics, params)
      
      state_updates = %{
        active_requests: updated_active_requests,
        provider_states: updated_provider_states,
        metrics: updated_metrics
      }
      
      {:ok, state_updates}
    rescue
      error ->
        ErrorHandling.system_error("Failed to update metrics: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end
  
  defp safe_update_provider_load(provider_states, provider) do
    try do
      update_in(provider_states, [provider, :current_load], fn
        load when is_integer(load) -> max(load - 1, 0)
        _ -> 0
      end)
    rescue
      _ -> provider_states
    end
  end
  
  defp safe_update_metrics(metrics, params) do
    try do
      metrics
      |> Map.update(:total_requests, 1, &(&1 + 1))
      |> update_in([:requests_by_provider, params.provider], &((&1 || 0) + 1))
      |> update_model_metrics(params.model)
      |> update_latency_metrics(params.provider, params.status, params.latency)
      |> update_error_metrics(params.provider, params.status)
    rescue
      _ -> metrics
    end
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