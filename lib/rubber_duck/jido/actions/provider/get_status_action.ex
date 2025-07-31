defmodule RubberDuck.Jido.Actions.Provider.GetStatusAction do
  @moduledoc """
  Action for getting provider status report.
  
  This action builds a comprehensive status report including circuit breaker state,
  rate limiter status, metrics, and active requests information.
  """
  
  use Jido.Action,
    name: "get_provider_status",
    description: "Gets comprehensive provider status report",
    schema: []

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    
    # Build status report
    status = build_status_report(agent)
    
    # Emit status signal
    signal_params = %{
      signal_type: "provider.status",
      data: Map.merge(status, %{
        timestamp: DateTime.utc_now()
      })
    }
    
    case EmitSignalAction.run(signal_params, %{agent: agent}) do
      {:ok, signal_result, _} ->
        {:ok, Map.merge(status, %{
          signal_emitted: signal_result.signal_emitted
        }), %{agent: agent}}
        
      error -> error
    end
  end

  # Private functions

  defp build_status_report(agent) do
    %{
      "provider" => agent.name,
      "status" => circuit_breaker_status(agent.state.circuit_breaker),
      "circuit_breaker" => %{
        "state" => Atom.to_string(agent.state.circuit_breaker.state),
        "failure_count" => agent.state.circuit_breaker.failure_count,
        "consecutive_failures" => agent.state.circuit_breaker.consecutive_failures
      },
      "rate_limiter" => %{
        "limit" => agent.state.rate_limiter.limit,
        "window_ms" => agent.state.rate_limiter.window,
        "current_count" => agent.state.rate_limiter.current_count
      },
      "metrics" => %{
        "total_requests" => agent.state.metrics.total_requests,
        "successful_requests" => agent.state.metrics.successful_requests,
        "failed_requests" => agent.state.metrics.failed_requests,
        "total_tokens" => agent.state.metrics.total_tokens,
        "avg_latency_ms" => agent.state.metrics.avg_latency,
        "success_rate" => calculate_success_rate(agent.state.metrics)
      },
      "active_requests" => map_size(agent.state.active_requests),
      "capabilities" => agent.state.capabilities
    }
  end

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