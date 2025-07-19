defmodule RubberDuck.Context.Strategies.FIM do
  @moduledoc """
  Fill-in-the-Middle (FIM) context building strategy.

  Optimized for code completion scenarios where we need to provide
  context before and after the cursor position.
  """

  @behaviour RubberDuck.Context.Builder

  alias RubberDuck.Memory
  alias RubberDuck.Context.InstructionEnhancer

  @default_prefix_tokens 1500
  @default_suffix_tokens 500

  @impl true
  def name(), do: :fim

  @impl true
  def supported_query_types(), do: [:completion, :code_completion]

  @impl true
  def build(_query, opts) do
    # Enhance options with instruction-driven preferences
    enhanced_opts = InstructionEnhancer.create_enhanced_options(opts)

    user_id = Keyword.get(enhanced_opts, :user_id)
    session_id = Keyword.get(enhanced_opts, :session_id)
    max_tokens = Keyword.get(enhanced_opts, :max_tokens, 4000)
    cursor_position = Keyword.get(enhanced_opts, :cursor_position, 0)
    file_content = Keyword.get(enhanced_opts, :file_content, "")

    # Extract prefix and suffix around cursor
    {prefix, suffix} = split_at_cursor(file_content, cursor_position)

    # Get recent interactions for additional context
    recent_context = get_recent_context(user_id, session_id)

    # Build FIM prompt
    base_context = build_fim_context(prefix, suffix, recent_context, max_tokens)

    # Enhance with instruction-driven features
    enhanced_context = InstructionEnhancer.enhance_strategy_context(base_context, :fim, enhanced_opts)

    {:ok, enhanced_context}
  rescue
    e ->
      {:error, e}
  end

  @impl true
  def estimate_quality(query, opts) do
    # FIM is best for completion queries with cursor position
    base_quality =
      cond do
        Keyword.has_key?(opts, :cursor_position) -> 0.9
        String.contains?(query, ["complete", "finish", "continue"]) -> 0.7
        true -> 0.3
      end

    # Boost quality if instructions prefer this strategy
    instruction_boost =
      if Keyword.get(opts, :preferred_strategy) == :fim do
        0.2
      else
        0.0
      end

    min(base_quality + instruction_boost, 1.0)
  end

  # Private functions

  defp split_at_cursor(content, position) do
    {
      String.slice(content, 0, position) || "",
      String.slice(content, position, String.length(content)) || ""
    }
  end

  defp get_recent_context(user_id, session_id) when is_binary(user_id) and is_binary(session_id) do
    case Memory.get_recent_interactions(user_id, session_id) do
      {:ok, interactions} ->
        interactions
        # Last 5 interactions
        |> Enum.take(5)
        |> Enum.map(& &1.content)
        |> Enum.join("\n")

      _ ->
        ""
    end
  end

  defp get_recent_context(_, _), do: ""

  defp build_fim_context(prefix, suffix, recent_context, max_tokens) do
    # Reserve tokens for FIM markers and response
    # Reserve 500 for response
    available_tokens = max_tokens - 500

    # Allocate tokens between prefix, suffix, and recent context
    prefix_tokens = min(@default_prefix_tokens, div(available_tokens * 6, 10))
    suffix_tokens = min(@default_suffix_tokens, div(available_tokens * 2, 10))
    context_tokens = available_tokens - prefix_tokens - suffix_tokens

    # Truncate to fit token limits (rough estimation: 1 token ≈ 4 chars)
    truncated_prefix = truncate_to_tokens(prefix, prefix_tokens, :start)
    truncated_suffix = truncate_to_tokens(suffix, suffix_tokens, :end)
    truncated_context = truncate_to_tokens(recent_context, context_tokens, :end)

    # Build the FIM prompt
    fim_content = build_fim_prompt(truncated_prefix, truncated_suffix, truncated_context)

    %{
      content: fim_content,
      metadata: %{
        prefix_length: String.length(truncated_prefix),
        suffix_length: String.length(truncated_suffix),
        context_included: truncated_context != ""
      },
      token_count: estimate_tokens(fim_content),
      strategy: :fim,
      sources: [
        %{type: :current_file, content: truncated_prefix <> truncated_suffix},
        %{type: :recent_interactions, content: truncated_context}
      ]
    }
  end

  defp truncate_to_tokens(text, max_tokens, direction) do
    # Rough estimation: 1 token ≈ 4 characters
    max_chars = max_tokens * 4

    if String.length(text) <= max_chars do
      text
    else
      case direction do
        :start ->
          # Keep the end of the text (most recent)
          "..." <> String.slice(text, -max_chars..-1)

        :end ->
          # Keep the start of the text
          String.slice(text, 0, max_chars) <> "..."
      end
    end
  end

  defp build_fim_prompt(prefix, suffix, recent_context) do
    parts = []

    # Add recent context if available
    parts1 =
      if recent_context != "" do
        ["# Recent context:\n#{recent_context}\n\n" | parts]
      else
        parts
      end

    # Add FIM markers
    parts2 =
      parts1 ++
        [
          "<fim_prefix>#{prefix}",
          "<fim_suffix>#{suffix}<fim_middle>"
        ]

    Enum.join(parts2, "")
  end

  defp estimate_tokens(text) do
    # Rough estimation: 1 token ≈ 4 characters
    div(String.length(text), 4)
  end
end
