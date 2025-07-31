defmodule RubberDuck.Jido.Actions.Provider.OpenAI.StreamRequestAction do
  @moduledoc """
  Action for handling OpenAI streaming completion requests.
  
  This action handles streaming responses from OpenAI, accumulating
  content and emitting incremental updates via callback signals.
  """
  
  use Jido.Action,
    name: "stream_request",
    description: "Handles OpenAI streaming completion requests",
    schema: [
      request_id: [type: :string, required: true],
      messages: [type: :list, required: true],
      model: [type: :string, required: true],
      callback_signal: [type: :string, required: true],
      temperature: [type: :number, default: 0.7],
      max_tokens: [type: :integer, default: nil]
    ]

  alias RubberDuck.LLM.{Request, Providers.OpenAI}
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Use base provider's rate limit and circuit breaker checks
    # First, check rate limits and circuit breaker (similar to ProviderRequestAction)
    case check_preconditions(agent) do
      {:ok, updated_agent} ->
        # Track request start
        case track_request_start(params, updated_agent) do
          {:ok, tracked_agent} ->
            # Start streaming task
            Task.start(fn ->
              handle_streaming_request(params, tracked_agent)
            end)
            
            {:ok, %{
              stream_started: true,
              request_id: params.request_id,
              status: "streaming"
            }, %{agent: tracked_agent}}
            
          error -> error
        end
        
      {:error, reason} ->
        emit_error(params.request_id, reason, agent)
    end
  end

  # Private functions

  defp check_preconditions(agent) do
    # Simplified precondition check - in a real implementation, 
    # this would reuse the rate limiting and circuit breaker logic
    active_count = map_size(agent.state.active_requests)
    
    if active_count >= agent.state.max_concurrent_requests do
      {:error, :too_many_requests}
    else
      {:ok, agent}
    end
  end

  defp track_request_start(params, agent) do
    request_info = %{
      started_at: System.monotonic_time(:millisecond),
      model: params.model,
      status: :streaming
    }
    
    active_requests = Map.put(agent.state.active_requests, params.request_id, request_info)
    state_updates = %{active_requests: active_requests}
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
      error -> error
    end
  end

  defp handle_streaming_request(params, agent) do
    # Build request with streaming enabled
    request = %Request{
      id: params.request_id,
      provider: :openai,
      model: params.model,
      messages: params.messages,
      options: %{
        temperature: params.temperature,
        max_tokens: params.max_tokens,
        stream: true
      },
      timestamp: DateTime.utc_now(),
      status: :pending
    }
    
    # Add functions if configured
    request = if functions = agent.state[:functions] do
      Map.put(request, :functions, functions)
    else
      request
    end
    
    start_time = System.monotonic_time(:millisecond)
    
    # Use an Agent to accumulate content and count tokens
    {:ok, accumulator} = Agent.start_link(fn -> %{content: [], tokens: 0} end)
    
    # Define streaming callback
    stream_callback = fn chunk ->
      # Accumulate content
      Agent.update(accumulator, fn state ->
        %{content: [chunk.content | state.content], tokens: state.tokens + 1}
      end)
      
      # Emit chunk signal
      signal_params = %{
        signal_type: params.callback_signal,
        data: %{
          request_id: params.request_id,
          chunk: chunk,
          provider: "openai",
          timestamp: DateTime.utc_now()
        }
      }
      EmitSignalAction.run(signal_params, %{agent: agent})
    end
    
    # Execute streaming request
    result = try do
      OpenAI.stream_completion(request, agent.state.provider_config, stream_callback)
    rescue
      error ->
        {:error, {:provider_error, Exception.format(:error, error)}}
    end
    
    end_time = System.monotonic_time(:millisecond)
    latency = end_time - start_time
    
    # Handle final result
    case result do
      {:ok, _} ->
        # Get accumulated data
        %{content: accumulated_content, tokens: token_count} = Agent.get(accumulator, fn state -> state end)
        Agent.stop(accumulator)
        
        # Build complete response
        complete_content = accumulated_content
        |> Enum.reverse()
        |> Enum.join("")
        
        # Estimate token usage
        usage = %{
          prompt_tokens: estimate_prompt_tokens(params.messages),
          completion_tokens: token_count,
          total_tokens: estimate_prompt_tokens(params.messages) + token_count
        }
        
        # Update metrics asynchronously
        send(agent.id, {:request_completed, params.request_id, :success, latency, usage})
        
        # Emit completion signal
        signal_params = %{
          signal_type: "provider.stream.complete",
          data: %{
            request_id: params.request_id,
            content: complete_content,
            usage: usage,
            provider: "openai",
            model: params.model,
            latency_ms: latency,
            timestamp: DateTime.utc_now()
          }
        }
        EmitSignalAction.run(signal_params, %{agent: agent})
        
      {:error, error} ->
        # Clean up accumulator
        Agent.stop(accumulator)
        
        # Update metrics asynchronously
        send(agent.id, {:request_completed, params.request_id, :failure, latency, nil})
        
        # Emit error
        signal_params = %{
          signal_type: "provider.error",
          data: %{
            request_id: params.request_id,
            error: format_error(error),
            provider: "openai",
            model: params.model,
            timestamp: DateTime.utc_now()
          }
        }
        EmitSignalAction.run(signal_params, %{agent: agent})
    end
  end

  defp emit_error(request_id, reason, agent) do
    error_message = case reason do
      :too_many_requests -> "Too many concurrent requests"
      other -> inspect(other)
    end
    
    signal_params = %{
      signal_type: "provider.error",
      data: %{
        request_id: request_id,
        error: error_message,
        provider: "openai",
        timestamp: DateTime.utc_now()
      }
    }
    
    case EmitSignalAction.run(signal_params, %{agent: agent}) do
      {:ok, signal_result, _} ->
        {:ok, %{
          stream_failed: true,
          request_id: request_id,
          error: error_message,
          signal_emitted: signal_result.signal_emitted
        }, %{agent: agent}}
        
      error -> error
    end
  end

  defp estimate_prompt_tokens(messages) do
    # Simple estimation - OpenAI roughly uses ~4 chars per token
    char_count = messages
    |> Enum.map(fn msg -> String.length(msg["content"] || "") end)
    |> Enum.sum()
    
    div(char_count, 4)
  end

  defp format_error({:provider_error, message}), do: message
  defp format_error(error), do: inspect(error)
end