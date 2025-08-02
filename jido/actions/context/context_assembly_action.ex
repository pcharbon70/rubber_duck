defmodule RubberDuck.Jido.Actions.Context.ContextAssemblyAction do
  @moduledoc """
  Action for assembling context from multiple sources with intelligent prioritization.

  This action handles the core context building workflow including source querying,
  entry prioritization, optimization, and final assembly. It supports both standard
  and streaming context assembly modes.

  ## Parameters

  - `request_id` - Unique identifier for the context request (auto-generated if nil)
  - `purpose` - Purpose of the context (default: "general") 
  - `max_tokens` - Maximum token limit for the assembled context (default: 4000)
  - `required_sources` - List of source IDs that must be included (default: [])
  - `excluded_sources` - List of source IDs to exclude (default: [])
  - `filters` - Filtering criteria for context entries (default: %{})
  - `preferences` - User preferences for context assembly (default: %{})
  - `streaming` - Whether to enable streaming context delivery (default: false)
  - `priority` - Request priority level (default: :normal)
  - `mode` - Assembly mode: :build, :update, :stream (default: :build)

  ## Returns

  - `{:ok, result}` - Context assembly completed successfully
  - `{:error, reason}` - Context assembly failed

  ## Example

      params = %{
        purpose: "code_generation",
        max_tokens: 6000,
        required_sources: ["memory_source", "code_source"],
        filters: %{"language" => "elixir"},
        streaming: false
      }

      {:ok, result} = ContextAssemblyAction.run(params, context)
  """

  use Jido.Action,
    name: "context_assembly",
    description: "Assemble context from multiple sources with intelligent prioritization",
    schema: [
      request_id: [
        type: :string,
        default: nil,
        doc: "Unique identifier for the context request"
      ],
      purpose: [
        type: :string,
        default: "general",
        doc: "Purpose of the context assembly"
      ],
      max_tokens: [
        type: :integer,
        default: 4000,
        doc: "Maximum token limit for assembled context"
      ],
      required_sources: [
        type: {:list, :string},
        default: [],
        doc: "List of source IDs that must be included"
      ],
      excluded_sources: [
        type: {:list, :string},
        default: [],
        doc: "List of source IDs to exclude"
      ],
      filters: [
        type: :map,
        default: %{},
        doc: "Filtering criteria for context entries"
      ],
      preferences: [
        type: :map,
        default: %{},
        doc: "User preferences for context assembly"
      ],
      streaming: [
        type: :boolean,
        default: false,
        doc: "Whether to enable streaming context delivery"
      ],
      priority: [
        type: :atom,
        default: :normal,
        doc: "Request priority level (low, normal, high, critical)"
      ],
      mode: [
        type: :atom,
        default: :build,
        doc: "Assembly mode: build, update, stream"
      ],
      chunk_size: [
        type: :integer,
        default: 1000,
        doc: "Chunk size for streaming mode"
      ],
      update_data: [
        type: :map,
        default: %{},
        doc: "Update data for update mode"
      ]
    ]

  require Logger

  alias RubberDuck.Context.{ContextEntry, ContextSource, ContextRequest}
  alias Jido.Signal

  @impl true
  def run(params, context) do
    request_id = params.request_id || generate_request_id()
    
    Logger.info("Starting context assembly for request: #{request_id}, mode: #{params.mode}")

    case params.mode do
      :build -> build_context(params, context, request_id)
      :update -> update_context(params, context, request_id)
      :stream -> stream_context(params, context, request_id)
      _ -> {:error, {:invalid_mode, params.mode}}
    end
  end

  # Private functions for different assembly modes

  defp build_context(params, context, request_id) do
    start_time = System.monotonic_time(:millisecond)
    
    # Create context request
    request = build_context_request(params, request_id)
    
    # Check cache first
    case get_cached_context(context, request_id) do
      {:ok, cached_context} ->
        emit_cache_hit_signal(request_id, cached_context)
        {:ok, cached_context}
        
      :not_found ->
        case assemble_new_context(request, context) do
          {:ok, assembled_context} ->
            build_time = System.monotonic_time(:millisecond) - start_time
            
            result = %{
              request_id: request_id,
              purpose: request.purpose,
              entries: assembled_context.entries,
              metadata: Map.merge(assembled_context.metadata, %{
                build_time_ms: build_time,
                cache_miss: true
              }),
              timestamp: DateTime.utc_now()
            }

            emit_context_built_signal(request_id, result, build_time)
            {:ok, result}
            
          {:error, reason} ->
            emit_context_error_signal(request_id, reason)
            {:error, reason}
        end
    end
  end

  defp update_context(params, context, request_id) do
    case get_existing_context(context, request_id) do
      {:ok, existing_context} ->
        updated_context = apply_context_updates(existing_context, params.update_data)
        
        result = %{
          request_id: request_id,
          entries: updated_context.entries,
          metadata: Map.merge(updated_context.metadata, %{
            updated_at: DateTime.utc_now(),
            update_type: :partial
          }),
          timestamp: DateTime.utc_now()
        }

        emit_context_updated_signal(request_id, result)
        {:ok, result}
        
      :not_found ->
        {:error, {:context_not_found, request_id}}
    end
  end

  defp stream_context(params, context, request_id) do
    request = build_context_request(params, request_id)
    
    emit_streaming_started_signal(request_id, request)
    
    case start_streaming_assembly(request, context, params.chunk_size) do
      {:ok, stream_info} ->
        result = %{
          request_id: request_id,
          streaming: true,
          stream_id: stream_info.stream_id,
          estimated_chunks: stream_info.estimated_chunks,
          started_at: DateTime.utc_now()
        }
        
        {:ok, result}
        
      {:error, reason} ->
        emit_context_error_signal(request_id, reason)
        {:error, reason}
    end
  end

  # Context assembly core logic

  defp assemble_new_context(request, context) do
    with {:ok, source_contexts} <- gather_source_contexts(request, context),
         {:ok, prioritized} <- prioritize_context_entries(source_contexts, request, context),
         {:ok, optimized} <- optimize_context(prioritized, request, context) do
      
      final_context = %{
        entries: optimized,
        metadata: build_context_metadata(optimized, source_contexts, request),
        timestamp: DateTime.utc_now()
      }
      
      {:ok, final_context}
    end
  end

  defp gather_source_contexts(request, context) do
    available_sources = get_available_sources(context)
    sources_to_query = determine_sources_to_query(available_sources, request)
    
    # Parallel fetch from sources with timeout
    tasks = Enum.map(sources_to_query, fn source ->
      Task.async(fn ->
        fetch_from_source(source, request, context)
      end)
    end)
    
    source_timeout = get_source_timeout(context)
    results = Task.yield_many(tasks, source_timeout)
    
    # Process results and handle timeouts
    source_contexts = Enum.flat_map(results, fn {task, result} ->
      case result do
        {:ok, {:ok, entries}} ->
          entries
          
        {:ok, {:error, reason}} ->
          Logger.warning("Source fetch error: #{inspect(reason)}")
          []
          
        nil ->
          Task.shutdown(task, :brutal_kill)
          Logger.warning("Source fetch timeout")
          []
      end
    end)
    
    {:ok, source_contexts}
  end

  defp prioritize_context_entries(entries, request, context) do
    priorities = get_priority_weights(context)
    
    scored_entries = Enum.map(entries, fn entry ->
      score = calculate_entry_score(entry, request, priorities)
      {entry, score}
    end)
    
    prioritized = scored_entries
    |> Enum.sort_by(fn {_entry, score} -> score end, :desc)
    |> Enum.map(fn {entry, _score} -> entry end)
    
    {:ok, prioritized}
  end

  defp optimize_context(entries, request, context) do
    optimization_config = get_optimization_config(context)
    
    # Apply optimization pipeline
    optimized = entries
    |> deduplicate_entries(optimization_config.dedup_threshold)
    |> apply_compression_if_needed(optimization_config, request.max_tokens)
    |> apply_summarization_if_needed(optimization_config, request.max_tokens)
    |> truncate_to_token_limit(request.max_tokens)
    
    {:ok, optimized}
  end

  # Source fetching

  defp fetch_from_source(source, request, context) do
    try do
      case source.type do
        :memory -> fetch_memory_context(source, request, context)
        :code_analysis -> fetch_code_context(source, request, context)
        :documentation -> fetch_doc_context(source, request, context)
        :conversation -> fetch_conversation_context(source, request, context)
        :planning -> fetch_planning_context(source, request, context)
        :custom -> fetch_custom_context(source, request, context)
        _ -> {:ok, []}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp fetch_memory_context(source, request, _context) do
    # Emit signal to memory system for context
    signal_data = %{
      purpose: request.purpose,
      filters: request.filters,
      limit: 20,
      source_id: source.id
    }
    
    case emit_signal("query_memories", signal_data) do
      {:ok, memories} when is_list(memories) ->
        entries = Enum.map(memories, &build_memory_entry(&1, source))
        {:ok, entries}
        
      _ ->
        {:ok, []}
    end
  end

  defp fetch_code_context(source, request, _context) do
    signal_data = %{
      purpose: request.purpose,
      file_patterns: request.filters["file_patterns"],
      include_tests: request.preferences["include_tests"] || false,
      source_id: source.id
    }
    
    case emit_signal("get_code_context", signal_data) do
      {:ok, code_data} when is_map(code_data) ->
        entries = build_code_entries(code_data, source)
        {:ok, entries}
        
      _ ->
        {:ok, []}
    end
  end

  defp fetch_doc_context(_source, _request, _context) do
    # Placeholder for documentation context fetching
    {:ok, []}
  end

  defp fetch_conversation_context(_source, _request, _context) do
    # Placeholder for conversation context fetching  
    {:ok, []}
  end

  defp fetch_planning_context(_source, _request, _context) do
    # Placeholder for planning context fetching
    {:ok, []}
  end

  defp fetch_custom_context(source, request, _context) do
    if source.config["transformer"] do
      # Apply custom transformation logic
      {:ok, []}
    else
      {:ok, []}
    end
  end

  # Entry building

  defp build_memory_entry(memory, source) do
    ContextEntry.new(%{
      source: source.id,
      content: memory["content"],
      metadata: Map.merge(memory["metadata"] || %{}, %{
        memory_id: memory["id"],
        memory_type: memory["type"],
        source_type: :memory
      }),
      relevance_score: memory["relevance_score"] || 0.5,
      timestamp: parse_timestamp(memory["accessed_at"])
    })
  end

  defp build_code_entries(code_data, source) do
    Enum.map(code_data["files"] || [], fn file ->
      ContextEntry.new(%{
        source: source.id,
        content: file["content"],
        metadata: %{
          file_path: file["path"],
          language: file["language"],
          type: :code,
          source_type: :code_analysis
        },
        relevance_score: file["relevance"] || 0.7,
        timestamp: parse_timestamp(file["modified_at"])
      })
    end)
  end

  # Optimization functions

  defp deduplicate_entries(entries, threshold) do
    Enum.reduce(entries, [], fn entry, acc ->
      if similar_entry_exists?(entry, acc, threshold) do
        acc
      else
        [entry | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp similar_entry_exists?(entry, entries, threshold) do
    Enum.any?(entries, fn existing ->
      ContextEntry.similar?(entry, existing, threshold)
    end)
  end

  defp apply_compression_if_needed(entries, config, max_tokens) do
    current_tokens = calculate_total_tokens(entries)
    
    if current_tokens > config.compression_threshold do
      Enum.map(entries, fn entry ->
        if entry.size_tokens > config.compression_threshold do
          ContextEntry.compress(entry)
        else
          entry
        end
      end)
    else
      entries
    end
  end

  defp apply_summarization_if_needed(entries, config, max_tokens) do
    current_tokens = calculate_total_tokens(entries)
    
    if current_tokens > max_tokens * 1.5 do
      # Summarize lower-priority entries (second half)
      {high_priority, low_priority} = Enum.split(entries, div(length(entries), 2))
      
      summarized_low = Enum.map(low_priority, fn entry ->
        ContextEntry.summarize(entry, config.summary_ratio)
      end)
      
      high_priority ++ summarized_low
    else
      entries
    end
  end

  defp truncate_to_token_limit(entries, max_tokens) do
    {kept, _} = Enum.reduce(entries, {[], 0}, fn entry, {acc, tokens} ->
      entry_tokens = entry.size_tokens
      
      if tokens + entry_tokens <= max_tokens do
        {[entry | acc], tokens + entry_tokens}
      else
        {acc, tokens}
      end
    end)
    
    Enum.reverse(kept)
  end

  # Scoring and prioritization

  defp calculate_entry_score(entry, request, priorities) do
    relevance = entry.relevance_score * priorities.relevance_weight
    recency = calculate_recency_score(entry.timestamp) * priorities.recency_weight
    importance = calculate_importance_score(entry, request) * priorities.importance_weight
    
    relevance + recency + importance
  end

  defp calculate_recency_score(timestamp) do
    age_minutes = DateTime.diff(DateTime.utc_now(), timestamp, :minute)
    
    cond do
      age_minutes < 5 -> 1.0
      age_minutes < 30 -> 0.8
      age_minutes < 60 -> 0.6
      age_minutes < 1440 -> 0.4  # 24 hours
      true -> 0.2
    end
  end

  defp calculate_importance_score(entry, request) do
    source_importance = Map.get(entry.metadata, :importance, 0.5)
    preference_boost = if matches_preferences?(entry, request.preferences), do: 0.2, else: 0.0
    
    min(source_importance + preference_boost, 1.0)
  end

  defp matches_preferences?(entry, preferences) do
    Enum.any?(preferences, fn {key, value} ->
      Map.get(entry.metadata, String.to_atom(key)) == value
    end)
  end

  # Streaming assembly

  defp start_streaming_assembly(request, context, chunk_size) do
    stream_id = generate_stream_id()
    
    # Start async streaming task
    parent = self()
    
    Task.start(fn ->
      case assemble_new_context(request, context) do
        {:ok, assembled_context} ->
          stream_context_chunks(assembled_context.entries, request.id, stream_id, chunk_size)
          send(parent, {:streaming_complete, stream_id})
          
        {:error, reason} ->
          emit_context_error_signal(request.id, reason)
          send(parent, {:streaming_error, stream_id, reason})
      end
    end)
    
    estimated_chunks = estimate_chunk_count(request, chunk_size)
    
    {:ok, %{
      stream_id: stream_id,
      estimated_chunks: estimated_chunks
    }}
  end

  defp stream_context_chunks(entries, request_id, stream_id, chunk_size) do
    entries
    |> Enum.chunk_every(chunk_size)
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, index} ->
      emit_context_chunk_signal(request_id, stream_id, chunk, index)
      Process.sleep(10)  # Small delay to prevent overwhelming
    end)
    
    emit_streaming_completed_signal(request_id, stream_id)
  end

  # Helper functions

  defp build_context_request(params, request_id) do
    ContextRequest.new(%{
      id: request_id,
      purpose: params.purpose,
      max_tokens: params.max_tokens,
      required_sources: params.required_sources,
      excluded_sources: params.excluded_sources,
      filters: params.filters,
      preferences: params.preferences,
      priority: params.priority,
      streaming: params.streaming
    })
  end

  defp build_context_metadata(entries, source_contexts, request) do
    %{
      total_entries: length(entries),
      total_tokens: calculate_total_tokens(entries),
      sources_used: entries |> Enum.map(& &1.source) |> Enum.uniq(),
      compression_applied: Enum.any?(entries, & &1.compressed),
      oldest_entry: find_oldest_timestamp(entries),
      newest_entry: find_newest_timestamp(entries),
      request_purpose: request.purpose,
      assembly_strategy: "priority_based"
    }
  end

  defp calculate_total_tokens(entries) do
    Enum.sum(Enum.map(entries, & &1.size_tokens))
  end

  defp find_oldest_timestamp(entries) do
    entries
    |> Enum.map(& &1.timestamp)
    |> Enum.min(DateTime, fn -> nil end)
  end

  defp find_newest_timestamp(entries) do
    entries
    |> Enum.map(& &1.timestamp)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp parse_timestamp(nil), do: DateTime.utc_now()
  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp parse_timestamp(%DateTime{} = dt), do: dt
  defp parse_timestamp(_), do: DateTime.utc_now()

  # Context access helpers

  defp get_cached_context(_context, _request_id) do
    # This would access the agent's cache
    # For now, return not found to force assembly
    :not_found
  end

  defp get_existing_context(_context, _request_id) do
    # This would check for existing context to update
    :not_found
  end

  defp get_available_sources(_context) do
    # This would access the agent's registered sources
    # Return empty list for now
    []
  end

  defp get_priority_weights(_context) do
    # Default priority weights
    %{
      relevance_weight: 0.4,
      recency_weight: 0.3,
      importance_weight: 0.3
    }
  end

  defp get_optimization_config(_context) do
    %{
      dedup_threshold: 0.85,
      compression_threshold: 1000,
      summary_ratio: 0.3
    }
  end

  defp get_source_timeout(_context), do: 5000

  defp determine_sources_to_query(sources, request) do
    Enum.filter(sources, fn source ->
      ContextRequest.should_use_source?(request, source.id) and
      ContextSource.available?(source)
    end)
  end

  defp apply_context_updates(context, updates) do
    # Update entries if provided
    updated_entries = Map.get(updates, "entries", context.entries)
    
    # Update metadata
    updated_metadata = Map.merge(context.metadata || %{}, updates["metadata"] || %{})
    
    %{context |
      entries: updated_entries,
      metadata: updated_metadata,
      timestamp: DateTime.utc_now()
    }
  end

  defp estimate_chunk_count(request, chunk_size) do
    # Rough estimation based on max tokens and average entry size
    estimated_entries = div(request.max_tokens, 100)  # Assume 100 tokens per entry
    max(1, div(estimated_entries, chunk_size))
  end

  # Signal emission

  defp emit_signal(type, data) do
    signal = Signal.new!(%{
      type: "context.#{type}",
      source: "context_assembly_action",
      data: data
    })
    
    case Signal.Bus.publish(signal) do
      :ok -> {:ok, :signal_sent}
      {:error, reason} -> 
        Logger.warning("Failed to emit signal #{type}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp emit_cache_hit_signal(request_id, context) do
    emit_signal("cache_hit", %{
      request_id: request_id,
      entries_count: length(context.entries),
      timestamp: DateTime.utc_now()
    })
  end

  defp emit_context_built_signal(request_id, result, build_time) do
    emit_signal("built", %{
      request_id: request_id,
      entries_count: length(result.entries),
      total_tokens: calculate_total_tokens(result.entries),
      build_time_ms: build_time,
      timestamp: DateTime.utc_now()
    })
  end

  defp emit_context_updated_signal(request_id, result) do
    emit_signal("updated", %{
      request_id: request_id,
      entries_count: length(result.entries),
      timestamp: DateTime.utc_now()
    })
  end

  defp emit_context_error_signal(request_id, reason) do
    emit_signal("error", %{
      request_id: request_id,
      error: inspect(reason),
      timestamp: DateTime.utc_now()
    })
  end

  defp emit_streaming_started_signal(request_id, request) do
    emit_signal("streaming.started", %{
      request_id: request_id,
      purpose: request.purpose,
      max_tokens: request.max_tokens,
      timestamp: DateTime.utc_now()
    })
  end

  defp emit_context_chunk_signal(request_id, stream_id, chunk, index) do
    emit_signal("streaming.chunk", %{
      request_id: request_id,
      stream_id: stream_id,
      chunk_index: index,
      chunk_entries: length(chunk),
      chunk_tokens: calculate_total_tokens(chunk),
      timestamp: DateTime.utc_now()
    })
  end

  defp emit_streaming_completed_signal(request_id, stream_id) do
    emit_signal("streaming.completed", %{
      request_id: request_id,
      stream_id: stream_id,
      timestamp: DateTime.utc_now()
    })
  end

  # ID generation

  defp generate_request_id do
    "ctx_req_" <> :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  defp generate_stream_id do
    "ctx_stream_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end