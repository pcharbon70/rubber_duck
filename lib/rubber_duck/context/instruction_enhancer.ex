defmodule RubberDuck.Context.InstructionEnhancer do
  @moduledoc """
  Pipeline for enhancing context building with instruction system integration.
  
  This module provides utilities for enhancing context building strategies
  with instruction-driven features including dynamic system prompts, user
  preferences, and project-specific context rules.
  
  ## Features
  
  - **Strategy Enhancement**: Enhance any context strategy with instructions
  - **Preference Application**: Apply user preferences from RUBBERDUCK.md files
  - **Dynamic System Prompts**: Generate context-aware system prompts
  - **Rule Application**: Apply project-specific context building rules
  - **Performance Optimization**: Cache instruction processing for speed
  
  ## Usage
  
      # Enhance a context strategy with instructions
      enhanced_context = InstructionEnhancer.enhance_strategy_context(
        base_context,
        strategy_name,
        options
      )
      
      # Apply instruction-driven preferences
      updated_options = InstructionEnhancer.apply_instruction_preferences(
        base_options,
        instruction_context
      )
  """

  alias RubberDuck.Instructions.ContextBridge
  require Logger

  @doc """
  Enhances a context strategy's output with instruction-driven features.
  
  This is the main enhancement function that coordinates all instruction-based
  enhancements for context building.
  """
  @spec enhance_strategy_context(map(), atom(), keyword()) :: map()
  def enhance_strategy_context(base_context, strategy_name, options) do
    if Keyword.get(options, :enable_instructions, true) do
      case load_instruction_context(options) do
        {:ok, instruction_context} ->
          base_context
          |> apply_instruction_system_prompt(instruction_context)
          |> apply_instruction_metadata(instruction_context, strategy_name)
          |> apply_context_rules(instruction_context)
          
        {:error, reason} ->
          Logger.debug("Failed to load instruction context: #{inspect(reason)}")
          base_context
      end
    else
      base_context
    end
  end

  @doc """
  Applies instruction-driven preferences to context building options.
  
  Modifies options like max_tokens, strategy selection, etc. based on
  user preferences defined in instruction files.
  """
  @spec apply_instruction_preferences(keyword(), map()) :: keyword()
  def apply_instruction_preferences(base_options, instruction_context) do
    user_preferences = ContextBridge.get_user_preferences(instruction_context)
    
    base_options
    |> apply_max_tokens_preference(user_preferences)
    |> apply_strategy_preference(instruction_context)
    |> apply_retrieval_preferences(user_preferences)
  end

  @doc """
  Determines if instruction enhancement should be applied for given options.
  
  Quick check to avoid unnecessary instruction loading when not beneficial.
  """
  @spec should_enhance?(keyword()) :: boolean()
  def should_enhance?(options) do
    cond do
      not Keyword.get(options, :enable_instructions, true) -> false
      is_nil(Keyword.get(options, :project_path)) -> false
      true -> ContextBridge.has_instructions?(Keyword.get(options, :project_path))
    end
  end

  @doc """
  Generates instruction-aware context variables for template processing.
  
  Creates variables that can be used in instruction templates based on
  the current context building scenario.
  """
  @spec build_context_variables(keyword()) :: map()
  def build_context_variables(options) do
    %{
      "strategy" => Keyword.get(options, :strategy, :unknown) |> Atom.to_string(),
      "query_type" => Keyword.get(options, :query_type, :general) |> Atom.to_string(),
      "max_tokens" => Keyword.get(options, :max_tokens, 4000),
      "user_id" => Keyword.get(options, :user_id, "unknown"),
      "session_id" => Keyword.get(options, :session_id, "none"),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Creates instruction-enhanced options for a context strategy.
  
  Merges base options with instruction-driven preferences and context rules.
  """
  @spec create_enhanced_options(keyword()) :: keyword()
  def create_enhanced_options(base_options) do
    if should_enhance?(base_options) do
      case load_instruction_context(base_options) do
        {:ok, instruction_context} ->
          apply_instruction_preferences(base_options, instruction_context)
        {:error, _reason} ->
          base_options
      end
    else
      base_options
    end
  end

  ## Private Functions

  defp load_instruction_context(options) do
    context_options = %{
      project_path: Keyword.get(options, :project_path),
      user_id: Keyword.get(options, :user_id),
      context_type: determine_context_type(options),
      workspace_path: Keyword.get(options, :workspace_path),
      session_id: Keyword.get(options, :session_id)
    }

    ContextBridge.load_instructions_for_context(context_options)
  end

  defp determine_context_type(options) do
    cond do
      Keyword.has_key?(options, :context_type) -> Keyword.get(options, :context_type)
      Keyword.has_key?(options, :strategy) -> Keyword.get(options, :strategy)
      true -> :general
    end
  end

  defp apply_instruction_system_prompt(context, instruction_context) do
    case ContextBridge.get_system_prompt(instruction_context, build_template_variables(context)) do
      {:ok, nil} -> context
      {:ok, system_prompt} ->
        Map.put(context, :instruction_system_prompt, system_prompt)
      {:error, _reason} -> context
    end
  end

  defp build_template_variables(context) do
    %{
      "content_length" => String.length(Map.get(context, :content, "")),
      "source_count" => length(Map.get(context, :sources, [])),
      "token_count" => Map.get(context, :token_count, 0),
      "strategy" => Map.get(context, :strategy, :unknown) |> Atom.to_string()
    }
  end

  defp apply_instruction_metadata(context, instruction_context, strategy_name) do
    enhanced_metadata = Map.merge(
      Map.get(context, :metadata, %{}),
      %{
        instruction_enhanced: true,
        instruction_files: instruction_context.applied_files,
        instruction_count: length(instruction_context.instructions),
        enhanced_strategy: strategy_name,
        enhancement_timestamp: :os.system_time(:millisecond)
      }
    )

    Map.put(context, :metadata, enhanced_metadata)
  end

  defp apply_context_rules(context, instruction_context) do
    context_rules = ContextBridge.get_context_rules(instruction_context)
    
    # Apply any context rules that affect the final context
    context
    |> apply_content_filters(context_rules)
    |> apply_source_prioritization(context_rules)
  end

  defp apply_content_filters(context, context_rules) do
    include_patterns = Map.get(context_rules, :include_patterns, [])
    exclude_patterns = Map.get(context_rules, :exclude_patterns, [])
    
    if length(include_patterns) > 0 or length(exclude_patterns) > 0 do
      filtered_sources = filter_sources_by_patterns(
        Map.get(context, :sources, []),
        include_patterns,
        exclude_patterns
      )
      Map.put(context, :sources, filtered_sources)
    else
      context
    end
  end

  defp filter_sources_by_patterns(sources, include_patterns, exclude_patterns) do
    sources
    |> Enum.filter(fn source ->
      file_path = get_source_file_path(source)
      
      included = if length(include_patterns) == 0 do
        true
      else
        Enum.any?(include_patterns, &matches_pattern?(file_path, &1))
      end
      
      excluded = Enum.any?(exclude_patterns, &matches_pattern?(file_path, &1))
      
      included and not excluded
    end)
  end

  defp get_source_file_path(source) do
    cond do
      Map.has_key?(source, :file_path) -> source.file_path
      Map.has_key?(source, :path) -> source.path
      Map.has_key?(source, :metadata) -> Map.get(source.metadata, :file_path, "")
      true -> ""
    end
  end

  defp matches_pattern?(file_path, pattern) do
    # Simple glob-style pattern matching
    cond do
      String.starts_with?(pattern, "*") ->
        suffix = String.slice(pattern, 1..-1)
        String.ends_with?(file_path, suffix)
        
      String.ends_with?(pattern, "*") ->
        prefix = String.slice(pattern, 0..-2)
        String.starts_with?(file_path, prefix)
        
      true ->
        file_path == pattern
    end
  end

  defp apply_source_prioritization(context, context_rules) do
    retrieval_focus = Map.get(context_rules, :retrieval_focus, [])
    
    if length(retrieval_focus) > 0 do
      prioritized_sources = prioritize_sources_by_focus(
        Map.get(context, :sources, []),
        retrieval_focus
      )
      Map.put(context, :sources, prioritized_sources)
    else
      context
    end
  end

  defp prioritize_sources_by_focus(sources, focus_terms) do
    sources
    |> Enum.map(fn source ->
      priority_boost = calculate_focus_priority(source, focus_terms)
      Map.put(source, :focus_priority, priority_boost)
    end)
    |> Enum.sort_by(&Map.get(&1, :focus_priority, 0), :desc)
  end

  defp calculate_focus_priority(source, focus_terms) do
    content = Map.get(source, :content, "")
    
    focus_terms
    |> Enum.reduce(0, fn term, acc ->
      if String.contains?(String.downcase(content), String.downcase(term)) do
        acc + 1
      else
        acc
      end
    end)
  end

  defp apply_max_tokens_preference(options, user_preferences) do
    case Map.get(user_preferences, "max_context_size") do
      nil -> options
      max_tokens when is_integer(max_tokens) ->
        Keyword.put(options, :max_tokens, max_tokens)
      _ -> options
    end
  end

  defp apply_strategy_preference(options, instruction_context) do
    case ContextBridge.get_preferred_strategy(instruction_context, nil) do
      nil -> options
      strategy when is_atom(strategy) ->
        Keyword.put(options, :preferred_strategy, strategy)
      strategy when is_binary(strategy) ->
        Keyword.put(options, :preferred_strategy, String.to_atom(strategy))
      _ -> options
    end
  end

  defp apply_retrieval_preferences(options, user_preferences) do
    # Apply retrieval-specific preferences
    retrieval_limit = Map.get(user_preferences, "retrieval_limit")
    
    if retrieval_limit do
      Keyword.put(options, :retrieval_limit, retrieval_limit)
    else
      options
    end
  end
end