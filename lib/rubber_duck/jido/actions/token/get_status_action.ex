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

  alias RubberDuck.Agents.{ErrorHandling, ActionErrorPatterns}
  require Logger

  @impl true
  def run(_params, context) do
    ErrorHandling.safe_execute(fn ->
      # Validate context
      with :ok <- validate_context(context) do
        agent = context.agent
        
        # Build status report with error handling
        case build_status_report(agent) do
          {:ok, status} ->
            {:ok, status, %{agent: agent}}
          error -> error
        end
      end
    end)
  end
  
  defp validate_context(%{agent: %{state: state}}) when is_map(state), do: :ok
  defp validate_context(_), do: ErrorHandling.validation_error("Invalid context: missing agent state", %{})

  # Private functions

  defp build_status_report(agent) do
    try do
      state = agent.state
      
      status = %{
        "healthy" => true,
        "budgets_active" => safe_map_size(Map.get(state, :budgets, %{})),
        "active_requests" => safe_map_size(Map.get(state, :active_requests, %{})),
        "buffer_size" => safe_list_length(Map.get(state, :usage_buffer, [])),
        "provenance_buffer_size" => safe_list_length(Map.get(state, :provenance_buffer, [])),
        "relationships_tracked" => safe_list_length(Map.get(state, :provenance_graph, [])),
        "total_tracked" => safe_get_metric(state, :requests_tracked, 0),
        "total_tokens" => safe_get_metric(state, :total_tokens, 0),
        "total_cost" => safe_get_cost_string(state),
        "last_flush" => safe_get_metric(state, :last_flush, nil),
        "config" => Map.get(state, :config, %{}),
        "pricing_models_loaded" => safe_count_pricing_models(Map.get(state, :pricing_models, %{})),
        "timestamp" => DateTime.utc_now()
      }
      
      {:ok, status}
    rescue
      error ->
        ErrorHandling.system_error("Failed to build status report: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end
  
  defp safe_map_size(map) when is_map(map), do: map_size(map)
  defp safe_map_size(_), do: 0
  
  defp safe_list_length(list) when is_list(list), do: length(list)
  defp safe_list_length(_), do: 0
  
  defp safe_get_metric(state, key, default) do
    case Map.get(state, :metrics) do
      metrics when is_map(metrics) -> Map.get(metrics, key, default)
      _ -> default
    end
  end
  
  defp safe_get_cost_string(state) do
    case safe_get_metric(state, :total_cost, 0) do
      cost when is_struct(cost) -> 
        try do
          Decimal.to_string(cost)
        rescue
          _ -> "0.00"
        end
      cost when is_number(cost) -> Float.to_string(cost)
      _ -> "0.00"
    end
  end

  defp safe_count_pricing_models(pricing_models) when is_map(pricing_models) do
    try do
      pricing_models
      |> Enum.map(fn
        {_provider, models} when is_map(models) -> map_size(models)
        _ -> 0
      end)
      |> Enum.sum()
    rescue
      _ -> 0
    end
  end
  defp safe_count_pricing_models(_), do: 0
end