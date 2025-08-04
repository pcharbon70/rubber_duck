defmodule RubberDuck.Jido.Actions.Provider.ResetCircuitBreakerAction do
  @moduledoc """
  Action for resetting circuit breaker state.
  
  This action manually resets the circuit breaker to a closed state,
  clearing failure counts and allowing requests to flow again.
  """
  
  use Jido.Action,
    name: "reset_circuit_breaker",
    description: "Resets circuit breaker to closed state",
    schema: []

  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  alias RubberDuck.Agents.ErrorHandling
  
  require Logger

  @impl true
  def run(_params, context) do
    ErrorHandling.safe_execute(fn ->
      # Validate context
      with :ok <- validate_context(context) do
        agent = context.agent
        
        # Safely reset circuit breaker state
        case reset_circuit_breaker_state(agent) do
          {:ok, state_updates} ->
            case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
              {:ok, _, %{agent: updated_agent}} ->
                Logger.info("Circuit breaker reset for provider #{updated_agent.name}")
                
                # Build status report with error handling
                case build_status_report(updated_agent) do
                  {:ok, status} ->
                    # Emit status signal
                    signal_params = %{
                      signal_type: "provider.status",
                      data: Map.merge(status, %{
                        timestamp: DateTime.utc_now()
                      })
                    }
                    
                    case EmitSignalAction.run(signal_params, %{agent: updated_agent}) do
                      {:ok, signal_result, _} ->
                        {:ok, %{
                          circuit_breaker_reset: true,
                          provider: updated_agent.name,
                          status: status,
                          signal_emitted: signal_result.signal_emitted
                        }, %{agent: updated_agent}}
                        
                      {:error, reason} ->
                        ErrorHandling.system_error("Failed to emit status signal: #{inspect(reason)}", %{reason: reason})
                      error ->
                        ErrorHandling.categorize_error(error)
                    end
                    
                  error -> error
                end
                
              {:error, reason} ->
                ErrorHandling.system_error("Failed to update circuit breaker state: #{inspect(reason)}", %{reason: reason})
              error ->
                ErrorHandling.categorize_error(error)
            end
            
          error -> error
        end
      end
    end)
  end
  
  defp validate_context(%{agent: %{state: %{circuit_breaker: breaker}}}) when is_map(breaker), do: :ok
  defp validate_context(_), do: ErrorHandling.validation_error("Invalid context: missing agent with circuit_breaker state", %{})
  
  defp reset_circuit_breaker_state(agent) do
    try do
      current_breaker = agent.state.circuit_breaker
      updated_breaker = %{current_breaker |
        state: :closed,
        failure_count: 0,
        consecutive_failures: 0,
        half_open_requests: Map.get(current_breaker, :half_open_requests, 0)
      }
      
      {:ok, %{circuit_breaker: updated_breaker}}
    rescue
      error ->
        ErrorHandling.system_error("Failed to reset circuit breaker: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end

  # Private functions (reused from GetStatusAction)

  defp build_status_report(agent) do
    try do
      status = %{
        "provider" => agent.name,
        "status" => safe_circuit_breaker_status(agent.state),
        "circuit_breaker" => safe_circuit_breaker_info(agent.state),
        "rate_limiter" => safe_rate_limiter_info(agent.state),
        "metrics" => safe_metrics_info(agent.state),
        "active_requests" => safe_active_requests_count(agent.state),
        "capabilities" => Map.get(agent.state, :capabilities, %{})
      }
      {:ok, status}
    rescue
      error ->
        ErrorHandling.system_error("Failed to build status report: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end
  
  defp safe_circuit_breaker_status(%{circuit_breaker: breaker}) when is_map(breaker) do
    circuit_breaker_status(breaker)
  end
  defp safe_circuit_breaker_status(_), do: "unknown"
  
  defp safe_circuit_breaker_info(%{circuit_breaker: breaker}) when is_map(breaker) do
    %{
      "state" => Atom.to_string(Map.get(breaker, :state, :unknown)),
      "failure_count" => Map.get(breaker, :failure_count, 0),
      "consecutive_failures" => Map.get(breaker, :consecutive_failures, 0)
    }
  end
  defp safe_circuit_breaker_info(_) do
    %{"state" => "unknown", "failure_count" => 0, "consecutive_failures" => 0}
  end
  
  defp safe_rate_limiter_info(%{rate_limiter: limiter}) when is_map(limiter) do
    %{
      "limit" => Map.get(limiter, :limit, 0),
      "window_ms" => Map.get(limiter, :window, 0),
      "current_count" => Map.get(limiter, :current_count, 0)
    }
  end
  defp safe_rate_limiter_info(_) do
    %{"limit" => 0, "window_ms" => 0, "current_count" => 0}
  end
  
  defp safe_metrics_info(%{metrics: metrics}) when is_map(metrics) do
    %{
      "total_requests" => Map.get(metrics, :total_requests, 0),
      "successful_requests" => Map.get(metrics, :successful_requests, 0),
      "failed_requests" => Map.get(metrics, :failed_requests, 0),
      "total_tokens" => Map.get(metrics, :total_tokens, 0),
      "avg_latency_ms" => Map.get(metrics, :avg_latency, 0),
      "success_rate" => calculate_success_rate(metrics)
    }
  end
  defp safe_metrics_info(_) do
    %{"total_requests" => 0, "successful_requests" => 0, "failed_requests" => 0, "total_tokens" => 0, "avg_latency_ms" => 0, "success_rate" => 100.0}
  end
  
  defp safe_active_requests_count(%{active_requests: requests}) when is_map(requests), do: map_size(requests)
  defp safe_active_requests_count(_), do: 0

  defp circuit_breaker_status(breaker) do
    case breaker.state do
      :closed -> "healthy"
      :open -> "unhealthy"
      :half_open -> "recovering"
    end
  end

  defp calculate_success_rate(%{total_requests: 0}), do: 100.0
  defp calculate_success_rate(%{total_requests: total, successful_requests: successful}) do
    Float.round(successful / total * 100, 2)
  end
end