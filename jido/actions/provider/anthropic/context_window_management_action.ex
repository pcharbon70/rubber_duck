defmodule RubberDuck.Jido.Actions.Provider.Anthropic.ContextWindowManagementAction do
  @moduledoc """
  Action for managing Anthropic Claude's context window efficiently.

  This action handles context window optimization for Claude models, including
  context compression, message pruning, and intelligent context management to
  work within token limits while maintaining conversation coherence.

  ## Parameters

  - `operation` - Context operation to perform (required: :optimize, :compress, :prune, :analyze)
  - `messages` - List of conversation messages to manage (required)
  - `model` - Claude model being used (default: "claude-3-opus")
  - `target_tokens` - Target token count after optimization (default: 100000)
  - `preserve_recent` - Number of recent messages to always preserve (default: 5)
  - `compression_strategy` - Strategy for context compression (default: :intelligent)
  - `include_system_prompt` - Whether to include system prompt in calculations (default: true)

  ## Returns

  - `{:ok, result}` - Context management completed successfully
  - `{:error, reason}` - Context management failed

  ## Example

      params = %{
        operation: :optimize,
        messages: conversation_messages,
        model: "claude-3-opus",
        target_tokens: 80000,
        compression_strategy: :aggressive
      }

      {:ok, result} = ContextWindowManagementAction.run(params, context)
  """

  use Jido.Action,
    name: "context_window_management",
    description: "Manage Anthropic Claude context window efficiently",
    schema: [
      operation: [
        type: :atom,
        required: true,
        doc: "Context operation (optimize, compress, prune, analyze, split)"
      ],
      messages: [
        type: :list,
        required: true,
        doc: "List of conversation messages to manage"
      ],
      model: [
        type: :string,
        default: "claude-3-opus",
        doc: "Claude model being used"
      ],
      target_tokens: [
        type: :integer,
        default: 100000,
        doc: "Target token count after optimization"
      ],
      preserve_recent: [
        type: :integer,
        default: 5,
        doc: "Number of recent messages to always preserve"
      ],
      compression_strategy: [
        type: :atom,
        default: :intelligent,
        doc: "Compression strategy (intelligent, aggressive, conservative, semantic)"
      ],
      include_system_prompt: [
        type: :boolean,
        default: true,
        doc: "Whether to include system prompt in calculations"
      ],
      preserve_context_markers: [
        type: :boolean,
        default: true,
        doc: "Whether to preserve context boundary markers"
      ],
      summarize_removed: [
        type: :boolean,
        default: true,
        doc: "Whether to create summaries of removed content"
      ]
    ]

  require Logger

  @model_limits %{
    "claude-3-opus" => 200_000,
    "claude-3-sonnet" => 200_000,
    "claude-3-haiku" => 200_000,
    "claude-3-5-sonnet" => 200_000,
    "claude-3-5-haiku" => 200_000
  }

  @compression_strategies [:intelligent, :aggressive, :conservative, :semantic, :chronological]
  @tokens_per_message_overhead 10
  @summary_compression_ratio 0.1

  @impl true
  def run(params, context) do
    Logger.info("Managing context window: #{params.operation} for #{params.model}")

    with {:ok, validated_params} <- validate_context_parameters(params),
         {:ok, analyzed_context} <- analyze_current_context(validated_params),
         {:ok, result} <- execute_context_operation(validated_params, analyzed_context, context) do
      
      emit_context_managed_signal(params.operation, result)
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Context window management failed: #{inspect(reason)}")
        emit_context_error_signal(params.operation, reason)
        {:error, reason}
    end
  end

  # Parameter validation

  defp validate_context_parameters(params) do
    with {:ok, _} <- validate_operation(params.operation),
         {:ok, _} <- validate_model(params.model),
         {:ok, _} <- validate_compression_strategy(params.compression_strategy),
         {:ok, _} <- validate_messages(params.messages),
         {:ok, _} <- validate_target_tokens(params.target_tokens, params.model) do
      
      {:ok, params}
    else
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  defp validate_operation(operation) do
    valid_operations = [:optimize, :compress, :prune, :analyze, :split]
    if operation in valid_operations do
      {:ok, operation}
    else
      {:error, {:invalid_operation, operation, valid_operations}}
    end
  end

  defp validate_model(model) do
    if Map.has_key?(@model_limits, model) do
      {:ok, model}
    else
      {:error, {:unsupported_model, model, Map.keys(@model_limits)}}
    end
  end

  defp validate_compression_strategy(strategy) do
    if strategy in @compression_strategies do
      {:ok, strategy}
    else
      {:error, {:invalid_compression_strategy, strategy, @compression_strategies}}
    end
  end

  defp validate_messages(messages) when is_list(messages) do
    if length(messages) > 0 do
      {:ok, messages}
    else
      {:error, :empty_messages_list}
    end
  end
  defp validate_messages(_), do: {:error, :invalid_messages_format}

  defp validate_target_tokens(target_tokens, model) do
    model_limit = Map.get(@model_limits, model)
    
    cond do
      target_tokens <= 0 ->
        {:error, :invalid_target_tokens}
      
      target_tokens > model_limit ->
        {:error, {:target_exceeds_model_limit, target_tokens, model_limit}}
      
      true ->
        {:ok, target_tokens}
    end
  end

  # Context analysis

  defp analyze_current_context(params) do
    messages = params.messages
    model = params.model
    
    analysis = %{
      total_messages: length(messages),
      estimated_tokens: estimate_total_tokens(messages),
      model_limit: Map.get(@model_limits, model),
      system_prompt_tokens: estimate_system_prompt_tokens(messages),
      message_breakdown: analyze_message_breakdown(messages),
      optimization_potential: calculate_optimization_potential(messages, params.target_tokens),
      context_coherence: assess_context_coherence(messages)
    }
    
    {:ok, analysis}
  end

  defp estimate_total_tokens(messages) do
    Enum.reduce(messages, 0, fn message, acc ->
      acc + estimate_message_tokens(message) + @tokens_per_message_overhead
    end)
  end

  defp estimate_message_tokens(message) do
    content = get_message_content(message)
    # Rough estimation: ~4 characters per token for English text
    byte_size(content) |> div(4) |> max(1)
  end

  defp get_message_content(%{content: content}) when is_binary(content), do: content
  defp get_message_content(%{"content" => content}) when is_binary(content), do: content
  defp get_message_content(%{content: content}) when is_list(content) do
    content
    |> Enum.map(fn
      %{text: text} -> text
      %{"text" => text} -> text
      text when is_binary(text) -> text
      _ -> ""
    end)
    |> Enum.join(" ")
  end
  defp get_message_content(_), do: ""

  defp estimate_system_prompt_tokens(messages) do
    system_messages = Enum.filter(messages, fn message ->
      get_message_role(message) == "system"
    end)
    
    Enum.reduce(system_messages, 0, &(estimate_message_tokens(&1) + &2))
  end

  defp get_message_role(%{role: role}), do: role
  defp get_message_role(%{"role" => role}), do: role
  defp get_message_role(_), do: "user"

  defp analyze_message_breakdown(messages) do
    messages
    |> Enum.with_index()
    |> Enum.map(fn {message, index} ->
      %{
        index: index,
        role: get_message_role(message),
        tokens: estimate_message_tokens(message),
        timestamp: get_message_timestamp(message),
        importance: assess_message_importance(message, index, length(messages))
      }
    end)
  end

  defp get_message_timestamp(message) do
    case message do
      %{timestamp: timestamp} -> timestamp
      %{"timestamp" => timestamp} -> timestamp
      _ -> DateTime.utc_now()
    end
  end

  defp assess_message_importance(message, index, total_messages) do
    role = get_message_role(message)
    content = get_message_content(message)
    tokens = estimate_message_tokens(message)
    
    base_score = case role do
      "system" -> 1.0
      "assistant" -> 0.8
      "user" -> 0.6
      _ -> 0.4
    end
    
    # Recent messages are more important
    recency_factor = (total_messages - index) / total_messages
    
    # Longer messages might be more important
    length_factor = min(tokens / 100, 1.0)
    
    # Special keywords increase importance
    keyword_factor = if String.contains?(String.downcase(content), ["important", "remember", "context", "summary"]) do
      1.2
    else
      1.0
    end
    
    base_score * (0.4 + 0.4 * recency_factor + 0.2 * length_factor) * keyword_factor
  end

  defp calculate_optimization_potential(messages, target_tokens) do
    current_tokens = estimate_total_tokens(messages)
    
    if current_tokens <= target_tokens do
      %{needs_optimization: false, potential_savings: 0, reduction_needed: 0}
    else
      reduction_needed = current_tokens - target_tokens
      potential_savings = calculate_potential_savings(messages)
      
      %{
        needs_optimization: true,
        potential_savings: potential_savings,
        reduction_needed: reduction_needed,
        optimization_feasible: potential_savings >= reduction_needed
      }
    end
  end

  defp calculate_potential_savings(messages) do
    # Estimate how many tokens could potentially be saved through various methods
    total_tokens = estimate_total_tokens(messages)
    
    # Conservative estimate: can save 20-40% through intelligent compression
    round(total_tokens * 0.3)
  end

  defp assess_context_coherence(messages) do
    # Simple coherence assessment based on conversation flow
    topic_changes = count_topic_changes(messages)
    role_transitions = count_role_transitions(messages)
    
    %{
      topic_changes: topic_changes,
      role_transitions: role_transitions,
      coherence_score: calculate_coherence_score(topic_changes, role_transitions, length(messages))
    }
  end

  defp count_topic_changes(messages) do
    # Simple heuristic: count messages with significantly different vocabulary
    # In a real implementation, this would use more sophisticated NLP
    length(messages) |> div(4)
  end

  defp count_role_transitions(messages) do
    messages
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.count(fn [msg1, msg2] ->
      get_message_role(msg1) != get_message_role(msg2)
    end)
  end

  defp calculate_coherence_score(topic_changes, role_transitions, total_messages) do
    if total_messages <= 1 do
      1.0
    else
      # Higher scores for more coherent conversations
      topic_factor = 1.0 - (topic_changes / total_messages)
      transition_factor = 1.0 - (role_transitions / (total_messages - 1))
      (topic_factor + transition_factor) / 2
    end
  end

  # Context operations

  defp execute_context_operation(params, analysis, context) do
    case params.operation do
      :optimize -> optimize_context(params, analysis, context)
      :compress -> compress_context(params, analysis, context)
      :prune -> prune_context(params, analysis, context)
      :analyze -> analyze_context_only(params, analysis, context)
      :split -> split_context(params, analysis, context)
    end
  end

  # Context optimization

  defp optimize_context(params, analysis, _context) do
    if analysis.optimization_potential.needs_optimization do
      optimized_messages = apply_optimization_strategy(params, analysis)
      
      result = %{
        operation: :optimize,
        original_messages: length(params.messages),
        optimized_messages: length(optimized_messages),
        original_tokens: analysis.estimated_tokens,
        optimized_tokens: estimate_total_tokens(optimized_messages),
        tokens_saved: analysis.estimated_tokens - estimate_total_tokens(optimized_messages),
        messages: optimized_messages,
        optimization_summary: create_optimization_summary(params, analysis, optimized_messages),
        metadata: %{
          strategy_used: params.compression_strategy,
          coherence_preserved: true,
          optimization_timestamp: DateTime.utc_now()
        }
      }
      
      {:ok, result}
    else
      {:ok, %{
        operation: :optimize,
        optimization_needed: false,
        current_tokens: analysis.estimated_tokens,
        target_tokens: params.target_tokens,
        messages: params.messages
      }}
    end
  end

  defp apply_optimization_strategy(params, analysis) do
    strategy = params.compression_strategy
    messages = params.messages
    
    case strategy do
      :intelligent -> apply_intelligent_optimization(params, analysis)
      :aggressive -> apply_aggressive_optimization(params, analysis)
      :conservative -> apply_conservative_optimization(params, analysis)
      :semantic -> apply_semantic_optimization(params, analysis)
      :chronological -> apply_chronological_optimization(params, analysis)
    end
  end

  defp apply_intelligent_optimization(params, analysis) do
    messages_with_importance = analysis.message_breakdown
    target_tokens = params.target_tokens
    preserve_recent = params.preserve_recent
    
    # Always preserve recent messages
    recent_messages = Enum.take(params.messages, -preserve_recent)
    older_messages = Enum.drop(params.messages, -preserve_recent)
    
    # Sort older messages by importance
    older_with_importance = older_messages
    |> Enum.with_index()
    |> Enum.map(fn {message, index} ->
      importance_data = Enum.at(messages_with_importance, index)
      {message, importance_data.importance}
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    
    # Select messages to keep based on token budget
    recent_tokens = estimate_total_tokens(recent_messages)
    available_tokens = target_tokens - recent_tokens
    
    selected_older = select_messages_by_token_budget(older_with_importance, available_tokens)
    
    # Combine and sort chronologically
    all_selected = selected_older ++ recent_messages
    
    # Sort by original position to maintain conversation flow
    Enum.sort_by(all_selected, fn message ->
      Enum.find_index(params.messages, &(&1 == message))
    end)
  end

  defp apply_aggressive_optimization(params, analysis) do
    # Keep only the most recent messages and highest importance messages
    preserve_recent = params.preserve_recent
    target_reduction = analysis.optimization_potential.reduction_needed
    
    recent_messages = Enum.take(params.messages, -preserve_recent)
    system_messages = Enum.filter(params.messages, fn msg ->
      get_message_role(msg) == "system"
    end)
    
    # Aggressive: keep only system + recent messages if within budget
    candidate_messages = system_messages ++ recent_messages
    candidate_tokens = estimate_total_tokens(candidate_messages)
    
    if candidate_tokens <= params.target_tokens do
      Enum.uniq(candidate_messages)
    else
      # Even more aggressive: summarize everything except most recent
      most_recent = Enum.take(params.messages, -2)
      system_messages ++ most_recent
    end
  end

  defp apply_conservative_optimization(params, analysis) do
    # Only remove messages with very low importance, preserve most context
    messages_with_importance = analysis.message_breakdown
    low_importance_threshold = 0.3
    
    messages_to_keep = params.messages
    |> Enum.with_index()
    |> Enum.filter(fn {_message, index} ->
      importance_data = Enum.at(messages_with_importance, index)
      importance_data.importance >= low_importance_threshold
    end)
    |> Enum.map(&elem(&1, 0))
    
    # If still too many tokens, compress content instead of removing messages
    if estimate_total_tokens(messages_to_keep) > params.target_tokens do
      compress_message_content(messages_to_keep, params.target_tokens)
    else
      messages_to_keep
    end
  end

  defp apply_semantic_optimization(params, _analysis) do
    # Group messages by semantic similarity and keep representatives
    # For now, implement a simplified version
    messages = params.messages
    preserve_recent = params.preserve_recent
    
    recent_messages = Enum.take(messages, -preserve_recent)
    older_messages = Enum.drop(messages, -preserve_recent)
    
    # Simple semantic grouping by role and rough content similarity
    grouped_messages = group_messages_semantically(older_messages)
    representative_messages = select_representative_messages(grouped_messages)
    
    representative_messages ++ recent_messages
  end

  defp apply_chronological_optimization(params, _analysis) do
    # Simple time-based approach: keep every nth message to maintain timeline
    total_messages = length(params.messages)
    target_messages = estimate_target_message_count(params.target_tokens)
    
    if total_messages <= target_messages do
      params.messages
    else
      step = total_messages / target_messages
      
      params.messages
      |> Enum.with_index()
      |> Enum.filter(fn {_message, index} ->
        rem(round(index / step), 1) == 0
      end)
      |> Enum.map(&elem(&1, 0))
    end
  end

  # Helper functions for optimization

  defp select_messages_by_token_budget(messages_with_importance, token_budget) do
    {selected, _remaining_budget} = Enum.reduce(messages_with_importance, {[], token_budget}, fn {message, _importance}, {acc, budget} ->
      message_tokens = estimate_message_tokens(message)
      
      if message_tokens <= budget do
        {[message | acc], budget - message_tokens}
      else
        {acc, budget}
      end
    end)
    
    Enum.reverse(selected)
  end

  defp compress_message_content(messages, target_tokens) do
    current_tokens = estimate_total_tokens(messages)
    compression_ratio = target_tokens / current_tokens
    
    Enum.map(messages, fn message ->
      compress_single_message(message, compression_ratio)
    end)
  end

  defp compress_single_message(message, compression_ratio) do
    content = get_message_content(message)
    
    if compression_ratio < 1.0 do
      # Simple compression: truncate to ratio of original length
      target_length = round(byte_size(content) * compression_ratio)
      compressed_content = String.slice(content, 0, target_length) <> "..."
      
      Map.merge(message, %{content: compressed_content})
    else
      message
    end
  end

  defp group_messages_semantically(messages) do
    # Simple grouping by role and rough content patterns
    Enum.group_by(messages, fn message ->
      role = get_message_role(message)
      content = get_message_content(message)
      content_type = classify_content_type(content)
      
      {role, content_type}
    end)
  end

  defp classify_content_type(content) do
    cond do
      String.contains?(content, ["?", "how", "what", "why"]) -> :question
      String.contains?(content, ["error", "exception", "fail"]) -> :error
      String.contains?(content, ["summary", "conclusion"]) -> :summary
      String.length(content) > 500 -> :long_form
      true -> :general
    end
  end

  defp select_representative_messages(grouped_messages) do
    grouped_messages
    |> Enum.flat_map(fn {_group_key, group_messages} ->
      # Select the most important message from each group
      case group_messages do
        [] -> []
        [single] -> [single]
        multiple -> [select_most_representative(multiple)]
      end
    end)
  end

  defp select_most_representative(messages) do
    # Select the message with median length as representative
    sorted_by_length = Enum.sort_by(messages, &byte_size(get_message_content(&1)))
    median_index = length(sorted_by_length) |> div(2)
    Enum.at(sorted_by_length, median_index)
  end

  defp estimate_target_message_count(target_tokens) do
    # Rough estimate: average message is ~100 tokens
    max(target_tokens |> div(100), 1)
  end

  # Context compression

  defp compress_context(params, analysis, _context) do
    compressed_messages = apply_compression_techniques(params.messages, params.compression_strategy)
    
    result = %{
      operation: :compress,
      original_messages: length(params.messages),
      compressed_messages: length(compressed_messages),
      original_tokens: analysis.estimated_tokens,
      compressed_tokens: estimate_total_tokens(compressed_messages),
      compression_ratio: estimate_total_tokens(compressed_messages) / analysis.estimated_tokens,
      messages: compressed_messages,
      compression_summary: create_compression_summary(params, analysis, compressed_messages)
    }
    
    {:ok, result}
  end

  defp apply_compression_techniques(messages, strategy) do
    case strategy do
      :intelligent -> intelligent_compress(messages)
      :aggressive -> aggressive_compress(messages)
      :conservative -> conservative_compress(messages)
      _ -> semantic_compress(messages)
    end
  end

  defp intelligent_compress(messages) do
    Enum.map(messages, fn message ->
      content = get_message_content(message)
      compressed_content = compress_text_intelligently(content)
      Map.merge(message, %{content: compressed_content})
    end)
  end

  defp aggressive_compress(messages) do
    Enum.map(messages, fn message ->
      content = get_message_content(message)
      # Aggressive: keep only first and last sentences
      compressed_content = extract_key_sentences(content, 2)
      Map.merge(message, %{content: compressed_content})
    end)
  end

  defp conservative_compress(messages) do
    # Only compress very long messages
    Enum.map(messages, fn message ->
      content = get_message_content(message)
      
      if byte_size(content) > 1000 do
        compressed_content = compress_text_intelligently(content)
        Map.merge(message, %{content: compressed_content})
      else
        message
      end
    end)
  end

  defp semantic_compress(messages) do
    # Group similar messages and create summaries
    grouped = group_messages_semantically(messages)
    
    Enum.flat_map(grouped, fn {_group_key, group_messages} ->
      if length(group_messages) > 3 do
        # Create a summary message for large groups
        summary_content = create_group_summary(group_messages)
        [%{
          role: "assistant",
          content: summary_content,
          metadata: %{type: :summary, original_count: length(group_messages)}
        }]
      else
        group_messages
      end
    end)
  end

  defp compress_text_intelligently(text) do
    # Simple intelligent compression: remove redundant words, keep key information
    text
    |> String.replace(~r/\s+/, " ")  # Collapse whitespace
    |> String.replace(~r/\b(very|really|quite|somewhat|rather)\s+/, "")  # Remove intensity modifiers
    |> String.replace(~r/\b(I think|I believe|it seems|probably)\s+/, "")  # Remove uncertainty phrases
    |> String.trim()
  end

  defp extract_key_sentences(text, count) do
    sentences = String.split(text, ~r/[.!?]+/, trim: true)
    
    case length(sentences) do
      0 -> text
      1 -> text
      n when n <= count -> text
      _ ->
        first_sentences = Enum.take(sentences, count - 1)
        last_sentence = List.last(sentences)
        Enum.join(first_sentences ++ [last_sentence], ". ") <> "."
    end
  end

  defp create_group_summary(messages) do
    topics = Enum.map(messages, fn message ->
      content = get_message_content(message)
      role = get_message_role(message)
      "#{role}: #{String.slice(content, 0, 100)}..."
    end)
    
    "Summary of #{length(messages)} messages: " <> Enum.join(topics, "; ")
  end

  # Context pruning

  defp prune_context(params, analysis, _context) do
    pruned_messages = apply_pruning_strategy(params, analysis)
    
    result = %{
      operation: :prune,
      original_messages: length(params.messages),
      pruned_messages: length(pruned_messages),
      original_tokens: analysis.estimated_tokens,
      pruned_tokens: estimate_total_tokens(pruned_messages),
      messages_removed: length(params.messages) - length(pruned_messages),
      messages: pruned_messages,
      pruning_summary: create_pruning_summary(params, analysis, pruned_messages)
    }
    
    {:ok, result}
  end

  defp apply_pruning_strategy(params, analysis) do
    messages_with_importance = analysis.message_breakdown
    preserve_recent = params.preserve_recent
    target_tokens = params.target_tokens
    
    # Always preserve recent messages and system messages
    recent_messages = Enum.take(params.messages, -preserve_recent)
    system_messages = Enum.filter(params.messages, fn msg ->
      get_message_role(msg) == "system"
    end)
    
    preserved_messages = Enum.uniq(system_messages ++ recent_messages)
    preserved_tokens = estimate_total_tokens(preserved_messages)
    
    if preserved_tokens >= target_tokens do
      # Even preserved messages exceed target, keep only most recent
      Enum.take(params.messages, -max(1, preserve_recent - 1))
    else
      # Add other messages by importance until target reached
      remaining_budget = target_tokens - preserved_tokens
      other_messages = params.messages -- preserved_messages
      
      other_with_importance = other_messages
      |> Enum.with_index()
      |> Enum.map(fn {message, index} ->
        # Find the importance score from analysis
        original_index = Enum.find_index(params.messages, &(&1 == message))
        importance_data = Enum.at(messages_with_importance, original_index)
        {message, importance_data.importance}
      end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      
      selected_others = select_messages_by_token_budget(other_with_importance, remaining_budget)
      
      # Maintain chronological order
      all_selected = preserved_messages ++ selected_others
      Enum.sort_by(all_selected, fn message ->
        Enum.find_index(params.messages, &(&1 == message))
      end)
    end
  end

  # Context analysis only

  defp analyze_context_only(_params, analysis, _context) do
    result = %{
      operation: :analyze,
      analysis: analysis,
      recommendations: generate_context_recommendations(analysis),
      optimization_strategies: suggest_optimization_strategies(analysis)
    }
    
    {:ok, result}
  end

  defp generate_context_recommendations(analysis) do
    recommendations = []
    
    recommendations = if analysis.optimization_potential.needs_optimization do
      strategy = if analysis.optimization_potential.optimization_feasible do
        "Apply intelligent optimization to reduce tokens by #{analysis.optimization_potential.reduction_needed}"
      else
        "Consider splitting conversation or using more aggressive compression"
      end
      [strategy | recommendations]
    else
      recommendations
    end
    
    recommendations = if analysis.context_coherence.coherence_score < 0.5 do
      ["Consider reorganizing conversation for better coherence" | recommendations]
    else
      recommendations
    end
    
    recommendations = if analysis.estimated_tokens > analysis.model_limit * 0.8 do
      ["Approaching model limit, proactive optimization recommended" | recommendations]
    else
      recommendations
    end
    
    Enum.reverse(recommendations)
  end

  defp suggest_optimization_strategies(analysis) do
    strategies = []
    
    strategies = if analysis.total_messages > 20 do
      [:intelligent, :semantic | strategies]
    else
      strategies
    end
    
    strategies = if analysis.context_coherence.topic_changes > analysis.total_messages / 3 do
      [:semantic, :chronological | strategies]
    else
      strategies
    end
    
    strategies = if analysis.estimated_tokens > analysis.model_limit * 0.9 do
      [:aggressive | strategies]
    else
      [:conservative | strategies]
    end
    
    Enum.uniq(strategies)
  end

  # Context splitting

  defp split_context(params, analysis, _context) do
    splits = create_context_splits(params, analysis)
    
    result = %{
      operation: :split,
      original_messages: length(params.messages),
      splits_created: length(splits),
      splits: splits,
      splitting_summary: create_splitting_summary(params, analysis, splits)
    }
    
    {:ok, result}
  end

  defp create_context_splits(params, analysis) do
    target_tokens = params.target_tokens
    messages = params.messages
    
    # Calculate tokens per split
    total_tokens = analysis.estimated_tokens
    splits_needed = ceil(total_tokens / target_tokens)
    
    if splits_needed <= 1 do
      [%{messages: messages, tokens: total_tokens, split_index: 1}]
    else
      # Create splits with overlap for context continuity
      overlap_messages = 2
      messages_per_split = length(messages) / splits_needed |> ceil()
      
      0..(splits_needed - 1)
      |> Enum.map(fn split_index ->
        start_index = max(0, split_index * messages_per_split - overlap_messages)
        end_index = min(length(messages), (split_index + 1) * messages_per_split)
        
        split_messages = Enum.slice(messages, start_index, end_index - start_index)
        
        %{
          messages: split_messages,
          tokens: estimate_total_tokens(split_messages),
          split_index: split_index + 1,
          start_message: start_index,
          end_message: end_index - 1,
          has_overlap: start_index > 0
        }
      end)
    end
  end

  # Summary generation

  defp create_optimization_summary(params, analysis, optimized_messages) do
    %{
      strategy_used: params.compression_strategy,
      original_stats: %{
        messages: length(params.messages),
        tokens: analysis.estimated_tokens
      },
      optimized_stats: %{
        messages: length(optimized_messages),
        tokens: estimate_total_tokens(optimized_messages)
      },
      savings: %{
        messages_removed: length(params.messages) - length(optimized_messages),
        tokens_saved: analysis.estimated_tokens - estimate_total_tokens(optimized_messages),
        compression_ratio: estimate_total_tokens(optimized_messages) / analysis.estimated_tokens
      },
      preservation: %{
        recent_messages_preserved: params.preserve_recent,
        system_prompts_preserved: true,
        context_markers_preserved: params.preserve_context_markers
      }
    }
  end

  defp create_compression_summary(params, analysis, compressed_messages) do
    %{
      compression_strategy: params.compression_strategy,
      original_tokens: analysis.estimated_tokens,
      compressed_tokens: estimate_total_tokens(compressed_messages),
      compression_ratio: estimate_total_tokens(compressed_messages) / analysis.estimated_tokens,
      messages_affected: count_modified_messages(params.messages, compressed_messages),
      average_compression_per_message: calculate_average_compression(params.messages, compressed_messages)
    }
  end

  defp create_pruning_summary(params, analysis, pruned_messages) do
    %{
      pruning_strategy: "importance_based",
      messages_removed: length(params.messages) - length(pruned_messages),
      tokens_removed: analysis.estimated_tokens - estimate_total_tokens(pruned_messages),
      preserved_recent: params.preserve_recent,
      removal_criteria: "Low importance score and not in recent/system messages"
    }
  end

  defp create_splitting_summary(params, analysis, splits) do
    %{
      total_splits: length(splits),
      original_tokens: analysis.estimated_tokens,
      average_tokens_per_split: Enum.reduce(splits, 0, &(&1.tokens + &2)) / length(splits),
      overlap_strategy: "2 message overlap between splits",
      target_tokens_per_split: params.target_tokens
    }
  end

  # Helper functions

  defp count_modified_messages(original_messages, modified_messages) do
    original_contents = Enum.map(original_messages, &get_message_content/1)
    modified_contents = Enum.map(modified_messages, &get_message_content/1)
    
    Enum.zip(original_contents, modified_contents)
    |> Enum.count(fn {orig, mod} -> orig != mod end)
  end

  defp calculate_average_compression(original_messages, compressed_messages) do
    if length(original_messages) == 0 or length(compressed_messages) == 0 do
      0.0
    else
      original_total = Enum.reduce(original_messages, 0, &(byte_size(get_message_content(&1)) + &2))
      compressed_total = Enum.reduce(compressed_messages, 0, &(byte_size(get_message_content(&1)) + &2))
      
      if original_total > 0 do
        compressed_total / original_total
      else
        1.0
      end
    end
  end

  # Signal emission

  defp emit_context_managed_signal(operation, result) do
    # TODO: Emit actual signal
    Logger.debug("Context #{operation} completed: #{inspect(Map.keys(result))}")
  end

  defp emit_context_error_signal(operation, reason) do
    # TODO: Emit actual signal
    Logger.debug("Context #{operation} failed: #{inspect(reason)}")
  end
end