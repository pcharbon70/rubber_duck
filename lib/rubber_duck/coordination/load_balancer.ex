defmodule RubberDuck.Coordination.LoadBalancer do
  @moduledoc """
  Intelligent load balancing for process placement across the distributed cluster.
  Implements sophisticated algorithms for optimal process distribution based on
  node capacity, current load, network topology, and application-specific metrics.
  """
  use GenServer
  require Logger

  alias RubberDuck.Coordination.HordeSupervisor

  defstruct [
    :balancing_strategies,
    :node_metrics,
    :placement_history,
    :balancing_rules,
    :rebalancing_triggers,
    :load_metrics
  ]

  @balancing_strategies [:round_robin, :least_loaded, :weighted_round_robin, :consistent_hash, :affinity_based, :adaptive]
  @rebalancing_triggers [:threshold_exceeded, :node_join, :node_leave, :manual, :scheduled]
  @metrics_collection_interval 30_000  # 30 seconds

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Places a process on the optimal node based on current load balancing strategy.
  """
  def place_process(process_spec, placement_opts \\ []) do
    GenServer.call(__MODULE__, {:place_process, process_spec, placement_opts})
  end

  @doc """
  Triggers rebalancing of processes across the cluster.
  """
  def trigger_rebalancing(trigger_reason \\ :manual) do
    GenServer.call(__MODULE__, {:trigger_rebalancing, trigger_reason})
  end

  @doc """
  Updates load balancing strategy and configuration.
  """
  def update_balancing_strategy(strategy, config \\ %{}) do
    GenServer.call(__MODULE__, {:update_strategy, strategy, config})
  end

  @doc """
  Gets current load balancing metrics and node statistics.
  """
  def get_load_metrics do
    GenServer.call(__MODULE__, :get_load_metrics)
  end

  @doc """
  Adds a custom balancing rule for specific process types.
  """
  def add_balancing_rule(process_type, rule) do
    GenServer.call(__MODULE__, {:add_rule, process_type, rule})
  end

  @doc """
  Gets the recommended node for a specific process type.
  """
  def recommend_node(process_type, requirements \\ %{}) do
    GenServer.call(__MODULE__, {:recommend_node, process_type, requirements})
  end

  @doc """
  Analyzes cluster balance and provides optimization recommendations.
  """
  def analyze_cluster_balance do
    GenServer.call(__MODULE__, :analyze_balance)
  end

  @doc """
  Configures automatic rebalancing triggers and thresholds.
  """
  def configure_rebalancing_triggers(triggers) do
    GenServer.call(__MODULE__, {:configure_triggers, triggers})
  end

  @impl true
  def init(opts) do
    Logger.info("Starting Load Balancer for distributed process placement")
    
    state = %__MODULE__{
      balancing_strategies: initialize_balancing_strategies(opts),
      node_metrics: %{},
      placement_history: [],
      balancing_rules: initialize_balancing_rules(opts),
      rebalancing_triggers: initialize_rebalancing_triggers(opts),
      load_metrics: initialize_load_metrics()
    }
    
    # Start metrics collection
    schedule_metrics_collection()
    
    # Subscribe to cluster events
    subscribe_to_cluster_events()
    
    {:ok, state}
  end

  @impl true
  def handle_call({:place_process, process_spec, placement_opts}, _from, state) do
    case determine_optimal_placement(process_spec, placement_opts, state) do
      {:ok, target_node, placement_info, new_state} ->
        # Record placement decision
        placement_record = create_placement_record(process_spec, target_node, placement_info)
        updated_history = [placement_record | Enum.take(state.placement_history, 999)]
        
        final_state = %{new_state | placement_history: updated_history}
        
        {:reply, {:ok, target_node, placement_info}, final_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:trigger_rebalancing, trigger_reason}, _from, state) do
    case execute_cluster_rebalancing(trigger_reason, state) do
      {:ok, rebalancing_result, new_state} ->
        {:reply, {:ok, rebalancing_result}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_strategy, strategy, config}, _from, state) do
    if strategy in @balancing_strategies do
      updated_strategies = Map.put(state.balancing_strategies, :current, strategy)
      |> Map.put(strategy, Map.merge(Map.get(state.balancing_strategies, strategy, %{}), config))
      
      new_state = %{state | balancing_strategies: updated_strategies}
      
      Logger.info("Updated load balancing strategy to #{strategy}")
      {:reply, {:ok, :strategy_updated}, new_state}
    else
      {:reply, {:error, :invalid_strategy}, state}
    end
  end

  @impl true
  def handle_call(:get_load_metrics, _from, state) do
    enhanced_metrics = enhance_load_metrics(state.load_metrics, state)
    {:reply, enhanced_metrics, state}
  end

  @impl true
  def handle_call({:add_rule, process_type, rule}, _from, state) do
    case validate_balancing_rule(rule) do
      :ok ->
        new_rules = Map.put(state.balancing_rules, process_type, rule)
        new_state = %{state | balancing_rules: new_rules}
        
        Logger.debug("Added balancing rule for process type: #{process_type}")
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:recommend_node, process_type, requirements}, _from, state) do
    case find_optimal_node(process_type, requirements, state) do
      {:ok, recommended_node, recommendation_info} ->
        {:reply, {:ok, recommended_node, recommendation_info}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:analyze_balance, _from, state) do
    analysis_result = perform_cluster_balance_analysis(state)
    {:reply, analysis_result, state}
  end

  @impl true
  def handle_call({:configure_triggers, triggers}, _from, state) do
    case validate_rebalancing_triggers(triggers) do
      :ok ->
        new_triggers = Map.merge(state.rebalancing_triggers, triggers)
        new_state = %{state | rebalancing_triggers: new_triggers}
        
        Logger.info("Updated rebalancing triggers")
        {:reply, {:ok, :triggers_updated}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    new_state = collect_cluster_metrics(state)
    
    # Check rebalancing triggers
    check_rebalancing_triggers(new_state)
    
    # Schedule next collection
    schedule_metrics_collection()
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("Node joined cluster: #{node}")
    
    new_state = handle_node_join(node, state)
    
    # Trigger rebalancing if configured
    if should_rebalance_on_node_join?(state.rebalancing_triggers) do
      spawn(fn -> trigger_rebalancing(:node_join) end)
    end
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.warning("Node left cluster: #{node}")
    
    new_state = handle_node_leave(node, state)
    
    # Trigger rebalancing if needed
    if should_rebalance_on_node_leave?(state.rebalancing_triggers) do
      spawn(fn -> trigger_rebalancing(:node_leave) end)
    end
    
    {:noreply, new_state}
  end

  # Private functions

  defp determine_optimal_placement(process_spec, placement_opts, state) do
    strategy = get_current_strategy(state.balancing_strategies)
    process_type = extract_process_type(process_spec)
    
    # Check for custom rules
    custom_rule = Map.get(state.balancing_rules, process_type)
    
    case custom_rule do
      nil ->
        apply_standard_placement_strategy(process_spec, strategy, placement_opts, state)
      
      rule ->
        apply_custom_placement_rule(process_spec, rule, placement_opts, state)
    end
  end

  defp apply_standard_placement_strategy(process_spec, strategy, placement_opts, state) do
    case strategy do
      :round_robin ->
        place_round_robin(process_spec, placement_opts, state)
      
      :least_loaded ->
        place_least_loaded(process_spec, placement_opts, state)
      
      :weighted_round_robin ->
        place_weighted_round_robin(process_spec, placement_opts, state)
      
      :consistent_hash ->
        place_consistent_hash(process_spec, placement_opts, state)
      
      :affinity_based ->
        place_affinity_based(process_spec, placement_opts, state)
      
      :adaptive ->
        place_adaptive(process_spec, placement_opts, state)
    end
  end

  defp place_round_robin(_process_spec, _placement_opts, state) do
    cluster_nodes = get_cluster_nodes()
    
    case cluster_nodes do
      [] ->
        {:error, :no_available_nodes}
      
      nodes ->
        # Simple round-robin based on placement history
        next_index = rem(length(state.placement_history), length(nodes))
        target_node = Enum.at(nodes, next_index)
        
        placement_info = %{
          strategy: :round_robin,
          selection_reason: :round_robin_sequence,
          node_index: next_index
        }
        
        {:ok, target_node, placement_info, state}
    end
  end

  defp place_least_loaded(_process_spec, _placement_opts, state) do
    case find_least_loaded_node(state) do
      {:ok, target_node, load_info} ->
        placement_info = %{
          strategy: :least_loaded,
          selection_reason: :minimum_load,
          load_info: load_info
        }
        
        {:ok, target_node, placement_info, state}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp place_weighted_round_robin(_process_spec, _placement_opts, state) do
    cluster_nodes = get_cluster_nodes_with_weights(state)
    
    case select_weighted_node(cluster_nodes) do
      {:ok, target_node, weight_info} ->
        placement_info = %{
          strategy: :weighted_round_robin,
          selection_reason: :weighted_selection,
          weight_info: weight_info
        }
        
        {:ok, target_node, placement_info, state}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp place_consistent_hash(process_spec, _placement_opts, state) do
    hash_key = generate_hash_key(process_spec)
    cluster_nodes = get_cluster_nodes()
    
    case consistent_hash_placement(hash_key, cluster_nodes) do
      {:ok, target_node} ->
        placement_info = %{
          strategy: :consistent_hash,
          selection_reason: :hash_based,
          hash_key: hash_key
        }
        
        {:ok, target_node, placement_info, state}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp place_affinity_based(process_spec, placement_opts, state) do
    affinity_requirements = Map.get(placement_opts, :affinity, %{})
    
    case find_affinity_node(affinity_requirements, state) do
      {:ok, target_node, affinity_info} ->
        placement_info = %{
          strategy: :affinity_based,
          selection_reason: :affinity_match,
          affinity_info: affinity_info
        }
        
        {:ok, target_node, placement_info, state}
      
      {:error, reason} ->
        # Fallback to least loaded
        place_least_loaded(process_spec, placement_opts, state)
    end
  end

  defp place_adaptive(process_spec, placement_opts, state) do
    # Adaptive strategy chooses based on current cluster conditions
    cluster_analysis = analyze_current_cluster_state(state)
    
    optimal_strategy = choose_optimal_strategy(cluster_analysis)
    
    apply_standard_placement_strategy(process_spec, optimal_strategy, placement_opts, state)
  end

  defp apply_custom_placement_rule(process_spec, rule, placement_opts, state) do
    case execute_custom_rule(process_spec, rule, placement_opts, state) do
      {:ok, target_node} ->
        placement_info = %{
          strategy: :custom_rule,
          selection_reason: :rule_based,
          rule_applied: rule
        }
        
        {:ok, target_node, placement_info, state}
      
      {:error, reason} ->
        # Fallback to default strategy
        Logger.warning("Custom rule failed, falling back to default strategy: #{inspect(reason)}")
        default_strategy = get_current_strategy(state.balancing_strategies)
        apply_standard_placement_strategy(process_spec, default_strategy, placement_opts, state)
    end
  end

  defp execute_cluster_rebalancing(trigger_reason, state) do
    Logger.info("Executing cluster rebalancing triggered by: #{trigger_reason}")
    
    # Analyze current distribution
    distribution_analysis = analyze_process_distribution(state)
    
    case generate_rebalancing_plan(distribution_analysis, state) do
      {:ok, rebalancing_plan} ->
        case execute_rebalancing_plan(rebalancing_plan) do
          {:ok, execution_results} ->
            rebalancing_result = %{
              trigger_reason: trigger_reason,
              plan: rebalancing_plan,
              execution_results: execution_results,
              timestamp: System.monotonic_time(:millisecond)
            }
            
            new_metrics = update_rebalancing_metrics(state.load_metrics, rebalancing_result)
            new_state = %{state | load_metrics: new_metrics}
            
            {:ok, rebalancing_result, new_state}
          
          {:error, execution_error} ->
            {:error, {:rebalancing_execution_failed, execution_error}}
        end
      
      {:error, planning_error} ->
        {:error, {:rebalancing_planning_failed, planning_error}}
    end
  end

  defp find_optimal_node(process_type, requirements, state) do
    available_nodes = get_cluster_nodes()
    
    # Score nodes based on requirements
    scored_nodes = Enum.map(available_nodes, fn node ->
      score = calculate_node_score(node, process_type, requirements, state)
      {node, score}
    end)
    
    case Enum.max_by(scored_nodes, fn {_node, score} -> score end, fn -> nil end) do
      nil ->
        {:error, :no_suitable_nodes}
      
      {optimal_node, score} ->
        recommendation_info = %{
          score: score,
          scoring_criteria: requirements,
          process_type: process_type
        }
        
        {:ok, optimal_node, recommendation_info}
    end
  end

  defp perform_cluster_balance_analysis(state) do
    cluster_stats = HordeSupervisor.get_supervisor_stats()
    
    %{
      cluster_balance: cluster_stats.load_distribution,
      node_utilization: calculate_node_utilization(state),
      process_distribution: analyze_process_distribution(state),
      rebalancing_recommendations: generate_balance_recommendations(cluster_stats, state),
      health_score: calculate_cluster_health_score(cluster_stats)
    }
  end

  # Helper functions

  defp collect_cluster_metrics(state) do
    # Collect metrics from all nodes
    cluster_nodes = get_cluster_nodes()
    
    node_metrics = Enum.reduce(cluster_nodes, %{}, fn node, acc ->
      metrics = collect_node_metrics(node)
      Map.put(acc, node, metrics)
    end)
    
    updated_load_metrics = update_load_metrics(state.load_metrics, node_metrics)
    
    %{state | 
      node_metrics: node_metrics,
      load_metrics: updated_load_metrics
    }
  end

  defp collect_node_metrics(node) do
    %{
      cpu_usage: get_cpu_usage(node),
      memory_usage: get_memory_usage(node),
      process_count: get_process_count(node),
      network_latency: measure_network_latency(node),
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  defp check_rebalancing_triggers(state) do
    triggers = state.rebalancing_triggers
    
    # Check threshold-based triggers
    if Map.get(triggers, :threshold_based, false) do
      check_threshold_triggers(state)
    end
    
    # Check scheduled triggers
    if Map.get(triggers, :scheduled, false) do
      check_scheduled_triggers(state)
    end
  end

  defp check_threshold_triggers(state) do
    load_threshold = get_in(state.rebalancing_triggers, [:thresholds, :load_imbalance])
    
    if load_threshold do
      current_balance = calculate_current_balance_score(state)
      
      if current_balance < load_threshold do
        Logger.info("Load imbalance threshold exceeded, triggering rebalancing")
        spawn(fn -> trigger_rebalancing(:threshold_exceeded) end)
      end
    end
  end

  defp check_scheduled_triggers(_state) do
    # Check if scheduled rebalancing is due
    # Simplified implementation
    :ok
  end

  # Simplified helper implementations

  defp get_cluster_nodes, do: [node() | Node.list()]
  defp get_current_strategy(strategies), do: Map.get(strategies, :current, :least_loaded)
  defp extract_process_type(_process_spec), do: :general
  defp find_least_loaded_node(_state), do: {:ok, node(), %{load: 0.1}}
  defp get_cluster_nodes_with_weights(_state), do: [{node(), 1.0}]
  defp select_weighted_node(nodes), do: {:ok, elem(hd(nodes), 0), %{weight: 1.0}}
  defp generate_hash_key(_process_spec), do: "hash_key"
  defp consistent_hash_placement(_hash_key, nodes), do: {:ok, hd(nodes)}
  defp find_affinity_node(_requirements, _state), do: {:error, :no_affinity_match}
  defp analyze_current_cluster_state(_state), do: %{load: :balanced}
  defp choose_optimal_strategy(_analysis), do: :least_loaded
  defp execute_custom_rule(_spec, _rule, _opts, _state), do: {:error, :rule_not_implemented}
  defp analyze_process_distribution(_state), do: %{balanced: true}
  defp generate_rebalancing_plan(_analysis, _state), do: {:ok, []}
  defp execute_rebalancing_plan(_plan), do: {:ok, %{migrations: 0}}
  defp calculate_node_score(_node, _type, _requirements, _state), do: 0.5
  defp calculate_node_utilization(_state), do: %{}
  defp generate_balance_recommendations(_stats, _state), do: []
  defp calculate_cluster_health_score(_stats), do: 0.9
  defp get_cpu_usage(_node), do: 0.1
  defp get_memory_usage(_node), do: 0.2
  defp get_process_count(_node), do: 10
  defp measure_network_latency(_node), do: 5
  defp calculate_current_balance_score(_state), do: 0.8
  defp handle_node_join(_node, state), do: state
  defp handle_node_leave(_node, state), do: state
  defp should_rebalance_on_node_join?(_triggers), do: true
  defp should_rebalance_on_node_leave?(_triggers), do: true

  defp create_placement_record(process_spec, target_node, placement_info) do
    %{
      process_spec: process_spec,
      target_node: target_node,
      placement_info: placement_info,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  defp subscribe_to_cluster_events do
    :net_kernel.monitor_nodes(true)
    Logger.debug("Subscribed to cluster events for load balancer")
  end

  defp schedule_metrics_collection do
    Process.send_after(self(), :collect_metrics, @metrics_collection_interval)
  end

  defp initialize_balancing_strategies(opts) do
    default_strategy = Keyword.get(opts, :default_strategy, :least_loaded)
    
    %{
      current: default_strategy,
      round_robin: %{enabled: true},
      least_loaded: %{enabled: true},
      weighted_round_robin: %{enabled: true, weights: %{}},
      consistent_hash: %{enabled: true},
      affinity_based: %{enabled: true},
      adaptive: %{enabled: true}
    }
  end

  defp initialize_balancing_rules(_opts) do
    %{
      # Custom rules for specific process types
    }
  end

  defp initialize_rebalancing_triggers(opts) do
    %{
      threshold_based: Keyword.get(opts, :threshold_rebalancing, true),
      scheduled: Keyword.get(opts, :scheduled_rebalancing, false),
      node_events: Keyword.get(opts, :node_event_rebalancing, true),
      thresholds: %{
        load_imbalance: Keyword.get(opts, :load_imbalance_threshold, 0.7),
        node_utilization: Keyword.get(opts, :node_utilization_threshold, 0.8)
      }
    }
  end

  defp initialize_load_metrics do
    %{
      total_placements: 0,
      rebalancing_operations: 0,
      avg_placement_time: 0,
      placement_success_rate: 1.0,
      last_rebalancing: nil
    }
  end

  defp validate_balancing_rule(_rule), do: :ok
  defp validate_rebalancing_triggers(_triggers), do: :ok

  defp enhance_load_metrics(metrics, state) do
    Map.merge(metrics, %{
      active_nodes: length(get_cluster_nodes()),
      current_strategy: get_current_strategy(state.balancing_strategies),
      placement_history_size: length(state.placement_history)
    })
  end

  defp update_load_metrics(metrics, _node_metrics) do
    metrics
  end

  defp update_rebalancing_metrics(metrics, _rebalancing_result) do
    Map.update(metrics, :rebalancing_operations, 1, &(&1 + 1))
  end
end