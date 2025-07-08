defmodule RubberDuck.LLM.Response do
  @moduledoc """
  Represents a response from an LLM provider.

  Provides a unified format across different providers.
  """

  @type usage :: %{
          prompt_tokens: non_neg_integer(),
          completion_tokens: non_neg_integer(),
          total_tokens: non_neg_integer()
        }

  @type choice :: %{
          index: non_neg_integer(),
          message: map(),
          finish_reason: String.t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          model: String.t(),
          provider: atom(),
          choices: list(choice()),
          usage: usage() | nil,
          created_at: DateTime.t(),
          metadata: map(),
          cached: boolean()
        }

  defstruct [
    :id,
    :model,
    :provider,
    :choices,
    :usage,
    :created_at,
    metadata: %{},
    cached: false
  ]

  @doc """
  Creates a new response from provider-specific format.
  """
  def from_provider(:openai, raw_response) do
    %__MODULE__{
      id: raw_response["id"],
      model: raw_response["model"],
      provider: :openai,
      choices: parse_openai_choices(raw_response["choices"]),
      usage: parse_openai_usage(raw_response["usage"]),
      created_at: DateTime.from_unix!(raw_response["created"]),
      metadata: %{
        object: raw_response["object"],
        system_fingerprint: raw_response["system_fingerprint"]
      }
    }
  end

  def from_provider(:anthropic, raw_response) do
    %__MODULE__{
      id: raw_response["id"],
      model: raw_response["model"],
      provider: :anthropic,
      choices: parse_anthropic_content(raw_response["content"]),
      usage: parse_anthropic_usage(raw_response["usage"]),
      created_at: DateTime.utc_now(),
      metadata: %{
        stop_reason: raw_response["stop_reason"],
        stop_sequence: raw_response["stop_sequence"]
      }
    }
  end

  def from_provider(:ollama, raw_response) do
    # Ollama uses a different response format
    content = raw_response["message"]["content"] || raw_response["response"] || ""

    %__MODULE__{
      id: generate_id(),
      model: raw_response["model"],
      provider: :ollama,
      choices: [
        %{
          index: 0,
          message: %{
            "role" => "assistant",
            "content" => content
          },
          finish_reason: if(raw_response["done"], do: "stop", else: "length")
        }
      ],
      usage: parse_ollama_usage(raw_response),
      created_at: DateTime.utc_now(),
      metadata: %{
        total_duration: raw_response["total_duration"],
        load_duration: raw_response["load_duration"],
        eval_duration: raw_response["eval_duration"],
        done: raw_response["done"]
      }
    }
  end

  def from_provider(:tgi, raw_response) do
    # TGI can return either OpenAI-compatible or native format
    if raw_response["id"] && raw_response["object"] do
      # OpenAI-compatible format from /v1/chat/completions
      %__MODULE__{
        id: raw_response["id"],
        model: raw_response["model"],
        provider: :tgi,
        choices: parse_openai_choices(raw_response["choices"]),
        usage: parse_openai_usage(raw_response["usage"]),
        created_at: parse_tgi_timestamp(raw_response["created"]) || DateTime.utc_now(),
        metadata: %{
          object: raw_response["object"],
          system_fingerprint: raw_response["system_fingerprint"]
        }
      }
    else
      # TGI native format from /generate endpoint
      %__MODULE__{
        id: generate_id(),
        model: raw_response["model"] || "tgi",
        provider: :tgi,
        choices: [
          %{
            index: 0,
            message: %{
              "role" => "assistant",
              "content" => raw_response["generated_text"] || ""
            },
            finish_reason: parse_tgi_finish_reason(raw_response["finish_reason"])
          }
        ],
        usage: parse_tgi_usage(raw_response["details"]),
        created_at: DateTime.utc_now(),
        metadata: %{
          details: raw_response["details"]
        }
      }
    end
  end

  def from_provider(provider, raw_response) do
    # Generic fallback for unknown providers
    %__MODULE__{
      id: generate_id(),
      model: raw_response["model"] || "unknown",
      provider: provider,
      choices: [
        %{
          index: 0,
          message: %{
            role: "assistant",
            content: extract_content(raw_response)
          },
          finish_reason: "stop"
        }
      ],
      usage: nil,
      created_at: DateTime.utc_now(),
      metadata: raw_response
    }
  end

  @doc """
  Gets the primary content from the response.
  """
  def get_content(%__MODULE__{choices: [choice | _]}) do
    choice.message["content"] || choice.message[:content]
  end

  def get_content(%__MODULE__{choices: []}), do: nil

  @doc """
  Gets all messages from the response.
  """
  def get_messages(%__MODULE__{choices: choices}) do
    Enum.map(choices, & &1.message)
  end

  @doc """
  Calculates the cost of the response based on provider pricing.
  """
  def calculate_cost(%__MODULE__{usage: nil}), do: 0.0

  def calculate_cost(%__MODULE__{provider: provider, model: model, usage: usage}) do
    pricing = get_pricing(provider, model)

    prompt_cost = usage.prompt_tokens / 1000 * pricing.prompt_price
    completion_cost = usage.completion_tokens / 1000 * pricing.completion_price

    prompt_cost + completion_cost
  end

  # Private functions

  defp parse_openai_choices(nil), do: []

  defp parse_openai_choices(choices) do
    Enum.map(choices, fn choice ->
      %{
        index: choice["index"],
        message: choice["message"],
        finish_reason: choice["finish_reason"]
      }
    end)
  end

  defp parse_openai_usage(nil), do: nil

  defp parse_openai_usage(usage) do
    %{
      prompt_tokens: usage["prompt_tokens"],
      completion_tokens: usage["completion_tokens"],
      total_tokens: usage["total_tokens"]
    }
  end

  defp parse_anthropic_content(nil), do: []

  defp parse_anthropic_content(content) when is_list(content) do
    # Anthropic returns content as a list of content blocks
    text_content =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map(& &1["text"])
      |> Enum.join("\n")

    [
      %{
        index: 0,
        message: %{
          role: "assistant",
          content: text_content
        },
        finish_reason: "stop"
      }
    ]
  end

  defp parse_anthropic_usage(nil), do: nil

  defp parse_anthropic_usage(usage) do
    %{
      prompt_tokens: usage["input_tokens"],
      completion_tokens: usage["output_tokens"],
      total_tokens: usage["input_tokens"] + usage["output_tokens"]
    }
  end

  defp parse_ollama_usage(nil), do: nil

  defp parse_ollama_usage(response) do
    prompt_tokens = response["prompt_eval_count"] || 0
    completion_tokens = response["eval_count"] || 0

    %{
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens
    }
  end

  defp extract_content(response) when is_map(response) do
    response["content"] || response["text"] || response["message"] || ""
  end

  defp extract_content(response) when is_binary(response), do: response
  defp extract_content(_), do: ""

  defp generate_id do
    ("resp_" <> :crypto.strong_rand_bytes(16)) |> Base.encode16(case: :lower)
  end

  defp get_pricing(:openai, model) do
    # Pricing in dollars per 1K tokens (as of 2024)
    case model do
      "gpt-4" -> %{prompt_price: 0.03, completion_price: 0.06}
      "gpt-4-turbo" -> %{prompt_price: 0.01, completion_price: 0.03}
      "gpt-3.5-turbo" -> %{prompt_price: 0.0005, completion_price: 0.0015}
      _ -> %{prompt_price: 0.01, completion_price: 0.03}
    end
  end

  defp get_pricing(:anthropic, model) do
    case model do
      "claude-3-opus" -> %{prompt_price: 0.015, completion_price: 0.075}
      "claude-3-sonnet" -> %{prompt_price: 0.003, completion_price: 0.015}
      "claude-3-haiku" -> %{prompt_price: 0.00025, completion_price: 0.00125}
      _ -> %{prompt_price: 0.003, completion_price: 0.015}
    end
  end

  defp get_pricing(:ollama, _model) do
    # Ollama is free (local models)
    %{prompt_price: 0.0, completion_price: 0.0}
  end

  defp get_pricing(:tgi, _model) do
    # TGI is free (self-hosted models)
    %{prompt_price: 0.0, completion_price: 0.0}
  end

  defp get_pricing(_, _) do
    # Default pricing for unknown providers
    %{prompt_price: 0.01, completion_price: 0.02}
  end

  defp parse_tgi_timestamp(nil), do: nil
  defp parse_tgi_timestamp(unix_timestamp) when is_integer(unix_timestamp) do
    DateTime.from_unix!(unix_timestamp)
  end

  defp parse_tgi_finish_reason(nil), do: "stop"
  defp parse_tgi_finish_reason(reason), do: reason

  defp parse_tgi_usage(nil), do: nil
  defp parse_tgi_usage(details) do
    %{
      prompt_tokens: details["prefill"] && length(details["prefill"]) || 0,
      completion_tokens: details["tokens"] && length(details["tokens"]) || 0,
      total_tokens: (details["prefill"] && length(details["prefill"]) || 0) + 
                   (details["tokens"] && length(details["tokens"]) || 0)
    }
  end
end
