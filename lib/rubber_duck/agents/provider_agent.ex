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
        agent = RubberDuck.Agents.ProviderAgent.handle_request_completed(agent, request_id, status, latency, usage)
        {:noreply, agent}
      end
    end
  end
  
  # Helper functions for metrics and state management
  # These are still used by the async GenServer callbacks
  
  def build_status_report(agent) do
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
  
  # Helper for handling request completion
  def handle_request_completed(agent, request_id, status, latency, usage) do
    # Remove from active requests
    {_request_info, agent} = pop_in(agent.state.active_requests[request_id])
    
    # Update metrics
    agent = update_metrics(agent, status, latency, usage)
    
    # Update circuit breaker
    agent = update_circuit_breaker(agent, status)
    
    agent
  end
  
  defp update_metrics(agent, status, latency, usage) do
    metrics = agent.state.metrics
    
    total_requests = metrics.total_requests + 1
    successful = if status == :success, do: metrics.successful_requests + 1, else: metrics.successful_requests
    failed = if status == :failure, do: metrics.failed_requests + 1, else: metrics.failed_requests
    
    # Update average latency
    avg_latency = if metrics.avg_latency == 0 do
      latency
    else
      (metrics.avg_latency * metrics.total_requests + latency) / total_requests
    end
    
    # Update token count
    total_tokens = if usage do
      metrics.total_tokens + (usage[:total_tokens] || 0)
    else
      metrics.total_tokens
    end
    
    updated_metrics = %{metrics |
      total_requests: total_requests,
      successful_requests: successful,
      failed_requests: failed,
      avg_latency: avg_latency,
      total_tokens: total_tokens,
      last_request_time: System.monotonic_time(:millisecond)
    }
    
    put_in(agent.state.metrics, updated_metrics)
  end
  
  defp update_circuit_breaker(agent, status) do
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