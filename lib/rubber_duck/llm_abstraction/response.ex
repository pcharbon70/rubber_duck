defmodule RubberDuck.LLMAbstraction.Response do
  @moduledoc """
  Standard response structure for LLM provider responses.
  
  This module defines the universal response format returned by all LLM providers
  to ensure consistent response handling across different provider implementations.
  """

  defstruct [
    :id,
    :object,
    :created,
    :model,
    :choices,
    :usage,
    :system_fingerprint,
    :metadata
  ]

  @type choice :: %{
    index: non_neg_integer(),
    message: RubberDuck.LLMAbstraction.Message.t() | nil,
    text: String.t() | nil,
    finish_reason: finish_reason(),
    logprobs: map() | nil
  }

  @type usage :: %{
    prompt_tokens: non_neg_integer(),
    completion_tokens: non_neg_integer(),
    total_tokens: non_neg_integer()
  }

  @type finish_reason :: :stop | :length | :function_call | :tool_calls | :content_filter | :null

  @type t :: %__MODULE__{
    id: String.t(),
    object: String.t(),
    created: non_neg_integer(),
    model: String.t(),
    choices: [choice()],
    usage: usage() | nil,
    system_fingerprint: String.t() | nil,
    metadata: map()
  }

  @doc """
  Create a new response structure.
  """
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      object: Keyword.get(opts, :object, "chat.completion"),
      created: Keyword.get(opts, :created, System.system_time(:second)),
      model: Keyword.get(opts, :model),
      choices: Keyword.get(opts, :choices, []),
      usage: Keyword.get(opts, :usage),
      system_fingerprint: Keyword.get(opts, :system_fingerprint),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a response with a single text completion.
  """
  def text_completion(text, opts \\ []) do
    choice = %{
      index: 0,
      text: text,
      message: nil,
      finish_reason: Keyword.get(opts, :finish_reason, :stop),
      logprobs: nil
    }

    new(Keyword.merge(opts, [choices: [choice], object: "text_completion"]))
  end

  @doc """
  Create a response with a single chat message.
  """
  def chat_completion(message, opts \\ []) do
    choice = %{
      index: 0,
      message: message,
      text: nil,
      finish_reason: Keyword.get(opts, :finish_reason, :stop),
      logprobs: nil
    }

    new(Keyword.merge(opts, [choices: [choice], object: "chat.completion"]))
  end

  @doc """
  Create an error response.
  """
  def error(error_type, message, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})
    error_metadata = Map.merge(metadata, %{
      error: %{
        type: error_type,
        message: message,
        code: Keyword.get(opts, :code),
        param: Keyword.get(opts, :param)
      }
    })

    new(Keyword.merge(opts, [metadata: error_metadata]))
  end

  @doc """
  Extract the primary completion text from the response.
  """
  def extract_content(%__MODULE__{choices: [%{message: %{content: content}} | _]}) when is_binary(content) do
    content
  end

  def extract_content(%__MODULE__{choices: [%{text: text} | _]}) when is_binary(text) do
    text
  end

  def extract_content(%__MODULE__{choices: []}) do
    ""
  end

  def extract_content(_) do
    ""
  end

  @doc """
  Extract the primary message from the response.
  """
  def extract_message(%__MODULE__{choices: [%{message: message} | _]}) when not is_nil(message) do
    message
  end

  def extract_message(_) do
    nil
  end

  @doc """
  Check if the response indicates an error.
  """
  def error?(%__MODULE__{metadata: %{error: _}}) do
    true
  end

  def error?(_) do
    false
  end

  @doc """
  Get error details from the response.
  """
  def get_error(%__MODULE__{metadata: %{error: error}}) do
    {:error, error}
  end

  def get_error(_) do
    {:error, :no_error}
  end

  @doc """
  Check if the response is complete.
  """
  def complete?(%__MODULE__{choices: choices}) do
    Enum.any?(choices, fn choice ->
      choice.finish_reason in [:stop, :function_call, :tool_calls]
    end)
  end

  @doc """
  Check if the response was truncated due to length limits.
  """
  def truncated?(%__MODULE__{choices: choices}) do
    Enum.any?(choices, fn choice ->
      choice.finish_reason == :length
    end)
  end

  @doc """
  Get total token usage from the response.
  """
  def get_token_usage(%__MODULE__{usage: %{total_tokens: total}}) do
    total
  end

  def get_token_usage(_) do
    0
  end

  @doc """
  Add metadata to the response.
  """
  def add_metadata(%__MODULE__{} = response, key, value) do
    new_metadata = Map.put(response.metadata, key, value)
    %{response | metadata: new_metadata}
  end

  @doc """
  Merge additional metadata into the response.
  """
  def merge_metadata(%__MODULE__{} = response, metadata) when is_map(metadata) do
    new_metadata = Map.merge(response.metadata, metadata)
    %{response | metadata: new_metadata}
  end

  @doc """
  Convert response to provider-specific format.
  """
  def to_provider_format(%__MODULE__{} = response, :openai) do
    %{
      "id" => response.id,
      "object" => response.object,
      "created" => response.created,
      "model" => response.model,
      "choices" => Enum.map(response.choices, &choice_to_openai/1),
      "usage" => usage_to_openai(response.usage),
      "system_fingerprint" => response.system_fingerprint
    }
    |> remove_nil_values()
  end

  def to_provider_format(%__MODULE__{} = response, :anthropic) do
    choice = List.first(response.choices) || %{}
    content = choice[:message][:content] || choice[:text] || ""

    %{
      "id" => response.id,
      "type" => "message",
      "role" => "assistant",
      "content" => [%{"type" => "text", "text" => content}],
      "model" => response.model,
      "stop_reason" => map_finish_reason_to_anthropic(choice[:finish_reason]),
      "stop_sequence" => nil,
      "usage" => usage_to_anthropic(response.usage)
    }
    |> remove_nil_values()
  end

  def to_provider_format(%__MODULE__{} = response, :generic) do
    Map.from_struct(response)
  end

  @doc """
  Convert from provider-specific format to standard response.
  """
  def from_provider_format(provider_response, :openai) do
    %__MODULE__{
      id: provider_response["id"],
      object: provider_response["object"],
      created: provider_response["created"],
      model: provider_response["model"],
      choices: Enum.map(provider_response["choices"] || [], &choice_from_openai/1),
      usage: usage_from_openai(provider_response["usage"]),
      system_fingerprint: provider_response["system_fingerprint"],
      metadata: %{}
    }
  end

  def from_provider_format(provider_response, :anthropic) do
    content = extract_anthropic_content(provider_response["content"])
    message = RubberDuck.LLMAbstraction.Message.assistant(content)

    choice = %{
      index: 0,
      message: message,
      text: nil,
      finish_reason: map_finish_reason_from_anthropic(provider_response["stop_reason"]),
      logprobs: nil
    }

    %__MODULE__{
      id: provider_response["id"],
      object: "chat.completion",
      created: System.system_time(:second),
      model: provider_response["model"],
      choices: [choice],
      usage: usage_from_anthropic(provider_response["usage"]),
      system_fingerprint: nil,
      metadata: %{}
    }
  end

  def from_provider_format(provider_response, :generic) do
    struct(__MODULE__, provider_response)
  end

  # Private Functions

  defp generate_id do
    "resp_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp choice_to_openai(choice) do
    base = %{
      "index" => choice.index,
      "finish_reason" => choice.finish_reason
    }

    base
    |> maybe_add_message(choice.message)
    |> maybe_add_text(choice.text)
    |> maybe_add_logprobs(choice.logprobs)
  end

  defp choice_from_openai(choice) do
    message = if choice["message"] do
      RubberDuck.LLMAbstraction.Message.from_provider_format(choice["message"], :openai)
    else
      nil
    end

    %{
      index: choice["index"],
      message: message,
      text: choice["text"],
      finish_reason: String.to_existing_atom(choice["finish_reason"] || "stop"),
      logprobs: choice["logprobs"]
    }
  rescue
    ArgumentError -> 
      %{
        index: choice["index"],
        message: nil,
        text: choice["text"],
        finish_reason: :stop,
        logprobs: choice["logprobs"]
      }
  end

  defp usage_to_openai(nil), do: nil
  defp usage_to_openai(usage) do
    %{
      "prompt_tokens" => usage.prompt_tokens,
      "completion_tokens" => usage.completion_tokens,
      "total_tokens" => usage.total_tokens
    }
  end

  defp usage_from_openai(nil), do: nil
  defp usage_from_openai(usage) do
    %{
      prompt_tokens: usage["prompt_tokens"],
      completion_tokens: usage["completion_tokens"],
      total_tokens: usage["total_tokens"]
    }
  end

  defp usage_to_anthropic(nil), do: nil
  defp usage_to_anthropic(usage) do
    %{
      "input_tokens" => usage.prompt_tokens,
      "output_tokens" => usage.completion_tokens
    }
  end

  defp usage_from_anthropic(nil), do: nil
  defp usage_from_anthropic(usage) do
    input_tokens = usage["input_tokens"] || 0
    output_tokens = usage["output_tokens"] || 0

    %{
      prompt_tokens: input_tokens,
      completion_tokens: output_tokens,
      total_tokens: input_tokens + output_tokens
    }
  end

  defp extract_anthropic_content(content) when is_list(content) do
    content
    |> Enum.filter(&(Map.get(&1, "type") == "text"))
    |> Enum.map(&Map.get(&1, "text", ""))
    |> Enum.join("")
  end

  defp extract_anthropic_content(content) when is_binary(content) do
    content
  end

  defp extract_anthropic_content(_) do
    ""
  end

  defp map_finish_reason_to_anthropic(:stop), do: "end_turn"
  defp map_finish_reason_to_anthropic(:length), do: "max_tokens"
  defp map_finish_reason_to_anthropic(:content_filter), do: "stop_sequence"
  defp map_finish_reason_to_anthropic(_), do: "end_turn"

  defp map_finish_reason_from_anthropic("end_turn"), do: :stop
  defp map_finish_reason_from_anthropic("max_tokens"), do: :length
  defp map_finish_reason_from_anthropic("stop_sequence"), do: :content_filter
  defp map_finish_reason_from_anthropic(_), do: :stop

  defp maybe_add_message(map, nil), do: map
  defp maybe_add_message(map, message) do
    Map.put(map, "message", RubberDuck.LLMAbstraction.Message.to_provider_format(message, :openai))
  end

  defp maybe_add_text(map, nil), do: map
  defp maybe_add_text(map, text), do: Map.put(map, "text", text)

  defp maybe_add_logprobs(map, nil), do: map
  defp maybe_add_logprobs(map, logprobs), do: Map.put(map, "logprobs", logprobs)

  defp remove_nil_values(map) do
    Map.reject(map, fn {_k, v} -> is_nil(v) end)
  end
end