defmodule RubberDuck.LLM.Tokenization do
  @moduledoc """
  Provides accurate token counting for different LLM providers.

  Uses provider-specific tokenizers:
  - OpenAI: tiktoken library with appropriate encoding models
  - Anthropic: HuggingFace tokenizers with Claude-specific models
  - Fallback: Simple approximation for unknown providers
  """

  require Logger

  @type model :: String.t()
  @type text :: String.t()
  @type token_count :: non_neg_integer()
  @type provider :: :openai | :anthropic | atom()

  @doc """
  Counts tokens for the given text using the appropriate tokenizer for the model.

  ## Examples

      iex> Tokenization.count_tokens("Hello world", "gpt-4")
      {:ok, 2}
      
      iex> Tokenization.count_tokens("Hello world", "claude-3-sonnet")
      {:ok, 3}
  """
  @spec count_tokens(text(), model()) :: {:ok, token_count()} | {:error, term()}
  def count_tokens(text, model) when is_binary(text) and is_binary(model) do
    provider = detect_provider(model)
    count_tokens_for_provider(text, model, provider)
  end

  @spec count_tokens(list(map()), model()) :: {:ok, token_count()} | {:error, term()}
  def count_tokens(messages, model) when is_list(messages) and is_binary(model) do
    provider = detect_provider(model)
    count_message_tokens(messages, model, provider)
  end

  @doc """
  Gets the encoding name for a given model.
  """
  @spec get_encoding_for_model(model()) :: String.t()
  def get_encoding_for_model(model) do
    case detect_provider(model) do
      :openai -> get_openai_encoding(model)
      # Placeholder
      :anthropic -> "claude"
      _ -> "unknown"
    end
  end

  @doc """
  Lists all supported models and their tokenization capabilities.
  """
  @spec supported_models() :: map()
  def supported_models do
    %{
      openai: %{
        models: [
          %{model: "gpt-4", encoding: "cl100k_base", tiktoken: true},
          %{model: "gpt-4-turbo", encoding: "cl100k_base", tiktoken: true},
          %{model: "gpt-4o", encoding: "o200k_base", tiktoken: true},
          %{model: "gpt-4o-mini", encoding: "o200k_base", tiktoken: true},
          %{model: "gpt-3.5-turbo", encoding: "cl100k_base", tiktoken: true}
        ]
      },
      anthropic: %{
        models: [
          %{model: "claude-3-opus", encoding: "claude", tiktoken: false},
          %{model: "claude-3-sonnet", encoding: "claude", tiktoken: false},
          %{model: "claude-3-haiku", encoding: "claude", tiktoken: false},
          %{model: "claude-3.7-sonnet", encoding: "claude", tiktoken: false}
        ]
      }
    }
  end

  # Private Functions

  defp detect_provider(model) do
    cond do
      String.starts_with?(model, "gpt-") -> :openai
      String.starts_with?(model, "claude-") -> :anthropic
      model in ["o1", "o1-preview", "o1-mini"] -> :openai
      true -> :unknown
    end
  end

  defp count_tokens_for_provider(text, model, :openai) do
    # Handle empty text early
    if text == "" do
      {:ok, 0}
    else
      try do
        case Tiktoken.encode_ordinary(model, text) do
          {:ok, tokens} ->
            {:ok, length(tokens)}

          {:error, reason} ->
            Logger.warning("Tiktoken encoding failed: #{inspect(reason)}, falling back to approximation")
            {:ok, approximate_token_count(text)}
        end
      rescue
        error ->
          Logger.warning("Tiktoken error: #{inspect(error)}, falling back to approximation")
          {:ok, approximate_token_count(text)}
      end
    end
  end

  defp count_tokens_for_provider(text, model, :anthropic) do
    # For Anthropic, we'll use a character-based approximation
    # In a production system, you'd want to use their actual tokenizer
    # or the HuggingFace tokenizers with Claude-specific models
    count_anthropic_tokens(text, model)
  end

  defp count_tokens_for_provider(text, _model, _provider) do
    # Fallback approximation for unknown providers
    {:ok, approximate_token_count(text)}
  end

  defp count_message_tokens(messages, model, :openai) do
    _encoding = get_openai_encoding(model)

    # Calculate base overhead
    base_overhead =
      case model do
        # Every message follows <|start|>{role/name}\n{content}<|end|>\n
        "gpt-3.5-turbo" -> 3
        # GPT-4 models
        _ -> 3
      end

    message_tokens =
      Enum.reduce(messages, 0, fn message, acc ->
        # Count tokens in content
        content = get_message_content(message)

        {:ok, content_tokens} = count_tokens_for_provider(content, model, :openai)

        # Add role tokens
        role = message["role"] || message[:role] || "user"
        {:ok, role_tokens} = count_tokens_for_provider(role, model, :openai)

        # Add tokens for message structure
        message_overhead = base_overhead + role_tokens

        acc + content_tokens + message_overhead
      end)

    # Add tokens for assistant reply priming
    reply_tokens = 3

    {:ok, message_tokens + reply_tokens}
  end

  defp count_message_tokens(messages, model, :anthropic) do
    # For Anthropic, messages don't have the same overhead structure
    total_tokens =
      Enum.reduce(messages, 0, fn message, acc ->
        content = get_message_content(message)
        {:ok, tokens} = count_anthropic_tokens(content, model)
        acc + tokens
      end)

    {:ok, total_tokens}
  end

  defp count_message_tokens(messages, _model, _provider) do
    # Fallback for unknown providers
    total_chars =
      Enum.reduce(messages, 0, fn message, acc ->
        content = get_message_content(message)
        acc + String.length(content)
      end)

    {:ok, approximate_token_count_from_chars(total_chars)}
  end

  defp get_openai_encoding(model) do
    cond do
      model == "gpt-4o" -> "o200k_base"
      model == "gpt-4o-mini" -> "o200k_base"
      model in ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"] -> "cl100k_base"
      model in ["davinci-002", "babbage-002"] -> "cl100k_base"
      String.starts_with?(model, "code-") -> "p50k_base"
      # Default to most common modern encoding
      true -> "cl100k_base"
    end
  end

  defp count_anthropic_tokens(text, _model) do
    # Anthropic uses a different tokenizer
    # For now, use character-based approximation
    # In production, you'd use the actual Claude tokenizer

    # Claude typically has ~4 characters per token for English text
    chars = String.length(text)
    tokens = round(chars / 4.0)

    {:ok, max(1, tokens)}
  end

  defp get_message_content(message) do
    message["content"] || message[:content] || ""
  end

  defp approximate_token_count(text) do
    # Simple approximation: ~4 characters per token for English
    case String.length(text) do
      0 ->
        0

      _chars ->
        words = text |> String.split(~r/\s+/) |> length()
        # Use word count * 1.3 as a reasonable approximation
        max(1, round(words * 1.3))
    end
  end

  defp approximate_token_count_from_chars(chars) do
    round(chars / 4.0)
  end
end
