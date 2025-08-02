defmodule RubberDuck.Agents.ContextBuilderAgent do
  @moduledoc """
  Context Builder Agent for intelligent context aggregation and optimization.
  
  This agent manages the collection, prioritization, and optimization of context
  from multiple sources to provide relevant information for LLM interactions.
  It ensures efficient token usage while maximizing context relevance.
  
  Migrated to Jido-compliant action-based architecture for better maintainability,
  testability, and reusability of context management workflows.
  
  ## Responsibilities
  
  - Route context requests to appropriate Actions
  - Maintain context sources registry and configuration
  - Provide centralized context caching and metrics
  - Handle context lifecycle management
  - Support streaming and real-time context updates
  
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
    category: "memory",
    schema: [
      sources: [type: :map, default: %{}, doc: "Registered context sources"],
      cache: [type: :map, default: %{}, doc: "Built context cache"],
      active_builds: [type: :map, default: %{}, doc: "Active context builds"],
      priorities: [type: :map, default: %{}, doc: "Context prioritization weights"],
      metrics: [type: :map, default: %{}, doc: "Performance and usage metrics"],
      config: [type: :map, default: %{}, doc: "Agent configuration"]
    ],
    actions: [
      RubberDuck.Jido.Actions.Context.ContextAssemblyAction,
      RubberDuck.Jido.Actions.Context.ContextCacheAction,
      RubberDuck.Jido.Actions.Context.ContextSourceManagementAction,
      RubberDuck.Jido.Actions.Context.ContextConfigurationAction
    ]

  alias RubberDuck.Context.{ContextEntry, ContextSource, ContextRequest}
  alias RubberDuck.Jido.Actions.Context.{
    ContextAssemblyAction, 
    ContextCacheAction,
    ContextSourceManagementAction,
    ContextConfigurationAction
  }
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

  ## Action-based Signal Processing
  
  # All signal handling now routed through Actions via signal_mappings
  # This enables:
  # - Pure function-based business logic
  # - Reusable action components
  # - Better testability and maintainability
  # - Consistent error handling patterns
  
  # Signal-to-Action parameter extraction functions
  
  # ContextAssemblyAction parameter extractors
  def extract_build_params(signal_data) do
    %{
      mode: :build,
      request_id: signal_data["request_id"],
      purpose: signal_data["purpose"] || "general",
      max_tokens: signal_data["max_tokens"] || @default_config.default_max_tokens,
      required_sources: signal_data["required_sources"] || [],
      excluded_sources: signal_data["excluded_sources"] || [],
      filters: signal_data["filters"] || %{},
      preferences: signal_data["preferences"] || %{},
      streaming: signal_data["streaming"] || false,
      priority: string_to_atom(signal_data["priority"]) || :normal
    }
  end

  def extract_context_update_params(signal_data) do
    %{
      mode: :update,
      request_id: signal_data["request_id"],
      update_data: signal_data["updates"] || %{}
    }
  end

  def extract_stream_params(signal_data) do
    %{
      mode: :stream,
      request_id: signal_data["request_id"],
      purpose: signal_data["purpose"] || "general",
      max_tokens: signal_data["max_tokens"] || @default_config.default_max_tokens,
      chunk_size: signal_data["chunk_size"] || 1000,
      streaming: true
    }
  end

  # ContextCacheAction parameter extractors
  def extract_invalidate_params(signal_data) do
    %{
      operation: :invalidate,
      invalidation_pattern: signal_data["pattern"],
      request_id: signal_data["request_id"],
      cache_key: signal_data["cache_key"]
    }
  end

  def extract_stats_params(_signal_data) do
    %{
      operation: :stats,
      metrics_enabled: true,
      include_detailed_metrics: true
    }
  end

  def extract_cleanup_params(signal_data) do
    %{
      operation: :cleanup,
      cleanup_threshold: signal_data["threshold"] || 0.8,
      max_entries: signal_data["max_entries"] || @default_config.max_cache_size
    }
  end

  # ContextSourceManagementAction parameter extractors
  def extract_register_params(signal_data) do
    %{
      operation: :register,
      source_data: signal_data
    }
  end

  def extract_source_update_params(signal_data) do
    %{
      operation: :update,
      source_id: signal_data["source_id"],
      updates: signal_data["updates"] || %{}
    }
  end

  def extract_remove_params(signal_data) do
    %{
      operation: :remove,
      source_id: signal_data["source_id"]
    }
  end

  def extract_status_params(signal_data) do
    %{
      operation: :status,
      source_id: signal_data["source_id"],
      include_config: signal_data["include_config"] || false
    }
  end

  # ContextConfigurationAction parameter extractors
  def extract_priorities_params(signal_data) do
    %{
      operation: :set_priorities,
      priorities: %{
        relevance_weight: signal_data["relevance_weight"],
        recency_weight: signal_data["recency_weight"],
        importance_weight: signal_data["importance_weight"]
      }
    }
  end

  def extract_limits_params(signal_data) do
    %{
      operation: :configure_limits,
      limits: signal_data
    }
  end

  def extract_metrics_params(signal_data) do
    %{
      operation: :get_metrics,
      include_detailed_metrics: signal_data["detailed"] || false,
      metrics_time_range: signal_data["time_range"] || 24
    }
  end

  # BaseAgent callback implementations
  
  @impl RubberDuck.Agents.BaseAgent
  def signal_mappings do
    %{
      # Context operations → ContextAssemblyAction
      "build_context" => {RubberDuck.Jido.Actions.Context.ContextAssemblyAction, :extract_build_params},
      "update_context" => {RubberDuck.Jido.Actions.Context.ContextAssemblyAction, :extract_context_update_params},
      "stream_context" => {RubberDuck.Jido.Actions.Context.ContextAssemblyAction, :extract_stream_params},
      
      # Cache operations → ContextCacheAction
      "invalidate_context" => {RubberDuck.Jido.Actions.Context.ContextCacheAction, :extract_invalidate_params},
      "get_cache_stats" => {RubberDuck.Jido.Actions.Context.ContextCacheAction, :extract_stats_params},
      "cleanup_cache" => {RubberDuck.Jido.Actions.Context.ContextCacheAction, :extract_cleanup_params},
      
      # Source management → ContextSourceManagementAction
      "register_source" => {RubberDuck.Jido.Actions.Context.ContextSourceManagementAction, :extract_register_params},
      "update_source" => {RubberDuck.Jido.Actions.Context.ContextSourceManagementAction, :extract_source_update_params},
      "remove_source" => {RubberDuck.Jido.Actions.Context.ContextSourceManagementAction, :extract_remove_params},
      "get_source_status" => {RubberDuck.Jido.Actions.Context.ContextSourceManagementAction, :extract_status_params},
      
      # Configuration → ContextConfigurationAction
      "set_priorities" => {RubberDuck.Jido.Actions.Context.ContextConfigurationAction, :extract_priorities_params},
      "configure_limits" => {RubberDuck.Jido.Actions.Context.ContextConfigurationAction, :extract_limits_params},
      "get_metrics" => {RubberDuck.Jido.Actions.Context.ContextConfigurationAction, :extract_metrics_params}
    }
  end

  # Helper functions
  defp string_to_atom(nil), do: nil
  defp string_to_atom(str) when is_binary(str), do: String.to_atom(str)
  defp string_to_atom(atom) when is_atom(atom), do: atom

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