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
  
  ## Signals
  
  ### Input Signals
  - `store_memory` - Store new memory entries
  - `update_memory` - Update existing memory entries
  - `delete_memory` - Delete memory entries
  - `bulk_store` - Store multiple memories in batch
  - `search_memories` - Search memories with text queries
  - `query_memories` - Execute complex memory queries
  - `get_memory` - Retrieve specific memory by ID
  - `get_related` - Get related memories
  - `optimize_storage` - Run storage optimization
  - `get_memory_stats` - Get memory statistics
  - `get_memory_versions` - Get version history
  - `rollback_memory` - Rollback to previous version
  - `reindex_memory` - Reindex specific memory
  - `backup_memories` - Create memory backups
  
  ### Output Signals
  - `memory.stored` - Memory successfully stored
  - `memory.updated` - Memory successfully updated
  - `memory.deleted` - Memory successfully deleted
  - `memory.search.result` - Search results
  - `memory.stats.report` - Memory statistics
  - `memory.optimization.complete` - Optimization completed
  - `memory.backup.complete` - Backup completed
  """
  
  use Jido.Agent,
    name: "long_term_memory_agent",
    description: "Manages persistent storage and retrieval of long-term memories",
    category: "memory",
    tags: ["memory", "storage", "long-term", "persistence", "search"],
    vsn: "1.0.0",
    schema: [
      storage_backend: [
        type: :atom,
        default: :postgresql,
        doc: "Storage backend type"
      ],
      indices: [
        type: :map,
        default: %{},
        doc: "Memory indices for search and retrieval"
      ],
      cache: [
        type: :map,
        default: %{},
        doc: "In-memory cache for frequently accessed memories"
      ],
      pending_writes: [
        type: {:list, :map},
        default: [],
        doc: "Buffer for pending write operations"
      ],
      versions: [
        type: :map,
        default: %{},
        doc: "Version history for memories"
      ],
      metrics: [
        type: :map,
        default: %{
          total_memories: 0,
          storage_size_bytes: 0,
          index_size_bytes: 0,
          queries_processed: 0,
          cache_hits: 0,
          cache_misses: 0,
          writes_processed: 0,
          last_optimization: nil
        },
        doc: "Performance and usage metrics"
      ],
      config: [
        type: :map,
        default: %{
          cache_size: 1000,
          write_buffer_size: 100,
          compression_enabled: true,
          encryption_enabled: false,
          flush_interval: 10_000,
          index_update_interval: 30_000,
          ttl_check_interval: 3_600_000
        },
        doc: "Agent configuration parameters"
      ]
    ]

  alias RubberDuck.Memory.{MemoryEntry, MemoryVersion, MemoryQuery}
  require Logger


  # Action to store memories
  defmodule StoreMemoryAction do
    use Jido.Action,
      name: "store_memory",
      description: "Store new memory entries with optional versioning and indexing",
      schema: [
        type: [type: :string, required: true, doc: "Memory type"],
        content: [type: :any, required: true, doc: "Memory content"],
        metadata: [type: :map, default: %{}, doc: "Memory metadata"],
        ttl: [type: :integer, doc: "Time to live in seconds"],
        tags: [type: {:list, :string}, default: [], doc: "Memory tags"],
        memory_id: [type: :string, doc: "Optional specific memory ID"]
      ]
    
    def run(params, context) do
      %{type: type, content: content, metadata: metadata, ttl: ttl, tags: tags} = params
      agent_state = context.agent.state
      
      memory_type = String.to_atom(type)
      
      memory_types = [:user_profile, :code_pattern, :interaction, :knowledge, :optimization, :configuration]
      
      if memory_type in memory_types do
        Logger.info("Storing memory of type: #{memory_type}")
        
        memory = MemoryEntry.new(%{
          id: Map.get(params, :memory_id),
          type: memory_type,
          content: content,
          metadata: metadata,
          ttl: ttl,
          tags: tags,
          compressed: agent_state.config.compression_enabled,
          encryption: agent_state.config.encryption_enabled
        })
        
        # Add to pending writes buffer
        agent_state = update_in(agent_state.pending_writes, &[memory | &1])
        
        # Check if we should flush
        agent_state = if length(agent_state.pending_writes) >= agent_state.config.write_buffer_size do
          flush_pending_writes(agent_state)
        else
          agent_state
        end
        
        # Update cache
        agent_state = update_cache(agent_state, memory)
        
        signal_data = %{
          memory_id: memory.id,
          type: memory.type,
          stored: true,
          timestamp: DateTime.utc_now()
        }
        
        {:ok, %{
          agent_state: agent_state,
          signal_data: signal_data,
          signal_type: "memory.stored",
          result: %{memory_id: memory.id, stored: true}
        }}
      else
        {:error, "Invalid memory type: #{type}"}
      end
    end
    
    defp flush_pending_writes(agent_state) do
      if agent_state.pending_writes != [] do
        # Group by type for batch operations
        by_type = Enum.group_by(agent_state.pending_writes, & &1.type)
        
        # Store each type batch
        Enum.each(by_type, fn {type, memories} ->
          store_memories_batch(agent_state.storage_backend, type, memories)
          update_indices_batch(agent_state, memories)
        end)
        
        # Update metrics
        count = length(agent_state.pending_writes)
        agent_state = agent_state
        |> update_in([Access.key(:metrics), :writes_processed], &(&1 + count))
        |> update_in([Access.key(:metrics), :total_memories], &(&1 + count))
        
        %{agent_state | pending_writes: []}
      else
        agent_state
      end
    end
    
    defp update_cache(agent_state, memory) do
      if map_size(agent_state.cache) >= agent_state.config.cache_size do
        # Evict least recently accessed
        _ = evict_from_cache(agent_state)
      end
      
      put_in(agent_state.cache[memory.id], memory)
    end
    
    defp evict_from_cache(agent_state) do
      # Find least recently accessed entry
      {lru_id, _} = agent_state.cache
      |> Enum.min_by(fn {_id, memory} -> memory.accessed_at end, fn -> {nil, nil} end)
      
      if lru_id do
        update_in(agent_state.cache, &Map.delete(&1, lru_id))
      else
        agent_state
      end
    end
    
    defp store_memories_batch(:postgresql, type, memories) do
      # Store in PostgreSQL using Ash
      Logger.info("Storing #{length(memories)} memories of type #{type}")
    end
    
    defp store_memories_batch(_, type, memories) do
      Logger.info("Storing #{length(memories)} memories of type #{type}")
    end
    
    defp update_indices_batch(agent_state, memories) do
      # Batch update indices
      Enum.each(agent_state.indices, fn {name, index_info} ->
        update_index_batch(agent_state.storage_backend, name, index_info, memories)
      end)
    end
    
    defp update_index_batch(_backend, _name, _info, _memories), do: :ok
  end

  # Action to retrieve memories
  defmodule RetrieveMemoryAction do
    use Jido.Action,
      name: "retrieve_memory",
      description: "Retrieve specific memories by ID or criteria",
      schema: [
        memory_id: [type: :string, doc: "Specific memory ID to retrieve"],
        memory_ids: [type: {:list, :string}, doc: "Multiple memory IDs to retrieve"],
        include_deleted: [type: :boolean, default: false, doc: "Include soft-deleted memories"],
        update_access_time: [type: :boolean, default: true, doc: "Update last accessed timestamp"]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      
      cond do
        memory_id = Map.get(params, :memory_id) ->
          retrieve_single_memory(agent_state, memory_id, params)
        
        memory_ids = Map.get(params, :memory_ids) ->
          retrieve_multiple_memories(agent_state, memory_ids, params)
        
        true ->
          {:error, "Either memory_id or memory_ids must be provided"}
      end
    end
    
    defp retrieve_single_memory(agent_state, memory_id, params) do
      case get_memory_entry(agent_state, memory_id) do
        {:ok, memory} ->
          # Update access metadata if requested
          {memory, agent_state} = if params.update_access_time do
            accessed_memory = MemoryEntry.record_access(memory)
            updated_state = update_memory_in_storage(agent_state, accessed_memory)
            {accessed_memory, updated_state}
          else
            {memory, agent_state}
          end
          
          signal_data = %{
            memory_id: memory_id,
            memory: memory,
            retrieved: true,
            timestamp: DateTime.utc_now()
          }
          
          {:ok, %{
            agent_state: agent_state,
            signal_data: signal_data,
            signal_type: "memory.retrieved",
            result: %{memory: memory}
          }}
        
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp retrieve_multiple_memories(agent_state, memory_ids, _params) do
      results = Enum.map(memory_ids, fn memory_id ->
        case get_memory_entry(agent_state, memory_id) do
          {:ok, memory} -> {memory_id, :ok, memory}
          {:error, reason} -> {memory_id, :error, reason}
        end
      end)
      
      successful = results |> Enum.filter(fn {_, status, _} -> status == :ok end) |> Enum.map(fn {_, _, memory} -> memory end)
      failed = results |> Enum.filter(fn {_, status, _} -> status == :error end) |> Enum.map(fn {id, _, reason} -> {id, reason} end)
      
      signal_data = %{
        requested_count: length(memory_ids),
        retrieved_count: length(successful),
        failed_count: length(failed),
        memories: successful,
        failures: failed,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, %{
        signal_data: signal_data,
        signal_type: "memory.bulk.retrieved",
        result: %{memories: successful, failures: failed}
      }}
    end
    
    defp get_memory_entry(agent_state, memory_id) do
      # Check cache first
      case Map.get(agent_state.cache, memory_id) do
        nil ->
          # Cache miss - load from storage
          load_from_storage(agent_state, memory_id)
        
        memory ->
          # Cache hit
          {:ok, memory}
      end
    end
    
    defp load_from_storage(agent_state, memory_id) do
      case agent_state.storage_backend do
        :postgresql -> load_from_postgresql(memory_id)
        :memory -> load_from_memory_storage(agent_state, memory_id)
        _ -> {:error, "Unsupported storage backend"}
      end
    end
    
    defp update_memory_in_storage(agent_state, memory) do
      Task.start(fn ->
        case agent_state.storage_backend do
          :postgresql -> update_in_postgresql(memory)
          :memory -> :ok
        end
      end)
      
      agent_state
    end
    
    # Placeholder functions for storage backends
    defp load_from_postgresql(_id), do: {:error, "Not implemented"}
    defp load_from_memory_storage(_agent, _id), do: {:error, "Not implemented"}
    defp update_in_postgresql(_memory), do: :ok
  end

  # Action to search memories
  defmodule SearchMemoryAction do
    use Jido.Action,
      name: "search_memory",
      description: "Search memories using text queries and filters",
      schema: [
        query: [type: :string, required: true, doc: "Search query text"],
        types: [type: {:list, :string}, doc: "Memory types to search within"],
        limit: [type: :integer, default: 20, doc: "Maximum number of results"],
        offset: [type: :integer, default: 0, doc: "Result offset for pagination"],
        include_deleted: [type: :boolean, default: false, doc: "Include soft-deleted memories"],
        search_type: [type: :string, default: "text", doc: "Type of search: text, semantic, or hybrid"]
      ]
    
    def run(params, context) do
      %{query: query_text, types: types, limit: limit, offset: offset} = params
      agent_state = context.agent.state
      
      Logger.info("Searching memories with query: #{query_text}")
      
      search_query = %{
        text: query_text,
        types: parse_types(types),
        limit: limit,
        offset: offset,
        include_deleted: params.include_deleted,
        search_type: params.search_type
      }
      
      # Perform search
      results = search_memories(agent_state, search_query)
      
      # Update metrics
      updated_metrics = agent_state.metrics
      |> Map.update(:queries_processed, 1, &(&1 + 1))
      
      agent_state = %{agent_state | metrics: updated_metrics}
      
      signal_data = %{
        query: query_text,
        results: results,
        count: length(results),
        search_type: params.search_type,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, %{
        agent_state: agent_state,
        signal_data: signal_data,
        signal_type: "memory.search.result",
        result: %{results: results, count: length(results)}
      }}
    end
    
    defp parse_types(nil), do: nil
    defp parse_types(types) when is_list(types) do
      Enum.map(types, &String.to_atom/1)
    end
    defp parse_types(type) when is_binary(type) do
      [String.to_atom(type)]
    end
    
    defp search_memories(agent_state, search_query) do
      # Perform full-text search
      memory_ids = search_fulltext_index(agent_state.storage_backend, search_query.text)
      
      # Filter by types if specified
      memory_ids = if search_query.types do
        filter_by_types(agent_state.storage_backend, memory_ids, search_query.types)
      else
        memory_ids
      end
      
      # Load memories
      memories = load_memories_batch(agent_state.storage_backend, memory_ids)
      
      # Apply limit and offset
      memories
      |> Enum.drop(search_query.offset)
      |> Enum.take(search_query.limit)
    end
    
    # Placeholder functions for search operations
    defp search_fulltext_index(_backend, _query), do: []
    defp filter_by_types(_backend, ids, _types), do: ids
    defp load_memories_batch(_backend, _ids), do: []
  end
  
  # Action to execute complex queries
  defmodule QueryMemoryAction do
    use Jido.Action,
      name: "query_memory",
      description: "Execute complex memory queries with advanced filtering",
      schema: [
        query_data: [type: :map, required: true, doc: "Query parameters and filters"],
        page: [type: :integer, default: 1, doc: "Page number for pagination"],
        page_size: [type: :integer, default: 20, doc: "Number of results per page"]
      ]
    
    def run(params, context) do
      %{query_data: query_data, page: page, page_size: page_size} = params
      agent_state = context.agent.state
      
      Logger.info("Executing complex memory query")
      
      query = MemoryQuery.build(Map.merge(query_data, %{page: page, page_size: page_size}))
      
      # Execute query
      {results, total_count} = execute_query(agent_state, query)
      
      # Update cache with frequently accessed memories
      agent_state = Enum.reduce(results, agent_state, fn memory, acc ->
        update_cache(acc, memory)
      end)
      
      # Update metrics
      updated_metrics = agent_state.metrics
      |> Map.update(:queries_processed, 1, &(&1 + 1))
      
      agent_state = %{agent_state | metrics: updated_metrics}
      
      signal_data = %{
        results: results,
        total_count: total_count,
        page: page,
        page_size: page_size,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, %{
        agent_state: agent_state,
        signal_data: signal_data,
        signal_type: "memory.query.result",
        result: %{
          results: results,
          total_count: total_count,
          page: page,
          page_size: page_size
        }
      }}
    end
    
    defp execute_query(agent_state, query) do
      # Build and execute database query
      results = case agent_state.storage_backend do
        :postgresql -> execute_postgresql_query(query)
        :memory -> execute_memory_query(agent_state, query)
        _ -> []
      end
      
      # Get total count for pagination
      total_count = count_query_results(agent_state, query)
      
      {results, total_count}
    end
    
    defp update_cache(agent_state, memory) do
      if map_size(agent_state.cache) >= agent_state.config.cache_size do
        # Evict least recently accessed
        _ = evict_from_cache(agent_state)
      end
      
      put_in(agent_state.cache[memory.id], memory)
    end
    
    defp evict_from_cache(agent_state) do
      # Find least recently accessed entry
      {lru_id, _} = agent_state.cache
      |> Enum.min_by(fn {_id, memory} -> memory.accessed_at end, fn -> {nil, nil} end)
      
      if lru_id do
        update_in(agent_state.cache, &Map.delete(&1, lru_id))
      else
        agent_state
      end
    end
    
    # Placeholder functions for query execution
    defp execute_postgresql_query(_query), do: []
    defp execute_memory_query(_agent, _query), do: []
    defp count_query_results(_agent, _query), do: 0
  end

  # Action for version control operations
  defmodule VersionMemoryAction do
    use Jido.Action,
      name: "version_memory",
      description: "Manage memory versions, rollbacks, and version history",
      schema: [
        operation: [type: :string, required: true, doc: "Version operation: get_versions, rollback, or create_version"],
        memory_id: [type: :string, required: true, doc: "Memory ID to operate on"],
        target_version: [type: :integer, doc: "Target version for rollback operations"],
        updates: [type: :map, doc: "Updates to create new version"],
        reason: [type: :string, doc: "Reason for version creation"]
      ]
    
    def run(params, context) do
      %{operation: operation, memory_id: memory_id} = params
      agent_state = context.agent.state
      
      case operation do
        "get_versions" ->
          get_memory_versions(agent_state, memory_id)
        
        "rollback" ->
          target_version = Map.get(params, :target_version)
          if target_version do
            rollback_memory_version(agent_state, memory_id, target_version)
          else
            {:error, "target_version is required for rollback operation"}
          end
        
        "create_version" ->
          updates = Map.get(params, :updates, %{})
          reason = Map.get(params, :reason, "Manual version creation")
          create_memory_version(agent_state, memory_id, updates, reason)
        
        _ ->
          {:error, "Unknown version operation: #{operation}"}
      end
    end
    
    defp get_memory_versions(agent_state, memory_id) do
      versions = Map.get(agent_state.versions, memory_id, [])
      
      signal_data = %{
        memory_id: memory_id,
        versions: versions,
        version_count: length(versions),
        timestamp: DateTime.utc_now()
      }
      
      {:ok, %{
        signal_data: signal_data,
        signal_type: "memory.versions.retrieved",
        result: %{versions: versions}
      }}
    end
    
    defp rollback_memory_version(agent_state, memory_id, target_version) do
      case rollback_to_version(agent_state, memory_id, target_version) do
        {:ok, restored_memory, updated_state} ->
          signal_data = %{
            memory_id: memory_id,
            target_version: target_version,
            memory: restored_memory,
            rolled_back: true,
            timestamp: DateTime.utc_now()
          }
          
          {:ok, %{
            agent_state: updated_state,
            signal_data: signal_data,
            signal_type: "memory.version.rollback",
            result: %{memory: restored_memory, rolled_back: true}
          }}
        
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp create_memory_version(agent_state, memory_id, updates, reason) do
      case get_memory_entry(agent_state, memory_id) do
        {:ok, existing_memory} ->
          # Create version before update
          version = create_version(existing_memory, updates, reason)
          agent_state = store_version(agent_state, memory_id, version)
          
          # Apply updates
          updated_memory = MemoryEntry.update(existing_memory, updates)
          
          # Update in storage and cache
          agent_state = agent_state
          |> update_memory_in_storage(updated_memory)
          |> update_cache(updated_memory)
          |> update_indices(updated_memory)
          
          signal_data = %{
            memory_id: memory_id,
            version: updated_memory.version,
            memory: updated_memory,
            version_info: version,
            timestamp: DateTime.utc_now()
          }
          
          {:ok, %{
            agent_state: agent_state,
            signal_data: signal_data,
            signal_type: "memory.updated",
            result: %{memory: updated_memory, version: version}
          }}
        
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp get_memory_entry(agent_state, memory_id) do
      # Check cache first
      case Map.get(agent_state.cache, memory_id) do
        nil ->
          # Cache miss - load from storage
          load_from_storage(agent_state, memory_id)
        
        memory ->
          # Cache hit
          {:ok, memory}
      end
    end
    
    defp rollback_to_version(agent_state, memory_id, target_version) do
      with {:ok, memory} <- get_memory_entry(agent_state, memory_id),
           {:ok, version} <- find_version(agent_state, memory_id, target_version),
           {:ok, restored} <- apply_version(memory, version) do
        
        agent_state = agent_state
        |> update_memory_in_storage(restored)
        |> update_cache(restored)
        |> update_indices(restored)
        
        {:ok, restored, agent_state}
      end
    end
    
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
    
    defp store_version(agent_state, memory_id, version) do
      update_in(agent_state.versions[memory_id], fn versions ->
        [version | (versions || [])]
        |> Enum.take(10)  # Keep last 10 versions
      end)
    end
    
    defp find_version(agent_state, memory_id, target_version) do
      versions = Map.get(agent_state.versions, memory_id, [])
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
    
    defp calculate_changes(old_memory, updates) do
      updates
      |> Enum.map(fn {key, new_value} ->
        old_value = Map.get(old_memory, key)
        {key, %{old: old_value, new: new_value}}
      end)
      |> Map.new()
    end
    
    # Placeholder functions (reused from other actions)
    defp load_from_storage(agent_state, _memory_id) do
      case agent_state.storage_backend do
        :postgresql -> {:error, "Not implemented"}
        :memory -> {:error, "Not implemented"}
        _ -> {:error, "Unsupported storage backend"}
      end
    end
    
    defp update_memory_in_storage(agent_state, _memory) do
      Task.start(fn ->
        case agent_state.storage_backend do
          :postgresql -> :ok
          :memory -> :ok
        end
      end)
      
      agent_state
    end
    
    defp update_cache(agent_state, memory) do
      put_in(agent_state.cache[memory.id], memory)
    end
    
    defp update_indices(agent_state, memory) do
      # Update each index type
      Enum.reduce(agent_state.indices, agent_state, fn {name, index_info}, acc ->
        update_index(acc, name, index_info, memory)
      end)
    end
    
    defp update_index(agent_state, "fulltext", _index_info, memory) do
      # Update full-text search index
      text_content = extract_searchable_text(memory)
      update_fulltext_index(agent_state.storage_backend, memory.id, text_content)
      agent_state
    end
    
    defp update_index(agent_state, _name, index_info, memory) do
      # Update metadata index
      field_value = Map.get(memory, index_info.field)
      update_metadata_index(agent_state.storage_backend, index_info.field, memory.id, field_value)
      agent_state
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
    
    defp update_fulltext_index(_backend, _id, _text), do: :ok
    defp update_metadata_index(_backend, _field, _id, _value), do: :ok
  end
  
  # Action for storage optimization
  defmodule OptimizeStorageAction do
    use Jido.Action,
      name: "optimize_storage",
      description: "Run storage optimization operations",
      schema: [
        optimization_type: [type: :string, default: "full", doc: "Type of optimization: full, vacuum, reindex"],
        force: [type: :boolean, default: false, doc: "Force optimization even if recently run"]
      ]
    
    def run(params, context) do
      %{optimization_type: optimization_type, force: force} = params
      agent_state = context.agent.state
      
      Logger.info("Starting storage optimization: #{optimization_type}")
      
      # Check if optimization was recently run
      last_optimization = agent_state.metrics.last_optimization
      time_since_last = if last_optimization do
        DateTime.diff(DateTime.utc_now(), last_optimization, :second)
      else
        86400  # 24 hours ago
      end
      
      if force || time_since_last > 3600 do  # 1 hour threshold
        # Run optimization in background
        Task.start(fn -> 
          run_storage_optimization(agent_state, optimization_type)
        end)
        
        # Update metrics
        updated_metrics = Map.put(agent_state.metrics, :last_optimization, DateTime.utc_now())
        agent_state = %{agent_state | metrics: updated_metrics}
        
        signal_data = %{
          optimization_type: optimization_type,
          optimization_started: true,
          timestamp: DateTime.utc_now()
        }
        
        {:ok, %{
          agent_state: agent_state,
          signal_data: signal_data,
          signal_type: "memory.optimization.started",
          result: %{optimization_started: true}
        }}
      else
        {:ok, %{
          result: %{
            optimization_skipped: true,
            reason: "Recently optimized",
            last_optimization: last_optimization
          }
        }}
      end
    end
    
    defp run_storage_optimization(agent_state, optimization_type) do
      Logger.info("Running storage optimization: #{optimization_type}")
      
      case optimization_type do
        "full" ->
          vacuum_deleted_memories(agent_state.storage_backend)
          optimize_indices(agent_state.storage_backend)
          clean_expired_memories(agent_state.storage_backend)
        
        "vacuum" ->
          vacuum_deleted_memories(agent_state.storage_backend)
        
        "reindex" ->
          optimize_indices(agent_state.storage_backend)
        
        "cleanup" ->
          clean_expired_memories(agent_state.storage_backend)
        
        _ ->
          Logger.warning("Unknown optimization type: #{optimization_type}")
      end
      
      # Note: In a real implementation, we'd emit a signal here when done
      Logger.info("Storage optimization completed: #{optimization_type}")
    end
    
    # Placeholder functions for storage operations
    defp vacuum_deleted_memories(_backend), do: :ok
    defp optimize_indices(_backend), do: :ok
    defp clean_expired_memories(_backend), do: :ok
  end

  # Action for backup operations
  defmodule BackupMemoryAction do
    use Jido.Action,
      name: "backup_memory",
      description: "Create backups of memory data",
      schema: [
        backup_type: [type: :string, default: "full", doc: "Type of backup: full, incremental, or selective"],
        memory_types: [type: {:list, :string}, doc: "Specific memory types to backup"],
        destination: [type: :string, doc: "Backup destination path or identifier"],
        compression: [type: :boolean, default: true, doc: "Enable backup compression"]
      ]
    
    def run(params, context) do
      %{backup_type: backup_type, compression: _compression} = params
      agent_state = context.agent.state
      
      Logger.info("Starting memory backup: #{backup_type}")
      
      backup_id = generate_backup_id()
      
      # Run backup in background
      Task.start(fn -> 
        run_backup_operation(agent_state, backup_type, params, backup_id)
      end)
      
      signal_data = %{
        backup_id: backup_id,
        backup_type: backup_type,
        backup_started: true,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, %{
        signal_data: signal_data,
        signal_type: "memory.backup.started",
        result: %{backup_id: backup_id, backup_started: true}
      }}
    end
    
    defp generate_backup_id do
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      "backup_#{timestamp}_#{:rand.uniform(1000)}"
    end
    
    defp run_backup_operation(agent_state, backup_type, params, backup_id) do
      Logger.info("Running backup operation: #{backup_id}")
      
      case backup_type do
        "full" ->
          create_full_backup(agent_state, params, backup_id)
        
        "incremental" ->
          create_incremental_backup(agent_state, params, backup_id)
        
        "selective" ->
          create_selective_backup(agent_state, params, backup_id)
        
        _ ->
          Logger.error("Unknown backup type: #{backup_type}")
      end
      
      Logger.info("Backup operation completed: #{backup_id}")
    end
    
    defp create_full_backup(agent_state, params, backup_id) do
      # Export all memories
      memories = export_all_memories(agent_state.storage_backend)
      indices = agent_state.indices
      
      backup_data = %{
        backup_id: backup_id,
        backup_type: "full",
        timestamp: DateTime.utc_now(),
        memories: memories,
        indices: indices,
        metrics: agent_state.metrics
      }
      
      write_backup_data(backup_data, params)
    end
    
    defp create_incremental_backup(_agent_state, _params, backup_id) do
      Logger.info("Incremental backup not yet implemented: #{backup_id}")
    end
    
    defp create_selective_backup(agent_state, params, backup_id) do
      memory_types = Map.get(params, :memory_types, [])
      
      if length(memory_types) > 0 do
        memories = export_memories_by_type(agent_state.storage_backend, memory_types)
        
        backup_data = %{
          backup_id: backup_id,
          backup_type: "selective",
          memory_types: memory_types,
          timestamp: DateTime.utc_now(),
          memories: memories
        }
        
        write_backup_data(backup_data, params)
      else
        Logger.warning("No memory types specified for selective backup: #{backup_id}")
      end
    end
    
    # Placeholder functions for backup operations
    defp export_all_memories(_backend), do: []
    defp export_memories_by_type(_backend, _types), do: []
    defp write_backup_data(_data, _params), do: :ok
  end
  # Action for memory statistics
  defmodule GetMemoryStatsAction do
    use Jido.Action,
      name: "get_memory_stats",
      description: "Retrieve memory system statistics and metrics",
      schema: [
        include_cache_details: [type: :boolean, default: false, doc: "Include detailed cache statistics"],
        include_indices: [type: :boolean, default: false, doc: "Include index information"]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      
      Logger.info("Collecting memory statistics")
      
      stats = %{
        "total_memories" => agent_state.metrics.total_memories,
        "storage_size_mb" => agent_state.metrics.storage_size_bytes / 1_048_576,
        "index_size_mb" => agent_state.metrics.index_size_bytes / 1_048_576,
        "cache_size" => map_size(agent_state.cache),
        "cache_hit_rate" => calculate_cache_hit_rate(agent_state),
        "pending_writes" => length(agent_state.pending_writes),
        "queries_processed" => agent_state.metrics.queries_processed,
        "storage_backend" => agent_state.storage_backend,
        "compression_enabled" => agent_state.config.compression_enabled,
        "last_optimization" => agent_state.metrics.last_optimization
      }
      
      # Add optional details
      stats = if params.include_cache_details do
        Map.put(stats, "cache_details", %{
          "cache_hits" => agent_state.metrics.cache_hits,
          "cache_misses" => agent_state.metrics.cache_misses,
          "max_cache_size" => agent_state.config.cache_size
        })
      else
        stats
      end
      
      stats = if params.include_indices do
        Map.put(stats, "indices", agent_state.indices)
      else
        stats
      end
      
      signal_data = Map.merge(stats, %{
        "timestamp" => DateTime.utc_now()
      })
      
      {:ok, %{
        signal_data: signal_data,
        signal_type: "memory.stats.report",
        result: stats
      }}
    end
    
    defp calculate_cache_hit_rate(agent_state) do
      total = agent_state.metrics.cache_hits + agent_state.metrics.cache_misses
      if total > 0 do
        agent_state.metrics.cache_hits / total * 100
      else
        0.0
      end
    end
  end

  def additional_actions do
    [
      StoreMemoryAction,
      RetrieveMemoryAction,
      SearchMemoryAction,
      QueryMemoryAction,
      VersionMemoryAction,
      OptimizeStorageAction,
      BackupMemoryAction,
      GetMemoryStatsAction
    ]
  end

  @impl true
  def handle_signal(state, %{"type" => "store_memory", "data" => data} = _signal) do
    params = %{
      type: data["type"],
      content: data["content"],
      metadata: data["metadata"] || %{},
      ttl: data["ttl"],
      tags: data["tags"] || [],
      memory_id: data["memory_id"]
    }
    context = %{agent: %{state: state}}
    
    case StoreMemoryAction.run(params, context) do
      {:ok, %{agent_state: new_state, signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:long_term_memory",
          data: signal_data
        })
        {:ok, new_state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => "get_memory", "data" => data} = _signal) do
    params = %{
      memory_id: data["memory_id"],
      update_access_time: Map.get(data, "update_access_time", true)
    }
    context = %{agent: %{state: state}}
    
    case RetrieveMemoryAction.run(params, context) do
      {:ok, %{agent_state: new_state, signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:long_term_memory",
          data: signal_data
        })
        {:ok, new_state, [signal]}
      {:ok, %{signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:long_term_memory",
          data: signal_data
        })
        {:ok, state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => "search_memories", "data" => data} = _signal) do
    params = %{
      query: data["query"],
      types: data["types"],
      limit: data["limit"] || 20,
      offset: data["offset"] || 0,
      include_deleted: Map.get(data, "include_deleted", false),
      search_type: Map.get(data, "search_type", "text")
    }
    context = %{agent: %{state: state}}
    
    case SearchMemoryAction.run(params, context) do
      {:ok, %{agent_state: new_state, signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:long_term_memory",
          data: signal_data
        })
        {:ok, new_state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => "query_memories", "data" => data} = _signal) do
    params = %{
      query_data: data,
      page: Map.get(data, "page", 1),
      page_size: Map.get(data, "page_size", 20)
    }
    context = %{agent: %{state: state}}
    
    case QueryMemoryAction.run(params, context) do
      {:ok, %{agent_state: new_state, signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:long_term_memory",
          data: signal_data
        })
        {:ok, new_state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => signal_type, "data" => data} = _signal) when signal_type in ["get_memory_versions", "rollback_memory", "update_memory"] do
    operation = case signal_type do
      "get_memory_versions" -> "get_versions"
      "rollback_memory" -> "rollback"
      "update_memory" -> "create_version"
    end
    
    params = %{
      operation: operation,
      memory_id: data["memory_id"],
      target_version: data["target_version"],
      updates: data["updates"],
      reason: data["reason"]
    }
    context = %{agent: %{state: state}}
    
    case VersionMemoryAction.run(params, context) do
      {:ok, %{agent_state: new_state, signal_data: signal_data, signal_type: result_signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: result_signal_type,
          source: "agent:long_term_memory",
          data: signal_data
        })
        {:ok, new_state, [signal]}
      {:ok, %{signal_data: signal_data, signal_type: result_signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: result_signal_type,
          source: "agent:long_term_memory",
          data: signal_data
        })
        {:ok, state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => "optimize_storage", "data" => data} = _signal) do
    params = %{
      optimization_type: Map.get(data, "optimization_type", "full"),
      force: Map.get(data, "force", false)
    }
    context = %{agent: %{state: state}}
    
    case OptimizeStorageAction.run(params, context) do
      {:ok, %{agent_state: new_state, signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:long_term_memory",
          data: signal_data
        })
        {:ok, new_state, [signal]}
      {:ok, %{result: result}} ->
        {:ok, state, [], result}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => "backup_memories", "data" => data} = _signal) do
    params = %{
      backup_type: Map.get(data, "backup_type", "full"),
      memory_types: data["memory_types"],
      destination: data["destination"],
      compression: Map.get(data, "compression", true)
    }
    
    case BackupMemoryAction.run(params, nil) do
      {:ok, %{signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:long_term_memory",
          data: signal_data
        })
        {:ok, state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => "get_memory_stats", "data" => data} = _signal) do
    params = %{
      include_cache_details: Map.get(data, "include_cache_details", false),
      include_indices: Map.get(data, "include_indices", false)
    }
    context = %{agent: %{state: state}}
    
    case GetMemoryStatsAction.run(params, context) do
      {:ok, %{signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:long_term_memory",
          data: signal_data
        })
        {:ok, state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, signal) do
    Logger.warning("LongTermMemoryAgent received unknown signal: #{inspect(signal["type"])}")
    {:ok, state}
  end
end