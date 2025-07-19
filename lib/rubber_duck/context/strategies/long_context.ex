defmodule RubberDuck.Context.Strategies.LongContext do
  @moduledoc """
  Long context window strategy for models that support extended contexts.

  This strategy maximizes the use of available context window by including
  comprehensive project context, conversation history, and relevant code.
  """

  @behaviour RubberDuck.Context.Builder

  alias RubberDuck.Memory
  alias RubberDuck.Context.InstructionEnhancer

  @impl true
  def name(), do: :long_context

  @impl true
  def supported_query_types(), do: [:analysis, :architecture, :refactoring, :documentation]

  @impl true
  def build(query, opts) do
    # Enhance options with instruction-driven preferences
    enhanced_opts = InstructionEnhancer.create_enhanced_options(opts)

    user_id = Keyword.get(enhanced_opts, :user_id)
    session_id = Keyword.get(enhanced_opts, :session_id)
    project_id = Keyword.get(enhanced_opts, :project_id)
    # Default for long context models
    max_tokens = Keyword.get(enhanced_opts, :max_tokens, 32000)
    files = Keyword.get(enhanced_opts, :files, [])

    # Build comprehensive context
    with {:ok, user_profile} <- get_user_profile(user_id),
         {:ok, conversation_history} <- get_conversation_history(user_id, session_id),
         {:ok, project_context} <- get_project_context(user_id, project_id),
         {:ok, file_contents} <- get_file_contents(files),
         base_context <-
           build_long_context(
             query,
             user_profile,
             conversation_history,
             project_context,
             file_contents,
             max_tokens
           ),
         # Enhance with instruction-driven features
         enhanced_context <- InstructionEnhancer.enhance_strategy_context(base_context, :long_context, enhanced_opts) do
      {:ok, enhanced_context}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :context_building_failed}
    end
  end

  @impl true
  def estimate_quality(query, opts) do
    # Long context is best for complex, multi-file operations
    base_quality =
      cond do
        # Model supports long context
        Keyword.get(opts, :max_tokens, 4000) >= 16000 -> 0.9
        # Multi-file operation
        length(Keyword.get(opts, :files, [])) > 3 -> 0.8
        String.contains?(query, ["architecture", "refactor", "analyze", "document"]) -> 0.7
        true -> 0.4
      end

    # Boost quality if instructions prefer this strategy
    instruction_boost =
      if Keyword.get(opts, :preferred_strategy) == :long_context do
        0.2
      else
        0.0
      end

    min(base_quality + instruction_boost, 1.0)
  end

  # Private functions

  defp get_user_profile(user_id) when is_binary(user_id) do
    case Memory.get_user_profile(user_id) do
      {:ok, profile} -> {:ok, profile}
      _ -> {:ok, nil}
    end
  end

  defp get_user_profile(_), do: {:ok, nil}

  defp get_conversation_history(user_id, session_id) when is_binary(user_id) and is_binary(session_id) do
    case Memory.get_recent_interactions(user_id, session_id) do
      {:ok, interactions} ->
        # Get more history for long context
        history =
          interactions
          # Last 20 interactions
          |> Enum.take(20)
          |> Enum.map(&format_interaction/1)
          # Chronological order
          |> Enum.reverse()

        {:ok, history}

      _ ->
        {:ok, []}
    end
  end

  defp get_conversation_history(_, _), do: {:ok, []}

  defp get_project_context(user_id, project_id) when is_binary(user_id) and is_binary(project_id) do
    # Get project-specific knowledge and patterns
    knowledge =
      case Memory.get_project_knowledge(user_id, project_id) do
        {:ok, items} -> Enum.take(items, 10)
        _ -> []
      end

    patterns =
      case Memory.search_patterns_keyword(user_id, "") do
        {:ok, items} -> Enum.take(items, 10)
        _ -> []
      end

    {:ok, %{knowledge: knowledge, patterns: patterns}}
  end

  defp get_project_context(_, _), do: {:ok, %{knowledge: [], patterns: []}}

  defp get_file_contents(files) when is_list(files) do
    contents =
      files
      |> Enum.map(fn
        # Handle map with path and content
        %{path: path, content: content} when is_binary(content) ->
          %{path: path, content: content, error: nil}

        # Handle just a path string
        path when is_binary(path) ->
          case File.read(path) do
            {:ok, content} ->
              %{path: path, content: content, error: nil}

            {:error, reason} ->
              %{path: path, content: nil, error: reason}
          end

        # Handle other formats
        _ ->
          nil
      end)
      # Only include successfully read files
      |> Enum.filter(&(&1 != nil and &1.content != nil))

    {:ok, contents}
  end

  defp get_file_contents(_), do: {:ok, []}

  defp format_interaction(interaction) do
    %{
      type: interaction.type,
      content: interaction.content,
      timestamp: interaction.inserted_at
    }
  end

  defp build_long_context(query, user_profile, history, project_context, files, max_tokens) do
    # Reserve tokens for response
    available_tokens = max_tokens - 2000

    # Build sections with priority
    sections = build_sections(query, user_profile, history, project_context, files)

    # Optimize to fit within token limit
    optimized_content = optimize_long_context(sections, available_tokens)

    %{
      content: optimized_content,
      metadata: %{
        total_sections: length(sections),
        history_included: length(history),
        files_included: length(files),
        user_profile_included: user_profile != nil
      },
      token_count: estimate_tokens(optimized_content),
      strategy: :long_context,
      sources: build_sources(history, project_context, files)
    }
  end

  defp build_sections(query, user_profile, history, project_context, files) do
    sections = []

    # System context
    sections1 =
      if user_profile do
        [
          {:system, format_system_context(user_profile), :high} | sections
        ]
      else
        sections
      end

    # Conversation history
    sections2 =
      if length(history) > 0 do
        [
          {:history, format_conversation_history(history), :high} | sections1
        ]
      else
        sections1
      end

    # Project knowledge
    sections3 =
      if length(project_context.knowledge) > 0 do
        [
          {:knowledge, format_project_knowledge(project_context.knowledge), :medium} | sections2
        ]
      else
        sections2
      end

    # Code patterns
    sections4 =
      if length(project_context.patterns) > 0 do
        [
          {:patterns, format_code_patterns(project_context.patterns), :medium} | sections3
        ]
      else
        sections3
      end

    # File contents
    sections5 =
      if length(files) > 0 do
        file_sections =
          files
          |> Enum.map(fn file ->
            {:file, format_file_content(file), :high}
          end)

        file_sections ++ sections4
      else
        sections4
      end

    # Query (always included)
    sections6 = [{:query, format_query(query), :critical} | sections5]

    Enum.reverse(sections6)
  end

  defp format_system_context(profile) do
    """
    ## System Context
    User Preferences:
    - Preferred Language: #{profile.preferred_language || "not specified"}
    - Coding Style: #{profile.coding_style || "not specified"}
    - Experience Level: #{profile.experience_level || "not specified"}
    #{if profile.preferences && map_size(profile.preferences) > 0 do
      "- Additional Preferences: #{inspect(profile.preferences)}"
    end}
    """
  end

  defp format_conversation_history(history) do
    """
    ## Conversation History
    #{Enum.map_join(history, "\n\n", fn interaction -> "[#{interaction.type}] #{interaction.content}" end)}
    """
  end

  defp format_project_knowledge(knowledge_items) do
    """
    ## Project Knowledge
    #{Enum.map_join(knowledge_items, "\n\n", fn item -> """
      ### #{item.title}
      Type: #{item.knowledge_type}
      #{item.content}
      """ end)}
    """
  end

  defp format_code_patterns(patterns) do
    """
    ## Common Code Patterns
    #{Enum.map_join(patterns, "\n\n", fn pattern -> """
      ### #{pattern.pattern_name} (#{pattern.language})
      #{pattern.description || ""}
      ```#{pattern.language}
      #{pattern.pattern_code}
      ```
      """ end)}
    """
  end

  defp format_file_content(file) do
    """
    ## File: #{file.path}
    ```#{get_language_from_path(file.path)}
    #{file.content}
    ```
    """
  end

  defp format_query(query) do
    """
    ## Current Query
    #{query}
    """
  end

  defp get_language_from_path(path) do
    case Path.extname(path) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      ".py" -> "python"
      ".rb" -> "ruby"
      ".rs" -> "rust"
      ".go" -> "go"
      _ -> "text"
    end
  end

  defp optimize_long_context(sections, available_tokens) do
    # Group by priority
    critical = Enum.filter(sections, fn {_, _, priority} -> priority == :critical end)
    high = Enum.filter(sections, fn {_, _, priority} -> priority == :high end)
    medium = Enum.filter(sections, fn {_, _, priority} -> priority == :medium end)
    low = Enum.filter(sections, fn {_, _, priority} -> priority == :low end)

    # Always include critical sections
    {included, remaining_tokens} = include_sections(critical, [], available_tokens)

    # Add other priorities in order
    {included, remaining_tokens} = include_sections(high, included, remaining_tokens)
    {included, remaining_tokens} = include_sections(medium, included, remaining_tokens)
    {included, _} = include_sections(low, included, remaining_tokens)

    # Build final content
    included
    |> Enum.reverse()
    |> Enum.map(fn {_, content, _} -> content end)
    |> Enum.join("\n\n")
  end

  defp include_sections(sections, included, remaining_tokens) do
    Enum.reduce(sections, {included, remaining_tokens}, fn {type, content, priority}, {acc, tokens_left} ->
      content_tokens = estimate_tokens(content)

      if content_tokens <= tokens_left do
        {[{type, content, priority} | acc], tokens_left - content_tokens}
      else
        # Try to include truncated version
        # Only truncate if we have reasonable space
        if tokens_left > 500 do
          truncated = truncate_content(content, tokens_left - 100)
          truncated_tokens = estimate_tokens(truncated)
          {[{type, truncated, priority} | acc], tokens_left - truncated_tokens}
        else
          {acc, tokens_left}
        end
      end
    end)
  end

  defp truncate_content(content, max_tokens) do
    max_chars = max_tokens * 4

    if String.length(content) <= max_chars do
      content
    else
      # Smart truncation - try to keep complete sections
      truncated = String.slice(content, 0, max_chars - 20)
      # Find last complete line
      case String.split(truncated, "\n") do
        [_] ->
          truncated <> "\n... (truncated)"

        lines ->
          lines
          |> Enum.drop(-1)
          |> Enum.join("\n")
          |> Kernel.<>("\n... (truncated)")
      end
    end
  end

  defp build_sources(history, project_context, files) do
    sources = []

    sources1 =
      if length(history) > 0 do
        [%{type: :conversation_history, count: length(history)} | sources]
      else
        sources
      end

    sources2 =
      if length(project_context.knowledge) > 0 do
        [%{type: :project_knowledge, count: length(project_context.knowledge)} | sources1]
      else
        sources1
      end

    sources3 =
      if length(project_context.patterns) > 0 do
        [%{type: :code_patterns, count: length(project_context.patterns)} | sources2]
      else
        sources2
      end

    if length(files) > 0 do
      [%{type: :files, paths: Enum.map(files, & &1.path)} | sources3]
    else
      sources3
    end
  end

  defp estimate_tokens(text) do
    div(String.length(text), 4)
  end
end
