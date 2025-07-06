defmodule RubberDuck.Context.Optimizer do
  @moduledoc """
  Optimizes context to fit within token limits while preserving the most important information.
  
  Provides smart truncation, token counting, and importance-based filtering.
  """

  # Rough token estimates per model
  @model_token_limits %{
    "gpt-3.5-turbo" => 4_096,
    "gpt-3.5-turbo-16k" => 16_384,
    "gpt-4" => 8_192,
    "gpt-4-32k" => 32_768,
    "gpt-4-turbo" => 128_000,
    "claude-2" => 100_000,
    "claude-3-opus" => 200_000,
    "claude-3-sonnet" => 200_000,
    "claude-3-haiku" => 200_000
  }

  # Characters per token approximation
  @chars_per_token 4

  @doc """
  Optimizes context to fit within the token limit for the specified model.
  
  Options:
  - `:model` - The LLM model being used
  - `:max_tokens` - Override the default token limit
  - `:reserve_tokens` - Tokens to reserve for the response (default: 20% of limit)
  """
  def optimize(context, opts \\ []) do
    model = Keyword.get(opts, :model, "gpt-3.5-turbo")
    max_tokens = Keyword.get(opts, :max_tokens) || get_model_limit(model)
    reserve_tokens = Keyword.get(opts, :reserve_tokens) || div(max_tokens, 5)  # 20%
    
    available_tokens = max_tokens - reserve_tokens
    current_tokens = estimate_tokens(context.content)
    
    if current_tokens <= available_tokens do
      # No optimization needed
      {:ok, context}
    else
      # Need to optimize
      optimized_content = optimize_content(
        context.content,
        context.sources,
        available_tokens,
        context.strategy
      )
      
      {:ok, %{context | 
        content: optimized_content,
        token_count: estimate_tokens(optimized_content),
        metadata: Map.put(context.metadata, :optimized, true)
      }}
    end
  end

  @doc """
  Counts tokens in text more accurately using the model's tokenizer.
  Falls back to approximation if exact counting fails.
  """
  def count_tokens(text, model \\ "gpt-3.5-turbo") do
    # TODO: Integrate with tiktoken or model-specific tokenizers
    # For now, use approximation
    estimate_tokens(text)
  end

  @doc """
  Estimates token count using character-based approximation.
  """
  def estimate_tokens(text) when is_binary(text) do
    # Account for whitespace and punctuation making tokens shorter on average
    words = String.split(text, ~r/\s+/)
    word_count = length(words)
    char_count = String.length(text)
    
    # Use a weighted average of word count and character-based estimation
    word_estimate = word_count * 1.3  # Most words ≈ 1.3 tokens
    char_estimate = char_count / @chars_per_token
    
    round((word_estimate + char_estimate) / 2)
  end
  def estimate_tokens(_), do: 0

  @doc """
  Splits text into chunks that fit within token limits.
  Useful for processing large documents.
  """
  def chunk_by_tokens(text, max_tokens_per_chunk) do
    lines = String.split(text, "\n")
    
    {chunks, current_chunk, _} =
      Enum.reduce(lines, {[], [], 0}, fn line, {chunks, current, tokens} ->
        line_tokens = estimate_tokens(line)
        
        if tokens + line_tokens > max_tokens_per_chunk and current != [] do
          # Start a new chunk
          {[Enum.reverse(current) | chunks], [line], line_tokens}
        else
          # Add to current chunk
          {chunks, [line | current], tokens + line_tokens}
        end
      end)
    
    # Don't forget the last chunk
    all_chunks = 
      if current_chunk != [] do
        [Enum.reverse(current_chunk) | chunks]
      else
        chunks
      end
    
    all_chunks
    |> Enum.reverse()
    |> Enum.map(&Enum.join(&1, "\n"))
  end

  # Private functions

  defp get_model_limit(model) do
    Map.get(@model_token_limits, model, 4_096)  # Default to smallest
  end

  defp optimize_content(content, sources, available_tokens, strategy) do
    # Strategy-specific optimization
    case strategy do
      :fim -> optimize_fim_content(content, available_tokens)
      :rag -> optimize_rag_content(content, sources, available_tokens)
      :long_context -> optimize_long_content(content, available_tokens)
      _ -> simple_truncate(content, available_tokens)
    end
  end

  defp optimize_fim_content(content, available_tokens) do
    # For FIM, preserve the area around the cursor
    # The content should have FIM markers
    if String.contains?(content, "<fim_") do
      parts = String.split(content, ~r/<fim_[^>]+>/)
      
      case parts do
        [prefix, suffix, middle] ->
          # Allocate tokens: 60% prefix, 30% suffix, 10% middle/context
          prefix_tokens = div(available_tokens * 6, 10)
          suffix_tokens = div(available_tokens * 3, 10)
          middle_tokens = available_tokens - prefix_tokens - suffix_tokens
          
          optimized_prefix = smart_truncate(prefix, prefix_tokens, :end)
          optimized_suffix = smart_truncate(suffix, suffix_tokens, :start)
          optimized_middle = smart_truncate(middle, middle_tokens, :end)
          
          "<fim_prefix>#{optimized_prefix}<fim_suffix>#{optimized_suffix}<fim_middle>#{optimized_middle}"
        
        _ ->
          simple_truncate(content, available_tokens)
      end
    else
      simple_truncate(content, available_tokens)
    end
  end

  defp optimize_rag_content(content, sources, available_tokens) do
    # For RAG, identify sections and prioritize
    sections = parse_sections(content)
    
    # Priority: query > code patterns > recent context > knowledge > summaries
    priority_order = ["Query", "Relevant Code Patterns", "Recent Context", 
                     "Relevant Knowledge", "Pattern Summaries"]
    
    optimized_sections = prioritize_sections(sections, priority_order, available_tokens)
    
    Enum.join(optimized_sections, "\n\n")
  end

  defp optimize_long_content(content, available_tokens) do
    # For long context, try to preserve structure
    sections = parse_sections(content)
    
    if length(sections) > 0 do
      # Distribute tokens proportionally
      tokens_per_section = div(available_tokens, length(sections))
      
      sections
      |> Enum.map(fn {header, body} ->
        optimized_body = smart_truncate(body, tokens_per_section - 10, :middle)
        "#{header}\n#{optimized_body}"
      end)
      |> Enum.join("\n\n")
    else
      smart_truncate(content, available_tokens, :middle)
    end
  end

  defp parse_sections(content) do
    # Parse markdown-style sections
    content
    |> String.split(~r/^##\s+/m, trim: true)
    |> Enum.map(fn section ->
      case String.split(section, "\n", parts: 2) do
        [header, body] -> {"## " <> String.trim(header), body}
        [header] -> {"## " <> String.trim(header), ""}
      end
    end)
    |> Enum.filter(fn {_, body} -> body != "" end)
  end

  defp prioritize_sections(sections, priority_order, available_tokens) do
    # Group sections by header
    section_map = Map.new(sections)
    
    {included, _remaining} =
      Enum.reduce(priority_order, {[], available_tokens}, fn header_prefix, {acc, tokens_left} ->
        case find_section(section_map, header_prefix) do
          {header, body} ->
            body_tokens = estimate_tokens(body)
            if body_tokens <= tokens_left do
              {["#{header}\n#{body}" | acc], tokens_left - body_tokens - 5}
            else
              truncated = smart_truncate(body, tokens_left - 50, :end)
              {["#{header}\n#{truncated}" | acc], 0}
            end
          
          nil ->
            {acc, tokens_left}
        end
      end)
    
    Enum.reverse(included)
  end

  defp find_section(section_map, prefix) do
    Enum.find(section_map, fn {header, _} ->
      String.starts_with?(header, "## " <> prefix)
    end)
  end

  defp smart_truncate(text, max_tokens, position) do
    max_chars = max_tokens * @chars_per_token
    
    cond do
      estimate_tokens(text) <= max_tokens ->
        text
      
      position == :start ->
        # Keep the end
        truncated = String.slice(text, -(max_chars - 20)..-1)
        "... (truncated)\n" <> truncated
      
      position == :end ->
        # Keep the beginning
        truncated = String.slice(text, 0, max_chars - 20)
        truncated <> "\n... (truncated)"
      
      position == :middle ->
        # Keep both ends
        half_chars = div(max_chars - 40, 2)
        beginning = String.slice(text, 0, half_chars)
        ending = String.slice(text, -half_chars..-1)
        beginning <> "\n... (content omitted) ...\n" <> ending
      
      true ->
        simple_truncate(text, max_tokens)
    end
  end

  defp simple_truncate(text, max_tokens) do
    max_chars = max_tokens * @chars_per_token
    
    if String.length(text) <= max_chars do
      text
    else
      String.slice(text, 0, max_chars - 20) <> "\n... (truncated)"
    end
  end
end