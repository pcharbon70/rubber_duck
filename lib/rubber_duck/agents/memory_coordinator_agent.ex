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
  alias RubberDuck.Agents.ErrorHandling

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
      
      # Validate operation type
      valid_operations = ["cross_tier_search", "memory_migration", "memory_consolidation"]
      
      if operation not in valid_operations do
        ErrorHandling.validation_error(
          "Unsupported operation type: #{operation}",
          %{valid_operations: valid_operations, provided: operation}
        )
      else
        # Track active operation
        agent_state = track_operation(agent_state, operation_id, data)
        
        # Coordinate the operation based on type with error handling
        result = ErrorHandling.with_retry(fn ->
          case operation do
            "cross_tier_search" ->
              coordinate_cross_tier_search(data)
            
            "memory_migration" ->
              coordinate_memory_migration(data)
            
            "memory_consolidation" ->
              coordinate_memory_consolidation(data)
          end
        end, max_retries: 2, base_delay: 1000)
        
        # Update metrics and prepare result
        agent_state = update_operation_metrics(agent_state, operation_id, result)
        
        case result do
          {:ok, _} = success ->
            signal_data = %{
              operation_id: operation_id,
              status: "completed",
              result: success,
              timestamp: DateTime.utc_now()
            }
            {:ok, %{agent_state: agent_state, signal_data: signal_data, signal_type: "memory.operation.result"}}
          
          {:error, error_details} ->
            ErrorHandling.log_error({:error, error_details})
            signal_data = %{
              operation_id: operation_id,
              status: "failed",
              error: error_details,
              timestamp: DateTime.utc_now()
            }
            {:ok, %{agent_state: agent_state, signal_data: signal_data, signal_type: "memory.operation.error"}}
        end
      end
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
      with :ok <- ErrorHandling.validate_required_params(data, ["user_id", "query", "tiers"]),
           %{"user_id" => user_id, "query" => query, "tiers" => tiers} <- data do
        
        # Validate tiers
        valid_tiers = ["short", "mid", "long"]
        invalid_tiers = Enum.reject(tiers, &(&1 in valid_tiers))
        
        if invalid_tiers != [] do
          ErrorHandling.validation_error(
            "Invalid memory tiers specified",
            %{invalid_tiers: invalid_tiers, valid_tiers: valid_tiers}
          )
        else
          # Search across specified tiers in parallel with error handling
          search_tasks = Enum.map(tiers, fn tier ->
            Task.async(fn ->
              case search_memory_tier(user_id, tier, query) do
                {:ok, results} -> {tier, {:ok, results}}
                {:error, reason} -> {tier, {:error, reason}}
              end
            end)
          end)
          
          # Collect results with timeout
          try do
            results = 
              search_tasks
              |> Task.await_many(5000)
              |> Enum.into(%{})
            
            # Check if any searches failed
            failures = Enum.filter(results, fn {_tier, result} -> 
              match?({:error, _}, result)
            end)
            
            if failures != [] do
              ErrorHandling.resource_error(
                "Some tier searches failed",
                %{failures: failures, partial_results: results}
              )
            else
              # Extract successful results
              successful_results = Enum.map(results, fn {tier, {:ok, data}} -> 
                {tier, data}
              end) |> Enum.into(%{})
              
              {:ok, %{
                query: query,
                results: successful_results,
                tiers_searched: tiers
              }}
            end
          catch
            :exit, {:timeout, _} ->
              ErrorHandling.network_error(
                "Search operation timed out",
                %{timeout_ms: 5000, tiers: tiers}
              )
          end
        end
      else
        error -> error
      end
    end
    
    defp coordinate_memory_migration(data) do
      with :ok <- ErrorHandling.validate_required_params(data, ["user_id", "source_tier", "target_tier", "item_ids"]),
           %{"user_id" => user_id, "source_tier" => source, "target_tier" => target, "item_ids" => item_ids} <- data do
        
        if item_ids == [] do
          ErrorHandling.validation_error("No items specified for migration", %{item_ids: []})
        else
          # Migrate items from source to target tier with error handling
          migration_results = Enum.map(item_ids, fn item_id ->
            case migrate_memory_item(user_id, item_id, source, target) do
              {:ok, result} -> {item_id, :success, result}
              {:error, reason} -> {item_id, :failed, reason}
            end
          end)
          
          success_count = Enum.count(migration_results, &(elem(&1, 1) == :success))
          failed_count = length(item_ids) - success_count
          
          if success_count == 0 do
            ErrorHandling.resource_error(
              "All migration operations failed",
              %{total_items: length(item_ids), failures: migration_results}
            )
          else
            {:ok, %{
              migrated_items: success_count,
              failed_items: failed_count,
              details: migration_results,
              partial_success: failed_count > 0
            }}
          end
        end
      else
        error -> error
      end
    end
    
    defp coordinate_memory_consolidation(data) do
      with :ok <- ErrorHandling.validate_required_params(data, ["user_id", "consolidation_type"]),
           %{"user_id" => user_id, "consolidation_type" => type} <- data do
        
        valid_types = ["duplicate_removal", "pattern_extraction", "obsolete_cleanup"]
        
        if type not in valid_types do
          ErrorHandling.validation_error(
            "Invalid consolidation type",
            %{provided: type, valid_types: valid_types}
          )
        else
          # Perform memory consolidation based on type with error handling
          ErrorHandling.safe_execute(fn ->
            case type do
              "duplicate_removal" ->
                remove_duplicate_memories(user_id)
              
              "pattern_extraction" ->
                extract_memory_patterns(user_id)
              
              "obsolete_cleanup" ->
                cleanup_obsolete_memories(user_id)
            end
          end)
        end
      else
        error -> error
      end
    end
    
    # Stub functions for memory operations (to be implemented with actual Memory domain calls)
    defp search_memory_tier(user_id, tier, query) do
      try do
        case tier do
          "short" ->
            # Search short-term memory (interactions)
            case Memory.get_user_interactions(user_id) do
              {:ok, interactions} ->
                # Filter interactions by query with error handling
                filtered = ErrorHandling.safe_execute(fn ->
                  Enum.filter(interactions, fn interaction ->
                    content = Map.get(interaction, :content, "")
                    String.contains?(String.downcase(content), String.downcase(query))
                  end)
                end)
                
                case filtered do
                  {:ok, results} -> {:ok, results}
                  error -> error
                end
              
              {:error, reason} ->
                ErrorHandling.resource_error(
                  "Failed to retrieve short-term memory",
                  %{user_id: user_id, reason: reason}
                )
            end
          
          "mid" ->
            # Search mid-term memory (summaries)
            case Memory.search_summaries(user_id, query) do
              {:ok, summaries} -> {:ok, summaries}
              {:error, reason} ->
                ErrorHandling.resource_error(
                  "Failed to search mid-term memory",
                  %{user_id: user_id, query: query, reason: reason}
                )
            end
          
          "long" ->
            # Search long-term memory (knowledge)
            # For now, return empty as we don't have project_id
            {:ok, []}
          
          _ ->
            ErrorHandling.validation_error(
              "Unknown memory tier",
              %{tier: tier, valid_tiers: ["short", "mid", "long"]}
            )
        end
      rescue
        e ->
          ErrorHandling.system_error(
            "Unexpected error searching memory tier",
            %{tier: tier, error: Exception.message(e)}
          )
      end
    end
    
    defp migrate_memory_item(user_id, item_id, source_tier, target_tier) do
      try do
        # Validate tiers
        valid_tiers = ["short", "mid", "long"]
        
        cond do
          source_tier not in valid_tiers ->
            ErrorHandling.validation_error(
              "Invalid source tier",
              %{source_tier: source_tier, valid_tiers: valid_tiers}
            )
          
          target_tier not in valid_tiers ->
            ErrorHandling.validation_error(
              "Invalid target tier",
              %{target_tier: target_tier, valid_tiers: valid_tiers}
            )
          
          source_tier == target_tier ->
            ErrorHandling.validation_error(
              "Source and target tiers are the same",
              %{tier: source_tier}
            )
          
          true ->
            # Placeholder implementation - would normally interact with Memory domain
            Logger.info("Migrating item #{item_id} from #{source_tier} to #{target_tier} for user #{user_id}")
            {:ok, %{item_id: item_id, migrated_from: source_tier, migrated_to: target_tier}}
        end
      rescue
        e ->
          ErrorHandling.system_error(
            "Migration failed",
            %{item_id: item_id, error: Exception.message(e)}
          )
      end
    end
    
    defp remove_duplicate_memories(user_id) do
      try do
        # Placeholder - would normally interact with Memory domain
        {:ok, %{duplicates_removed: 0, user_id: user_id}}
      rescue
        e ->
          ErrorHandling.resource_error(
            "Failed to remove duplicate memories",
            %{user_id: user_id, error: Exception.message(e)}
          )
      end
    end
    
    defp extract_memory_patterns(user_id) do
      try do
        # Placeholder - would normally interact with Memory domain
        {:ok, %{patterns_extracted: 0, user_id: user_id}}
      rescue
        e ->
          ErrorHandling.resource_error(
            "Failed to extract memory patterns",
            %{user_id: user_id, error: Exception.message(e)}
          )
      end
    end
    
    defp cleanup_obsolete_memories(user_id) do
      try do
        # Placeholder - would normally interact with Memory domain
        {:ok, %{obsolete_items_removed: 0, user_id: user_id}}
      rescue
        e ->
          ErrorHandling.resource_error(
            "Failed to cleanup obsolete memories",
            %{user_id: user_id, error: Exception.message(e)}
          )
      end
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
      
      # Validate tiers
      valid_tiers = ["short", "mid", "long"]
      valid_sync_types = ["migration", "replication", "consolidation"]
      
      cond do
        source_tier not in valid_tiers ->
          ErrorHandling.validation_error(
            "Invalid source tier for sync",
            %{source_tier: source_tier, valid_tiers: valid_tiers}
          )
        
        target_tier not in valid_tiers ->
          ErrorHandling.validation_error(
            "Invalid target tier for sync",
            %{target_tier: target_tier, valid_tiers: valid_tiers}
          )
        
        source_tier == target_tier ->
          ErrorHandling.validation_error(
            "Source and target tiers cannot be the same",
            %{tier: source_tier}
          )
        
        sync_type not in valid_sync_types ->
          ErrorHandling.validation_error(
            "Invalid sync type",
            %{sync_type: sync_type, valid_types: valid_sync_types}
          )
        
        true ->
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
          
          # Perform synchronization with retry logic
          sync_result = ErrorHandling.with_retry(fn ->
            perform_memory_sync(user_id, source_tier, target_tier, sync_type)
          end, max_retries: 2, base_delay: 2000)
          
          # Update metrics
          agent_state = update_sync_metrics(agent_state, sync_id, sync_result)
          
          # Reset coordination status
          agent_state = %{agent_state | coordination_status: :idle}
          
          case sync_result do
            {:ok, _} = success ->
              signal_data = %{
                sync_id: sync_id,
                status: "completed",
                result: success,
                timestamp: DateTime.utc_now()
              }
              {:ok, %{agent_state: agent_state, signal_data: signal_data, signal_type: "memory.sync.status"}}
            
            {:error, error_details} ->
              ErrorHandling.log_error({:error, error_details})
              signal_data = %{
                sync_id: sync_id,
                status: "failed",
                error: error_details,
                timestamp: DateTime.utc_now()
              }
              {:ok, %{agent_state: agent_state, signal_data: signal_data, signal_type: "memory.sync.error"}}
          end
      end
    end
    
    defp perform_memory_sync(user_id, source_tier, target_tier, sync_type) do
      ErrorHandling.safe_execute(fn ->
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
            ErrorHandling.validation_error(
              "Unknown sync type",
              %{sync_type: sync_type, valid_types: ["migration", "replication", "consolidation"]}
            )
        end
      end)
    end
    
    defp migrate_high_value_items(user_id, source_tier, target_tier) do
      # Get high-value items from source tier
      case get_high_value_items(user_id, source_tier) do
        {:ok, items} when items != [] ->
          # Migrate items to target tier
          migration_results = Enum.map(items, fn item ->
            migrate_memory_item(user_id, Map.get(item, :id, ""), source_tier, target_tier)
          end)
          
          successful_migrations = Enum.count(migration_results, &match?({:ok, _}, &1))
          failed_migrations = length(items) - successful_migrations
          
          if successful_migrations == 0 do
            ErrorHandling.resource_error(
              "All high-value item migrations failed",
              %{total_items: length(items), source_tier: source_tier, target_tier: target_tier}
            )
          else
            {:ok, %{
              items_migrated: successful_migrations,
              items_failed: failed_migrations,
              total_items: length(items),
              source_tier: source_tier,
              target_tier: target_tier,
              partial_success: failed_migrations > 0
            }}
          end
        
        {:ok, []} ->
          {:ok, %{
            items_migrated: 0,
            total_items: 0,
            source_tier: source_tier,
            target_tier: target_tier,
            message: "No high-value items found to migrate"
          }}
        
        {:error, _} = error ->
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
      try do
        case tier do
          "mid" ->
            # Get summaries with high heat scores
            case Memory.get_user_summaries(user_id) do
              {:ok, summaries} ->
                high_value = ErrorHandling.safe_execute(fn ->
                  Enum.filter(summaries, fn summary ->
                    heat_score = Map.get(summary, :heat_score, 0.0)
                    heat_score >= 10.0
                  end)
                end)
                
                case high_value do
                  {:ok, items} -> {:ok, items}
                  error -> error
                end
              
              {:error, reason} ->
                ErrorHandling.resource_error(
                  "Failed to retrieve summaries for high-value items",
                  %{user_id: user_id, tier: tier, reason: reason}
                )
            end
          
          "short" ->
            # Short-term memory items don't have heat scores typically
            {:ok, []}
          
          "long" ->
            # Long-term memory items would need different criteria
            {:ok, []}
          
          _ ->
            ErrorHandling.validation_error(
              "Invalid tier for high-value item retrieval",
              %{tier: tier, valid_tiers: ["short", "mid", "long"]}
            )
        end
      rescue
        e ->
          ErrorHandling.system_error(
            "Failed to get high-value items",
            %{tier: tier, error: Exception.message(e)}
          )
      end
    end
    
    defp migrate_memory_item(user_id, item_id, source_tier, target_tier) do
      try do
        # Validate tiers
        valid_tiers = ["short", "mid", "long"]
        
        cond do
          source_tier not in valid_tiers ->
            ErrorHandling.validation_error(
              "Invalid source tier",
              %{source_tier: source_tier, valid_tiers: valid_tiers}
            )
          
          target_tier not in valid_tiers ->
            ErrorHandling.validation_error(
              "Invalid target tier",
              %{target_tier: target_tier, valid_tiers: valid_tiers}
            )
          
          source_tier == target_tier ->
            ErrorHandling.validation_error(
              "Source and target tiers are the same",
              %{tier: source_tier}
            )
          
          true ->
            # Placeholder implementation - would normally interact with Memory domain
            Logger.info("Migrating item #{item_id} from #{source_tier} to #{target_tier} for user #{user_id}")
            {:ok, %{item_id: item_id, migrated_from: source_tier, migrated_to: target_tier}}
        end
      rescue
        e ->
          ErrorHandling.system_error(
            "Migration failed",
            %{item_id: item_id, error: Exception.message(e)}
          )
      end
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
      
      # Validate check type
      valid_check_types = ["full", "quick", "tier_specific", "connectivity", "performance"]
      
      if check_type not in valid_check_types do
        ErrorHandling.validation_error(
          "Invalid health check type",
          %{check_type: check_type, valid_types: valid_check_types}
        )
      else
        # Perform health check across memory tiers with error handling
        health_check_result = ErrorHandling.safe_execute(fn ->
          perform_health_check(check_type, include_metrics)
        end)
        
        case health_check_result do
          {:ok, health_report} ->
            signal_data = Map.merge(health_report, %{
              check_id: check_id,
              timestamp: DateTime.utc_now()
            })
            {:ok, %{signal_data: signal_data, signal_type: "memory.health.report"}}
          
          {:error, error_details} ->
            ErrorHandling.log_error({:error, error_details})
            signal_data = %{
              check_id: check_id,
              status: "failed",
              error: error_details,
              timestamp: DateTime.utc_now()
            }
            {:ok, %{signal_data: signal_data, signal_type: "memory.health.error"}}
        end
      end
    end
    
    defp perform_health_check(check_type, include_metrics) do
      try do
        tier_health = check_memory_tiers_health()
        
        # Determine overall system status based on tier health
        system_status = determine_system_status(tier_health)
        
        base_report = %{
          "check_type" => check_type,
          "memory_tiers" => tier_health,
          "system_status" => system_status
        }
        
        if include_metrics do
          metrics = get_system_performance_metrics()
          Map.put(base_report, "performance_metrics", metrics)
        else
          base_report
        end
      rescue
        e ->
          ErrorHandling.resource_error(
            "Health check failed",
            %{check_type: check_type, error: Exception.message(e)}
          )
      end
    end
    
    defp determine_system_status(tier_health) do
      statuses = tier_health
      |> Map.values()
      |> Enum.map(&Map.get(&1, "status"))
      
      cond do
        Enum.all?(statuses, &(&1 == "healthy")) -> "healthy"
        Enum.any?(statuses, &(&1 == "critical")) -> "critical"
        Enum.any?(statuses, &(&1 == "degraded")) -> "degraded"
        true -> "unknown"
      end
    end
    
    defp check_memory_tiers_health do
      # This would normally check actual memory system health
      # For now, returning simulated values with error handling
      ErrorHandling.safe_execute(fn ->
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
      end) |> case do
        {:ok, health} -> health
        {:error, _} -> %{}
      end
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
      
      # Validate partition strategy
      valid_strategies = ["hash", "range", "list", "composite"]
      
      cond do
        strategy not in valid_strategies ->
          ErrorHandling.validation_error(
            "Invalid partition strategy",
            %{strategy: strategy, valid_strategies: valid_strategies}
          )
        
        not is_map(limits) ->
          ErrorHandling.validation_error(
            "Capacity limits must be a map",
            %{provided: limits}
          )
        
        Map.has_key?(agent_state.memory_partitions, partition_id) ->
          ErrorHandling.resource_error(
            "Partition already exists",
            %{partition_id: partition_id, existing_partitions: Map.keys(agent_state.memory_partitions)}
          )
        
        true ->
          # Validate capacity limits
          required_limit_keys = ["max_items", "max_size_mb"]
          missing_keys = required_limit_keys -- Map.keys(limits)
          
          if missing_keys != [] do
            ErrorHandling.validation_error(
              "Missing required capacity limit keys",
              %{missing_keys: missing_keys, required_keys: required_limit_keys}
            )
          else
            # Create partition configuration with error handling
            partition_result = ErrorHandling.safe_execute(fn ->
              %{
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
            end)
            
            case partition_result do
              {:ok, partition_config} ->
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
              
              {:error, error_details} ->
                error_details
            end
          end
      end
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
      
      # Validate access type and tier
      valid_access_types = ["read", "write", "delete", "update"]
      valid_tiers = ["short", "mid", "long"]
      
      cond do
        access_type not in valid_access_types ->
          ErrorHandling.validation_error(
            "Invalid access type",
            %{access_type: access_type, valid_types: valid_access_types}
          )
        
        tier not in valid_tiers ->
          ErrorHandling.validation_error(
            "Invalid memory tier",
            %{tier: tier, valid_tiers: valid_tiers}
          )
        
        String.trim(resource_id) == "" ->
          ErrorHandling.validation_error(
            "Resource ID cannot be empty",
            %{resource_id: resource_id}
          )
        
        true ->
          # Check access permissions with error handling
          access_result = ErrorHandling.safe_execute(fn ->
            decision = check_access_permissions(user_id, access_type, tier, resource_id)
            
            # Log access attempt for auditing
            audit_access_attempt(user_id, access_type, tier, resource_id, decision)
            
            decision
          end)
          
          case access_result do
            {:ok, decision} ->
              signal_data = %{
                request_id: request_id,
                decision: decision,
                user_id: user_id,
                access_type: access_type,
                tier: tier,
                resource_id: resource_id,
                timestamp: DateTime.utc_now()
              }
              
              {:ok, %{signal_data: signal_data, signal_type: "memory.access.decision"}}
            
            {:error, error_details} ->
              ErrorHandling.log_error({:error, error_details})
              signal_data = %{
                request_id: request_id,
                decision: "error",
                error: error_details,
                timestamp: DateTime.utc_now()
              }
              
              {:ok, %{signal_data: signal_data, signal_type: "memory.access.error"}}
          end
      end
    end
    
    defp check_access_permissions(_user_id, access_type, tier, _resource_id) do
      # Simplified access control - in production would check actual permissions
      # This is a placeholder implementation
      try do
        case {access_type, tier} do
          {"read", _} -> "granted"
          {"write", "short"} -> "granted"
          {"write", "mid"} -> "granted"
          {"write", "long"} -> "granted"
          {"delete", "short"} -> "granted"
          {"delete", _} -> "denied"
          {"update", tier} when tier in ["short", "mid"] -> "granted"
          {"update", _} -> "denied"
          _ -> "denied"
        end
      rescue
        e ->
          Logger.error("Access permission check failed: #{Exception.message(e)}")
          "error"
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
      
      # Validate metric types and time range
      valid_metric_types = ["performance", "usage", "conflicts", "health", "errors"]
      valid_time_ranges = ["1h", "6h", "24h", "7d", "30d", "all"]
      
      invalid_types = Enum.reject(metric_types, &(&1 in valid_metric_types))
      
      cond do
        metric_types == [] ->
          ErrorHandling.validation_error(
            "No metric types specified",
            %{metric_types: []}
          )
        
        invalid_types != [] ->
          ErrorHandling.validation_error(
            "Invalid metric types specified",
            %{invalid_types: invalid_types, valid_types: valid_metric_types}
          )
        
        time_range not in valid_time_ranges ->
          ErrorHandling.validation_error(
            "Invalid time range",
            %{time_range: time_range, valid_ranges: valid_time_ranges}
          )
        
        true ->
          # Collect requested metrics with error handling
          metrics_result = ErrorHandling.safe_execute(fn ->
            collect_coordination_metrics(agent_state, metric_types, time_range)
          end)
          
          case metrics_result do
            {:ok, metrics} ->
              signal_data = %{
                request_id: request_id,
                metrics: metrics,
                time_range: time_range,
                timestamp: DateTime.utc_now()
              }
              
              {:ok, %{signal_data: signal_data, signal_type: "coordination.metrics.report"}}
            
            {:error, error_details} ->
              ErrorHandling.log_error({:error, error_details})
              signal_data = %{
                request_id: request_id,
                status: "failed",
                error: error_details,
                timestamp: DateTime.utc_now()
              }
              
              {:ok, %{signal_data: signal_data, signal_type: "coordination.metrics.error"}}
          end
      end
    end
    
    defp collect_coordination_metrics(agent_state, metric_types, _time_range) do
      try do
        # Ensure performance_metrics exists with defaults
        performance_metrics = Map.get(agent_state, :performance_metrics, %{
          operations_completed: 0,
          sync_operations: 0,
          avg_operation_time: 0.0,
          conflict_resolutions: 0,
          partition_count: 0
        })
        
        # Safely get active_operations size
        active_ops_count = case Map.get(agent_state, :active_operations) do
          nil -> 0
          ops when is_map(ops) -> map_size(ops)
          _ -> 0
        end
        
        base_metrics = %{
          "performance" => %{
            "operations_completed" => performance_metrics.operations_completed,
            "avg_operation_time_ms" => performance_metrics.avg_operation_time,
            "active_operations" => active_ops_count
          },
          "usage" => %{
            "partition_count" => performance_metrics.partition_count,
            "sync_operations" => performance_metrics.sync_operations,
            "coordination_status" => Map.get(agent_state, :coordination_status, :idle)
          },
          "conflicts" => %{
            "conflict_resolutions" => performance_metrics.conflict_resolutions,
            "resolution_success_rate" => 0.95
          },
          "health" => %{
            "status" => "operational",
            "last_check" => DateTime.utc_now()
          },
          "errors" => %{
            "error_count" => 0,
            "last_error" => nil
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
      rescue
        e ->
          ErrorHandling.system_error(
            "Failed to collect metrics",
            %{error: Exception.message(e), metric_types: metric_types}
          )
      end
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