defmodule RubberDuck.LLMAbstraction.Response do
  @moduledoc """
  Unified response structure for all LLM providers.
  
  This module provides a consistent response format that includes the actual
  content along with important metadata like token usage, costs, and timing
  information. It supports both streaming and non-streaming responses.
  """

  defstruct [
    :id,
    :provider,
    :model,
    :content,
    :role,
    :finish_reason,
    :usage,
    :metadata,
    :created_at,
    :latency_ms,
    :raw_response
  ]

  @type finish_reason :: :stop | :length | :function_call | :content_filter | :error | nil

  @type usage :: %{
    prompt_tokens: non_neg_integer(),
    completion_tokens: non_neg_integer(),
    total_tokens: non_neg_integer(),
    cost: float() | nil
  }

  @type t :: %__MODULE__{
    id: String.t() | nil,
    provider: atom(),
    model: String.t(),
    content: String.t() | nil,
    role: atom(),
    finish_reason: finish_reason(),
    usage: usage() | nil,
    metadata: map(),
    created_at: DateTime.t(),
    latency_ms: non_neg_integer() | nil,
    raw_response: term()
  }

  @doc """
  Create a new response from provider data.
  """
  def new(attrs) do
    %__MODULE__{
      id: attrs[:id],
      provider: attrs[:provider] || :unknown,
      model: attrs[:model] || "unknown",
      content: attrs[:content],
      role: attrs[:role] || :assistant,
      finish_reason: attrs[:finish_reason],
      usage: attrs[:usage],
      metadata: attrs[:metadata] || %{},
      created_at: attrs[:created_at] || DateTime.utc_now(),
      latency_ms: attrs[:latency_ms],
      raw_response: attrs[:raw_response]
    }
  end

  @doc """
  Parse a response from OpenAI format.
  """
  def from_openai(response, provider \\ :openai, latency_ms \\ nil) do
    choice = List.first(response["choices"] || [])
    
    %__MODULE__{
      id: response["id"],
      provider: provider,
      model: response["model"],
      content: get_in(choice, ["message", "content"]),
      role: String.to_atom(get_in(choice, ["message", "role"]) || "assistant"),
      finish_reason: parse_finish_reason(choice["finish_reason"]),
      usage: parse_openai_usage(response["usage"]),
      metadata: %{
        system_fingerprint: response["system_fingerprint"],
        created: response["created"]
      },
      created_at: DateTime.utc_now(),
      latency_ms: latency_ms,
      raw_response: response
    }
  end

  @doc """
  Parse a response from Anthropic format.
  """
  def from_anthropic(response, latency_ms \\ nil) do
    content = case response["content"] do
      [%{"text" => text} | _] -> text
      [%{"type" => "text", "text" => text} | _] -> text
      _ -> nil
    end

    %__MODULE__{
      id: response["id"],
      provider: :anthropic,
      model: response["model"],
      content: content,
      role: :assistant,
      finish_reason: parse_anthropic_stop_reason(response["stop_reason"]),
      usage: parse_anthropic_usage(response["usage"]),
      metadata: %{
        stop_sequence: response["stop_sequence"]
      },
      created_at: DateTime.utc_now(),
      latency_ms: latency_ms,
      raw_response: response
    }
  end

  @doc """
  Check if the response indicates an error.
  """
  def error?(response) do
    response.finish_reason == :error
  end

  @doc """
  Check if the response was truncated due to length.
  """
  def truncated?(response) do
    response.finish_reason == :length
  end

  @doc """
  Check if the response contains a function call.
  """
  def function_call?(response) do
    response.finish_reason == :function_call
  end

  @doc """
  Get the total token count.
  """
  def total_tokens(response) do
    case response.usage do
      %{total_tokens: tokens} -> tokens
      _ -> 0
    end
  end

  @doc """
  Calculate the cost of the response if pricing info is available.
  """
  def calculate_cost(response, pricing \\ nil) do
    case {response.usage, pricing} do
      {%{prompt_tokens: prompt, completion_tokens: completion}, %{input: input_price, output: output_price}} ->
        (prompt * input_price + completion * output_price) / 1_000_000
      
      {%{cost: cost}, _} when is_number(cost) ->
        cost
        
      _ ->
        nil
    end
  end

  @doc """
  Convert response to a message for continuing conversations.
  """
  def to_message(response) do
    alias RubberDuck.LLMAbstraction.Message

    Message.Factory.assistant(response.content, metadata: response.metadata)
  end

  # Private helpers

  defp parse_finish_reason(nil), do: nil
  defp parse_finish_reason("stop"), do: :stop
  defp parse_finish_reason("length"), do: :length
  defp parse_finish_reason("function_call"), do: :function_call
  defp parse_finish_reason("content_filter"), do: :content_filter
  defp parse_finish_reason(_), do: :unknown

  defp parse_anthropic_stop_reason(nil), do: nil
  defp parse_anthropic_stop_reason("end_turn"), do: :stop
  defp parse_anthropic_stop_reason("max_tokens"), do: :length
  defp parse_anthropic_stop_reason("stop_sequence"), do: :stop
  defp parse_anthropic_stop_reason(_), do: :unknown

  defp parse_openai_usage(nil), do: nil
  defp parse_openai_usage(usage) do
    %{
      prompt_tokens: usage["prompt_tokens"] || 0,
      completion_tokens: usage["completion_tokens"] || 0,
      total_tokens: usage["total_tokens"] || 0,
      cost: nil  # Will be calculated separately based on model pricing
    }
  end

  defp parse_anthropic_usage(nil), do: nil
  defp parse_anthropic_usage(usage) do
    %{
      prompt_tokens: usage["input_tokens"] || 0,
      completion_tokens: usage["output_tokens"] || 0,
      total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0),
      cost: nil
    }
  end
end

defmodule RubberDuck.LLMAbstraction.StreamResponse do
  @moduledoc """
  Streaming response handler for real-time token generation.
  
  This module provides utilities for handling streaming responses from LLM providers,
  accumulating chunks into complete responses while providing real-time updates.
  """

  alias RubberDuck.LLMAbstraction.Response

  defstruct [
    :id,
    :provider,
    :model,
    :accumulated_content,
    :chunks,
    :started_at,
    :metadata
  ]

  @type t :: %__MODULE__{
    id: String.t() | nil,
    provider: atom(),
    model: String.t(),
    accumulated_content: String.t(),
    chunks: [map()],
    started_at: DateTime.t(),
    metadata: map()
  }

  @doc """
  Initialize a new streaming response.
  """
  def new(provider, model, opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id),
      provider: provider,
      model: model,
      accumulated_content: "",
      chunks: [],
      started_at: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Add a chunk to the streaming response.
  """
  def add_chunk(stream_response, chunk) do
    content = extract_content(chunk, stream_response.provider)
    
    %{stream_response |
      accumulated_content: stream_response.accumulated_content <> (content || ""),
      chunks: stream_response.chunks ++ [chunk]
    }
  end

  @doc """
  Convert the accumulated streaming response to a final Response.
  """
  def to_response(stream_response, finish_reason \\ :stop) do
    latency_ms = DateTime.diff(DateTime.utc_now(), stream_response.started_at, :millisecond)
    
    # Try to extract usage from the last chunk
    usage = extract_usage_from_chunks(stream_response.chunks, stream_response.provider)
    
    Response.new(%{
      id: stream_response.id,
      provider: stream_response.provider,
      model: stream_response.model,
      content: stream_response.accumulated_content,
      role: :assistant,
      finish_reason: finish_reason,
      usage: usage,
      metadata: stream_response.metadata,
      created_at: stream_response.started_at,
      latency_ms: latency_ms,
      raw_response: stream_response.chunks
    })
  end

  @doc """
  Create a stream transformer for provider-specific chunk parsing.
  """
  def chunk_transformer(provider) do
    fn chunk ->
      case parse_chunk(chunk, provider) do
        {:ok, parsed} -> parsed
        {:error, _} -> nil
      end
    end
  end

  # Private helpers

  defp extract_content(chunk, :openai) do
    get_in(chunk, ["choices", Access.at(0), "delta", "content"])
  end

  defp extract_content(chunk, :anthropic) do
    case chunk do
      %{"delta" => %{"text" => text}} -> text
      %{"content_block" => %{"text" => text}} -> text
      _ -> nil
    end
  end

  defp extract_content(chunk, _provider) do
    # Generic extraction attempt
    chunk["content"] || chunk["text"] || chunk["delta"]
  end

  defp extract_usage_from_chunks(chunks, provider) do
    # Look for usage info in the last few chunks
    chunks
    |> Enum.reverse()
    |> Enum.take(5)
    |> Enum.find_value(&extract_usage_from_chunk(&1, provider))
  end

  defp extract_usage_from_chunk(chunk, :openai) do
    if usage = chunk["usage"] do
      %{
        prompt_tokens: usage["prompt_tokens"] || 0,
        completion_tokens: usage["completion_tokens"] || 0,
        total_tokens: usage["total_tokens"] || 0,
        cost: nil
      }
    end
  end

  defp extract_usage_from_chunk(chunk, :anthropic) do
    if usage = chunk["usage"] do
      %{
        prompt_tokens: usage["input_tokens"] || 0,
        completion_tokens: usage["output_tokens"] || 0,
        total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0),
        cost: nil
      }
    end
  end

  defp extract_usage_from_chunk(_, _), do: nil

  defp parse_chunk(data, _provider) when is_binary(data) do
    case String.trim(data) do
      "" -> {:error, :empty}
      "data: [DONE]" -> {:error, :done}
      "data: " <> json -> Jason.decode(json)
      json -> Jason.decode(json)
    end
  end

  defp parse_chunk(data, _provider) when is_map(data) do
    {:ok, data}
  end
end