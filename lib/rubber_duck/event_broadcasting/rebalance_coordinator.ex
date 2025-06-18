defmodule RubberDuck.EventBroadcasting.RebalanceCoordinator do
  @moduledoc """
  Event-driven provider rebalancing coordinator for cluster topology changes.
  
  Monitors cluster events, health changes, and load metrics to trigger intelligent
  provider rebalancing across nodes. Ensures optimal resource utilization,
  fault tolerance, and performance by automatically redistributing workloads
  based on cluster state and provider health.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.EventBroadcasting.{EventBroadcaster, HealthBroadcaster, ProviderCoordinator}
  alias RubberDuck.LoadBalancing.FailoverManager
  
  @type rebalance_trigger :: :node_join | :node_leave | :health_degradation | :load_imbalance | :manual | :scheduled
  @type rebalance_strategy :: :even_distribution | :capacity_based | :health_weighted | :performance_optimized
  
  @type rebalance_decision :: %{
    trigger: rebalance_trigger(),
    strategy: rebalance_strategy(),
    confidence: float(),
    estimated_benefit: float(),
    risk_assessment: :low | :medium | :high,
    actions: [map()]
  }
  
  @type rebalance_execution :: %{
    decision_id: String.t(),
    started_at: non_neg_integer(),
    estimated_duration: non_neg_integer(),
    current_phase: atom(),
    progress_percentage: float(),
    actions_completed: non_neg_integer(),
    actions_total: non_neg_integer()
  }
  
  @health_degradation_threshold 0.7
  @load_imbalance_threshold 0.3
  @rebalance_cooldown 300_000  # 5 minutes
  @decision_confidence_threshold 0.8
  @max_concurrent_rebalances 1
  
  # Client API
  
  @doc """
  Start the RebalanceCoordinator GenServer.
  
  ## Examples
  
      {:ok, pid} = RebalanceCoordinator.start_link()
      {:ok, pid} = RebalanceCoordinator.start_link(rebalance_strategy: :capacity_based)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Trigger manual rebalancing with specific strategy.
  
  ## Examples
  
      :ok = RebalanceCoordinator.trigger_rebalance(:even_distribution)
      {:ok, decision_id} = RebalanceCoordinator.trigger_rebalance(:performance_optimized, force: true)
  """
  def trigger_rebalance(strategy \\ :even_distribution, opts \\ []) do
    GenServer.call(__MODULE__, {:trigger_rebalance, strategy, opts})
  end
  
  @doc """
  Get current rebalancing status and active executions.
  
  ## Examples
  
      status = RebalanceCoordinator.get_rebalance_status()
      # %{
      #   active_rebalances: 1,
      #   last_rebalance: %{...},
      #   cooldown_remaining: 120_000,
      #   cluster_balance_score: 0.85
      # }
  """
  def get_rebalance_status do
    GenServer.call(__MODULE__, :get_rebalance_status)
  end
  
  @doc """
  Get rebalancing history and statistics.
  
  ## Examples
  
      history = RebalanceCoordinator.get_rebalance_history(limit: 20)
      # [%{trigger: :node_join, completed_at: ..., success: true}, ...]
  """
  def get_rebalance_history(opts \\ []) do
    GenServer.call(__MODULE__, {:get_rebalance_history, opts})
  end
  
  @doc """
  Cancel an active rebalancing operation.
  
  ## Examples
  
      :ok = RebalanceCoordinator.cancel_rebalance(decision_id)
      {:error, :not_found} = RebalanceCoordinator.cancel_rebalance("invalid_id")
  """
  def cancel_rebalance(decision_id) do
    GenServer.call(__MODULE__, {:cancel_rebalance, decision_id})
  end
  
  @doc """
  Get cluster balance analysis and recommendations.
  
  ## Examples
  
      analysis = RebalanceCoordinator.analyze_cluster_balance()
      # %{
      #   balance_score: 0.75,
      #   imbalanced_providers: [:openai],
      #   recommendations: ["Move openai from node1 to node3"],
      #   estimated_improvement: 0.15
      # }
  """
  def analyze_cluster_balance do
    GenServer.call(__MODULE__, :analyze_cluster_balance)
  end
  
  @doc """
  Update rebalancing configuration.
  
  ## Examples
  
      config = %{
        health_threshold: 0.8,
        load_threshold: 0.2,
        default_strategy: :capacity_based
      }
      :ok = RebalanceCoordinator.update_config(config)
  """
  def update_config(config) do
    GenServer.call(__MODULE__, {:update_config, config})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Subscribe to relevant events
    EventBroadcaster.subscribe("cluster.*")
    EventBroadcaster.subscribe("provider.health.*")
    EventBroadcaster.subscribe("provider.migration.*")
    EventBroadcaster.subscribe("metrics.aggregated")
    HealthBroadcaster.subscribe_to_health("cluster.health")
    
    state = %{
      default_strategy: Keyword.get(opts, :rebalance_strategy, :even_distribution),
      health_threshold: Keyword.get(opts, :health_threshold, @health_degradation_threshold),
      load_threshold: Keyword.get(opts, :load_threshold, @load_imbalance_threshold),
      cooldown_period: Keyword.get(opts, :cooldown_period, @rebalance_cooldown),
      active_rebalances: %{},
      rebalance_history: [],
      last_rebalance_time: 0,
      cluster_state_cache: %{},
      pending_decisions: %{},
      stats: %{
        total_rebalances: 0,
        successful_rebalances: 0,
        failed_rebalances: 0,
        cancelled_rebalances: 0,
        triggers: %{
          node_join: 0,
          node_leave: 0,
          health_degradation: 0,
          load_imbalance: 0,
          manual: 0,
          scheduled: 0
        }
      }
    }
    
    # Perform initial cluster analysis
    updated_state = update_cluster_state_cache(state)
    
    Logger.info("RebalanceCoordinator started with strategy: #{state.default_strategy}")
    {:ok, updated_state}
  end
  
  @impl true
  def handle_call({:trigger_rebalance, strategy, opts}, _from, state) do
    force = Keyword.get(opts, :force, false)
    
    case can_trigger_rebalance?(state, force) do
      false ->
        {:reply, {:error, :cooldown_active}, state}
      
      true ->
        case create_rebalance_decision(:manual, strategy, state) do
          {:ok, decision} ->
            if decision.confidence >= @decision_confidence_threshold or force do
              case execute_rebalance_decision(decision, state) do
                {:ok, updated_state} ->
                  {:reply, {:ok, decision.decision_id}, updated_state}
                
                {:error, reason} ->
                  {:reply, {:error, reason}, state}
              end
            else
              {:reply, {:error, :low_confidence}, state}
            end
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  @impl true
  def handle_call(:get_rebalance_status, _from, state) do
    current_time = System.monotonic_time(:millisecond)
    cooldown_remaining = max(0, state.last_rebalance_time + state.cooldown_period - current_time)
    
    cluster_balance_score = calculate_cluster_balance_score(state)
    
    status = %{
      active_rebalances: map_size(state.active_rebalances),
      last_rebalance: List.first(state.rebalance_history),
      cooldown_remaining: cooldown_remaining,
      cluster_balance_score: cluster_balance_score,
      pending_decisions: map_size(state.pending_decisions),
      stats: state.stats
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_call({:get_rebalance_history, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 50)
    history = Enum.take(state.rebalance_history, limit)
    {:reply, history, state}
  end
  
  @impl true
  def handle_call({:cancel_rebalance, decision_id}, _from, state) do
    case Map.get(state.active_rebalances, decision_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      execution ->
        # Cancel the rebalancing execution
        updated_state = cancel_rebalance_execution(execution, state)
        {:reply, :ok, updated_state}
    end
  end
  
  @impl true
  def handle_call(:analyze_cluster_balance, _from, state) do
    analysis = perform_cluster_balance_analysis(state)
    {:reply, analysis, state}
  end
  
  @impl true
  def handle_call({:update_config, config}, _from, state) do
    updated_state = Map.merge(state, config)
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_info({:event, event}, state) do
    case event.topic do
      "cluster.node_joined" ->
        handle_node_join_event(event, state)
      
      "cluster.node_left" ->
        handle_node_leave_event(event, state)
      
      "provider.health.degraded" ->
        handle_health_degradation_event(event, state)
      
      "provider.migration.completed" ->
        handle_migration_completed_event(event, state)
      
      "metrics.aggregated" ->
        handle_metrics_event(event, state)
      
      _ ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:health_update, health_aggregation}, state) do
    # Process cluster health updates
    if health_aggregation.overall_status in [:critical, :failed] do
      handle_health_crisis(health_aggregation, state)
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:rebalance_timeout, decision_id}, state) do
    case Map.get(state.active_rebalances, decision_id) do
      nil ->
        {:noreply, state}
      
      execution ->
        Logger.warning("Rebalance execution timeout: #{decision_id}")
        updated_state = handle_rebalance_failure(execution, :timeout, state)
        {:noreply, updated_state}
    end
  end
  
  @impl true
  def handle_info({:evaluate_pending_decision, decision_id}, state) do
    case Map.get(state.pending_decisions, decision_id) do
      nil ->
        {:noreply, state}
      
      decision ->
        # Re-evaluate the decision after some time
        case should_execute_decision?(decision, state) do
          true ->
            case execute_rebalance_decision(decision, state) do
              {:ok, updated_state} ->
                final_state = %{updated_state | pending_decisions: Map.delete(updated_state.pending_decisions, decision_id)}
                {:noreply, final_state}
              
              {:error, _reason} ->
                updated_state = %{state | pending_decisions: Map.delete(state.pending_decisions, decision_id)}
                {:noreply, updated_state}
            end
          
          false ->
            updated_state = %{state | pending_decisions: Map.delete(state.pending_decisions, decision_id)}
            {:noreply, updated_state}
        end
    end
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  # Private Functions
  
  defp handle_node_join_event(event, state) do
    Logger.info("Evaluating rebalance for node join: #{event.payload.node}")
    
    # Update cluster state cache
    updated_state = update_cluster_state_cache(state)
    
    # Create rebalance decision for node join
    case create_rebalance_decision(:node_join, :even_distribution, updated_state) do
      {:ok, decision} ->
        if decision.confidence >= @decision_confidence_threshold do
          case execute_rebalance_decision(decision, updated_state) do
            {:ok, final_state} -> {:noreply, final_state}
            {:error, _reason} -> {:noreply, updated_state}
          end
        else
          # Store as pending decision
          pending_decisions = Map.put(updated_state.pending_decisions, decision.decision_id, decision)
          Process.send_after(self(), {:evaluate_pending_decision, decision.decision_id}, 60_000)
          {:noreply, %{updated_state | pending_decisions: pending_decisions}}
        end
      
      {:error, _reason} ->
        {:noreply, updated_state}
    end
  end
  
  defp handle_node_leave_event(event, state) do
    Logger.info("Evaluating rebalance for node leave: #{event.payload.node}")
    
    # Update cluster state cache
    updated_state = update_cluster_state_cache(state)
    
    # Create urgent rebalance decision for node leave
    case create_rebalance_decision(:node_leave, :health_weighted, updated_state) do
      {:ok, decision} ->
        # Node leave is urgent, execute immediately regardless of confidence
        case execute_rebalance_decision(decision, updated_state) do
          {:ok, final_state} -> {:noreply, final_state}
          {:error, _reason} -> {:noreply, updated_state}
        end
      
      {:error, _reason} ->
        {:noreply, updated_state}
    end
  end
  
  defp handle_health_degradation_event(event, state) do
    provider_id = event.payload.provider_id
    health_score = event.payload.health_score
    
    if health_score < state.health_threshold do
      Logger.info("Evaluating rebalance for health degradation: #{provider_id} (#{health_score})")
      
      case create_rebalance_decision(:health_degradation, :health_weighted, state) do
        {:ok, decision} ->
          if decision.confidence >= @decision_confidence_threshold do
            case execute_rebalance_decision(decision, state) do
              {:ok, updated_state} -> {:noreply, updated_state}
              {:error, _reason} -> {:noreply, state}
            end
          else
            {:noreply, state}
          end
        
        {:error, _reason} ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end
  
  defp handle_migration_completed_event(event, state) do
    migration_id = event.payload.migration_id
    
    # Update active rebalances
    updated_rebalances = Map.new(state.active_rebalances, fn {decision_id, execution} ->
      updated_execution = %{execution | actions_completed: execution.actions_completed + 1}
      progress = updated_execution.actions_completed / updated_execution.actions_total * 100
      
      final_execution = %{updated_execution | progress_percentage: progress}
      
      if progress >= 100 do
        # Rebalance completed
        complete_rebalance_execution(final_execution, state)
      end
      
      {decision_id, final_execution}
    end)
    
    {:noreply, %{state | active_rebalances: updated_rebalances}}
  end
  
  defp handle_metrics_event(event, state) do
    # Check for load imbalance based on metrics
    load_metrics = event.payload
    
    imbalance_score = calculate_load_imbalance(load_metrics)
    
    if imbalance_score > state.load_threshold do
      Logger.info("Evaluating rebalance for load imbalance: #{imbalance_score}")
      
      case create_rebalance_decision(:load_imbalance, :performance_optimized, state) do
        {:ok, decision} ->
          if decision.confidence >= @decision_confidence_threshold do
            case execute_rebalance_decision(decision, state) do
              {:ok, updated_state} -> {:noreply, updated_state}
              {:error, _reason} -> {:noreply, state}
            end
          else
            {:noreply, state}
          end
        
        {:error, _reason} ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end
  
  defp handle_health_crisis(health_aggregation, state) do
    provider_id = health_aggregation.provider_id
    Logger.warning("Health crisis detected for provider: #{provider_id}")
    
    # Trigger immediate rebalancing for critical health issues
    case create_rebalance_decision(:health_degradation, :health_weighted, state) do
      {:ok, decision} ->
        # Execute immediately for health crisis
        case execute_rebalance_decision(decision, state) do
          {:ok, updated_state} -> {:noreply, updated_state}
          {:error, _reason} -> {:noreply, state}
        end
      
      {:error, _reason} ->
        {:noreply, state}
    end
  end
  
  defp can_trigger_rebalance?(state, force) do
    if force do
      true
    else
      current_time = System.monotonic_time(:millisecond)
      cooldown_expired = current_time - state.last_rebalance_time > state.cooldown_period
      under_concurrent_limit = map_size(state.active_rebalances) < @max_concurrent_rebalances
      
      cooldown_expired and under_concurrent_limit
    end
  end
  
  defp create_rebalance_decision(trigger, strategy, state) do
    decision_id = generate_decision_id()
    
    # Analyze current cluster state
    cluster_analysis = perform_cluster_balance_analysis(state)
    
    # Calculate confidence based on cluster state and metrics
    confidence = calculate_decision_confidence(trigger, cluster_analysis, state)
    
    # Estimate benefit of rebalancing
    estimated_benefit = estimate_rebalance_benefit(strategy, cluster_analysis)
    
    # Assess risk
    risk_assessment = assess_rebalance_risk(trigger, cluster_analysis, state)
    
    # Generate rebalance actions
    actions = generate_rebalance_actions(strategy, cluster_analysis)
    
    decision = %{
      decision_id: decision_id,
      trigger: trigger,
      strategy: strategy,
      confidence: confidence,
      estimated_benefit: estimated_benefit,
      risk_assessment: risk_assessment,
      actions: actions,
      created_at: System.monotonic_time(:millisecond),
      cluster_analysis: cluster_analysis
    }
    
    {:ok, decision}
  end
  
  defp execute_rebalance_decision(decision, state) do
    Logger.info("Executing rebalance decision: #{decision.decision_id} (#{decision.trigger}/#{decision.strategy})")
    
    # Create execution tracking
    execution = %{
      decision_id: decision.decision_id,
      started_at: System.monotonic_time(:millisecond),
      estimated_duration: estimate_execution_duration(decision.actions),
      current_phase: :preparing,
      progress_percentage: 0.0,
      actions_completed: 0,
      actions_total: length(decision.actions)
    }
    
    # Execute rebalance actions
    case perform_rebalance_actions(decision.actions) do
      :ok ->
        # Update state
        updated_rebalances = Map.put(state.active_rebalances, decision.decision_id, execution)
        updated_stats = update_rebalance_stats(state.stats, decision.trigger)
        
        updated_state = %{state |
          active_rebalances: updated_rebalances,
          last_rebalance_time: System.monotonic_time(:millisecond),
          stats: updated_stats
        }
        
        # Schedule timeout
        timeout_duration = execution.estimated_duration * 2  # 2x buffer
        Process.send_after(self(), {:rebalance_timeout, decision.decision_id}, timeout_duration)
        
        {:ok, updated_state}
      
      {:error, reason} ->
        Logger.error("Failed to execute rebalance decision: #{reason}")
        {:error, reason}
    end
  end
  
  defp perform_rebalance_actions(actions) do
    # Execute actions through ProviderCoordinator
    Enum.reduce_while(actions, :ok, fn action, _acc ->
      case execute_rebalance_action(action) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
  
  defp execute_rebalance_action(action) do
    case action.type do
      :migrate_provider ->
        ProviderCoordinator.migrate_provider(action.provider_id, action.target_node)
      
      :redistribute_load ->
        # Trigger load redistribution
        FailoverManager.rebalance_providers()
        :ok
      
      :adjust_capacity ->
        # Adjust node capacity settings
        :ok
      
      _ ->
        Logger.warning("Unknown rebalance action type: #{action.type}")
        :ok
    end
  end
  
  defp update_cluster_state_cache(state) do
    # Get current cluster topology and health
    cluster_topology = try do
      ProviderCoordinator.get_provider_assignments()
    catch
      :exit, :noproc -> %{}
      _, _ -> %{}
    end
    
    cluster_health = try do
      HealthBroadcaster.get_cluster_health_summary()
    catch
      :exit, :noproc -> %{}
      _, _ -> %{}
    end
    
    updated_cache = %{
      topology: cluster_topology,
      health: cluster_health,
      last_updated: System.monotonic_time(:millisecond)
    }
    
    %{state | cluster_state_cache: updated_cache}
  end
  
  defp perform_cluster_balance_analysis(state) do
    topology = get_in(state.cluster_state_cache, [:topology]) || %{}
    health = get_in(state.cluster_state_cache, [:health]) || %{}
    
    # Analyze provider distribution
    node_provider_counts = Enum.reduce(topology, %{}, fn {_provider_id, assignment}, acc ->
      node = assignment.assigned_node
      Map.update(acc, node, 1, &(&1 + 1))
    end)
    
    # Calculate balance metrics
    total_providers = map_size(topology)
    node_count = map_size(node_provider_counts)
    
    balance_score = if node_count > 0 and total_providers > 0 do
      ideal_distribution = total_providers / node_count
      imbalances = Enum.map(node_provider_counts, fn {_node, count} ->
        abs(count - ideal_distribution) / ideal_distribution
      end)
      
      avg_imbalance = Enum.sum(imbalances) / length(imbalances)
      max(0, 1 - avg_imbalance)
    else
      1.0
    end
    
    # Identify imbalanced providers
    imbalanced_providers = Enum.filter(topology, fn {provider_id, assignment} ->
      provider_health = Map.get(health.node_health_scores || %{}, assignment.assigned_node, 1.0)
      provider_health < 0.8
    end)
    |> Enum.map(fn {provider_id, _assignment} -> provider_id end)
    
    %{
      balance_score: balance_score,
      node_provider_counts: node_provider_counts,
      imbalanced_providers: imbalanced_providers,
      total_providers: total_providers,
      node_count: node_count,
      cluster_health: health
    }
  end
  
  defp calculate_decision_confidence(trigger, cluster_analysis, _state) do
    base_confidence = case trigger do
      :node_join -> 0.8
      :node_leave -> 0.95  # High confidence for urgent scenarios
      :health_degradation -> 0.85
      :load_imbalance -> 0.7
      :manual -> 0.9
      :scheduled -> 0.8
    end
    
    # Adjust based on cluster balance
    balance_adjustment = cluster_analysis.balance_score * 0.2
    
    # Adjust based on cluster health
    health_adjustment = (cluster_analysis.cluster_health[:overall_cluster_health] || 0.5) * 0.1
    
    min(1.0, base_confidence + balance_adjustment + health_adjustment)
  end
  
  defp estimate_rebalance_benefit(strategy, cluster_analysis) do
    current_balance = cluster_analysis.balance_score
    
    # Estimate improvement based on strategy
    estimated_improvement = case strategy do
      :even_distribution -> max(0, 0.9 - current_balance)
      :capacity_based -> max(0, 0.85 - current_balance)
      :health_weighted -> max(0, 0.8 - current_balance) * 1.2
      :performance_optimized -> max(0, 0.95 - current_balance)
    end
    
    estimated_improvement
  end
  
  defp assess_rebalance_risk(trigger, cluster_analysis, _state) do
    # Base risk assessment
    base_risk = case trigger do
      :node_leave -> :medium  # Some risk during topology change
      :health_degradation -> :low  # Low risk, necessary for health
      :load_imbalance -> :low
      :manual -> :medium
      _ -> :low
    end
    
    # Adjust risk based on cluster stability
    cluster_health = cluster_analysis.cluster_health[:overall_cluster_health] || 0.5
    
    if cluster_health < 0.5 do
      :high
    else
      base_risk
    end
  end
  
  defp generate_rebalance_actions(strategy, cluster_analysis) do
    case strategy do
      :even_distribution ->
        generate_even_distribution_actions(cluster_analysis)
      
      :health_weighted ->
        generate_health_weighted_actions(cluster_analysis)
      
      :performance_optimized ->
        generate_performance_actions(cluster_analysis)
      
      _ ->
        generate_basic_actions(cluster_analysis)
    end
  end
  
  defp generate_even_distribution_actions(cluster_analysis) do
    # Generate actions to evenly distribute providers
    node_counts = cluster_analysis.node_provider_counts
    total_providers = cluster_analysis.total_providers
    node_count = cluster_analysis.node_count
    
    if node_count > 0 do
      ideal_per_node = div(total_providers, node_count)
      
      overloaded_nodes = Enum.filter(node_counts, fn {_node, count} -> count > ideal_per_node + 1 end)
      underloaded_nodes = Enum.filter(node_counts, fn {_node, count} -> count < ideal_per_node end)
      
      # Create migration actions from overloaded to underloaded nodes
      Enum.flat_map(overloaded_nodes, fn {source_node, count} ->
        excess = count - ideal_per_node
        Enum.take(underloaded_nodes, excess)
        |> Enum.map(fn {target_node, _count} ->
          %{
            type: :migrate_provider,
            source_node: source_node,
            target_node: target_node,
            priority: :normal
          }
        end)
      end)
    else
      []
    end
  end
  
  defp generate_health_weighted_actions(cluster_analysis) do
    # Generate actions based on health scores
    Enum.map(cluster_analysis.imbalanced_providers, fn provider_id ->
      %{
        type: :migrate_provider,
        provider_id: provider_id,
        target_node: :best_health,  # Will be resolved during execution
        priority: :high
      }
    end)
  end
  
  defp generate_performance_actions(cluster_analysis) do
    # Generate performance-optimized actions
    [
      %{
        type: :redistribute_load,
        strategy: :performance_optimized,
        priority: :normal
      }
    ]
  end
  
  defp generate_basic_actions(_cluster_analysis) do
    [
      %{
        type: :redistribute_load,
        strategy: :basic,
        priority: :normal
      }
    ]
  end
  
  defp calculate_cluster_balance_score(state) do
    case get_in(state.cluster_state_cache, [:topology]) do
      nil -> 0.0
      topology when map_size(topology) == 0 -> 1.0
      topology ->
        # Calculate distribution balance
        node_counts = Enum.reduce(topology, %{}, fn {_provider_id, assignment}, acc ->
          node = assignment.assigned_node
          Map.update(acc, node, 1, &(&1 + 1))
        end)
        
        if map_size(node_counts) <= 1 do
          1.0
        else
          values = Map.values(node_counts)
          avg = Enum.sum(values) / length(values)
          variance = Enum.sum(Enum.map(values, fn v -> (v - avg) * (v - avg) end)) / length(values)
          max(0, 1 - (variance / (avg * avg)))
        end
    end
  end
  
  defp calculate_load_imbalance(load_metrics) do
    # Simplified load imbalance calculation
    case load_metrics do
      %{node_loads: node_loads} when map_size(node_loads) > 1 ->
        loads = Map.values(node_loads)
        max_load = Enum.max(loads)
        min_load = Enum.min(loads)
        
        if max_load > 0 do
          (max_load - min_load) / max_load
        else
          0.0
        end
      
      _ -> 0.0
    end
  end
  
  defp complete_rebalance_execution(execution, state) do
    Logger.info("Rebalance execution completed: #{execution.decision_id}")
    
    # Move to history
    history_entry = %{
      decision_id: execution.decision_id,
      started_at: execution.started_at,
      completed_at: System.monotonic_time(:millisecond),
      duration: System.monotonic_time(:millisecond) - execution.started_at,
      success: true,
      actions_completed: execution.actions_completed
    }
    
    updated_history = [history_entry | Enum.take(state.rebalance_history, 99)]
    updated_rebalances = Map.delete(state.active_rebalances, execution.decision_id)
    updated_stats = %{state.stats | successful_rebalances: state.stats.successful_rebalances + 1}
    
    %{state |
      rebalance_history: updated_history,
      active_rebalances: updated_rebalances,
      stats: updated_stats
    }
  end
  
  defp cancel_rebalance_execution(execution, state) do
    Logger.info("Cancelling rebalance execution: #{execution.decision_id}")
    
    # Move to history as cancelled
    history_entry = %{
      decision_id: execution.decision_id,
      started_at: execution.started_at,
      cancelled_at: System.monotonic_time(:millisecond),
      duration: System.monotonic_time(:millisecond) - execution.started_at,
      success: false,
      cancelled: true,
      actions_completed: execution.actions_completed
    }
    
    updated_history = [history_entry | Enum.take(state.rebalance_history, 99)]
    updated_rebalances = Map.delete(state.active_rebalances, execution.decision_id)
    updated_stats = %{state.stats | cancelled_rebalances: state.stats.cancelled_rebalances + 1}
    
    %{state |
      rebalance_history: updated_history,
      active_rebalances: updated_rebalances,
      stats: updated_stats
    }
  end
  
  defp handle_rebalance_failure(execution, reason, state) do
    Logger.error("Rebalance execution failed: #{execution.decision_id}, reason: #{reason}")
    
    # Move to history as failed
    history_entry = %{
      decision_id: execution.decision_id,
      started_at: execution.started_at,
      failed_at: System.monotonic_time(:millisecond),
      duration: System.monotonic_time(:millisecond) - execution.started_at,
      success: false,
      failure_reason: reason,
      actions_completed: execution.actions_completed
    }
    
    updated_history = [history_entry | Enum.take(state.rebalance_history, 99)]
    updated_rebalances = Map.delete(state.active_rebalances, execution.decision_id)
    updated_stats = %{state.stats | failed_rebalances: state.stats.failed_rebalances + 1}
    
    %{state |
      rebalance_history: updated_history,
      active_rebalances: updated_rebalances,
      stats: updated_stats
    }
  end
  
  defp should_execute_decision?(decision, state) do
    # Re-evaluate decision criteria
    current_analysis = perform_cluster_balance_analysis(state)
    new_confidence = calculate_decision_confidence(decision.trigger, current_analysis, state)
    
    new_confidence >= @decision_confidence_threshold
  end
  
  defp estimate_execution_duration(actions) do
    # Estimate duration based on action types and count
    base_duration = length(actions) * 30_000  # 30 seconds per action
    min(base_duration, 300_000)  # Max 5 minutes
  end
  
  defp update_rebalance_stats(stats, trigger) do
    %{stats |
      total_rebalances: stats.total_rebalances + 1,
      triggers: Map.update!(stats.triggers, trigger, &(&1 + 1))
    }
  end
  
  defp generate_decision_id do
    "rebalance_#{System.unique_integer([:positive, :monotonic])}"
  end
end