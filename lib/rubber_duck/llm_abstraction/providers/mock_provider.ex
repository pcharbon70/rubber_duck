defmodule RubberDuck.LLMAbstraction.Providers.MockProvider do
  @moduledoc """
  Mock LLM provider for testing purposes.
  
  This provider simulates LLM responses without making actual API calls,
  useful for testing and development. It supports configurable responses,
  latency simulation, and error injection.
  """

  @behaviour RubberDuck.LLMAbstraction.Provider

  alias RubberDuck.LLMAbstraction.{Message, Response, Capability}

  defstruct [
    :responses,
    :default_response,
    :latency_ms,
    :error_rate,
    :call_count,
    :health
  ]

  @impl true
  def init(config) do
    state = %__MODULE__{
      responses: config[:responses] || %{},
      default_response: config[:default_response] || "This is a mock response.",
      latency_ms: config[:latency_ms] || 0,
      error_rate: config[:error_rate] || 0.0,
      call_count: 0,
      health: :healthy
    }
    
    {:ok, state}
  end

  @impl true
  def chat(messages, state, opts) do
    # Simulate latency
    if state.latency_ms > 0 do
      Process.sleep(state.latency_ms)
    end
    
    # Simulate errors based on error rate
    if :rand.uniform() < state.error_rate do
      {:error, :simulated_error, increment_call_count(state)}
    else
      # Get the last user message for response lookup
      last_user_message = messages
      |> Enum.reverse()
      |> Enum.find(&(Message.role(&1) == :user))
      
      content = if last_user_message do
        user_content = Message.content(last_user_message)
        Map.get(state.responses, user_content, state.default_response)
      else
        state.default_response
      end
      
      response = Response.new(%{
        id: "mock-#{:erlang.unique_integer([:positive])}",
        provider: :mock,
        model: Keyword.get(opts, :model, "mock-model"),
        content: content,
        role: :assistant,
        finish_reason: :stop,
        usage: %{
          prompt_tokens: calculate_tokens(messages),
          completion_tokens: calculate_tokens(content),
          total_tokens: calculate_tokens(messages) + calculate_tokens(content),
          cost: nil
        },
        metadata: %{mock: true},
        created_at: DateTime.utc_now(),
        latency_ms: state.latency_ms
      })
      
      {:ok, response, increment_call_count(state)}
    end
  end

  @impl true
  def complete(prompt, state, opts) do
    # Simulate latency
    if state.latency_ms > 0 do
      Process.sleep(state.latency_ms)
    end
    
    # Simulate errors
    if :rand.uniform() < state.error_rate do
      {:error, :simulated_error, increment_call_count(state)}
    else
      content = Map.get(state.responses, prompt, state.default_response)
      
      response = Response.new(%{
        id: "mock-#{:erlang.unique_integer([:positive])}",
        provider: :mock,
        model: Keyword.get(opts, :model, "mock-model"),
        content: content,
        role: :assistant,
        finish_reason: :stop,
        usage: %{
          prompt_tokens: calculate_tokens(prompt),
          completion_tokens: calculate_tokens(content),
          total_tokens: calculate_tokens(prompt) + calculate_tokens(content),
          cost: nil
        },
        metadata: %{mock: true},
        created_at: DateTime.utc_now(),
        latency_ms: state.latency_ms
      })
      
      {:ok, response, increment_call_count(state)}
    end
  end

  @impl true
  def embed(input, state, _opts) do
    # Simulate latency
    if state.latency_ms > 0 do
      Process.sleep(state.latency_ms)
    end
    
    # Simulate errors
    if :rand.uniform() < state.error_rate do
      {:error, :simulated_error, increment_call_count(state)}
    else
      # Generate mock embeddings
      embeddings = case input do
        text when is_binary(text) ->
          [generate_mock_embedding(text)]
        texts when is_list(texts) ->
          Enum.map(texts, &generate_mock_embedding/1)
      end
      
      {:ok, embeddings, increment_call_count(state)}
    end
  end

  @impl true
  def stream_chat(messages, state, opts) do
    # Create a mock stream
    content = chat(messages, state, opts)
    |> elem(1)
    |> Map.get(:content)
    
    # Split content into chunks
    chunks = content
    |> String.graphemes()
    |> Enum.chunk_every(5)
    |> Enum.map(&Enum.join/1)
    
    stream = Stream.map(chunks, fn chunk ->
      %{
        "choices" => [
          %{
            "delta" => %{"content" => chunk},
            "index" => 0
          }
        ]
      }
    end)
    
    {:ok, stream, increment_call_count(state)}
  end

  @impl true
  def capabilities(_state) do
    [
      Capability.chat_completion(
        constraints: [
          {:max_tokens, 4096},
          {:max_context_window, 8192}
        ]
      ),
      Capability.text_completion(
        constraints: [
          {:max_tokens, 2048}
        ]
      ),
      Capability.embeddings(
        constraints: [
          {:supported_models, ["mock-embedding"]}
        ]
      ),
      Capability.streaming(),
      Capability.function_calling(
        constraints: [
          {:max_functions, 10}
        ]
      )
    ]
  end

  @impl true
  def health_check(state) do
    state.health
  end

  @impl true
  def terminate(_state) do
    :ok
  end

  @impl true
  def validate_config(_config) do
    # Mock provider accepts any config
    :ok
  end

  @impl true
  def metadata() do
    %{
      name: "Mock Provider",
      version: "1.0.0",
      description: "Mock LLM provider for testing",
      author: "RubberDuck Team"
    }
  end

  # Helper functions

  defp increment_call_count(state) do
    %{state | call_count: state.call_count + 1}
  end

  defp calculate_tokens(messages) when is_list(messages) do
    messages
    |> Enum.map(&Message.content/1)
    |> Enum.join(" ")
    |> calculate_tokens()
  end

  defp calculate_tokens(text) when is_binary(text) do
    # Simple approximation: ~4 characters per token
    div(String.length(text), 4)
  end

  defp calculate_tokens(_), do: 0

  defp generate_mock_embedding(text) do
    # Generate a deterministic mock embedding based on text
    # This creates a 384-dimensional vector (common size)
    :crypto.hash(:sha384, text)
    |> :binary.bin_to_list()
    |> Enum.map(fn byte -> (byte - 128) / 128.0 end)
  end
end