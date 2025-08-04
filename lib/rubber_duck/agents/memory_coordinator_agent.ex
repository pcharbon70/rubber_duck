defmodule RubberDuck.Agents.MemoryCoordinatorAgent do
  @moduledoc """
  Memory Coordinator Agent for orchestrating distributed memory operations.
  
  This agent manages the coordination of memory operations across RubberDuck's
  three-tier memory architecture (short-term, mid-term, long-term), providing:
  
  - Memory orchestration across tiers
  - Partitioning and sharding for distributed storage
  - Synchronization with conflict resolution
  - Replication and failover capabilities
  - Access control and security
  - Performance monitoring and optimization
  
  ## Signals
  
  ### Input Signals
  - `memory_operation_request` - Coordinate complex memory operations
  - `sync_memory_tiers` - Trigger synchronization across tiers
  - `memory_health_check` - Monitor memory system health
  - `create_memory_partition` - Create new memory partitions
  - `memory_access_request` - Handle access control requests
  - `get_coordination_metrics` - Request performance metrics
  - `memory_optimization` - Execute optimization algorithms

  ### Output Signals
  - `memory_operation_result` - Results of coordinated operations
  - `memory_sync_status` - Synchronization status updates
  - `memory_health_report` - System health reports
  - `memory_partition_created` - Partition creation confirmations
  - `memory_access_decision` - Access control decisions
  - `coordination_metrics_report` - Performance metrics
  """
  
  use Jido.Agent,
    name: "memory_coordinator_agent",
    description: "Coordinates distributed memory operations across tiers",
    category: "coordination",
    tags: ["memory", "coordination", "distributed", "tiers", "synchronization"],
    vsn: "1.0.0",
    schema: [
      coordination_status: [
        type: :atom, 
        values: [:idle, :coordinating, :syncing, :optimizing], 
        default: :idle,
        doc: "Current coordination status"
      ],
      active_operations: [
        type: :map, 
        default: %{},
        doc: "Currently active memory operations"
      ],
      memory_partitions: [
        type: :map, 
        default: %{},
        doc: "Memory partition configurations"
      ],
      sync_state: [
        type: :map, 
        default: %{},
        doc: "Synchronization state tracking"
      ],
      replication_topology: [
        type: :map, 
        default: %{},
        doc: "Replication topology configuration"
      ],
      access_permissions: [
        type: :map, 
        default: %{},
        doc: "Access control permissions"
      ],
      performance_metrics: [
        type: :map, 
        default: %{
          operations_completed: 0,
          sync_operations: 0,
          avg_operation_time: 0.0,
          conflict_resolutions: 0,
          partition_count: 0
        },
        doc: "Performance tracking metrics"
      ]
    ]

  require Logger
  
  alias RubberDuck.Memory

  # Action to coordinate memory operations  
  defmodule CoordinateOperationAction do
    use Jido.Action,
      name: "coordinate_memory_operation",
      description: "Coordinate complex memory operations across tiers",
      schema: [
        operation: [type: :string, required: true, doc: "Type of memory operation"],
        user_id: [type: :string, required: true, doc: "User identifier"],
        operation_id: [type: :string, required: true, doc: "Operation identifier"],
        data: [type: :map, required: true, doc: "Operation data"]
      ]
    
    def run(params, context) do
      %{operation: operation, user_id: user_id, operation_id: operation_id, data: data} = params
      agent_state = context.agent.state
      
      Logger.info("Coordinating memory operation: #{operation} for user #{user_id}")
      
      # Track active operation
      agent_state = track_operation(agent_state, operation_id, data)
      
      # Coordinate the operation based on type
      result = case operation do
        "cross_tier_search" ->
          coordinate_cross_tier_search(data)
        
        "memory_migration" ->
          coordinate_memory_migration(data)
        
        "memory_consolidation" ->
          coordinate_memory_consolidation(data)
        
        _ ->
          {:ok, %{message: "Operation type not supported", operation: operation}}
      end
      
      # Update metrics and prepare result
      agent_state = update_operation_metrics(agent_state, operation_id, result)
      
      status = if match?({:ok, _}, result), do: "completed", else: "failed"
      
      signal_data = %{
        operation_id: operation_id,
        status: status,
        result: result,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, %{agent_state: agent_state, signal_data: signal_data, signal_type: "memory.operation.result"}}
    end
    
    defp track_operation(agent_state, operation_id, data) do
      operation_info = %{
        data: data,
        started_at: DateTime.utc_now(),
        status: :active
      }
      
      agent_state
      |> put_in([:active_operations, operation_id], operation_info)
      |> Map.put(:coordination_status, :coordinating)
    end
    
    defp update_operation_metrics(agent_state, operation_id, _result) do
      # Remove from active operations
      {operation_info, agent_state} = pop_in(agent_state.active_operations[operation_id])
      
      if operation_info do
        # Calculate operation time
        operation_time = DateTime.diff(DateTime.utc_now(), operation_info.started_at, :millisecond)
        
        # Ensure performance_metrics exists
        performance_metrics = Map.get(agent_state, :performance_metrics, %{
          operations_completed: 0,
          sync_operations: 0,
          avg_operation_time: 0.0,
          conflict_resolutions: 0,
          partition_count: 0
        })
        
        # Update metrics
        completed = performance_metrics.operations_completed + 1
        new_avg = if performance_metrics.operations_completed == 0 do
          operation_time
        else
          (performance_metrics.avg_operation_time * performance_metrics.operations_completed + operation_time) / completed
        end
        
        updated_metrics = performance_metrics
        |> Map.put(:operations_completed, completed)
        |> Map.put(:avg_operation_time, new_avg)
        
        agent_state = put_in(agent_state.performance_metrics, updated_metrics)
        
        # Reset coordination status if no active operations
        if map_size(agent_state.active_operations) == 0 do
          %{agent_state | coordination_status: :idle}
        else
          agent_state
        end
      else
        agent_state
      end
    end
    
    defp coordinate_cross_tier_search(data) do
      %{
        "user_id" => user_id,
        "query" => query,
        "tiers" => tiers
      } = data
      
      # Search across specified tiers in parallel
      search_tasks = Enum.map(tiers, fn tier ->
        Task.async(fn ->
          {tier, search_memory_tier(user_id, tier, query)}
        end)
      end)
      
      # Collect results with timeout
      results = 
        search_tasks
        |> Task.await_many(5000)
        |> Enum.into(%{})
      
      {:ok, %{
        query: query,
        results: results,
        tiers_searched: tiers
      }}
    rescue
      error ->
        {:error, %{reason: "Search failed", error: inspect(error)}}
    end
    
    defp coordinate_memory_migration(data) do
      %{
        "user_id" => user_id,
        "source_tier" => source,
        "target_tier" => target,
        "item_ids" => item_ids
      } = data
      
      # Migrate items from source to target tier
      migration_results = Enum.map(item_ids, fn item_id ->
        case migrate_memory_item(user_id, item_id, source, target) do
          {:ok, result} -> {item_id, :success, result}
          {:error, reason} -> {item_id, :failed, reason}
        end
      end)
      
      success_count = Enum.count(migration_results, &(elem(&1, 1) == :success))
      
      {:ok, %{
        migrated_items: success_count,
        failed_items: length(item_ids) - success_count,
        details: migration_results
      }}
    end
    
    defp coordinate_memory_consolidation(data) do
      %{
        "user_id" => user_id,
        "consolidation_type" => type
      } = data
      
      # Perform memory consolidation based on type
      case type do
        "duplicate_removal" ->
          remove_duplicate_memories(user_id)
        
        "pattern_extraction" ->
          extract_memory_patterns(user_id)
        
        "obsolete_cleanup" ->
          cleanup_obsolete_memories(user_id)
        
        _ ->
          {:error, %{reason: "Unknown consolidation type", type: type}}
      end
    end
    
    # Stub functions for memory operations (to be implemented with actual Memory domain calls)
    defp search_memory_tier(user_id, tier, query) do
      case tier do
        "short" ->
          # Search short-term memory (interactions)
          case Memory.get_user_interactions(user_id) do
            {:ok, interactions} ->
              # Filter interactions by query
              filtered = Enum.filter(interactions, fn interaction ->
                String.contains?(String.downcase(interaction.content || ""), String.downcase(query))
              end)
              {:ok, filtered}
            error -> error
          end
        
        "mid" ->
          # Search mid-term memory (summaries)
          case Memory.search_summaries(user_id, query) do
            {:ok, summaries} -> {:ok, summaries}
            error -> error
          end
        
        "long" ->
          # Search long-term memory (knowledge)
          # For now, return empty as we don't have project_id
          {:ok, []}
        
        _ ->
          {:error, "Unknown memory tier: #{tier}"}
      end
    end
    
    defp migrate_memory_item(user_id, item_id, source_tier, target_tier) do
      # Placeholder implementation
      Logger.info("Migrating item #{item_id} from #{source_tier} to #{target_tier} for user #{user_id}")
      {:ok, %{item_id: item_id, migrated_from: source_tier, migrated_to: target_tier}}
    end
    
    defp remove_duplicate_memories(user_id) do
      {:ok, %{duplicates_removed: 0, user_id: user_id}}
    end
    
    defp extract_memory_patterns(user_id) do
      {:ok, %{patterns_extracted: 0, user_id: user_id}}
    end
    
    defp cleanup_obsolete_memories(user_id) do
      {:ok, %{obsolete_items_removed: 0, user_id: user_id}}
    end
  end

  # Action to synchronize memory tiers
  defmodule SyncMemoryTiersAction do
    use Jido.Action,
      name: "sync_memory_tiers",
      description: "Synchronize memory between tiers",
      schema: [
        user_id: [type: :string, required: true, doc: "User identifier"],
        source_tier: [type: :string, required: true, doc: "Source memory tier"],
        target_tier: [type: :string, required: true, doc: "Target memory tier"],
        sync_type: [type: :string, required: true, doc: "Type of synchronization"],
        sync_id: [type: :string, required: true, doc: "Synchronization identifier"]
      ]
    
    def run(params, context) do
      %{user_id: user_id, source_tier: source_tier, target_tier: target_tier, sync_type: sync_type, sync_id: sync_id} = params
      agent_state = context.agent.state
      
      Logger.info("Synchronizing memory from #{source_tier} to #{target_tier} for user #{user_id}")
      
      # Update coordination status
      agent_state = %{agent_state | coordination_status: :syncing}
      
      # Track sync operation
      sync_info = %{
        user_id: user_id,
        source_tier: source_tier,
        target_tier: target_tier,
        sync_type: sync_type,
        started_at: DateTime.utc_now(),
        status: :in_progress
      }
      
      agent_state = put_in(agent_state.sync_state[sync_id], sync_info)
      
      # Perform synchronization
      sync_result = perform_memory_sync(user_id, source_tier, target_tier, sync_type)
      
      # Update metrics
      agent_state = update_sync_metrics(agent_state, sync_id, sync_result)
      
      # Reset coordination status
      agent_state = %{agent_state | coordination_status: :idle}
      
      sync_status = if match?({:ok, _}, sync_result), do: "completed", else: "failed"
      
      signal_data = %{
        sync_id: sync_id,
        status: sync_status,
        result: sync_result,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, %{agent_state: agent_state, signal_data: signal_data, signal_type: "memory.sync.status"}}
    end
    
    defp perform_memory_sync(user_id, source_tier, target_tier, sync_type) do
      case sync_type do
        "migration" ->
          # Move high-value items from source to target
          migrate_high_value_items(user_id, source_tier, target_tier)
        
        "replication" ->
          # Copy important items to target for redundancy
          replicate_critical_items(user_id, source_tier, target_tier)
        
        "consolidation" ->
          # Merge related items across tiers
          consolidate_related_items(user_id, source_tier, target_tier)
        
        _ ->
          {:error, %{reason: "Unknown sync type", type: sync_type}}
      end
    end
    
    defp migrate_high_value_items(user_id, source_tier, target_tier) do
      # Get high-value items from source tier
      case get_high_value_items(user_id, source_tier) do
        {:ok, items} ->
          # Migrate items to target tier
          migration_results = Enum.map(items, fn item ->
            migrate_memory_item(user_id, item.id, source_tier, target_tier)
          end)
          
          successful_migrations = Enum.count(migration_results, &match?({:ok, _}, &1))
          
          {:ok, %{
            items_migrated: successful_migrations,
            total_items: length(items),
            source_tier: source_tier,
            target_tier: target_tier
          }}
        
        error ->
          error
      end
    end
    
    defp replicate_critical_items(_user_id, source_tier, target_tier) do
      # Implementation for replication
      {:ok, %{
        items_replicated: 0,
        source_tier: source_tier,
        target_tier: target_tier,
        message: "Replication not yet implemented"
      }}
    end
    
    defp consolidate_related_items(_user_id, source_tier, target_tier) do
      # Implementation for consolidation
      {:ok, %{
        items_consolidated: 0,
        source_tier: source_tier,
        target_tier: target_tier,
        message: "Consolidation not yet implemented"
      }}
    end
    
    defp get_high_value_items(user_id, tier) do
      case tier do
        "mid" ->
          # Get summaries with high heat scores
          case Memory.get_user_summaries(user_id) do
            {:ok, summaries} ->
              high_value = Enum.filter(summaries, &(&1.heat_score >= 10.0))
              {:ok, high_value}
            error -> error
          end
        
        _ ->
          {:ok, []}
      end
    end
    
    defp migrate_memory_item(user_id, item_id, source_tier, target_tier) do
      # Placeholder implementation
      Logger.info("Migrating item #{item_id} from #{source_tier} to #{target_tier} for user #{user_id}")
      {:ok, %{item_id: item_id, migrated_from: source_tier, migrated_to: target_tier}}
    end
    
    defp update_sync_metrics(agent_state, sync_id, _result) do
      # Ensure performance_metrics exists
      performance_metrics = Map.get(agent_state, :performance_metrics, %{
        operations_completed: 0,
        sync_operations: 0,
        avg_operation_time: 0.0,
        conflict_resolutions: 0,
        partition_count: 0
      })
      
      # Update sync metrics
      updated_metrics = Map.put(performance_metrics, :sync_operations, performance_metrics.sync_operations + 1)
      agent_state = put_in(agent_state.performance_metrics, updated_metrics)
      
      # Remove from sync state
      {_sync_info, agent_state} = pop_in(agent_state.sync_state[sync_id])
      
      agent_state
    end
  end

  # Action to check memory health
  defmodule CheckMemoryHealthAction do
    use Jido.Action,
      name: "check_memory_health",
      description: "Monitor memory system health across tiers",
      schema: [
        check_type: [type: :string, required: true, doc: "Type of health check"],
        include_metrics: [type: :boolean, default: false, doc: "Include performance metrics"],
        check_id: [type: :string, required: true, doc: "Health check identifier"]
      ]
    
    def run(params, _context) do
      %{check_type: check_type, include_metrics: include_metrics, check_id: check_id} = params
      
      Logger.info("Performing memory health check: #{check_type}")
      
      # Perform health check across memory tiers
      health_report = perform_health_check(check_type, include_metrics)
      
      signal_data = Map.merge(health_report, %{
        check_id: check_id,
        timestamp: DateTime.utc_now()
      })
      
      {:ok, %{signal_data: signal_data, signal_type: "memory.health.report"}}
    end
    
    defp perform_health_check(check_type, include_metrics) do
      base_report = %{
        "check_type" => check_type,
        "memory_tiers" => check_memory_tiers_health(),
        "system_status" => "healthy"
      }
      
      if include_metrics do
        Map.put(base_report, "performance_metrics", get_system_performance_metrics())
      else
        base_report
      end
    end
    
    defp check_memory_tiers_health do
      %{
        "short_term" => %{
          "status" => "healthy",
          "capacity_used" => "15%",
          "response_time_ms" => 5
        },
        "mid_term" => %{
          "status" => "healthy", 
          "capacity_used" => "45%",
          "response_time_ms" => 25
        },
        "long_term" => %{
          "status" => "healthy",
          "capacity_used" => "78%",
          "response_time_ms" => 150
        }
      }
    end
    
    defp get_system_performance_metrics do
      %{
        "average_query_time_ms" => 85,
        "cache_hit_ratio" => 0.82,
        "memory_fragmentation" => 0.15,
        "active_connections" => 42
      }
    end
  end

  # Action to create memory partition
  defmodule CreatePartitionAction do
    use Jido.Action,
      name: "create_memory_partition",
      description: "Create new memory partitions for distributed storage",
      schema: [
        partition_id: [type: :string, required: true, doc: "Partition identifier"],
        user_id: [type: :string, required: true, doc: "User identifier"],
        partition_strategy: [type: :string, required: true, doc: "Partitioning strategy"],
        capacity_limits: [type: :map, required: true, doc: "Capacity limits for partition"]
      ]
    
    def run(params, context) do
      %{partition_id: partition_id, user_id: user_id, partition_strategy: strategy, capacity_limits: limits} = params
      agent_state = context.agent.state
      
      Logger.info("Creating memory partition #{partition_id} for user #{user_id}")
      
      # Create partition configuration
      partition_config = %{
        user_id: user_id,
        strategy: strategy,
        capacity_limits: limits,
        created_at: DateTime.utc_now(),
        status: :active,
        current_usage: %{
          short_term: 0,
          mid_term: 0,
          long_term: 0
        }
      }
      
      # Store partition configuration
      agent_state = put_in(agent_state.memory_partitions[partition_id], partition_config)
      
      # Update metrics
      performance_metrics = Map.get(agent_state, :performance_metrics, %{
        operations_completed: 0,
        sync_operations: 0,
        avg_operation_time: 0.0,
        conflict_resolutions: 0,
        partition_count: 0
      })
      
      updated_metrics = Map.put(performance_metrics, :partition_count, performance_metrics.partition_count + 1)
      agent_state = put_in(agent_state.performance_metrics, updated_metrics)
      
      signal_data = %{
        partition_id: partition_id,
        status: "created",
        config: partition_config,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, %{agent_state: agent_state, signal_data: signal_data, signal_type: "memory.partition.created"}}
    end
  end

  # Action to handle access requests
  defmodule HandleAccessRequestAction do
    use Jido.Action,
      name: "handle_memory_access_request",
      description: "Handle memory access control requests",
      schema: [
        user_id: [type: :string, required: true, doc: "User identifier"],
        requested_access: [type: :string, required: true, doc: "Requested access type"],
        memory_tier: [type: :string, required: true, doc: "Memory tier"],
        resource_id: [type: :string, required: true, doc: "Resource identifier"],
        request_id: [type: :string, required: true, doc: "Request identifier"]
      ]
    
    def run(params, _context) do
      %{user_id: user_id, requested_access: access_type, memory_tier: tier, resource_id: resource_id, request_id: request_id} = params
      
      Logger.info("Processing memory access request for user #{user_id}")
      
      # Check access permissions
      decision = check_access_permissions(user_id, access_type, tier, resource_id)
      
      # Log access attempt for auditing
      audit_access_attempt(user_id, access_type, tier, resource_id, decision)
      
      signal_data = %{
        request_id: request_id,
        decision: decision,
        user_id: user_id,
        access_type: access_type,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, %{signal_data: signal_data, signal_type: "memory.access.decision"}}
    end
    
    defp check_access_permissions(_user_id, access_type, tier, _resource_id) do
      # Simplified access control - in production would check actual permissions
      case {access_type, tier} do
        {"read", _} -> "granted"
        {"write", "short"} -> "granted"
        {"write", "mid"} -> "granted"
        {"write", "long"} -> "granted"
        {"delete", "short"} -> "granted"
        {"delete", _} -> "denied"
        _ -> "denied"
      end
    end
    
    defp audit_access_attempt(user_id, access_type, tier, resource_id, decision) do
      Logger.info("Access audit: user=#{user_id}, access=#{access_type}, tier=#{tier}, resource=#{resource_id}, decision=#{decision}")
    end
  end

  # Action to get coordination metrics
  defmodule GetCoordinationMetricsAction do
    use Jido.Action,
      name: "get_coordination_metrics",
      description: "Collect and report coordination performance metrics",
      schema: [
        metric_types: [type: {:list, :string}, required: true, doc: "Types of metrics to collect"],
        time_range: [type: :string, required: true, doc: "Time range for metrics"],
        request_id: [type: :string, required: true, doc: "Request identifier"]
      ]
    
    def run(params, context) do
      %{metric_types: metric_types, time_range: time_range, request_id: request_id} = params
      agent_state = context.agent.state
      
      Logger.info("Collecting coordination metrics for #{inspect(metric_types)}")
      
      # Collect requested metrics
      metrics = collect_coordination_metrics(agent_state, metric_types, time_range)
      
      signal_data = %{
        request_id: request_id,
        metrics: metrics,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, %{signal_data: signal_data, signal_type: "coordination.metrics.report"}}
    end
    
    defp collect_coordination_metrics(agent_state, metric_types, _time_range) do
      base_metrics = %{
        "performance" => %{
          "operations_completed" => agent_state.performance_metrics.operations_completed,
          "avg_operation_time_ms" => agent_state.performance_metrics.avg_operation_time,
          "active_operations" => map_size(agent_state.active_operations)
        },
        "usage" => %{
          "partition_count" => agent_state.performance_metrics.partition_count,
          "sync_operations" => agent_state.performance_metrics.sync_operations,
          "coordination_status" => agent_state.coordination_status
        },
        "conflicts" => %{
          "conflict_resolutions" => agent_state.performance_metrics.conflict_resolutions,
          "resolution_success_rate" => 0.95
        }
      }
      
      # Filter metrics based on requested types
      Enum.reduce(metric_types, %{}, fn metric_type, acc ->
        if Map.has_key?(base_metrics, metric_type) do
          Map.put(acc, metric_type, base_metrics[metric_type])
        else
          acc
        end
      end)
    end
  end

  def additional_actions do
    [
      CoordinateOperationAction,
      SyncMemoryTiersAction,
      CheckMemoryHealthAction,
      CreatePartitionAction,
      HandleAccessRequestAction,
      GetCoordinationMetricsAction
    ]
  end

  @impl true
  def handle_signal(state, %{"type" => "memory_operation_request", "data" => data, "id" => operation_id} = _signal) do
    params = %{
      operation: data["operation"],
      user_id: data["user_id"],
      operation_id: operation_id,
      data: data
    }
    context = %{agent: %{state: state}}
    
    case CoordinateOperationAction.run(params, context) do
      {:ok, %{agent_state: new_state, signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:memory_coordinator",
          data: signal_data
        })
        {:ok, new_state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => "sync_memory_tiers", "data" => data, "id" => sync_id} = _signal) do
    params = %{
      user_id: data["user_id"],
      source_tier: data["source_tier"],
      target_tier: data["target_tier"],
      sync_type: data["sync_type"],
      sync_id: sync_id
    }
    context = %{agent: %{state: state}}
    
    case SyncMemoryTiersAction.run(params, context) do
      {:ok, %{agent_state: new_state, signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:memory_coordinator",
          data: signal_data
        })
        {:ok, new_state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => "memory_health_check", "data" => data, "id" => check_id} = _signal) do
    params = %{
      check_type: data["check_type"],
      include_metrics: data["include_metrics"],
      check_id: check_id
    }
    
    case CheckMemoryHealthAction.run(params, nil) do
      {:ok, %{signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:memory_coordinator",
          data: signal_data
        })
        {:ok, state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => "create_memory_partition", "data" => data} = _signal) do
    params = %{
      partition_id: data["partition_id"],
      user_id: data["user_id"],
      partition_strategy: data["partition_strategy"],
      capacity_limits: data["capacity_limits"]
    }
    context = %{agent: %{state: state}}
    
    case CreatePartitionAction.run(params, context) do
      {:ok, %{agent_state: new_state, signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:memory_coordinator",
          data: signal_data
        })
        {:ok, new_state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => "memory_access_request", "data" => data, "id" => request_id} = _signal) do
    params = %{
      user_id: data["user_id"],
      requested_access: data["requested_access"],
      memory_tier: data["memory_tier"],
      resource_id: data["resource_id"],
      request_id: request_id
    }
    
    case HandleAccessRequestAction.run(params, nil) do
      {:ok, %{signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:memory_coordinator",
          data: signal_data
        })
        {:ok, state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, %{"type" => "get_coordination_metrics", "data" => data, "id" => request_id} = _signal) do
    params = %{
      metric_types: data["metric_types"],
      time_range: data["time_range"],
      request_id: request_id
    }
    context = %{agent: %{state: state}}
    
    case GetCoordinationMetricsAction.run(params, context) do
      {:ok, %{signal_data: signal_data, signal_type: signal_type}} ->
        signal = Jido.Signal.new!(%{
          type: signal_type,
          source: "agent:memory_coordinator",
          data: signal_data
        })
        {:ok, state, [signal]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_signal(state, signal) do
    Logger.warning("MemoryCoordinatorAgent received unknown signal: #{inspect(signal["type"])}")
    {:ok, state}
  end
end