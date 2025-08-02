defmodule RubberDuck.Agents.ContextBuilderAgent do
  @moduledoc """
  Context Builder Agent for intelligent context aggregation and optimization.
  
  This agent manages the collection, prioritization, and optimization of context
  from multiple sources to provide relevant information for LLM interactions.
  It ensures efficient token usage while maximizing context relevance.
  
  ## Responsibilities
  
  - Aggregate context from multiple sources
  - Prioritize content based on relevance and importance
  - Optimize context size through compression and deduplication
  - Provide streaming context updates
  - Track context quality metrics
  
  ## State Structure
  
  ```elixir
  %{
    sources: %{source_id => source_config},
    cache: %{request_id => built_context},
    active_builds: %{request_id => build_state},
    priorities: %{
      relevance_weight: float,
      recency_weight: float,
      importance_weight: float
    },
    metrics: %{
      builds_completed: integer,
      avg_build_time_ms: float,
      cache_hit_rate: float,
      avg_compression_ratio: float
    },
    config: %{
      max_cache_size: integer,
      default_max_tokens: integer,
      compression_threshold: integer
    }
  }
  ```
  """

  use RubberDuck.Agents.BaseAgent,
    name: "context_builder",
    description: "Manages context aggregation, prioritization, and optimization for LLM interactions",
    category: "memory"

  alias RubberDuck.Context.{ContextEntry, ContextSource, ContextRequest}
  require Logger

  @default_config %{
    max_cache_size: 100,
    cache_ttl: 300_000,  # 5 minutes
    default_max_tokens: 4000,
    compression_threshold: 1000,
    parallel_source_limit: 10,
    source_timeout: 5000,
    dedup_threshold: 0.85,
    summary_ratio: 0.3
  }

  @default_priorities %{
    relevance_weight: 0.4,
    recency_weight: 0.3,
    importance_weight: 0.3
  }

  @source_types [:memory, :code_analysis, :documentation, :conversation, :planning, :custom]

  ## Initialization

  @impl true
  def init(_args) do
    state = %{
      sources: initialize_default_sources(),
      cache: %{},
      active_builds: %{},
      priorities: @default_priorities,
      metrics: %{
        builds_completed: 0,
        avg_build_time_ms: 0.0,
        cache_hits: 0,
        cache_misses: 0,
        total_tokens_saved: 0,
        avg_compression_ratio: 1.0,
        source_failures: %{}
      },
      config: @default_config
    }
    
    # Schedule periodic cache cleanup
    schedule_cache_cleanup()
    
    {:ok, state}
  end

  ## Signal Handlers - Context Operations

    def handle_signal("build_context", data, agent) do
    request = build_context_request(data)
    
    # Check cache first
    case get_cached_context(agent, request.id) do
      {:ok, cached_context} ->
        agent = update_in(agent.metrics.cache_hits, &(&1 + 1))
        {:ok, cached_context, agent}
        
      :not_found ->
        agent = update_in(agent.metrics.cache_misses, &(&1 + 1))
        build_new_context(agent, request)
    end
  end

    def handle_signal("update_context", data, agent) do
    %{
      "request_id" => request_id,
      "updates" => updates
    } = data
    
    case Map.get(agent.cache, request_id) do
      nil ->
        {:error, "Context not found", agent}
        
      existing_context ->
        updated_context = apply_context_updates(existing_context, updates)
        agent = put_in(agent.cache[request_id], updated_context)
        
        {:ok, updated_context, agent}
    end
  end

    def handle_signal("stream_context", data, agent) do
    request = build_context_request(data)
    chunk_size = data["chunk_size"] || 1000
    
    # Start async context building with streaming
    {:ok, build_pid} = start_streaming_build(agent, request, chunk_size)
    
    agent = put_in(agent.active_builds[request.id], %{
      pid: build_pid,
      started_at: DateTime.utc_now(),
      request: request
    })
    
    {:ok, %{"build_id" => request.id, "streaming" => true}, agent}
  end

    def handle_signal("invalidate_context", %{"pattern" => pattern}, agent) do
    invalidated = invalidate_cache_entries(agent, pattern)
    
    {:ok, %{"invalidated" => length(invalidated)}, agent}
  end

  ## Signal Handlers - Source Management

    def handle_signal("register_source", data, agent) do
    source = ContextSource.new(%{
      id: data["id"] || generate_source_id(),
      name: data["name"],
      type: String.to_atom(data["type"]),
      weight: data["weight"] || 1.0,
      config: data["config"] || %{},
      transformer: data["transformer"]
    })
    
    if source.type in @source_types do
      agent = put_in(agent.sources[source.id], source)
      
      emit_signal("source_registered", %{
        "source_id" => source.id,
        "type" => source.type
      })
      
      {:ok, %{"source_id" => source.id}, agent}
    else
      {:error, "Invalid source type: #{source.type}", agent}
    end
  end

    def handle_signal("update_source", data, agent) do
    %{"source_id" => source_id, "updates" => updates} = data
    
    case Map.get(agent.sources, source_id) do
      nil ->
        {:error, "Source not found", agent}
        
      source ->
        updated_source = ContextSource.update(source, updates)
        agent = put_in(agent.sources[source_id], updated_source)
        
        {:ok, %{"source" => updated_source}, agent}
    end
  end

    def handle_signal("remove_source", %{"source_id" => source_id}, agent) do
    agent = update_in(agent.sources, &Map.delete(&1, source_id))
    
    # Invalidate cache entries using this source
    agent = invalidate_source_cache(agent, source_id)
    
    {:ok, %{"removed" => true}, agent}
  end

    def handle_signal("get_source_status", %{"source_id" => source_id}, agent) do
    case Map.get(agent.sources, source_id) do
      nil ->
        {:error, "Source not found", agent}
        
      source ->
        status = %{
          "id" => source.id,
          "name" => source.name,
          "type" => source.type,
          "status" => source.status,
          "last_fetch" => source.last_fetch,
          "failure_count" => Map.get(agent.metrics.source_failures, source_id, 0),
          "weight" => source.weight
        }
        
        {:ok, status, agent}
    end
  end

  ## Signal Handlers - Configuration

    def handle_signal("set_priorities", data, agent) do
    priorities = %{
      relevance_weight: data["relevance_weight"] || agent.priorities.relevance_weight,
      recency_weight: data["recency_weight"] || agent.priorities.recency_weight,
      importance_weight: data["importance_weight"] || agent.priorities.importance_weight
    }
    
    # Normalize weights
    total = priorities.relevance_weight + priorities.recency_weight + priorities.importance_weight
    normalized = Map.new(priorities, fn {k, v} -> {k, v / total} end)
    
    agent = %{agent | priorities: normalized}
    
    {:ok, normalized, agent}
  end

    def handle_signal("configure_limits", data, agent) do
    config_updates = %{
      max_cache_size: data["max_cache_size"] || agent.config.max_cache_size,
      default_max_tokens: data["default_max_tokens"] || agent.config.default_max_tokens,
      compression_threshold: data["compression_threshold"] || agent.config.compression_threshold,
      source_timeout: data["source_timeout"] || agent.config.source_timeout
    }
    
    agent = update_in(agent.config, &Map.merge(&1, config_updates))
    
    {:ok, agent.config, agent}
  end

    def handle_signal("get_metrics", _data, agent) do
    metrics = Map.merge(agent.metrics, %{
      "cache_size" => map_size(agent.cache),
      "active_builds" => map_size(agent.active_builds),
      "registered_sources" => map_size(agent.sources),
      "cache_hit_rate" => calculate_cache_hit_rate(agent)
    })
    
    {:ok, metrics, agent}
  end

  ## Private Functions - Context Building

  defp build_context_request(data) do
    ContextRequest.new(%{
      id: data["request_id"] || generate_request_id(),
      purpose: data["purpose"] || "general",
      max_tokens: data["max_tokens"] || @default_config.default_max_tokens,
      required_sources: data["required_sources"] || [],
      filters: data["filters"] || %{},
      preferences: data["preferences"] || %{}
    })
  end

  defp build_new_context(agent, request) do
    start_time = System.monotonic_time(:millisecond)
    
    # Mark build as active
    agent = put_in(agent.active_builds[request.id], %{
      started_at: DateTime.utc_now(),
      request: request
    })
    
    # Gather context from sources
    source_contexts = gather_source_contexts(agent, request)
    
    # Prioritize entries
    prioritized = prioritize_context_entries(agent, source_contexts, request)
    
    # Optimize context
    optimized = optimize_context(agent, prioritized, request.max_tokens)
    
    # Build final context
    final_context = %{
      "request_id" => request.id,
      "purpose" => request.purpose,
      "entries" => optimized,
      "metadata" => build_context_metadata(optimized, source_contexts),
      "timestamp" => DateTime.utc_now()
    }
    
    # Update metrics
    build_time = System.monotonic_time(:millisecond) - start_time
    agent = update_build_metrics(agent, build_time, optimized)
    
    # Cache result
    agent = cache_context(agent, request.id, final_context)
    
    # Clean up active build
    agent = update_in(agent.active_builds, &Map.delete(&1, request.id))
    
    emit_signal("context_built", %{
      "request_id" => request.id,
      "entries" => length(optimized),
      "total_tokens" => calculate_total_tokens(optimized),
      "build_time_ms" => build_time
    })
    
    {:ok, final_context, agent}
  end

  defp gather_source_contexts(agent, request) do
    # Determine which sources to use
    sources_to_query = determine_sources(agent, request)
    
    # Parallel fetch from sources
    tasks = Enum.map(sources_to_query, fn {_source_id, source} ->
      Task.async(fn ->
        fetch_from_source(agent, source, request)
      end)
    end)
    
    # Gather results with timeout
    results = Task.yield_many(tasks, agent.config.source_timeout)
    
    # Process results
    Enum.flat_map(results, fn {task, result} ->
      case result do
        {:ok, {:ok, entries}} ->
          entries
          
        {:ok, {:error, reason}} ->
          Logger.warning("Source fetch error: #{reason}")
          []
          
        nil ->
          Task.shutdown(task, :brutal_kill)
          []
      end
    end)
  end

  defp fetch_from_source(agent, source, request) do
    try do
      case source.type do
        :memory ->
          fetch_memory_context(agent, source, request)
          
        :code_analysis ->
          fetch_code_context(agent, source, request)
          
        :documentation ->
          fetch_doc_context(agent, source, request)
          
        :conversation ->
          fetch_conversation_context(agent, source, request)
          
        :planning ->
          fetch_planning_context(agent, source, request)
          
        :custom ->
          fetch_custom_context(agent, source, request)
      end
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  defp fetch_memory_context(_agent, source, request) do
    # Query memory agents for relevant context
    query_data = %{
      "purpose" => request.purpose,
      "filters" => request.filters,
      "limit" => 20
    }
    
    case emit_signal("query_memories", query_data) do
      {:ok, memories} ->
        entries = Enum.map(memories, fn memory ->
          ContextEntry.new(%{
            source: source.id,
            content: memory["content"],
            metadata: Map.merge(memory["metadata"] || %{}, %{
              memory_id: memory["id"],
              memory_type: memory["type"]
            }),
            relevance_score: memory["relevance_score"] || 0.5,
            timestamp: memory["accessed_at"] || DateTime.utc_now()
          })
        end)
        
        {:ok, entries}
        
      _ ->
        {:ok, []}
    end
  end

  defp fetch_code_context(_agent, source, request) do
    # Get code analysis context
    analysis_data = %{
      "purpose" => request.purpose,
      "file_patterns" => request.filters["file_patterns"],
      "include_tests" => request.preferences["include_tests"] || false
    }
    
    case emit_signal("get_code_context", analysis_data) do
      {:ok, code_data} ->
        entries = build_code_entries(source, code_data)
        {:ok, entries}
        
      _ ->
        {:ok, []}
    end
  end

  defp fetch_doc_context(_agent, _source, _request) do
    # Fetch relevant documentation
    {:ok, []}  # Placeholder
  end

  defp fetch_conversation_context(_agent, _source, _request) do
    # Get recent conversation history
    {:ok, []}  # Placeholder
  end

  defp fetch_planning_context(_agent, _source, _request) do
    # Get planning and task context
    {:ok, []}  # Placeholder
  end

  defp fetch_custom_context(_agent, source, _request) do
    # Use custom transformer if provided
    if source.config["transformer"] do
      # Apply custom transformation
      {:ok, []}
    else
      {:ok, []}
    end
  end

  ## Private Functions - Prioritization

  defp prioritize_context_entries(agent, entries, request) do
    scored_entries = Enum.map(entries, fn entry ->
      score = calculate_entry_score(agent, entry, request)
      {entry, score}
    end)
    
    # Sort by score descending
    scored_entries
    |> Enum.sort_by(fn {_entry, score} -> score end, :desc)
    |> Enum.map(fn {entry, _score} -> entry end)
  end

  defp calculate_entry_score(agent, entry, request) do
    relevance = entry.relevance_score * agent.priorities.relevance_weight
    
    recency = calculate_recency_score(entry.timestamp) * agent.priorities.recency_weight
    
    importance = calculate_importance_score(entry, request) * agent.priorities.importance_weight
    
    relevance + recency + importance
  end

  defp calculate_recency_score(timestamp) do
    # Score based on age - newer is better
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
    # Base importance on source weight and metadata
    source_importance = Map.get(entry.metadata, :importance, 0.5)
    
    # Boost if entry matches request preferences
    preference_boost = if matches_preferences?(entry, request.preferences), do: 0.2, else: 0.0
    
    min(source_importance + preference_boost, 1.0)
  end

  defp matches_preferences?(entry, preferences) do
    Enum.any?(preferences, fn {key, value} ->
      Map.get(entry.metadata, String.to_atom(key)) == value
    end)
  end

  ## Private Functions - Optimization

  defp optimize_context(agent, entries, max_tokens) do
    # First pass: remove duplicates
    deduped = deduplicate_entries(entries, agent.config.dedup_threshold)
    
    # Calculate current size
    current_tokens = calculate_total_tokens(deduped)
    
    if current_tokens <= max_tokens do
      deduped
    else
      # Apply optimization strategies
      deduped
      |> apply_compression(agent.config)
      |> apply_summarization(agent.config, max_tokens)
      |> truncate_to_limit(max_tokens)
    end
  end

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
      similarity_score(entry.content, existing.content) >= threshold
    end)
  end

  defp similarity_score(content1, content2) do
    # Simple similarity based on content overlap
    # In production, use more sophisticated algorithms
    str1 = content_to_string(content1)
    str2 = content_to_string(content2)
    
    if str1 == str2 do
      1.0
    else
      # Calculate Jaccard similarity
      tokens1 = MapSet.new(String.split(str1))
      tokens2 = MapSet.new(String.split(str2))
      
      intersection = MapSet.intersection(tokens1, tokens2) |> MapSet.size()
      union = MapSet.union(tokens1, tokens2) |> MapSet.size()
      
      if union > 0, do: intersection / union, else: 0.0
    end
  end

  defp apply_compression(entries, config) do
    Enum.map(entries, fn entry ->
      if entry.size_tokens > config.compression_threshold do
        ContextEntry.compress(entry)
      else
        entry
      end
    end)
  end

  defp apply_summarization(entries, config, max_tokens) do
    current_tokens = calculate_total_tokens(entries)
    
    if current_tokens > max_tokens * 1.5 do
      # Summarize lower-priority entries
      {high_priority, low_priority} = Enum.split(entries, div(length(entries), 2))
      
      summarized_low = Enum.map(low_priority, fn entry ->
        ContextEntry.summarize(entry, config.summary_ratio)
      end)
      
      high_priority ++ summarized_low
    else
      entries
    end
  end

  defp truncate_to_limit(entries, max_tokens) do
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

  ## Private Functions - Caching

  defp get_cached_context(agent, request_id) do
    case Map.get(agent.cache, request_id) do
      nil ->
        :not_found
        
      context ->
        # Check if still valid
        if context_still_valid?(context, agent.config.cache_ttl) do
          {:ok, context}
        else
          :not_found
        end
    end
  end

  defp cache_context(agent, request_id, context) do
    # Enforce cache size limit
    agent = if map_size(agent.cache) >= agent.config.max_cache_size do
      evict_oldest_cache_entry(agent)
    else
      agent
    end
    
    put_in(agent.cache[request_id], context)
  end

  defp context_still_valid?(context, ttl) do
    age = DateTime.diff(DateTime.utc_now(), context["timestamp"], :millisecond)
    age < ttl
  end

  defp evict_oldest_cache_entry(agent) do
    oldest = agent.cache
    |> Enum.min_by(fn {_id, context} -> context["timestamp"] end, DateTime, fn -> {nil, nil} end)
    
    case oldest do
      {nil, nil} -> agent
      {id, _} -> update_in(agent.cache, &Map.delete(&1, id))
    end
  end

  defp invalidate_cache_entries(agent, pattern) do
    regex = ~r/#{pattern}/
    
    matching_ids = agent.cache
    |> Map.keys()
    |> Enum.filter(&Regex.match?(regex, &1))
    
    agent_updated = Enum.reduce(matching_ids, agent, fn id, acc ->
      update_in(acc.cache, &Map.delete(&1, id))
    end)
    
    {matching_ids, agent_updated}
  end

  defp invalidate_source_cache(agent, source_id) do
    # Remove cache entries that used this source
    updated_cache = agent.cache
    |> Enum.reject(fn {_id, context} ->
      Enum.any?(context["entries"] || [], fn entry ->
        entry.source == source_id
      end)
    end)
    |> Map.new()
    
    %{agent | cache: updated_cache}
  end

  ## Private Functions - Streaming

  defp start_streaming_build(agent, request, chunk_size) do
    parent = self()
    
    Task.start(fn ->
      # Build context in chunks
      source_contexts = gather_source_contexts(agent, request)
      prioritized = prioritize_context_entries(agent, source_contexts, request)
      
      # Stream chunks
      prioritized
      |> Enum.chunk_every(chunk_size)
      |> Enum.each(fn chunk ->
        optimized_chunk = optimize_context(agent, chunk, div(request.max_tokens, 10))
        
        emit_signal("context_chunk", %{
          "request_id" => request.id,
          "chunk" => optimized_chunk,
          "partial" => true
        })
        
        Process.sleep(10)  # Small delay to prevent overwhelming
      end)
      
      # Signal completion
      emit_signal("context_chunk", %{
        "request_id" => request.id,
        "chunk" => [],
        "partial" => false,
        "completed" => true
      })
      
      send(parent, {:streaming_complete, request.id})
    end)
  end

  ## Private Functions - Helpers

  defp initialize_default_sources do
    %{
      "memory_source" => ContextSource.new(%{
        id: "memory_source",
        name: "Memory System",
        type: :memory,
        weight: 1.0,
        config: %{
          "include_short_term" => true,
          "include_long_term" => true
        }
      }),
      "code_source" => ContextSource.new(%{
        id: "code_source",
        name: "Code Analysis",
        type: :code_analysis,
        weight: 0.8,
        config: %{
          "max_file_size" => 10000,
          "include_comments" => true
        }
      })
    }
  end

  defp determine_sources(agent, request) do
    if request.required_sources == [] do
      # Use all active sources
      agent.sources
      |> Enum.filter(fn {_id, source} -> source.status == :active end)
    else
      # Use only required sources
      agent.sources
      |> Enum.filter(fn {id, source} ->
        id in request.required_sources and source.status == :active
      end)
    end
  end

  defp build_code_entries(source, code_data) do
    Enum.map(code_data["files"] || [], fn file ->
      ContextEntry.new(%{
        source: source.id,
        content: file["content"],
        metadata: %{
          file_path: file["path"],
          language: file["language"],
          type: :code
        },
        relevance_score: file["relevance"] || 0.7
      })
    end)
  end

  defp apply_context_updates(context, updates) do
    # Update entries if provided
    updated_entries = if updates["entries"] do
      updates["entries"]
    else
      context["entries"]
    end
    
    # Update metadata
    updated_metadata = Map.merge(context["metadata"] || %{}, updates["metadata"] || %{})
    
    %{context |
      "entries" => updated_entries,
      "metadata" => updated_metadata,
      "timestamp" => DateTime.utc_now()
    }
  end

  defp build_context_metadata(entries, _source_contexts) do
    %{
      "total_entries" => length(entries),
      "total_tokens" => calculate_total_tokens(entries),
      "sources_used" => entries |> Enum.map(& &1.source) |> Enum.uniq() |> length(),
      "compression_applied" => Enum.any?(entries, & &1.compressed),
      "oldest_entry" => find_oldest_timestamp(entries),
      "newest_entry" => find_newest_timestamp(entries)
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

  defp content_to_string(content) when is_binary(content), do: content
  defp content_to_string(content) when is_map(content), do: Jason.encode!(content)
  defp content_to_string(_), do: ""

  defp update_build_metrics(agent, build_time, optimized_entries) do
    completed = agent.metrics.builds_completed + 1
    avg_time = (agent.metrics.avg_build_time_ms * agent.metrics.builds_completed + build_time) / completed
    
    original_size = calculate_total_tokens(optimized_entries) * 1.5  # Estimate
    final_size = calculate_total_tokens(optimized_entries)
    compression_ratio = if original_size > 0, do: final_size / original_size, else: 1.0
    
    tokens_saved = original_size - final_size
    
    agent
    |> put_in([Access.key(:metrics), :builds_completed], completed)
    |> put_in([Access.key(:metrics), :avg_build_time_ms], avg_time)
    |> update_in([Access.key(:metrics), :total_tokens_saved], &(&1 + tokens_saved))
    |> put_in([Access.key(:metrics), :avg_compression_ratio], compression_ratio)
  end

  defp calculate_cache_hit_rate(agent) do
    total = agent.metrics.cache_hits + agent.metrics.cache_misses
    if total > 0 do
      agent.metrics.cache_hits / total * 100
    else
      0.0
    end
  end

  defp generate_request_id do
    "ctx_req_" <> :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  defp generate_source_id do
    "ctx_src_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  ## Scheduled Tasks

  defp schedule_cache_cleanup do
    Process.send_after(self(), :cleanup_cache, 60_000)  # Every minute
  end

  @impl true
  def handle_info(:cleanup_cache, agent) do
    # Remove expired cache entries
    now = DateTime.utc_now()
    
    updated_cache = agent.cache
    |> Enum.filter(fn {_id, context} ->
      age = DateTime.diff(now, context["timestamp"], :millisecond)
      age < agent.config.cache_ttl
    end)
    |> Map.new()
    
    removed = map_size(agent.cache) - map_size(updated_cache)
    
    if removed > 0 do
      Logger.debug("Context cache cleanup: removed #{removed} expired entries")
    end
    
    schedule_cache_cleanup()
    
    {:noreply, %{agent | cache: updated_cache}}
  end

  @impl true
  def handle_info({:streaming_complete, request_id}, agent) do
    # Clean up active build
    agent = update_in(agent.active_builds, &Map.delete(&1, request_id))
    {:noreply, agent}
  end
end