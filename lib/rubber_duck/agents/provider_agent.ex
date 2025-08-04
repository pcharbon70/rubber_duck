defmodule RubberDuck.Agents.ProviderAgent do
  @moduledoc """
  Base module for provider-specific LLM agents.
  
  This module provides common functionality for all provider agents including:
  - Rate limiting
  - Circuit breaking
  - Metrics collection
  - Request tracking
  - Error handling
  
  Provider-specific agents should use this module and implement
  provider-specific configuration and behavior.
  
  This version uses the Jido actions pattern instead of handle_signal callbacks.
  """
  
  alias RubberDuck.LLM.{Request, Response, ProviderConfig}
  alias RubberDuck.Agents.ErrorHandling
  require Logger
  
  defmacro __using__(opts) do
    base_actions = [
      RubberDuck.Jido.Actions.Provider.ProviderRequestAction,
      RubberDuck.Jido.Actions.Provider.ProviderHealthCheckAction,
      RubberDuck.Jido.Actions.Provider.ProviderConfigUpdateAction,
      RubberDuck.Jido.Actions.Provider.ProviderRateLimitAction,
      RubberDuck.Jido.Actions.Provider.ProviderFailoverAction,
      RubberDuck.Jido.Actions.Provider.FeatureCheckAction,
      RubberDuck.Jido.Actions.Provider.TokenEstimateAction,
      RubberDuck.Jido.Actions.Provider.GetStatusAction,
      RubberDuck.Jido.Actions.Provider.ResetCircuitBreakerAction
    ]
    
    additional_actions = opts[:actions] || []
    all_actions = base_actions ++ additional_actions
    
    quote do
      use Jido.Agent,
        name: unquote(opts[:name]) || "provider",
        description: unquote(opts[:description]) || "Provider-specific LLM agent",
        schema: [
          provider_module: [type: :atom, required: true],
          provider_config: [type: :map, required: true],
          active_requests: [type: :map, default: %{}],
          metrics: [type: :map, default: %{
            total_requests: 0,
            successful_requests: 0,
            failed_requests: 0,
            total_tokens: 0,
            avg_latency: 0.0,
            last_request_time: nil
          }],
          rate_limiter: [type: :map, default: %{
            limit: nil,          # requests per window
            window: nil,         # window in milliseconds
            current_count: 0,
            window_start: nil
          }],
          circuit_breaker: [type: :map, default: %{
            state: :closed,      # :closed, :open, :half_open
            failure_count: 0,
            consecutive_failures: 0,
            last_failure_time: nil,
            last_success_time: nil,
            failure_threshold: 5,
            success_threshold: 2,  # successes needed to close from half_open
            timeout: 60_000,       # time before trying half_open
            half_open_requests: 0
          }],
          capabilities: [type: {:list, :atom}, default: []],
          max_concurrent_requests: [type: :integer, default: 10]
        ],
        actions: unquote(all_actions)
      
      require Logger
      alias RubberDuck.LLM.{Request, Response, ProviderConfig}
      
      # GenServer callbacks for handling internal state updates from actions
      
      # GenServer callbacks for handling async updates from actions
      @impl true
      def handle_info({:request_completed, request_id, status, latency, usage}, agent) do
        case RubberDuck.Agents.ProviderAgent.safe_handle_request_completed(agent, request_id, status, latency, usage) do
          {:ok, updated_agent} ->
            {:noreply, updated_agent}
          {:error, error} ->
            Logger.error("Failed to handle request completion: #{inspect(error)}")
            {:noreply, agent}
        end
      end
    end
  end
  
  # Helper functions for metrics and state management
  # These are still used by the async GenServer callbacks
  
  def build_status_report(agent) do
    ErrorHandling.safe_execute(fn ->
      %{
        "provider" => agent.name,
        "status" => safe_circuit_breaker_status(agent.state),
        "circuit_breaker" => safe_circuit_breaker_info(agent.state),
        "rate_limiter" => safe_rate_limiter_info(agent.state),
        "metrics" => safe_metrics_info(agent.state),
        "active_requests" => safe_active_requests_count(agent.state),
        "capabilities" => Map.get(agent.state, :capabilities, [])
      }
    end)
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
      "limit" => Map.get(limiter, :limit),
      "window_ms" => Map.get(limiter, :window),
      "current_count" => Map.get(limiter, :current_count, 0)
    }
  end
  defp safe_rate_limiter_info(_) do
    %{"limit" => nil, "window_ms" => nil, "current_count" => 0}
  end
  
  defp safe_metrics_info(%{metrics: metrics}) when is_map(metrics) do
    %{
      "total_requests" => Map.get(metrics, :total_requests, 0),
      "successful_requests" => Map.get(metrics, :successful_requests, 0),
      "failed_requests" => Map.get(metrics, :failed_requests, 0),
      "total_tokens" => Map.get(metrics, :total_tokens, 0),
      "avg_latency_ms" => Map.get(metrics, :avg_latency, 0.0),
      "success_rate" => safe_calculate_success_rate(metrics)
    }
  end
  defp safe_metrics_info(_) do
    %{"total_requests" => 0, "successful_requests" => 0, "failed_requests" => 0, "total_tokens" => 0, "avg_latency_ms" => 0.0, "success_rate" => 100.0}
  end
  
  defp safe_active_requests_count(%{active_requests: requests}) when is_map(requests), do: map_size(requests)
  defp safe_active_requests_count(_), do: 0
  
  defp safe_calculate_success_rate(%{total_requests: 0}), do: 100.0
  defp safe_calculate_success_rate(%{total_requests: total, successful_requests: successful}) when is_integer(total) and is_integer(successful) and total > 0 do
    Float.round(successful / total * 100, 2)
  end
  defp safe_calculate_success_rate(_), do: 0.0
  
  defp circuit_breaker_status(breaker) do
    case breaker.state do
      :closed -> "healthy"
      :open -> "unhealthy"
      :half_open -> "recovering"
    end
  end
  
  
  # Safe wrapper for handling request completion
  def safe_handle_request_completed(agent, request_id, status, latency, usage) do
    ErrorHandling.safe_execute(fn ->
      # Validate inputs
      with :ok <- validate_completion_params(request_id, status, latency, usage) do
        # Remove from active requests
        {_request_info, agent} = pop_in(agent.state.active_requests[request_id])
        
        # Update metrics
        agent = safe_update_metrics(agent, status, latency, usage)
        
        # Update circuit breaker
        agent = safe_update_circuit_breaker(agent, status)
        
        agent
      end
    end)
  end
  
  # Legacy function for backward compatibility
  def handle_request_completed(agent, request_id, status, latency, usage) do
    case safe_handle_request_completed(agent, request_id, status, latency, usage) do
      {:ok, updated_agent} -> updated_agent
      {:error, _error} -> agent  # Return original agent on error
    end
  end
  
  defp validate_completion_params(request_id, status, latency, usage) do
    cond do
      not is_binary(request_id) or byte_size(request_id) == 0 ->
        ErrorHandling.validation_error("Invalid request_id", %{request_id: request_id})
      status not in [:success, :failure] ->
        ErrorHandling.validation_error("Invalid status", %{status: status})
      not is_integer(latency) or latency < 0 ->
        ErrorHandling.validation_error("Invalid latency", %{latency: latency})
      not is_nil(usage) and not is_map(usage) ->
        ErrorHandling.validation_error("Invalid usage data", %{usage: usage})
      true -> :ok
    end
  end
  
  defp safe_update_metrics(agent, status, latency, usage) do
    try do
      metrics = Map.get(agent.state, :metrics, %{
        total_requests: 0,
        successful_requests: 0,
        failed_requests: 0,
        avg_latency: 0.0,
        total_tokens: 0,
        last_request_time: nil
      })
      
      total_requests = Map.get(metrics, :total_requests, 0) + 1
      successful = if status == :success, do: Map.get(metrics, :successful_requests, 0) + 1, else: Map.get(metrics, :successful_requests, 0)
      failed = if status == :failure, do: Map.get(metrics, :failed_requests, 0) + 1, else: Map.get(metrics, :failed_requests, 0)
      
      # Update average latency safely
      current_avg = Map.get(metrics, :avg_latency, 0.0)
      avg_latency = if current_avg == 0 do
        latency * 1.0
      else
        (current_avg * (total_requests - 1) + latency) / total_requests
      end
      
      # Update token count safely
      current_tokens = Map.get(metrics, :total_tokens, 0)
      additional_tokens = if is_map(usage), do: Map.get(usage, :total_tokens, 0), else: 0
      total_tokens = current_tokens + additional_tokens
      
      updated_metrics = %{
        total_requests: total_requests,
        successful_requests: successful,
        failed_requests: failed,
        avg_latency: avg_latency,
        total_tokens: total_tokens,
        last_request_time: System.monotonic_time(:millisecond)
      }
      
      put_in(agent.state.metrics, updated_metrics)
    rescue
      error ->
        Logger.error("Failed to update metrics: #{Exception.message(error)}")
        agent
    end
  end
  
  defp safe_update_circuit_breaker(agent, status) do
    try do
      update_circuit_breaker_logic(agent, status)
    rescue
      error ->
        Logger.error("Failed to update circuit breaker: #{Exception.message(error)}")
        agent
    end
  end
  
  defp update_circuit_breaker_logic(agent, status) do
    breaker = agent.state.circuit_breaker
    now = System.monotonic_time(:millisecond)
    
    case {breaker.state, status} do
      {_, :success} ->
        # Success in any state
        updated_breaker = case breaker.state do
          :half_open ->
            if breaker.half_open_requests >= breaker.success_threshold do
              # Close the circuit
              %{breaker |
                state: :closed,
                failure_count: 0,
                consecutive_failures: 0,
                last_success_time: now,
                half_open_requests: 0
              }
            else
              %{breaker |
                consecutive_failures: 0,
                last_success_time: now
              }
            end
            
          _ ->
            %{breaker |
              consecutive_failures: 0,
              last_success_time: now
            }
        end
        
        put_in(agent.state.circuit_breaker, updated_breaker)
        
      {:closed, :failure} ->
        # Failure in closed state
        consecutive = breaker.consecutive_failures + 1
        failure_count = breaker.failure_count + 1
        
        updated_breaker = if consecutive >= breaker.failure_threshold do
          # Open the circuit
          %{breaker |
            state: :open,
            failure_count: failure_count,
            consecutive_failures: consecutive,
            last_failure_time: now
          }
        else
          %{breaker |
            failure_count: failure_count,
            consecutive_failures: consecutive,
            last_failure_time: now
          }
        end
        
        put_in(agent.state.circuit_breaker, updated_breaker)
        
      {:half_open, :failure} ->
        # Failure in half-open state - reopen immediately
        updated_breaker = %{breaker |
          state: :open,
          failure_count: breaker.failure_count + 1,
          consecutive_failures: breaker.consecutive_failures + 1,
          last_failure_time: now,
          half_open_requests: 0
        }
        
        put_in(agent.state.circuit_breaker, updated_breaker)
        
      _ ->
        # No change needed
        agent
    end
  end
end