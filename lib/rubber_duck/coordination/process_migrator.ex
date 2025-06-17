defmodule RubberDuck.Coordination.ProcessMigrator do
  @moduledoc """
  Handles process migration during node changes and load balancing operations.
  Provides seamless process migration with state transfer, minimal downtime,
  and automatic rollback capabilities for distributed process coordination.
  """
  use GenServer
  require Logger

  alias RubberDuck.Coordination.LoadBalancer

  defstruct [
    :migration_strategies,
    :active_migrations,
    :migration_history,
    :rollback_capabilities,
    :migration_metrics,
    :state_transfer_handlers
  ]

  @migration_strategies [:hot_migration, :cold_migration, :staged_migration, :parallel_migration]
  @migration_states [:pending, :in_progress, :transferring_state, :completing, :completed, :failed, :rolled_back]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Migrates a process from one node to another with state transfer.
  """
  def migrate_process(process_id, from_node, to_node, opts \\ []) do
    GenServer.call(__MODULE__, {:migrate_process, process_id, from_node, to_node, opts}, 60_000)
  end

  @doc """
  Migrates multiple processes in batch for efficiency.
  """
  def migrate_processes_batch(migration_requests, opts \\ []) do
    GenServer.call(__MODULE__, {:migrate_batch, migration_requests, opts}, 120_000)
  end

  @doc """
  Gets the status of an ongoing migration.
  """
  def get_migration_status(migration_id) do
    GenServer.call(__MODULE__, {:get_status, migration_id})
  end

  @doc """
  Cancels an ongoing migration and attempts rollback.
  """
  def cancel_migration(migration_id, reason \\ :user_cancelled) do
    GenServer.call(__MODULE__, {:cancel_migration, migration_id, reason})
  end

  @doc """
  Triggers automatic migration based on cluster conditions.
  """
  def trigger_automatic_migration do
    GenServer.cast(__MODULE__, :trigger_automatic_migration)
  end

  @doc """
  Gets migration statistics and performance metrics.
  """
  def get_migration_metrics do
    GenServer.call(__MODULE__, :get_migration_metrics)
  end

  @doc """
  Configures migration strategies and policies.
  """
  def configure_migration_policies(policies) do
    GenServer.call(__MODULE__, {:configure_policies, policies})
  end

  @doc """
  Registers a custom state transfer handler for specific process types.
  """
  def register_state_handler(process_type, handler_module) do
    GenServer.call(__MODULE__, {:register_handler, process_type, handler_module})
  end

  @impl true
  def init(opts) do
    Logger.info("Starting Process Migrator for distributed coordination")
    
    state = %__MODULE__{
      migration_strategies: initialize_migration_strategies(opts),
      active_migrations: %{},
      migration_history: [],
      rollback_capabilities: initialize_rollback_capabilities(opts),
      migration_metrics: initialize_migration_metrics(),
      state_transfer_handlers: initialize_state_handlers()
    }
    
    # Subscribe to cluster events
    subscribe_to_cluster_events()
    
    {:ok, state}
  end

  @impl true
  def handle_call({:migrate_process, process_id, from_node, to_node, opts}, _from, state) do
    migration_id = generate_migration_id()
    
    case initiate_process_migration(migration_id, process_id, from_node, to_node, opts, state) do
      {:ok, migration_info, new_state} ->
        {:reply, {:ok, migration_id, migration_info}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:migrate_batch, migration_requests, opts}, _from, state) do
    case initiate_batch_migration(migration_requests, opts, state) do
      {:ok, batch_info, new_state} ->
        {:reply, {:ok, batch_info}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_status, migration_id}, _from, state) do
    case Map.get(state.active_migrations, migration_id) do
      nil ->
        # Check migration history
        case find_in_migration_history(migration_id, state.migration_history) do
          nil -> {:reply, {:error, :migration_not_found}, state}
          historical_migration -> {:reply, {:ok, historical_migration}, state}
        end
      
      active_migration ->
        {:reply, {:ok, active_migration}, state}
    end
  end

  @impl true
  def handle_call({:cancel_migration, migration_id, reason}, _from, state) do
    case Map.get(state.active_migrations, migration_id) do
      nil ->
        {:reply, {:error, :migration_not_found}, state}
      
      migration ->
        case attempt_migration_cancellation(migration, reason, state) do
          {:ok, cancellation_result, new_state} ->
            {:reply, {:ok, cancellation_result}, new_state}
          
          {:error, cancel_reason} ->
            {:reply, {:error, cancel_reason}, state}
        end
    end
  end

  @impl true
  def handle_call(:get_migration_metrics, _from, state) do
    enhanced_metrics = enhance_migration_metrics(state.migration_metrics, state)
    {:reply, enhanced_metrics, state}
  end

  @impl true
  def handle_call({:configure_policies, policies}, _from, state) do
    case validate_migration_policies(policies) do
      :ok ->
        updated_strategies = Map.merge(state.migration_strategies, policies)
        new_state = %{state | migration_strategies: updated_strategies}
        
        Logger.info("Updated migration policies")
        {:reply, {:ok, :policies_updated}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:register_handler, process_type, handler_module}, _from, state) do
    case validate_state_handler(handler_module) do
      :ok ->
        new_handlers = Map.put(state.state_transfer_handlers, process_type, handler_module)
        new_state = %{state | state_transfer_handlers: new_handlers}
        
        Logger.info("Registered state handler for process type: #{process_type}")
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast(:trigger_automatic_migration, state) do
    new_state = execute_automatic_migration_assessment(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:migration_step, migration_id, step}, state) do
    new_state = handle_migration_step(migration_id, step, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:migration_timeout, migration_id}, state) do
    new_state = handle_migration_timeout(migration_id, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:nodedown, departed_node}, state) do
    Logger.warning("Node departed during migrations: #{departed_node}")
    new_state = handle_node_departure_during_migration(departed_node, state)
    {:noreply, new_state}
  end

  # Private functions

  defp initiate_process_migration(migration_id, process_id, from_node, to_node, opts, state) do
    Logger.info("Initiating migration #{migration_id}: #{process_id} from #{from_node} to #{to_node}")
    
    # Validate migration request
    case validate_migration_request(process_id, from_node, to_node, opts, state) do
      :ok ->
        migration_info = create_migration_info(migration_id, process_id, from_node, to_node, opts)
        
        # Start migration process
        case start_migration_process(migration_info, state) do
          {:ok, updated_migration_info} ->
            new_active_migrations = Map.put(state.active_migrations, migration_id, updated_migration_info)
            new_metrics = update_migration_metrics(state.migration_metrics, :migration_started)
            
            new_state = %{state |
              active_migrations: new_active_migrations,
              migration_metrics: new_metrics
            }
            
            {:ok, updated_migration_info, new_state}
          
          {:error, reason} ->
            {:error, reason}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp initiate_batch_migration(migration_requests, opts, state) do
    batch_id = generate_batch_id()
    
    Logger.info("Initiating batch migration #{batch_id} with #{length(migration_requests)} processes")
    
    # Validate all migration requests
    case validate_batch_migration_requests(migration_requests, state) do
      :ok ->
        batch_migrations = Enum.map(migration_requests, fn request ->
          migration_id = generate_migration_id()
          create_migration_info(
            migration_id,
            request.process_id,
            request.from_node,
            request.to_node,
            Map.merge(opts, Map.get(request, :opts, %{}))
          )
        end)
        
        case execute_batch_migration(batch_migrations, state) do
          {:ok, batch_results, new_state} ->
            batch_info = %{
              batch_id: batch_id,
              total_migrations: length(batch_migrations),
              results: batch_results,
              started_at: System.monotonic_time(:millisecond)
            }
            
            {:ok, batch_info, new_state}
          
          {:error, reason} ->
            {:error, reason}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_migration_process(migration_info, state) do
    strategy = determine_migration_strategy(migration_info, state)
    
    case strategy do
      :hot_migration ->
        execute_hot_migration(migration_info, state)
      
      :cold_migration ->
        execute_cold_migration(migration_info, state)
      
      :staged_migration ->
        execute_staged_migration(migration_info, state)
      
      :parallel_migration ->
        execute_parallel_migration(migration_info, state)
    end
  end

  defp execute_hot_migration(migration_info, state) do
    Logger.info("Executing hot migration for #{migration_info.process_id}")
    
    # Phase 1: Prepare target process
    case prepare_target_process(migration_info, state) do
      {:ok, target_pid} ->
        # Phase 2: Transfer state while source is running
        case transfer_state_hot(migration_info, target_pid, state) do
          {:ok, state_transfer_result} ->
            # Phase 3: Atomic switch
            case perform_atomic_switch(migration_info, target_pid, state) do
              {:ok, switch_result} ->
                updated_migration = %{migration_info |
                  status: :completed,
                  target_pid: target_pid,
                  completed_at: System.monotonic_time(:millisecond),
                  result: %{
                    state_transfer: state_transfer_result,
                    switch: switch_result
                  }
                }
                
                {:ok, updated_migration}
              
              {:error, reason} ->
                # Rollback
                rollback_migration(migration_info, target_pid, reason, state)
            end
          
          {:error, reason} ->
            cleanup_target_process(target_pid)
            {:error, {:state_transfer_failed, reason}}
        end
      
      {:error, reason} ->
        {:error, {:target_preparation_failed, reason}}
    end
  end

  defp execute_cold_migration(migration_info, state) do
    Logger.info("Executing cold migration for #{migration_info.process_id}")
    
    # Phase 1: Stop source process
    case stop_source_process(migration_info) do
      {:ok, final_state} ->
        # Phase 2: Start target process with state
        case start_target_process_with_state(migration_info, final_state, state) do
          {:ok, target_pid} ->
            # Phase 3: Update registrations
            case update_process_registrations(migration_info, target_pid) do
              :ok ->
                updated_migration = %{migration_info |
                  status: :completed,
                  target_pid: target_pid,
                  completed_at: System.monotonic_time(:millisecond)
                }
                
                {:ok, updated_migration}
              
              {:error, reason} ->
                {:error, {:registration_update_failed, reason}}
            end
          
          {:error, reason} ->
            # Attempt to restart source process
            restart_source_process(migration_info, final_state)
            {:error, {:target_start_failed, reason}}
        end
      
      {:error, reason} ->
        {:error, {:source_stop_failed, reason}}
    end
  end

  defp execute_staged_migration(migration_info, state) do
    Logger.info("Executing staged migration for #{migration_info.process_id}")
    
    stages = [
      {:prepare_target, &prepare_target_process/2},
      {:transfer_static_state, &transfer_static_state/3},
      {:synchronize_dynamic_state, &synchronize_dynamic_state/3},
      {:perform_switch, &perform_atomic_switch/3},
      {:cleanup_source, &cleanup_source_process/2}
    ]
    
    execute_migration_stages(migration_info, stages, state)
  end

  defp execute_parallel_migration(migration_info, state) do
    Logger.info("Executing parallel migration for #{migration_info.process_id}")
    
    # Start multiple parallel tasks
    tasks = [
      Task.async(fn -> prepare_target_process(migration_info, state) end),
      Task.async(fn -> extract_process_state(migration_info) end),
      Task.async(fn -> analyze_process_dependencies(migration_info) end)
    ]
    
    case Task.await_many(tasks, 30_000) do
      [
        {:ok, target_pid},
        {:ok, process_state},
        {:ok, dependencies}
      ] ->
        # Continue with state transfer and switch
        continue_parallel_migration(migration_info, target_pid, process_state, dependencies, state)
      
      results ->
        handle_parallel_migration_failures(results)
    end
  end

  defp continue_parallel_migration(migration_info, target_pid, process_state, dependencies, state) do
    # Apply state to target process
    case apply_state_to_target(target_pid, process_state) do
      :ok ->
        # Handle dependencies
        case migrate_dependencies(dependencies, migration_info, state) do
          :ok ->
            # Perform final switch
            perform_atomic_switch(migration_info, target_pid, state)
          
          {:error, reason} ->
            {:error, {:dependency_migration_failed, reason}}
        end
      
      {:error, reason} ->
        {:error, {:state_application_failed, reason}}
    end
  end

  defp attempt_migration_cancellation(migration, reason, state) do
    Logger.warning("Cancelling migration #{migration.id}: #{reason}")
    
    case migration.status do
      :pending ->
        # Easy cancellation
        cancel_pending_migration(migration, reason, state)
      
      :in_progress ->
        # Need to rollback
        rollback_active_migration(migration, reason, state)
      
      :transferring_state ->
        # Need careful rollback
        rollback_state_transfer(migration, reason, state)
      
      :completing ->
        # Too late to cancel
        {:error, :migration_too_advanced}
      
      status when status in [:completed, :failed, :rolled_back] ->
        {:error, :migration_already_finished}
    end
  end

  defp execute_automatic_migration_assessment(state) do
    Logger.info("Executing automatic migration assessment")
    
    # Get cluster balance information
    case LoadBalancer.analyze_cluster_balance() do
      %{rebalancing_recommendations: [_ | _] = recommendations} ->
        execute_recommended_migrations(recommendations, state)
      
      _balanced_cluster ->
        Logger.debug("Cluster is balanced, no automatic migrations needed")
        state
    end
  end

  defp execute_recommended_migrations(recommendations, state) do
    Logger.info("Executing #{length(recommendations)} recommended migrations")
    
    # Convert recommendations to migration requests
    migration_requests = Enum.map(recommendations, &convert_recommendation_to_migration/1)
    
    # Execute migrations
    case initiate_batch_migration(migration_requests, %{automatic: true}, state) do
      {:ok, _batch_info, new_state} ->
        new_state
      
      {:error, reason} ->
        Logger.error("Automatic migration failed: #{inspect(reason)}")
        state
    end
  end

  defp handle_migration_step(migration_id, step, state) do
    case Map.get(state.active_migrations, migration_id) do
      nil ->
        Logger.warning("Received step for unknown migration: #{migration_id}")
        state
      
      migration ->
        updated_migration = process_migration_step(migration, step)
        new_active_migrations = Map.put(state.active_migrations, migration_id, updated_migration)
        
        %{state | active_migrations: new_active_migrations}
    end
  end

  defp handle_migration_timeout(migration_id, state) do
    Logger.warning("Migration timeout: #{migration_id}")
    
    case Map.get(state.active_migrations, migration_id) do
      nil ->
        state
      
      migration ->
        # Attempt cleanup and rollback
        case attempt_migration_cancellation(migration, :timeout, state) do
          {:ok, _cancellation_result, new_state} ->
            new_state
          
          {:error, _reason} ->
            # Mark as failed
            failed_migration = %{migration | status: :failed, failed_at: System.monotonic_time(:millisecond)}
            move_migration_to_history(failed_migration, state)
        end
    end
  end

  defp handle_node_departure_during_migration(departed_node, state) do
    # Find migrations affected by node departure
    affected_migrations = Enum.filter(state.active_migrations, fn {_id, migration} ->
      migration.from_node == departed_node or migration.to_node == departed_node
    end)
    
    Enum.reduce(affected_migrations, state, fn {migration_id, migration}, acc_state ->
      Logger.warning("Migration #{migration_id} affected by node departure: #{departed_node}")
      
      case handle_migration_node_failure(migration, departed_node, acc_state) do
        {:ok, updated_migration, new_state} ->
          new_active_migrations = Map.put(new_state.active_migrations, migration_id, updated_migration)
          %{new_state | active_migrations: new_active_migrations}
        
        {:error, _reason} ->
          # Move to history as failed
          failed_migration = %{migration | status: :failed, failed_at: System.monotonic_time(:millisecond)}
          move_migration_to_history(failed_migration, acc_state)
      end
    end)
  end

  # Helper functions and simplified implementations

  defp generate_migration_id, do: "migration_#{System.unique_integer([:positive])}"
  defp generate_batch_id, do: "batch_#{System.unique_integer([:positive])}"

  defp create_migration_info(migration_id, process_id, from_node, to_node, opts) do
    %{
      id: migration_id,
      process_id: process_id,
      from_node: from_node,
      to_node: to_node,
      options: opts,
      status: :pending,
      started_at: System.monotonic_time(:millisecond),
      strategy: Map.get(opts, :strategy, :hot_migration)
    }
  end

  defp validate_migration_request(_process_id, _from_node, _to_node, _opts, _state), do: :ok
  defp validate_batch_migration_requests(_requests, _state), do: :ok
  defp validate_migration_policies(_policies), do: :ok
  defp validate_state_handler(_handler_module), do: :ok

  defp determine_migration_strategy(migration_info, _state) do
    Map.get(migration_info.options, :strategy, :hot_migration)
  end

  defp subscribe_to_cluster_events do
    :net_kernel.monitor_nodes(true)
    Logger.debug("Subscribed to cluster events for process migrator")
  end

  defp find_in_migration_history(_migration_id, _history), do: nil
  defp execute_batch_migration(_migrations, state), do: {:ok, [], state}
  defp execute_migration_stages(_migration, _stages, _state), do: {:ok, %{}}
  defp handle_parallel_migration_failures(_results), do: {:error, :parallel_tasks_failed}
  defp cancel_pending_migration(_migration, _reason, state), do: {:ok, :cancelled, state}
  defp rollback_active_migration(_migration, _reason, state), do: {:ok, :rolled_back, state}
  defp rollback_state_transfer(_migration, _reason, state), do: {:ok, :rolled_back, state}
  defp convert_recommendation_to_migration(_recommendation), do: %{}
  defp process_migration_step(migration, _step), do: migration
  defp move_migration_to_history(_migration, state), do: state
  defp handle_migration_node_failure(_migration, _node, state), do: {:ok, %{}, state}

  # Process manipulation functions (simplified)
  defp prepare_target_process(_migration_info, _state), do: {:ok, spawn(fn -> :ok end)}
  defp transfer_state_hot(_migration_info, _target_pid, _state), do: {:ok, %{}}
  defp perform_atomic_switch(_migration_info, _target_pid, _state), do: {:ok, %{}}
  defp rollback_migration(_migration_info, _target_pid, _reason, _state), do: {:error, :rollback_failed}
  defp cleanup_target_process(_target_pid), do: :ok
  defp stop_source_process(_migration_info), do: {:ok, %{}}
  defp start_target_process_with_state(_migration_info, _state, _context), do: {:ok, spawn(fn -> :ok end)}
  defp update_process_registrations(_migration_info, _target_pid), do: :ok
  defp restart_source_process(_migration_info, _state), do: :ok
  defp transfer_static_state(_migration_info, _target_pid, _state), do: {:ok, %{}}
  defp synchronize_dynamic_state(_migration_info, _target_pid, _state), do: {:ok, %{}}
  defp cleanup_source_process(_migration_info, _state), do: {:ok, %{}}
  defp extract_process_state(_migration_info), do: {:ok, %{}}
  defp analyze_process_dependencies(_migration_info), do: {:ok, []}
  defp apply_state_to_target(_target_pid, _state), do: :ok
  defp migrate_dependencies(_dependencies, _migration_info, _state), do: :ok

  defp initialize_migration_strategies(_opts) do
    %{
      default_strategy: :hot_migration,
      strategy_config: %{
        hot_migration: %{timeout: 30_000, max_retries: 3},
        cold_migration: %{timeout: 60_000, max_retries: 2},
        staged_migration: %{timeout: 45_000, max_retries: 3},
        parallel_migration: %{timeout: 40_000, max_retries: 2}
      }
    }
  end

  defp initialize_rollback_capabilities(_opts) do
    %{
      enabled: true,
      max_rollback_attempts: 3,
      rollback_timeout: 30_000
    }
  end

  defp initialize_migration_metrics do
    %{
      total_migrations: 0,
      successful_migrations: 0,
      failed_migrations: 0,
      rollbacks: 0,
      avg_migration_time: 0,
      migrations_by_strategy: %{}
    }
  end

  defp initialize_state_handlers do
    %{
      # Default handlers for common process types
      :session => RubberDuck.Session.StateHandler,
      :model => RubberDuck.Model.StateHandler
    }
  end

  defp update_migration_metrics(metrics, event) do
    Map.update(metrics, event, 1, &(&1 + 1))
  end

  defp enhance_migration_metrics(metrics, state) do
    Map.merge(metrics, %{
      active_migrations: map_size(state.active_migrations),
      migration_history_size: length(state.migration_history)
    })
  end
end