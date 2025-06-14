defmodule RubberDuck.EventBroadcasting.ProviderCoordinator do
  @moduledoc """
  Cross-node provider failover and redistribution coordinator.
  
  Handles provider failover across cluster nodes, coordinates provider migration
  during topology changes, and ensures optimal provider distribution for load
  balancing and fault tolerance. Integrates with cluster events and health monitoring.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.EventBroadcasting.{EventBroadcaster, MetricsCollector, ClusterEventCoordinator}
  alias RubberDuck.LoadBalancing.{LoadBalancer, FailoverManager, CircuitBreaker}
  
  @type provider_assignment :: %{
    provider_id: term(),
    assigned_node: node(),
    backup_nodes: [node()],
    health_score: float(),
    assignment_timestamp: non_neg_integer(),
    migration_status: :stable | :migrating | :failed
  }
  
  @type redistribution_plan :: %{
    plan_id: String.t(),
    created_at: non_neg_integer(),
    trigger_reason: atom(),
    source_assignments: %{term() => provider_assignment()},
    target_assignments: %{term() => provider_assignment()},
    migration_steps: [map()],
    estimated_duration: non_neg_integer()
  }
  
  @failover_timeout 30_000
  @migration_timeout 60_000
  @health_check_interval 15_000
  @redistribution_cooldown 120_000
  
  # Client API
  
  @doc """
  Start the ProviderCoordinator GenServer.
  
  ## Examples
  
      {:ok, pid} = ProviderCoordinator.start_link()
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get current provider assignments across the cluster.
  
  ## Examples
  
      assignments = ProviderCoordinator.get_provider_assignments()
      # %{
      #   openai: %{assigned_node: :node1, backup_nodes: [:node2], ...},
      #   anthropic: %{assigned_node: :node2, backup_nodes: [:node1, :node3], ...}
      # }
  """
  def get_provider_assignments do
    GenServer.call(__MODULE__, :get_provider_assignments)
  end
  
  @doc """
  Request provider migration to a specific node.
  
  ## Examples
  
      :ok = ProviderCoordinator.migrate_provider(:openai, :node2)
      {:error, :migration_in_progress} = ProviderCoordinator.migrate_provider(:busy_provider, :node3)
  """
  def migrate_provider(provider_id, target_node) do
    GenServer.call(__MODULE__, {:migrate_provider, provider_id, target_node})
  end
  
  @doc """
  Trigger immediate failover for a failed provider.
  
  ## Examples
  
      :ok = ProviderCoordinator.trigger_failover(:failed_provider)
  """
  def trigger_failover(provider_id) do
    GenServer.call(__MODULE__, {:trigger_failover, provider_id})
  end
  
  @doc """
  Get the optimal node assignment for a new provider.
  
  ## Examples
  
      {:ok, :node2} = ProviderCoordinator.get_optimal_assignment(:new_provider, requirements)
      {:error, :no_suitable_nodes} = ProviderCoordinator.get_optimal_assignment(:provider, strict_requirements)
  """
  def get_optimal_assignment(provider_id, requirements \\ %{}) do
    GenServer.call(__MODULE__, {:get_optimal_assignment, provider_id, requirements})
  end
  
  @doc """
  Force redistribution of all providers across the cluster.
  
  ## Examples
  
      {:ok, plan_id} = ProviderCoordinator.force_redistribution()
  """
  def force_redistribution do
    GenServer.call(__MODULE__, :force_redistribution)
  end
  
  @doc """
  Get status of ongoing redistributions.
  
  ## Examples
  
      status = ProviderCoordinator.get_redistribution_status()
      # %{
      #   active_redistributions: 1,
      #   completed_redistributions: 5,
      #   failed_redistributions: 0,
      #   current_plan: %{...}
      # }
  """
  def get_redistribution_status do
    GenServer.call(__MODULE__, :get_redistribution_status)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Subscribe to cluster and provider events
    EventBroadcaster.subscribe("cluster.*")
    EventBroadcaster.subscribe("provider.*")
    EventBroadcaster.subscribe("loadbalancer.*")
    
    state = %{
      provider_assignments: %{},
      active_migrations: %{},
      redistribution_plans: %{},
      last_redistribution: 0,
      health_check_timer: schedule_health_check(),
      node_capabilities: %{},
      redistribution_stats: %{
        total_redistributions: 0,
        successful_redistributions: 0,
        failed_redistributions: 0,
        total_migrations: 0
      }
    }
    
    # Initialize with current cluster state
    updated_state = discover_existing_providers(state)
    
    Logger.info("ProviderCoordinator started")
    {:ok, updated_state}
  end
  
  @impl true
  def handle_call(:get_provider_assignments, _from, state) do
    {:reply, state.provider_assignments, state}
  end
  
  @impl true
  def handle_call({:migrate_provider, provider_id, target_node}, _from, state) do
    case Map.get(state.provider_assignments, provider_id) do
      nil ->
        {:reply, {:error, :provider_not_found}, state}
      
      assignment ->
        if assignment.migration_status == :migrating do
          {:reply, {:error, :migration_in_progress}, state}
        else
          case start_provider_migration(provider_id, assignment, target_node, state) do
            {:ok, updated_state} ->
              {:reply, :ok, updated_state}
            
            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        end
    end
  end
  
  @impl true
  def handle_call({:trigger_failover, provider_id}, _from, state) do
    case Map.get(state.provider_assignments, provider_id) do
      nil ->
        {:reply, {:error, :provider_not_found}, state}
      
      assignment ->
        case execute_provider_failover(provider_id, assignment, state) do
          {:ok, updated_state} ->
            {:reply, :ok, updated_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  @impl true
  def handle_call({:get_optimal_assignment, provider_id, requirements}, _from, state) do
    case calculate_optimal_node_assignment(provider_id, requirements, state) do
      {:ok, node} ->
        {:reply, {:ok, node}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:force_redistribution, _from, state) do
    case create_redistribution_plan(:forced, state) do
      {:ok, plan, updated_state} ->
        final_state = execute_redistribution_plan(plan, updated_state)
        {:reply, {:ok, plan.plan_id}, final_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:get_redistribution_status, _from, state) do
    status = %{
      active_redistributions: map_size(state.redistribution_plans),
      completed_redistributions: state.redistribution_stats.successful_redistributions,
      failed_redistributions: state.redistribution_stats.failed_redistributions,
      current_plan: get_current_redistribution_plan(state.redistribution_plans),
      active_migrations: map_size(state.active_migrations),
      total_migrations: state.redistribution_stats.total_migrations
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_info({:event, event}, state) do
    case event.topic do
      "cluster.node_joined" ->
        handle_node_joined_event(event, state)
      
      "cluster.node_left" ->
        handle_node_left_event(event, state)
      
      "cluster.provider_redistribution" ->
        handle_redistribution_request(event, state)
      
      "provider.health_changed" ->
        handle_provider_health_change(event, state)
      
      "provider.failed" ->
        handle_provider_failure(event, state)
      
      _ ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:health_check, state) do
    # Perform health checks on provider assignments
    updated_state = perform_provider_health_checks(state)
    
    # Schedule next health check
    timer = schedule_health_check()
    
    {:noreply, %{updated_state | health_check_timer: timer}}
  end
  
  @impl true
  def handle_info({:migration_timeout, migration_id}, state) do
    case Map.get(state.active_migrations, migration_id) do
      nil ->
        {:noreply, state}
      
      migration ->
        Logger.warning("Migration timeout for #{migration.provider_id}: #{migration_id}")
        updated_state = handle_migration_failure(migration, :timeout, state)
        {:noreply, updated_state}
    end
  end
  
  @impl true
  def handle_info({:redistribution_complete, plan_id}, state) do
    case Map.get(state.redistribution_plans, plan_id) do
      nil ->
        {:noreply, state}
      
      plan ->
        Logger.info("Redistribution plan completed: #{plan_id}")
        
        updated_plans = Map.delete(state.redistribution_plans, plan_id)
        updated_stats = %{state.redistribution_stats |
          successful_redistributions: state.redistribution_stats.successful_redistributions + 1
        }
        
        updated_state = %{state |
          redistribution_plans: updated_plans,
          redistribution_stats: updated_stats
        }
        
        # Broadcast completion event
        completion_event = %{
          topic: "provider.redistribution_completed",
          payload: %{
            plan_id: plan_id,
            duration: System.monotonic_time(:millisecond) - plan.created_at,
            migrations_completed: length(plan.migration_steps)
          }
        }
        EventBroadcaster.broadcast_async(completion_event)
        
        {:noreply, updated_state}
    end
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    if state.health_check_timer do
      Process.cancel_timer(state.health_check_timer)
    end
    :ok
  end
  
  # Private Functions
  
  defp discover_existing_providers(state) do
    # Discover providers on current node
    try do
      current_providers = LoadBalancer.get_provider_stats()
      
      current_assignments = Map.new(current_providers, fn {provider_id, provider_info} ->
        assignment = %{
          provider_id: provider_id,
          assigned_node: node(),
          backup_nodes: [],
          health_score: Map.get(provider_info, :health_score, 1.0),
          assignment_timestamp: System.monotonic_time(:millisecond),
          migration_status: :stable
        }
        {provider_id, assignment}
      end)
      
      # Broadcast current assignments
      if map_size(current_assignments) > 0 do
        assignment_event = %{
          topic: "provider.assignments_discovered",
          payload: %{
            node: node(),
            assignments: current_assignments,
            timestamp: System.monotonic_time(:millisecond)
          }
        }
        EventBroadcaster.broadcast_async(assignment_event)
      end
      
      %{state | provider_assignments: current_assignments}
    catch
      :exit, :noproc ->
        Logger.debug("LoadBalancer not available during provider discovery")
        state
      _, _ ->
        state
    end
  end
  
  defp start_provider_migration(provider_id, current_assignment, target_node, state) do
    if target_node == current_assignment.assigned_node do
      {:error, :already_assigned_to_target}
    else
      migration_id = generate_migration_id()
      
      migration = %{
        migration_id: migration_id,
        provider_id: provider_id,
        source_node: current_assignment.assigned_node,
        target_node: target_node,
        started_at: System.monotonic_time(:millisecond),
        status: :in_progress
      }
      
      # Update assignment status
      updated_assignment = %{current_assignment | migration_status: :migrating}
      updated_assignments = Map.put(state.provider_assignments, provider_id, updated_assignment)
      
      updated_migrations = Map.put(state.active_migrations, migration_id, migration)
      
      # Schedule migration timeout
      Process.send_after(self(), {:migration_timeout, migration_id}, @migration_timeout)
      
      # Broadcast migration start
      migration_event = %{
        topic: "provider.migration_started",
        payload: migration
      }
      EventBroadcaster.broadcast_async(migration_event)
      
      # Trigger actual migration
      spawn(fn -> perform_provider_migration(migration) end)
      
      updated_state = %{state |
        provider_assignments: updated_assignments,
        active_migrations: updated_migrations
      }
      
      {:ok, updated_state}
    end
  end
  
  defp perform_provider_migration(migration) do
    # Simulate provider migration process
    Logger.info("Migrating provider #{migration.provider_id} from #{migration.source_node} to #{migration.target_node}")
    
    # Step 1: Prepare target node
    preparation_result = prepare_target_node(migration.target_node, migration.provider_id)
    
    if preparation_result == :ok do
      # Step 2: Gracefully drain source
      drain_result = drain_source_provider(migration.source_node, migration.provider_id)
      
      if drain_result == :ok do
        # Step 3: Activate on target
        activation_result = activate_provider_on_target(migration.target_node, migration.provider_id)
        
        if activation_result == :ok do
          # Migration successful
          success_event = %{
            topic: "provider.migration_completed",
            payload: %{
              migration_id: migration.migration_id,
              provider_id: migration.provider_id,
              source_node: migration.source_node,
              target_node: migration.target_node,
              duration: System.monotonic_time(:millisecond) - migration.started_at
            }
          }
          EventBroadcaster.broadcast_async(success_event)
        else
          # Migration failed at activation
          failure_event = %{
            topic: "provider.migration_failed",
            payload: %{
              migration_id: migration.migration_id,
              provider_id: migration.provider_id,
              reason: :activation_failed,
              step: :activate_target
            }
          }
          EventBroadcaster.broadcast_async(failure_event)
        end
      else
        # Migration failed at drain
        failure_event = %{
          topic: "provider.migration_failed",
          payload: %{
            migration_id: migration.migration_id,
            provider_id: migration.provider_id,
            reason: :drain_failed,
            step: :drain_source
          }
        }
        EventBroadcaster.broadcast_async(failure_event)
      end
    else
      # Migration failed at preparation
      failure_event = %{
        topic: "provider.migration_failed",
        payload: %{
          migration_id: migration.migration_id,
          provider_id: migration.provider_id,
          reason: :preparation_failed,
          step: :prepare_target
        }
      }
      EventBroadcaster.broadcast_async(failure_event)
    end
  end
  
  defp prepare_target_node(_target_node, _provider_id) do
    # Simulate preparation work
    Process.sleep(1000)
    :ok
  end
  
  defp drain_source_provider(_source_node, _provider_id) do
    # Simulate draining
    Process.sleep(2000)
    :ok
  end
  
  defp activate_provider_on_target(_target_node, _provider_id) do
    # Simulate activation
    Process.sleep(1000)
    :ok
  end
  
  defp execute_provider_failover(provider_id, assignment, state) do
    # Find best backup node
    case find_best_backup_node(assignment.backup_nodes, state) do
      {:ok, backup_node} ->
        # Trigger immediate failover
        failover_assignment = %{assignment |
          assigned_node: backup_node,
          migration_status: :stable,
          assignment_timestamp: System.monotonic_time(:millisecond)
        }
        
        updated_assignments = Map.put(state.provider_assignments, provider_id, failover_assignment)
        
        # Broadcast failover event
        failover_event = %{
          topic: "provider.failover_completed",
          payload: %{
            provider_id: provider_id,
            failed_node: assignment.assigned_node,
            backup_node: backup_node,
            timestamp: System.monotonic_time(:millisecond)
          }
        }
        EventBroadcaster.broadcast_async(failover_event)
        
        Logger.info("Provider #{provider_id} failed over from #{assignment.assigned_node} to #{backup_node}")
        
        {:ok, %{state | provider_assignments: updated_assignments}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp find_best_backup_node(backup_nodes, state) do
    # Get cluster topology
    cluster_topology = ClusterEventCoordinator.get_cluster_topology()
    active_nodes = Map.get(cluster_topology, :nodes, %{})
    
    # Filter available backup nodes
    available_backups = Enum.filter(backup_nodes, fn node ->
      case Map.get(active_nodes, node) do
        nil -> false
        node_info -> node_info.status == :active and node_info.health_score >= 0.7
      end
    end)
    
    if length(available_backups) > 0 do
      # Select node with highest health score
      best_node = Enum.max_by(available_backups, fn node ->
        node_info = Map.get(active_nodes, node)
        node_info.health_score
      end)
      
      {:ok, best_node}
    else
      {:error, :no_healthy_backup_nodes}
    end
  end
  
  defp calculate_optimal_node_assignment(provider_id, requirements, state) do
    # Get current cluster topology
    cluster_topology = ClusterEventCoordinator.get_cluster_topology()
    active_nodes = Map.keys(Map.get(cluster_topology, :nodes, %{}))
    
    if length(active_nodes) == 0 do
      {:error, :no_active_nodes}
    else
      # Score nodes based on requirements and current load
      scored_nodes = Enum.map(active_nodes, fn node ->
        score = calculate_node_score(node, provider_id, requirements, state)
        {node, score}
      end)
      |> Enum.filter(fn {_node, score} -> score > 0 end)
      |> Enum.sort_by(fn {_node, score} -> score end, :desc)
      
      case scored_nodes do
        [] -> {:error, :no_suitable_nodes}
        [{best_node, _score} | _] -> {:ok, best_node}
      end
    end
  end
  
  defp calculate_node_score(node, provider_id, requirements, state) do
    # Base score
    base_score = 100.0
    
    # Check current load
    current_assignments = Enum.count(state.provider_assignments, fn {_id, assignment} ->
      assignment.assigned_node == node
    end)
    
    load_penalty = current_assignments * 10
    
    # Check node capabilities if available
    capability_bonus = if Map.has_key?(state.node_capabilities, node) do
      capabilities = Map.get(state.node_capabilities, node)
      if meets_requirements?(capabilities, requirements), do: 20, else: -50
    else
      0
    end
    
    # Health bonus
    health_bonus = get_node_health_bonus(node)
    
    max(0, base_score - load_penalty + capability_bonus + health_bonus)
  end
  
  defp meets_requirements?(_capabilities, _requirements) do
    # Simplified requirements checking
    true
  end
  
  defp get_node_health_bonus(_node) do
    # Simplified health bonus calculation
    10
  end
  
  defp create_redistribution_plan(reason, state) do
    current_time = System.monotonic_time(:millisecond)
    
    # Check cooldown period
    if current_time - state.last_redistribution < @redistribution_cooldown do
      {:error, :redistribution_cooldown_active}
    else
      plan_id = generate_plan_id()
      
      # Create redistribution plan
      plan = %{
        plan_id: plan_id,
        created_at: current_time,
        trigger_reason: reason,
        source_assignments: state.provider_assignments,
        target_assignments: calculate_optimal_redistribution(state),
        migration_steps: [],
        estimated_duration: 60_000
      }
      
      # Calculate migration steps
      migration_steps = calculate_migration_steps(plan.source_assignments, plan.target_assignments)
      updated_plan = %{plan | migration_steps: migration_steps}
      
      updated_plans = Map.put(state.redistribution_plans, plan_id, updated_plan)
      updated_state = %{state | 
        redistribution_plans: updated_plans,
        last_redistribution: current_time
      }
      
      {:ok, updated_plan, updated_state}
    end
  end
  
  defp calculate_optimal_redistribution(state) do
    # Simplified redistribution calculation
    # In practice, this would use sophisticated algorithms to balance load
    state.provider_assignments
  end
  
  defp calculate_migration_steps(source_assignments, target_assignments) do
    # Calculate what migrations are needed
    Enum.flat_map(source_assignments, fn {provider_id, source_assignment} ->
      case Map.get(target_assignments, provider_id) do
        nil -> []
        target_assignment ->
          if source_assignment.assigned_node != target_assignment.assigned_node do
            [%{
              provider_id: provider_id,
              source_node: source_assignment.assigned_node,
              target_node: target_assignment.assigned_node,
              estimated_duration: 30_000
            }]
          else
            []
          end
      end
    end)
  end
  
  defp execute_redistribution_plan(plan, state) do
    Logger.info("Executing redistribution plan: #{plan.plan_id}")
    
    # Broadcast redistribution start
    start_event = %{
      topic: "provider.redistribution_started",
      payload: %{
        plan_id: plan.plan_id,
        migration_count: length(plan.migration_steps),
        estimated_duration: plan.estimated_duration
      }
    }
    EventBroadcaster.broadcast_async(start_event)
    
    # Execute migration steps
    spawn(fn -> execute_migration_steps(plan.migration_steps, plan.plan_id) end)
    
    updated_stats = %{state.redistribution_stats |
      total_redistributions: state.redistribution_stats.total_redistributions + 1
    }
    
    %{state | redistribution_stats: updated_stats}
  end
  
  defp execute_migration_steps(migration_steps, plan_id) do
    # Execute migrations sequentially
    Enum.each(migration_steps, fn step ->
      Logger.info("Executing migration step: #{step.provider_id} -> #{step.target_node}")
      Process.sleep(step.estimated_duration)
    end)
    
    # Notify completion
    send(self(), {:redistribution_complete, plan_id})
  end
  
  defp handle_node_joined_event(event, state) do
    joined_node = event.payload.node
    Logger.info("Handling node joined event for provider coordination: #{joined_node}")
    
    # Update node capabilities if provided
    updated_capabilities = if Map.has_key?(event.payload, :capabilities) do
      Map.put(state.node_capabilities, joined_node, event.payload.capabilities)
    else
      state.node_capabilities
    end
    
    # Consider redistribution if cluster is significantly unbalanced
    updated_state = %{state | node_capabilities: updated_capabilities}
    
    # Schedule redistribution check
    Process.send_after(self(), {:check_redistribution, :node_join}, 30_000)
    
    {:noreply, updated_state}
  end
  
  defp handle_node_left_event(event, state) do
    left_node = event.payload.node
    Logger.info("Handling node left event for provider coordination: #{left_node}")
    
    # Find providers that were on the failed node
    failed_assignments = Enum.filter(state.provider_assignments, fn {_id, assignment} ->
      assignment.assigned_node == left_node
    end)
    
    if length(failed_assignments) > 0 do
      Logger.warning("#{length(failed_assignments)} providers were on failed node #{left_node}")
      
      # Trigger immediate failover for affected providers
      updated_state = Enum.reduce(failed_assignments, state, fn {provider_id, assignment}, acc_state ->
        case execute_provider_failover(provider_id, assignment, acc_state) do
          {:ok, new_state} -> new_state
          {:error, reason} ->
            Logger.error("Failed to failover provider #{provider_id}: #{reason}")
            acc_state
        end
      end)
      
      {:noreply, updated_state}
    else
      {:noreply, state}
    end
  end
  
  defp handle_redistribution_request(event, state) do
    reason = event.payload.reason
    Logger.info("Handling redistribution request: #{reason}")
    
    # Only process if we don't have an active redistribution
    if map_size(state.redistribution_plans) == 0 do
      case create_redistribution_plan(reason, state) do
        {:ok, plan, updated_state} ->
          final_state = execute_redistribution_plan(plan, updated_state)
          {:noreply, final_state}
        
        {:error, _reason} ->
          {:noreply, state}
      end
    else
      Logger.debug("Skipping redistribution request - active redistribution in progress")
      {:noreply, state}
    end
  end
  
  defp handle_provider_health_change(event, state) do
    provider_id = event.payload.provider_id
    health_score = event.payload.health_score
    
    case Map.get(state.provider_assignments, provider_id) do
      nil ->
        {:noreply, state}
      
      assignment ->
        updated_assignment = %{assignment | health_score: health_score}
        updated_assignments = Map.put(state.provider_assignments, provider_id, updated_assignment)
        
        # Trigger failover if health is critically low
        if health_score < 0.3 do
          case execute_provider_failover(provider_id, updated_assignment, state) do
            {:ok, final_state} ->
              {:noreply, final_state}
            
            {:error, _reason} ->
              {:noreply, %{state | provider_assignments: updated_assignments}}
          end
        else
          {:noreply, %{state | provider_assignments: updated_assignments}}
        end
    end
  end
  
  defp handle_provider_failure(event, state) do
    provider_id = event.payload.provider_id
    
    case Map.get(state.provider_assignments, provider_id) do
      nil ->
        {:noreply, state}
      
      assignment ->
        case execute_provider_failover(provider_id, assignment, state) do
          {:ok, updated_state} ->
            {:noreply, updated_state}
          
          {:error, reason} ->
            Logger.error("Failed to handle provider failure for #{provider_id}: #{reason}")
            {:noreply, state}
        end
    end
  end
  
  defp perform_provider_health_checks(state) do
    # Check health of all assigned providers
    current_time = System.monotonic_time(:millisecond)
    
    updated_assignments = Map.new(state.provider_assignments, fn {provider_id, assignment} ->
      # Get latest health from circuit breaker
      updated_health = try do
        health_scores = CircuitBreaker.get_health_scores()
        Map.get(health_scores, provider_id, assignment.health_score)
      catch
        :exit, :noproc -> assignment.health_score
        _, _ -> assignment.health_score
      end
      
      updated_assignment = %{assignment | health_score: updated_health}
      {provider_id, updated_assignment}
    end)
    
    %{state | provider_assignments: updated_assignments}
  end
  
  defp handle_migration_failure(migration, reason, state) do
    Logger.error("Migration failed: #{migration.migration_id}, reason: #{reason}")
    
    # Update assignment status
    updated_assignments = Map.update!(state.provider_assignments, migration.provider_id, fn assignment ->
      %{assignment | migration_status: :failed}
    end)
    
    # Remove from active migrations
    updated_migrations = Map.delete(state.active_migrations, migration.migration_id)
    
    # Update stats
    updated_stats = %{state.redistribution_stats |
      total_migrations: state.redistribution_stats.total_migrations + 1
    }
    
    %{state |
      provider_assignments: updated_assignments,
      active_migrations: updated_migrations,
      redistribution_stats: updated_stats
    }
  end
  
  defp get_current_redistribution_plan(redistribution_plans) do
    case Map.values(redistribution_plans) do
      [] -> nil
      [plan | _] -> plan
    end
  end
  
  defp generate_migration_id do
    "migration_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp generate_plan_id do
    "plan_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end
end