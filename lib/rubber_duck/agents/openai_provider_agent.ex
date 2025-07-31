defmodule RubberDuck.Agents.OpenAIProviderAgent do
  @moduledoc """
  OpenAI-specific provider agent handling GPT model requests.
  
  This agent manages:
  - OpenAI API rate limits
  - Model-specific capabilities
  - Function calling support
  - Streaming responses
  - Token usage tracking
  
  ## Signals
  
  Inherits all signals from ProviderAgent plus:
  - `configure_functions`: Configure function calling
  - `stream_request`: Handle streaming completion
  """
  
  use RubberDuck.Agents.ProviderAgent,
    name: "openai_provider",
    description: "OpenAI GPT models provider agent"
  
  alias RubberDuck.LLM.Providers.OpenAI
  alias RubberDuck.LLM.{ProviderConfig, ConfigLoader}
  
  @impl true
  def mount(_params, initial_state) do
    # Load OpenAI configuration
    config = build_openai_config()
    
    # Set OpenAI-specific defaults
    state = initial_state
    |> Map.put(:provider_module, OpenAI)
    |> Map.put(:provider_config, config)
    |> Map.put(:capabilities, [
      :chat, :code, :analysis, :function_calling, 
      :streaming, :json_mode, :system_messages
    ])
    |> Map.update(:rate_limiter, %{}, fn limiter ->
      %{limiter |
        limit: get_rate_limit(config),
        window: 60_000  # 1 minute window
      }
    end)
    |> Map.update(:circuit_breaker, %{}, fn breaker ->
      %{breaker |
        failure_threshold: 5,
        timeout: 30_000  # 30 seconds
      }
    end)
    
    {:ok, state}
  end
  
  @impl true
  def handle_signal(agent, %{"type" => "configure_functions"} = signal) do
    %{"data" => %{"functions" => functions}} = signal
    
    # Store functions in agent state for use in requests
    agent = put_in(agent.state[:functions], functions)
    
    signal = Jido.Signal.new!(%{
      type: "provider.functions.configured",
      source: "agent:#{agent.id}",
      data: %{
        provider: "openai",
        function_count: length(functions),
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "stream_request"} = signal) do
    %{
      "data" => %{
        "request_id" => _request_id,
        "messages" => messages,
        "model" => _model,
        "callback_signal" => callback_signal
      } = _data
    } = signal
    
    # Use the base provider's rate limit and circuit breaker checks
    RubberDuck.Agents.ProviderAgent.handle_provider_request(
      agent, signal,
      &emit_error_response_internal/3,
      fn agent, req_id, mdl, dt ->
        # Track request
        agent = RubberDuck.Agents.ProviderAgent.track_request_start(agent, req_id, mdl)
        
        # Start streaming task
        Task.start(fn ->
          handle_streaming_request(agent.id, req_id, messages, mdl, dt, callback_signal)
        end)
        
        agent
      end
    )
  end
  
  # Delegate other signals to base implementation
  def handle_signal(agent, signal) do
    super(agent, signal)
  end
  
  # Private functions
  
  defp build_openai_config do
    # Load from configuration
    base_config = %ProviderConfig{
      name: :openai,
      adapter: OpenAI,
      api_key: System.get_env("OPENAI_API_KEY"),
      base_url: System.get_env("OPENAI_BASE_URL") || "https://api.openai.com/v1",
      models: [
        "gpt-4-turbo-preview",
        "gpt-4",
        "gpt-4-32k", 
        "gpt-3.5-turbo",
        "gpt-3.5-turbo-16k"
      ],
      priority: 1,
      rate_limit: parse_rate_limit(System.get_env("OPENAI_RATE_LIMIT")),
      max_retries: 3,
      timeout: 120_000,  # 2 minutes for GPT-4
      headers: %{},
      options: []
    }
    
    # Apply any runtime overrides
    ConfigLoader.load_provider_config(:openai)
    |> case do
      nil -> base_config
      config -> struct(ProviderConfig, config)
    end
  end
  
  defp get_rate_limit(%ProviderConfig{rate_limit: {limit, :minute}}), do: limit
  defp get_rate_limit(%ProviderConfig{rate_limit: {limit, :hour}}), do: div(limit, 60)
  defp get_rate_limit(_), do: 60  # Default: 60 requests per minute
  
  defp parse_rate_limit(nil), do: {3000, :minute}  # Default tier
  defp parse_rate_limit(str) do
    case String.split(str, "/") do
      [limit, "min"] -> {String.to_integer(limit), :minute}
      [limit, "hour"] -> {String.to_integer(limit), :hour}
      _ -> {3000, :minute}
    end
  end
  
  defp handle_streaming_request(agent_id, request_id, messages, model, data, callback_signal) do
    # Get current agent state
    agent = GenServer.call(agent_id, :get_state)
    
    # Build request with streaming enabled
    request = RubberDuck.Agents.ProviderAgent.build_request(request_id, messages, model, Map.put(data, "stream", true))
    
    # Add functions if configured
    request = if functions = agent.state[:functions] do
      Map.put(request, :functions, functions)
    else
      request
    end
    
    start_time = System.monotonic_time(:millisecond)
    
    # Use an Elixir Agent to accumulate content and count tokens
    {:ok, accumulator} = Elixir.Agent.start_link(fn -> %{content: [], tokens: 0} end)
    
    # Define streaming callback
    stream_callback = fn chunk ->
      # Accumulate content
      Elixir.Agent.update(accumulator, fn state ->
        %{content: [chunk.content | state.content], tokens: state.tokens + 1}
      end)
      
      # Emit chunk signal
      signal = Jido.Signal.new!(%{
        type: callback_signal,
        source: "agent:openai_provider",
        data: %{
          request_id: request_id,
          chunk: chunk,
          provider: "openai",
          timestamp: DateTime.utc_now()
        }
      })
      emit_signal(agent_id, signal)
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
        %{content: accumulated_content, tokens: token_count} = Elixir.Agent.get(accumulator, fn state -> state end)
        Elixir.Agent.stop(accumulator)
        
        # Build complete response
        complete_content = accumulated_content
        |> Enum.reverse()
        |> Enum.join("")
        
        # Estimate token usage
        usage = %{
          prompt_tokens: estimate_prompt_tokens(messages),
          completion_tokens: token_count,
          total_tokens: estimate_prompt_tokens(messages) + token_count
        }
        
        # Update metrics
        GenServer.cast(agent_id, {:request_completed, request_id, :success, latency, usage})
        
        # Emit completion signal
        signal = Jido.Signal.new!(%{
          type: "provider.stream.complete",
          source: "agent:openai_provider",
          data: %{
            request_id: request_id,
            content: complete_content,
            usage: usage,
            provider: "openai",
            model: model,
            latency_ms: latency,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent_id, signal)
        
      {:error, error} ->
        # Clean up accumulator
        Elixir.Agent.stop(accumulator)
        
        # Update metrics
        GenServer.cast(agent_id, {:request_completed, request_id, :failure, latency, nil})
        
        # Emit error
        signal = Jido.Signal.new!(%{
          type: "provider.error",
          source: "agent:openai_provider",
          data: %{
            request_id: request_id,
            error: RubberDuck.Agents.ProviderAgent.format_error(error),
            provider: "openai",
            model: model,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent_id, signal)
    end
  end
  
  defp estimate_prompt_tokens(messages) do
    # Simple estimation - OpenAI roughly uses ~4 chars per token
    char_count = messages
    |> Enum.map(fn msg -> String.length(msg["content"] || "") end)
    |> Enum.sum()
    
    div(char_count, 4)
  end
  
  # Build status report with OpenAI-specific info
  def build_status_report(agent) do
    base_report = RubberDuck.Agents.ProviderAgent.build_status_report(agent)
    
    Map.merge(base_report, %{
      "models" => agent.state.provider_config.models,
      "supports_functions" => Map.has_key?(agent.state, :functions),
      "function_count" => length(Map.get(agent.state, :functions, [])),
      "tier_info" => %{
        "rate_limit" => agent.state.rate_limiter.limit,
        "rate_window" => "1 minute"
      }
    })
  end
end