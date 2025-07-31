defmodule RubberDuck.Jido.Actions.Provider.ProviderRequestAction do
  @moduledoc """
  Action for handling LLM provider requests with rate limiting and circuit breaking.
  
  This action implements the core provider request handling logic including:
  - Rate limiting checks
  - Circuit breaker state management
  - Concurrent request limiting
  - Request tracking and execution
  - Error handling and metrics collection
  """
  
  use Jido.Action,
    name: "provider_request",
    description: "Handles LLM provider requests with rate limiting and circuit breaking",
    schema: [
      request_id: [type: :string, required: true],
      messages: [type: :list, required: true],
      model: [type: :string, required: true],
      provider: [type: :string, default: nil],
      temperature: [type: :number, default: 0.7],
      max_tokens: [type: :integer, default: nil],
      top_p: [type: :number, default: nil],
      frequency_penalty: [type: :number, default: nil],
      presence_penalty: [type: :number, default: nil],
      stop: [type: {:union, [:string, {:list, :string}]}, default: nil],
      stream: [type: :boolean, default: false]
    ]

  alias RubberDuck.LLM.{Request, Response}
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Check rate limits
    case check_rate_limit(agent) do
      {:ok, updated_agent} ->
        # Check circuit breaker
        case check_circuit_breaker(updated_agent) do
          {:ok, circuit_checked_agent} ->
            # Check concurrent request limit
            active_count = map_size(circuit_checked_agent.state.active_requests)
            
            if active_count >= circuit_checked_agent.state.max_concurrent_requests do
              emit_error_and_return(params.request_id, :too_many_requests,
                "Provider at maximum concurrent requests (#{active_count}/#{circuit_checked_agent.state.max_concurrent_requests})",
                circuit_checked_agent)
            else
              # Track and execute request
              track_and_execute_request(params, circuit_checked_agent)
            end
            
          {:error, :circuit_open} ->
            emit_error_and_return(params.request_id, :circuit_breaker_open,
              "Provider circuit breaker is open due to repeated failures", updated_agent)
        end
        
      {:error, :rate_limited} ->
        emit_error_and_return(params.request_id, :rate_limited,
          "Provider rate limit exceeded", agent)
    end
  end

  # Private functions

  defp check_rate_limit(agent) do
    case agent.state.rate_limiter do
      %{limit: nil} ->
        # No rate limit configured
        {:ok, agent}
        
      %{limit: limit, window: window} = limiter ->
        now = System.monotonic_time(:millisecond)
        window_start = limiter.window_start || now
        
        cond do
          now - window_start > window ->
            # New window
            updated_limiter = %{limiter |
              current_count: 1,
              window_start: now
            }
            state_updates = %{rate_limiter: updated_limiter}
            
            case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
              {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
              error -> error
            end
            
          limiter.current_count < limit ->
            # Within limit
            updated_limiter = %{limiter |
              current_count: limiter.current_count + 1
            }
            state_updates = %{rate_limiter: updated_limiter}
            
            case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
              {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
              error -> error
            end
            
          true ->
            # Rate limited
            {:error, :rate_limited}
        end
    end
  end

  defp check_circuit_breaker(agent) do
    breaker = agent.state.circuit_breaker
    now = System.monotonic_time(:millisecond)
    
    case breaker.state do
      :closed ->
        {:ok, agent}
        
      :open ->
        # Check if we should try half-open
        if breaker.last_failure_time && now - breaker.last_failure_time > breaker.timeout do
          updated_breaker = %{breaker | state: :half_open, half_open_requests: 0}
          state_updates = %{circuit_breaker: updated_breaker}
          
          case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
            {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
            error -> error
          end
        else
          {:error, :circuit_open}
        end
        
      :half_open ->
        # Allow limited requests in half-open state
        if breaker.half_open_requests < breaker.success_threshold do
          updated_breaker = %{breaker | half_open_requests: breaker.half_open_requests + 1}
          state_updates = %{circuit_breaker: updated_breaker}
          
          case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
            {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
            error -> error
          end
        else
          {:error, :circuit_open}
        end
    end
  end

  defp track_and_execute_request(params, agent) do
    # Track request start
    request_info = %{
      started_at: System.monotonic_time(:millisecond),
      model: params.model,
      status: :active
    }
    
    active_requests = Map.put(agent.state.active_requests, params.request_id, request_info)
    state_updates = %{active_requests: active_requests}
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} ->
        # Execute asynchronously
        Task.start(fn ->
          execute_provider_request(params, updated_agent)
        end)
        
        {:ok, %{
          request_tracked: true,
          request_id: params.request_id,
          status: "executing"
        }, %{agent: updated_agent}}
        
      error -> error
    end
  end

  defp execute_provider_request(params, agent) do
    # Build request
    request = %Request{
      id: params.request_id,
      provider: String.to_atom(params.provider || "unknown"),
      model: params.model,
      messages: params.messages,
      options: %{
        temperature: params.temperature,
        max_tokens: params.max_tokens,
        top_p: params.top_p,
        frequency_penalty: params.frequency_penalty,
        presence_penalty: params.presence_penalty,
        stop: params.stop,
        stream: params.stream
      },
      timestamp: DateTime.utc_now(),
      status: :pending
    }
    
    # Execute through provider
    start_time = System.monotonic_time(:millisecond)
    
    result = try do
      agent.state.provider_module.execute(request, agent.state.provider_config)
    rescue
      error ->
        {:error, {:provider_error, Exception.format(:error, error)}}
    end
    
    end_time = System.monotonic_time(:millisecond)
    latency = end_time - start_time
    
    # Handle result
    case result do
      {:ok, response} ->
        # Update metrics asynchronously
        send(agent.id, {:request_completed, params.request_id, :success, latency, response.usage})
        
        # Emit response signal
        signal_params = %{
          signal_type: "provider.response",
          data: %{
            request_id: params.request_id,
            response: response,
            provider: agent.name,
            model: params.model,
            latency_ms: latency,
            timestamp: DateTime.utc_now()
          }
        }
        EmitSignalAction.run(signal_params, %{agent: agent})
        
      {:error, error} ->
        # Update metrics asynchronously
        send(agent.id, {:request_completed, params.request_id, :failure, latency, nil})
        
        # Emit error signal
        signal_params = %{
          signal_type: "provider.error",
          data: %{
            request_id: params.request_id,
            error: format_error(error),
            provider: agent.name,
            model: params.model,
            timestamp: DateTime.utc_now()
          }
        }
        EmitSignalAction.run(signal_params, %{agent: agent})
    end
  end

  defp emit_error_and_return(request_id, error_type, message, agent) do
    signal_params = %{
      signal_type: "provider.error",
      data: %{
        request_id: request_id,
        error_type: Atom.to_string(error_type),
        error: message,
        timestamp: DateTime.utc_now()
      }
    }
    
    case EmitSignalAction.run(signal_params, %{agent: agent}) do
      {:ok, _, _} ->
        {:ok, %{
          error_emitted: true,
          request_id: request_id,
          error_type: error_type,
          error: message
        }, %{agent: agent}}
        
      error -> error
    end
  end

  defp format_error({:provider_error, message}), do: message
  defp format_error(error), do: inspect(error)
end