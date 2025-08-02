defmodule RubberDuck.Agents.LongTermMemoryAgent do
  @moduledoc """
  Long-Term Memory Agent for persistent memory storage and retrieval.
  
  This agent manages durable storage of memories with comprehensive indexing,
  versioning, and advanced search capabilities. It serves as the persistent
  layer in the memory hierarchy, working with the Memory Coordinator Agent.
  
  ## Responsibilities
  
  - Persistent memory storage with multiple backends
  - Full-text and metadata indexing
  - Advanced search and retrieval
  - Version control and history
  - Storage optimization and lifecycle management
  
  ## State Structure
  
  ```elixir
  %{
    storage_backend: atom(),
    indices: %{index_name => index_info},
    cache: %{memory_id => cached_entry},
    pending_writes: [memory_entry],
    metrics: %{
      total_memories: integer,
      storage_size_bytes: integer,
      index_size_bytes: integer,
      queries_processed: integer,
      cache_hit_rate: float
    },
    config: %{
      cache_size: integer,
      write_buffer_size: integer,
      compression_enabled: boolean,
      encryption_enabled: boolean
    }
  }
  ```
  """

  use RubberDuck.Agents.BaseAgent,
    name: "long_term_memory",
    description: "Manages persistent storage and retrieval of long-term memories",
    category: "memory"

  alias RubberDuck.Memory.{MemoryEntry, MemoryVersion, MemoryQuery}
  require Logger

  @default_config %{
    cache_size: 1000,
    write_buffer_size: 100,
    compression_enabled: true,
    encryption_enabled: false,
    flush_interval: 10_000,
    index_update_interval: 30_000,
    ttl_check_interval: 3_600_000,
    storage_backend: :postgresql
  }

  @memory_types [:user_profile, :code_pattern, :interaction, :knowledge, :optimization, :configuration]

  ## Initialization

  @impl true
  def init(_args) do
    state = %{
      storage_backend: @default_config.storage_backend,
      indices: initialize_indices(),
      cache: %{},
      pending_writes: [],
      versions: %{},
      metrics: %{
        total_memories: 0,
        storage_size_bytes: 0,
        index_size_bytes: 0,
        queries_processed: 0,
        cache_hits: 0,
        cache_misses: 0,
        writes_processed: 0,
        last_optimization: DateTime.utc_now()
      },
      config: @default_config
    }
    
    # Schedule periodic tasks
    schedule_write_flush()
    schedule_index_update()
    schedule_ttl_cleanup()
    schedule_metrics_update()
    
    # Load initial metrics from storage
    state = load_storage_metrics(state)
    
    {:ok, state}
  end

  ## Signal Handlers - Storage Operations

    def handle_signal("store_memory", data, agent) do
    %{
      "type" => type,
      "content" => content,
      "metadata" => metadata,
      "ttl" => ttl,
      "tags" => tags
    } = data
    
    memory_type = String.to_atom(type)
    
    if memory_type in @memory_types do
      memory = MemoryEntry.new(%{
        type: memory_type,
        content: content,
        metadata: metadata || %{},
        ttl: ttl,
        tags: tags || [],
        compressed: agent.config.compression_enabled,
        encryption: agent.config.encryption_enabled
      })
      
      # Add to pending writes buffer
      agent = update_in(agent.pending_writes, &[memory | &1])
      
      # Check if we should flush
      agent = if length(agent.pending_writes) >= agent.config.write_buffer_size do
        flush_pending_writes(agent)
      else
        agent
      end
      
      # Update cache
      agent = update_cache(agent, memory)
      
      emit_signal("memory_stored", %{
        "memory_id" => memory.id,
        "type" => memory.type,
        "timestamp" => DateTime.utc_now()
      })
      
      {:ok, %{"memory_id" => memory.id, "stored" => true}, agent}
    else
      {:error, "Invalid memory type: #{type}", agent}
    end
  end

    def handle_signal("update_memory", data, agent) do
    %{
      "memory_id" => memory_id,
      "updates" => updates,
      "reason" => reason
    } = data
    
    case get_memory_entry(agent, memory_id) do
      {:ok, existing_memory} ->
        # Create version before update
        version = create_version(existing_memory, updates, reason)
        agent = store_version(agent, memory_id, version)
        
        # Apply updates
        updated_memory = MemoryEntry.update(existing_memory, updates)
        
        # Update in storage and cache
        agent = agent
        |> update_memory_in_storage(updated_memory)
        |> update_cache(updated_memory)
        |> update_indices(updated_memory)
        
        emit_signal("memory_updated", %{
          "memory_id" => memory_id,
          "version" => updated_memory.version,
          "timestamp" => DateTime.utc_now()
        })
        
        {:ok, %{"memory" => updated_memory, "version" => version}, agent}
        
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

    def handle_signal("delete_memory", %{"memory_id" => memory_id} = data, agent) do
    soft_delete = Map.get(data, "soft_delete", true)
    
    if soft_delete do
      # Soft delete - mark as deleted but keep in storage
      case get_memory_entry(agent, memory_id) do
        {:ok, memory} ->
          deleted_memory = MemoryEntry.mark_deleted(memory)
          agent = update_memory_in_storage(agent, deleted_memory)
          agent = remove_from_cache(agent, memory_id)
          
          {:ok, %{"deleted" => true, "soft_delete" => true}, agent}
          
        {:error, reason} ->
          {:error, reason, agent}
      end
    else
      # Hard delete - remove completely
      agent = agent
      |> delete_from_storage(memory_id)
      |> remove_from_indices(memory_id)
      |> remove_from_cache(memory_id)
      
      {:ok, %{"deleted" => true, "hard_delete" => true}, agent}
    end
  end

    def handle_signal("bulk_store", %{"memories" => memories_data}, agent) do
    memories = Enum.map(memories_data, fn data ->
      MemoryEntry.new(%{
        type: String.to_atom(data["type"]),
        content: data["content"],
        metadata: data["metadata"] || %{},
        ttl: data["ttl"],
        tags: data["tags"] || []
      })
    end)
    
    # Add all to pending writes
    agent = update_in(agent.pending_writes, &(memories ++ &1))
    
    # Force flush for bulk operations
    agent = flush_pending_writes(agent)
    
    memory_ids = Enum.map(memories, & &1.id)
    
    {:ok, %{"memory_ids" => memory_ids, "count" => length(memories)}, agent}
  end

  ## Signal Handlers - Retrieval Operations

    def handle_signal("search_memories", data, agent) do
    %{
      "query" => query_text,
      "types" => types,
      "limit" => limit,
      "offset" => offset
    } = data
    
    search_query = %{
      text: query_text,
      types: parse_types(types),
      limit: limit || 20,
      offset: offset || 0,
      include_deleted: Map.get(data, "include_deleted", false)
    }
    
    # Perform search
    results = search_memories(agent, search_query)
    
    # Update metrics
    agent = update_in(agent.metrics.queries_processed, &(&1 + 1))
    
    {:ok, %{"results" => results, "count" => length(results)}, agent}
  end

    def handle_signal("query_memories", data, agent) do
    query = MemoryQuery.build(data)
    
    # Execute query
    {results, total_count} = execute_query(agent, query)
    
    # Update cache with frequently accessed memories
    agent = Enum.reduce(results, agent, fn memory, acc ->
      update_cache(acc, memory)
    end)
    
    # Update metrics
    agent = update_in(agent.metrics.queries_processed, &(&1 + 1))
    
    {:ok, %{
      "results" => results,
      "total_count" => total_count,
      "page" => query.page,
      "page_size" => query.page_size
    }, agent}
  end

    def handle_signal("get_memory", %{"memory_id" => memory_id}, agent) do
    case get_memory_entry(agent, memory_id) do
      {:ok, memory} ->
        # Update access metadata
        accessed_memory = MemoryEntry.record_access(memory)
        agent = update_memory_in_storage(agent, accessed_memory)
        
        {:ok, %{"memory" => accessed_memory}, agent}
        
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

    def handle_signal("get_related", data, agent) do
    %{
      "memory_id" => memory_id,
      "relationship_types" => rel_types,
      "limit" => limit
    } = data
    
    case get_memory_entry(agent, memory_id) do
      {:ok, memory} ->
        related = find_related_memories(agent, memory, rel_types, limit || 10)
        {:ok, %{"related" => related}, agent}
        
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  ## Signal Handlers - Management Operations

    def handle_signal("optimize_storage", _data, agent) do
    Task.start(fn -> 
      run_storage_optimization(agent)
    end)
    
    agent = put_in(agent.metrics.last_optimization, DateTime.utc_now())
    
    {:ok, %{"optimization_started" => true}, agent}
  end

    def handle_signal("reindex_memory", %{"memory_id" => memory_id}, agent) do
    case get_memory_entry(agent, memory_id) do
      {:ok, memory} ->
        agent = update_indices(agent, memory)
        {:ok, %{"reindexed" => true}, agent}
        
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

    def handle_signal("get_memory_stats", _data, agent) do
    stats = %{
      "total_memories" => agent.metrics.total_memories,
      "storage_size_mb" => agent.metrics.storage_size_bytes / 1_048_576,
      "index_size_mb" => agent.metrics.index_size_bytes / 1_048_576,
      "cache_size" => map_size(agent.cache),
      "cache_hit_rate" => calculate_cache_hit_rate(agent),
      "pending_writes" => length(agent.pending_writes),
      "queries_processed" => agent.metrics.queries_processed,
      "storage_backend" => agent.storage_backend,
      "compression_enabled" => agent.config.compression_enabled,
      "last_optimization" => agent.metrics.last_optimization
    }
    
    {:ok, stats, agent}
  end

    def handle_signal("get_memory_versions", %{"memory_id" => memory_id}, agent) do
    versions = Map.get(agent.versions, memory_id, [])
    
    {:ok, %{"versions" => versions}, agent}
  end

    def handle_signal("rollback_memory", data, agent) do
    %{
      "memory_id" => memory_id,
      "version" => target_version
    } = data
    
    case rollback_to_version(agent, memory_id, target_version) do
      {:ok, restored_memory, agent} ->
        {:ok, %{"memory" => restored_memory, "rolled_back" => true}, agent}
        
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  ## Private Functions - Storage Operations

  defp get_memory_entry(agent, memory_id) do
    # Check cache first
    case Map.get(agent.cache, memory_id) do
      nil ->
        # Cache miss - load from storage
        agent = update_in(agent.metrics.cache_misses, &(&1 + 1))
        load_from_storage(agent, memory_id)
        
      memory ->
        # Cache hit
        _ = update_in(agent.metrics.cache_hits, &(&1 + 1))
        {:ok, memory}
    end
  end

  defp flush_pending_writes(agent) do
    if agent.pending_writes != [] do
      # Group by type for batch operations
      by_type = Enum.group_by(agent.pending_writes, & &1.type)
      
      # Store each type batch
      Enum.each(by_type, fn {type, memories} ->
        store_memories_batch(agent.storage_backend, type, memories)
        update_indices_batch(agent, memories)
      end)
      
      # Update metrics
      count = length(agent.pending_writes)
      agent = agent
      |> update_in([Access.key(:metrics), :writes_processed], &(&1 + count))
      |> update_in([Access.key(:metrics), :total_memories], &(&1 + count))
      
      emit_signal("memories_flushed", %{
        "count" => count,
        "timestamp" => DateTime.utc_now()
      })
      
      %{agent | pending_writes: []}
    else
      agent
    end
  end

  defp update_cache(agent, memory) do
    if map_size(agent.cache) >= agent.config.cache_size do
      # Evict least recently accessed
      _ = evict_from_cache(agent)
    end
    
    put_in(agent.cache[memory.id], memory)
  end

  defp remove_from_cache(agent, memory_id) do
    update_in(agent.cache, &Map.delete(&1, memory_id))
  end
  
  defp remove_from_indices(agent, memory_id) do
    # Remove from all indices
    indices = agent.indices
    |> Enum.map(fn {name, info} ->
      # Remove memory_id from each index
      updated_info = Map.update(info, :entries, [], fn entries ->
        Enum.reject(entries, fn {id, _} -> id == memory_id end)
      end)
      {name, updated_info}
    end)
    |> Map.new()
    
    %{agent | indices: indices}
  end

  defp evict_from_cache(agent) do
    # Find least recently accessed entry
    {lru_id, _} = agent.cache
    |> Enum.min_by(fn {_id, memory} -> memory.accessed_at end, fn -> {nil, nil} end)
    
    if lru_id do
      remove_from_cache(agent, lru_id)
    else
      agent
    end
  end

  ## Private Functions - Index Operations

  defp initialize_indices do
    %{
      "fulltext" => %{type: :fulltext, fields: [:content, :tags], last_updated: DateTime.utc_now()},
      "type" => %{type: :metadata, field: :type, last_updated: DateTime.utc_now()},
      "tags" => %{type: :metadata, field: :tags, last_updated: DateTime.utc_now()},
      "metadata" => %{type: :metadata, field: :metadata, last_updated: DateTime.utc_now()}
    }
  end

  defp update_indices(agent, memory) do
    # Update each index type
    Enum.reduce(agent.indices, agent, fn {name, index_info}, acc ->
      update_index(acc, name, index_info, memory)
    end)
  end

  defp update_indices_batch(agent, memories) do
    # Batch update indices
    Enum.each(agent.indices, fn {name, index_info} ->
      update_index_batch(agent.storage_backend, name, index_info, memories)
    end)
  end

  defp update_index(agent, "fulltext", _index_info, memory) do
    # Update full-text search index
    text_content = extract_searchable_text(memory)
    update_fulltext_index(agent.storage_backend, memory.id, text_content)
    agent
  end

  defp update_index(agent, _name, index_info, memory) do
    # Update metadata index
    field_value = Map.get(memory, index_info.field)
    update_metadata_index(agent.storage_backend, index_info.field, memory.id, field_value)
    agent
  end

  defp extract_searchable_text(memory) do
    # Extract all text content for indexing
    content_text = case memory.content do
      map when is_map(map) -> 
        map
        |> Map.values()
        |> Enum.filter(&is_binary/1)
        |> Enum.join(" ")
      text when is_binary(text) -> text
      _ -> ""
    end
    
    tags_text = Enum.join(memory.tags, " ")
    
    "#{content_text} #{tags_text}"
  end

  ## Private Functions - Search and Query

  defp search_memories(agent, search_query) do
    # Perform full-text search
    memory_ids = search_fulltext_index(agent.storage_backend, search_query.text)
    
    # Filter by types if specified
    memory_ids = if search_query.types do
      filter_by_types(agent.storage_backend, memory_ids, search_query.types)
    else
      memory_ids
    end
    
    # Load memories
    memories = load_memories_batch(agent.storage_backend, memory_ids)
    
    # Apply limit and offset
    memories
    |> Enum.drop(search_query.offset)
    |> Enum.take(search_query.limit)
  end

  defp execute_query(agent, query) do
    # Build and execute database query
    results = case agent.storage_backend do
      :postgresql -> execute_postgresql_query(query)
      :memory -> execute_memory_query(agent, query)
      _ -> []
    end
    
    # Get total count for pagination
    total_count = count_query_results(agent, query)
    
    {results, total_count}
  end

  defp find_related_memories(agent, memory, relationship_types, limit) do
    related_ids = memory.relationships
    |> Enum.filter(fn rel -> 
      rel_type = Map.get(rel, :type)
      relationship_types == nil or rel_type in relationship_types
    end)
    |> Enum.map(& &1.target_id)
    |> Enum.take(limit)
    
    load_memories_batch(agent.storage_backend, related_ids)
  end

  ## Private Functions - Version Control

  defp create_version(memory, updates, reason) do
    changes = calculate_changes(memory, updates)
    
    MemoryVersion.new(%{
      memory_id: memory.id,
      version: memory.version,
      changes: changes,
      reason: reason,
      author: "system"  # TODO: Get from context
    })
  end

  defp store_version(agent, memory_id, version) do
    update_in(agent.versions[memory_id], fn versions ->
      [version | (versions || [])]
      |> Enum.take(10)  # Keep last 10 versions
    end)
  end

  defp rollback_to_version(agent, memory_id, target_version) do
    with {:ok, memory} <- get_memory_entry(agent, memory_id),
         {:ok, version} <- find_version(agent, memory_id, target_version),
         {:ok, restored} <- apply_version(memory, version) do
      
      agent = agent
      |> update_memory_in_storage(restored)
      |> update_cache(restored)
      |> update_indices(restored)
      
      {:ok, restored, agent}
    end
  end

  defp calculate_changes(old_memory, updates) do
    updates
    |> Enum.map(fn {key, new_value} ->
      old_value = Map.get(old_memory, key)
      {key, %{old: old_value, new: new_value}}
    end)
    |> Map.new()
  end

  ## Private Functions - Storage Backend Operations

  defp load_from_storage(agent, memory_id) do
    case agent.storage_backend do
      :postgresql -> load_from_postgresql(memory_id)
      :memory -> load_from_memory_storage(agent, memory_id)
      _ -> {:error, "Unsupported storage backend"}
    end
  end

  defp store_memories_batch(:postgresql, type, memories) do
    # Store in PostgreSQL using Ash
    # This would use the Ash resource API
    Logger.info("Storing #{length(memories)} memories of type #{type}")
  end

  defp update_memory_in_storage(agent, memory) do
    Task.start(fn ->
      case agent.storage_backend do
        :postgresql -> update_in_postgresql(memory)
        :memory -> :ok
      end
    end)
    
    agent
  end

  defp delete_from_storage(agent, memory_id) do
    Task.start(fn ->
      case agent.storage_backend do
        :postgresql -> delete_from_postgresql(memory_id)
        :memory -> :ok
      end
    end)
    
    agent
  end

  ## Private Functions - Metrics and Optimization

  defp load_storage_metrics(agent) do
    # Load metrics from storage backend
    metrics = case agent.storage_backend do
      :postgresql -> load_postgresql_metrics()
      _ -> agent.metrics
    end
    
    %{agent | metrics: metrics}
  end

  defp calculate_cache_hit_rate(agent) do
    total = agent.metrics.cache_hits + agent.metrics.cache_misses
    if total > 0 do
      agent.metrics.cache_hits / total * 100
    else
      0.0
    end
  end

  defp run_storage_optimization(agent) do
    Logger.info("Running storage optimization...")
    
    # Vacuum deleted entries
    vacuum_deleted_memories(agent.storage_backend)
    
    # Optimize indices
    optimize_indices(agent.storage_backend)
    
    # Clean expired memories
    clean_expired_memories(agent.storage_backend)
    
    emit_signal("storage_optimized", %{
      "timestamp" => DateTime.utc_now()
    })
  end

  ## Private Functions - Helper Functions

  defp parse_types(nil), do: nil
  defp parse_types(types) when is_list(types) do
    Enum.map(types, &String.to_atom/1)
  end
  defp parse_types(type) when is_binary(type) do
    [String.to_atom(type)]
  end

  defp find_version(agent, memory_id, target_version) do
    versions = Map.get(agent.versions, memory_id, [])
    version = Enum.find(versions, fn v -> v.version == target_version end)
    
    if version do
      {:ok, version}
    else
      {:error, "Version not found"}
    end
  end

  defp apply_version(memory, version) do
    # Apply version changes to memory
    restored = Enum.reduce(version.changes, memory, fn {field, %{old: old_value}}, acc ->
      Map.put(acc, field, old_value)
    end)
    
    {:ok, restored}
  end

  ## Placeholder functions for storage backends

  defp search_fulltext_index(_backend, _query), do: []
  defp filter_by_types(_backend, ids, _types), do: ids
  defp load_memories_batch(_backend, _ids), do: []
  defp execute_postgresql_query(_query), do: []
  defp execute_memory_query(_agent, _query), do: []
  defp count_query_results(_agent, _query), do: 0
  defp update_fulltext_index(_backend, _id, _text), do: :ok
  defp update_metadata_index(_backend, _field, _id, _value), do: :ok
  defp update_index_batch(_backend, _name, _info, _memories), do: :ok
  defp load_from_postgresql(_id), do: {:error, "Not implemented"}
  defp load_from_memory_storage(_agent, _id), do: {:error, "Not implemented"}
  defp update_in_postgresql(_memory), do: :ok
  defp delete_from_postgresql(_id), do: :ok
  defp load_postgresql_metrics(), do: %{}
  defp vacuum_deleted_memories(_backend), do: :ok
  defp optimize_indices(_backend), do: :ok
  defp clean_expired_memories(_backend), do: :ok

  ## Scheduled Tasks

  defp schedule_write_flush do
    Process.send_after(self(), :flush_writes, @default_config.flush_interval)
  end

  defp schedule_index_update do
    Process.send_after(self(), :update_indices, @default_config.index_update_interval)
  end

  defp schedule_ttl_cleanup do
    Process.send_after(self(), :cleanup_ttl, @default_config.ttl_check_interval)
  end

  defp schedule_metrics_update do
    Process.send_after(self(), :update_metrics, 60_000)
  end

  @impl true
  def handle_info(:flush_writes, agent) do
    agent = flush_pending_writes(agent)
    schedule_write_flush()
    {:noreply, agent}
  end

  @impl true
  def handle_info(:update_indices, agent) do
    # Update index statistics
    agent = update_in(agent.indices, fn indices ->
      Map.new(indices, fn {name, info} ->
        {name, Map.put(info, :last_updated, DateTime.utc_now())}
      end)
    end)
    
    schedule_index_update()
    {:noreply, agent}
  end

  @impl true
  def handle_info(:cleanup_ttl, agent) do
    Task.start(fn ->
      clean_expired_memories(agent.storage_backend)
    end)
    
    schedule_ttl_cleanup()
    {:noreply, agent}
  end

  @impl true
  def handle_info(:update_metrics, agent) do
    emit_signal("memory_metrics", %{
      "total_memories" => agent.metrics.total_memories,
      "cache_hit_rate" => calculate_cache_hit_rate(agent),
      "queries_processed" => agent.metrics.queries_processed,
      "writes_processed" => agent.metrics.writes_processed
    })
    
    schedule_metrics_update()
    {:noreply, agent}
  end
end