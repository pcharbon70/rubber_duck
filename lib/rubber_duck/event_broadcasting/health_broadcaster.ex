defmodule RubberDuck.EventBroadcasting.HealthBroadcaster do
  @moduledoc """
  Health status broadcasting and subscription system for distributed cluster coordination.
  
  Manages real-time health status propagation across cluster nodes, aggregates health
  data for decision making, and triggers automated responses to health changes.
  Integrates with provider monitoring, circuit breakers, and load balancing systems.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.EventBroadcasting.EventBroadcaster
  alias RubberDuck.LoadBalancing.CircuitBreaker
  
  @type health_status :: %{
    provider_id: term(),
    node: node(),
    health_score: float(),
    status: :healthy | :degraded | :critical | :failed,
    last_check: non_neg_integer(),
    metrics: map(),
    error_count: non_neg_integer(),
    consecutive_failures: non_neg_integer(),
    recovery_count: non_neg_integer()
  }
  
  @type health_aggregation :: %{
    provider_id: term(),
    cluster_health_score: float(),
    node_statuses: %{node() => health_status()},
    overall_status: :healthy | :degraded | :critical | :failed,
    last_updated: non_neg_integer(),
    trend: :improving | :stable | :degrading
  }
  
  @health_check_interval 15_000
  @broadcast_interval 30_000
  @aggregation_interval 10_000
  @health_history_retention 300_000  # 5 minutes
  
  # Client API
  
  @doc """
  Start the HealthBroadcaster GenServer.
  
  ## Examples
  
      {:ok, pid} = HealthBroadcaster.start_link()
      {:ok, pid} = HealthBroadcaster.start_link(health_check_interval: 10_000)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Subscribe to health status updates for specific providers or patterns.
  
  ## Examples
  
      :ok = HealthBroadcaster.subscribe_to_health("provider.*")
      :ok = HealthBroadcaster.subscribe_to_health("provider.openai")
      :ok = HealthBroadcaster.subscribe_to_health("cluster.health", severity: :critical)
  """
  def subscribe_to_health(pattern, opts \\ []) do
    GenServer.call(__MODULE__, {:subscribe_to_health, self(), pattern, opts})
  end
  
  @doc """
  Unsubscribe from health status updates.
  
  ## Examples
  
      :ok = HealthBroadcaster.unsubscribe_from_health("provider.*")
  """
  def unsubscribe_from_health(pattern) do
    GenServer.call(__MODULE__, {:unsubscribe_from_health, self(), pattern})
  end
  
  @doc """
  Get current health status for a specific provider across all nodes.
  
  ## Examples
  
      health = HealthBroadcaster.get_provider_health(:openai)
      # %{
      #   provider_id: :openai,
      #   cluster_health_score: 0.94,
      #   node_statuses: %{node1: %{health_score: 0.95, ...}, ...},
      #   overall_status: :healthy
      # }
  """
  def get_provider_health(provider_id) do
    GenServer.call(__MODULE__, {:get_provider_health, provider_id})
  end
  
  @doc """
  Get cluster-wide health summary.
  
  ## Examples
  
      summary = HealthBroadcaster.get_cluster_health_summary()
      # %{
      #   overall_cluster_health: 0.89,
      #   healthy_providers: 5,
      #   degraded_providers: 1,
      #   failed_providers: 0,
      #   node_health_scores: %{...}
      # }
  """
  def get_cluster_health_summary do
    GenServer.call(__MODULE__, :get_cluster_health_summary)
  end
  
  @doc """
  Manually report health status for a provider.
  
  ## Examples
  
      health_data = %{
        health_score: 0.85,
        error_count: 2,
        last_error: "Connection timeout",
        response_time: 250
      }
      :ok = HealthBroadcaster.report_health(:openai, health_data)
  """
  def report_health(provider_id, health_data) do
    GenServer.cast(__MODULE__, {:report_health, provider_id, health_data})
  end
  
  @doc """
  Get health status history for analysis and trending.
  
  ## Examples
  
      history = HealthBroadcaster.get_health_history(:openai, minutes: 30)
      # [%{timestamp: ..., health_score: 0.95, status: :healthy}, ...]
  """
  def get_health_history(provider_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_health_history, provider_id, opts})
  end
  
  @doc """
  Trigger immediate health check for all providers.
  
  ## Examples
  
      :ok = HealthBroadcaster.trigger_health_check()
  """
  def trigger_health_check do
    GenServer.cast(__MODULE__, :trigger_health_check)
  end
  
  @doc """
  Get health broadcasting statistics.
  
  ## Examples
  
      stats = HealthBroadcaster.get_stats()
      # %{
      #   health_checks_performed: 1250,
      #   broadcasts_sent: 830,
      #   subscriptions_active: 8,
      #   providers_monitored: 6
      # }
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    health_check_interval = Keyword.get(opts, :health_check_interval, @health_check_interval)
    broadcast_interval = Keyword.get(opts, :broadcast_interval, @broadcast_interval)
    
    # Subscribe to relevant events
    EventBroadcaster.subscribe("provider.health.*")
    EventBroadcaster.subscribe("cluster.*")
    EventBroadcaster.subscribe("circuit_breaker.*")
    
    state = %{
      health_check_interval: health_check_interval,
      broadcast_interval: broadcast_interval,
      provider_health: %{},
      cluster_aggregations: %{},
      health_history: %{},
      health_subscriptions: %{},
      local_health_cache: %{},
      stats: %{
        health_checks_performed: 0,
        broadcasts_sent: 0,
        subscriptions_active: 0,
        providers_monitored: 0
      },
      health_check_timer: schedule_health_check(health_check_interval),
      broadcast_timer: schedule_broadcast(broadcast_interval),
      aggregation_timer: schedule_aggregation()
    }
    
    # Perform initial health check
    updated_state = perform_health_checks(state)
    
    Logger.info("HealthBroadcaster started")
    {:ok, updated_state}
  end
  
  @impl true
  def handle_call({:subscribe_to_health, subscriber, pattern, opts}, _from, state) do
    monitor_ref = Process.monitor(subscriber)
    
    subscription = %{
      subscriber: subscriber,
      pattern: pattern,
      severity_filter: Keyword.get(opts, :severity),
      node_filter: Keyword.get(opts, :node),
      monitor_ref: monitor_ref
    }
    
    subscription_key = {subscriber, pattern}
    updated_subscriptions = Map.put(state.health_subscriptions, subscription_key, subscription)
    
    updated_stats = %{state.stats | subscriptions_active: map_size(updated_subscriptions)}
    updated_state = %{state | health_subscriptions: updated_subscriptions, stats: updated_stats}
    
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call({:unsubscribe_from_health, subscriber, pattern}, _from, state) do
    subscription_key = {subscriber, pattern}
    
    case Map.get(state.health_subscriptions, subscription_key) do
      nil ->
        {:reply, :ok, state}
      
      subscription ->
        Process.demonitor(subscription.monitor_ref)
        updated_subscriptions = Map.delete(state.health_subscriptions, subscription_key)
        updated_stats = %{state.stats | subscriptions_active: map_size(updated_subscriptions)}
        updated_state = %{state | health_subscriptions: updated_subscriptions, stats: updated_stats}
        
        {:reply, :ok, updated_state}
    end
  end
  
  @impl true
  def handle_call({:get_provider_health, provider_id}, _from, state) do
    aggregation = Map.get(state.cluster_aggregations, provider_id)
    {:reply, aggregation, state}
  end
  
  @impl true
  def handle_call(:get_cluster_health_summary, _from, state) do
    summary = calculate_cluster_health_summary(state)
    {:reply, summary, state}
  end
  
  @impl true
  def handle_call({:get_health_history, provider_id, opts}, _from, state) do
    history = get_provider_health_history(state.health_history, provider_id, opts)
    {:reply, history, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end
  
  @impl true
  def handle_cast({:report_health, provider_id, health_data}, state) do
    current_time = System.monotonic_time(:millisecond)
    
    # Create health status from reported data
    health_status = %{
      provider_id: provider_id,
      node: node(),
      health_score: Map.get(health_data, :health_score, 0.0),
      status: determine_health_status(health_data),
      last_check: current_time,
      metrics: Map.get(health_data, :metrics, %{}),
      error_count: Map.get(health_data, :error_count, 0),
      consecutive_failures: Map.get(health_data, :consecutive_failures, 0),
      recovery_count: Map.get(health_data, :recovery_count, 0)
    }
    
    # Update local health cache
    updated_cache = Map.put(state.local_health_cache, provider_id, health_status)
    
    # Add to history
    updated_history = add_to_health_history(state.health_history, provider_id, health_status)
    
    # Broadcast health update
    broadcast_health_update(health_status)
    
    updated_state = %{state | 
      local_health_cache: updated_cache,
      health_history: updated_history
    }
    
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_cast(:trigger_health_check, state) do
    updated_state = perform_health_checks(state)
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info({:event, event}, state) do
    case event.topic do
      "provider.health." <> _type ->
        handle_health_event(event, state)
      
      "cluster.node_joined" ->
        handle_cluster_change_event(event, state)
      
      "cluster.node_left" ->
        handle_cluster_change_event(event, state)
      
      "circuit_breaker.state_changed" ->
        handle_circuit_breaker_event(event, state)
      
      _ ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:perform_health_check, state) do
    updated_state = perform_health_checks(state)
    
    # Schedule next health check
    timer = schedule_health_check(state.health_check_interval)
    
    {:noreply, %{updated_state | health_check_timer: timer}}
  end
  
  @impl true
  def handle_info(:broadcast_health, state) do
    # Broadcast current health status
    updated_state = broadcast_current_health(state)
    
    # Schedule next broadcast
    timer = schedule_broadcast(state.broadcast_interval)
    
    {:noreply, %{updated_state | broadcast_timer: timer}}
  end
  
  @impl true
  def handle_info(:aggregate_health, state) do
    # Aggregate health data from all nodes
    updated_state = aggregate_cluster_health(state)
    
    # Schedule next aggregation
    timer = schedule_aggregation()
    
    {:noreply, %{updated_state | aggregation_timer: timer}}
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove subscriptions for dead processes
    updated_subscriptions = state.health_subscriptions
    |> Enum.reject(fn {{subscriber, _pattern}, _sub} -> subscriber == pid end)
    |> Map.new()
    
    updated_stats = %{state.stats | subscriptions_active: map_size(updated_subscriptions)}
    updated_state = %{state | health_subscriptions: updated_subscriptions, stats: updated_stats}
    
    {:noreply, updated_state}
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
    if state.broadcast_timer do
      Process.cancel_timer(state.broadcast_timer)
    end
    if state.aggregation_timer do
      Process.cancel_timer(state.aggregation_timer)
    end
    :ok
  end
  
  # Private Functions
  
  defp perform_health_checks(state) do
    # Get current provider statuses from circuit breakers
    current_time = System.monotonic_time(:millisecond)
    
    provider_health_data = try do
      CircuitBreaker.get_all_provider_health()
    catch
      :exit, :noproc -> %{}
      _, _ -> %{}
    end
    
    # Update local health cache with fresh data
    updated_cache = Map.new(provider_health_data, fn {provider_id, health_data} ->
      health_status = %{
        provider_id: provider_id,
        node: node(),
        health_score: Map.get(health_data, :health_score, 0.0),
        status: determine_health_status(health_data),
        last_check: current_time,
        metrics: Map.get(health_data, :metrics, %{}),
        error_count: Map.get(health_data, :error_count, 0),
        consecutive_failures: Map.get(health_data, :consecutive_failures, 0),
        recovery_count: Map.get(health_data, :recovery_count, 0)
      }
      
      {provider_id, health_status}
    end)
    
    # Update health history
    updated_history = Enum.reduce(updated_cache, state.health_history, fn {provider_id, health_status}, acc ->
      add_to_health_history(acc, provider_id, health_status)
    end)
    
    # Update stats
    updated_stats = %{state.stats |
      health_checks_performed: state.stats.health_checks_performed + map_size(updated_cache),
      providers_monitored: map_size(updated_cache)
    }
    
    %{state |
      local_health_cache: updated_cache,
      health_history: updated_history,
      stats: updated_stats
    }
  end
  
  defp determine_health_status(health_data) do
    health_score = Map.get(health_data, :health_score, 0.0)
    consecutive_failures = Map.get(health_data, :consecutive_failures, 0)
    
    cond do
      health_score >= 0.9 and consecutive_failures == 0 -> :healthy
      health_score >= 0.7 and consecutive_failures < 3 -> :degraded
      health_score >= 0.3 or consecutive_failures < 10 -> :critical
      true -> :failed
    end
  end
  
  defp broadcast_health_update(health_status) do
    event = %{
      topic: "provider.health.update",
      payload: health_status,
      priority: :normal,
      metadata: %{
        source: :health_broadcaster,
        node: node()
      }
    }
    
    EventBroadcaster.broadcast_async(event)
  end
  
  defp broadcast_current_health(state) do
    # Broadcast all current health statuses
    Enum.each(state.local_health_cache, fn {_provider_id, health_status} ->
      broadcast_health_update(health_status)
    end)
    
    # Update stats
    broadcast_count = map_size(state.local_health_cache)
    updated_stats = %{state.stats | broadcasts_sent: state.stats.broadcasts_sent + broadcast_count}
    
    %{state | stats: updated_stats}
  end
  
  defp aggregate_cluster_health(state) do
    # Aggregate health data from provider_health (received from other nodes)
    updated_aggregations = state.provider_health
    |> Enum.group_by(fn {{provider_id, _node}, _health} -> provider_id end)
    |> Map.new(fn {provider_id, provider_node_data} ->
      node_statuses = Map.new(provider_node_data, fn {{_provider_id, node}, health_status} ->
        {node, health_status}
      end)
      
      # Calculate cluster health score for this provider
      health_scores = Enum.map(node_statuses, fn {_node, status} -> status.health_score end)
      cluster_health_score = if length(health_scores) > 0 do
        Enum.sum(health_scores) / length(health_scores)
      else
        0.0
      end
      
      # Determine overall status
      statuses = Enum.map(node_statuses, fn {_node, status} -> status.status end)
      overall_status = determine_overall_status(statuses)
      
      # Calculate trend (simplified)
      trend = calculate_health_trend(provider_id, state.health_history)
      
      aggregation = %{
        provider_id: provider_id,
        cluster_health_score: cluster_health_score,
        node_statuses: node_statuses,
        overall_status: overall_status,
        last_updated: System.monotonic_time(:millisecond),
        trend: trend
      }
      
      {provider_id, aggregation}
    end)
    
    # Notify subscribers of health aggregation updates
    notify_health_subscribers(updated_aggregations, state)
    
    %{state | cluster_aggregations: updated_aggregations}
  end
  
  defp determine_overall_status(statuses) do
    cond do
      Enum.any?(statuses, &(&1 == :failed)) -> :failed
      Enum.any?(statuses, &(&1 == :critical)) -> :critical
      Enum.any?(statuses, &(&1 == :degraded)) -> :degraded
      true -> :healthy
    end
  end
  
  defp calculate_health_trend(provider_id, health_history) do
    case Map.get(health_history, provider_id) do
      nil -> :stable
      history ->
        recent_scores = history
        |> Enum.take(-10)  # Last 10 data points
        |> Enum.map(& &1.health_score)
        
        if length(recent_scores) < 3 do
          :stable
        else
          first_half = Enum.take(recent_scores, div(length(recent_scores), 2))
          second_half = Enum.drop(recent_scores, div(length(recent_scores), 2))
          
          first_avg = Enum.sum(first_half) / length(first_half)
          second_avg = Enum.sum(second_half) / length(second_half)
          
          diff = second_avg - first_avg
          
          cond do
            diff > 0.1 -> :improving
            diff < -0.1 -> :degrading
            true -> :stable
          end
        end
    end
  end
  
  defp handle_health_event(event, state) do
    case event.payload do
      %{provider_id: provider_id, node: source_node} = health_status ->
        # Store health data from remote node
        key = {provider_id, source_node}
        updated_provider_health = Map.put(state.provider_health, key, health_status)
        
        {:noreply, %{state | provider_health: updated_provider_health}}
      
      _ ->
        {:noreply, state}
    end
  end
  
  defp handle_cluster_change_event(_event, state) do
    # Trigger health aggregation when cluster topology changes
    send(self(), :aggregate_health)
    {:noreply, state}
  end
  
  defp handle_circuit_breaker_event(event, state) do
    # Update health status based on circuit breaker state changes
    provider_id = event.payload.provider_id
    
    case Map.get(state.local_health_cache, provider_id) do
      nil ->
        {:noreply, state}
      
      current_health ->
        # Update health status based on circuit breaker state
        updated_health = case event.payload.state do
          :open -> %{current_health | status: :failed, consecutive_failures: current_health.consecutive_failures + 1}
          :half_open -> %{current_health | status: :degraded}
          :closed -> %{current_health | status: :healthy, consecutive_failures: 0, recovery_count: current_health.recovery_count + 1}
        end
        
        updated_cache = Map.put(state.local_health_cache, provider_id, updated_health)
        
        # Broadcast updated health
        broadcast_health_update(updated_health)
        
        {:noreply, %{state | local_health_cache: updated_cache}}
    end
  end
  
  defp notify_health_subscribers(aggregations, state) do
    Enum.each(aggregations, fn {provider_id, aggregation} ->
      matching_subscriptions = find_matching_health_subscriptions(provider_id, state.health_subscriptions)
      
      Enum.each(matching_subscriptions, fn subscription ->
        if should_deliver_health_update?(aggregation, subscription) do
          send(subscription.subscriber, {:health_update, aggregation})
        end
      end)
    end)
  end
  
  defp find_matching_health_subscriptions(provider_id, subscriptions) do
    provider_string = to_string(provider_id)
    
    Enum.filter(subscriptions, fn {_key, subscription} ->
      pattern_matches_provider?(provider_string, subscription.pattern)
    end)
    |> Enum.map(fn {_key, subscription} -> subscription end)
  end
  
  defp pattern_matches_provider?(provider_string, pattern) do
    case String.split(pattern, ".") do
      ["provider", "*"] -> true
      ["provider", ^provider_string] -> true
      ["cluster", "health"] -> true
      _ -> false
    end
  end
  
  defp should_deliver_health_update?(aggregation, subscription) do
    severity_match = case subscription.severity_filter do
      nil -> true
      filter_severity -> severity_matches?(aggregation.overall_status, filter_severity)
    end
    
    node_match = case subscription.node_filter do
      nil -> true
      filter_node -> Map.has_key?(aggregation.node_statuses, filter_node)
    end
    
    severity_match and node_match
  end
  
  defp severity_matches?(status, filter) do
    case {status, filter} do
      {:failed, :critical} -> true
      {:critical, :critical} -> true
      {:degraded, :degraded} -> true
      {:healthy, :healthy} -> true
      _ -> false
    end
  end
  
  defp add_to_health_history(history, provider_id, health_status) do
    current_history = Map.get(history, provider_id, [])
    updated_history = [health_status | current_history]
    
    # Trim history to retention limit
    cutoff_time = System.monotonic_time(:millisecond) - @health_history_retention
    trimmed_history = Enum.filter(updated_history, fn status ->
      status.last_check > cutoff_time
    end)
    
    Map.put(history, provider_id, trimmed_history)
  end
  
  defp get_provider_health_history(history, provider_id, opts) do
    case Map.get(history, provider_id) do
      nil -> []
      provider_history ->
        limit = Keyword.get(opts, :limit, 100)
        minutes = Keyword.get(opts, :minutes)
        
        filtered_history = if minutes do
          cutoff_time = System.monotonic_time(:millisecond) - (minutes * 60 * 1000)
          Enum.filter(provider_history, fn status -> status.last_check > cutoff_time end)
        else
          provider_history
        end
        
        Enum.take(filtered_history, limit)
    end
  end
  
  defp calculate_cluster_health_summary(state) do
    aggregations = Map.values(state.cluster_aggregations)
    
    if length(aggregations) == 0 do
      %{
        overall_cluster_health: 0.0,
        healthy_providers: 0,
        degraded_providers: 0,
        critical_providers: 0,
        failed_providers: 0,
        total_providers: 0,
        node_health_scores: %{}
      }
    else
      status_counts = Enum.reduce(aggregations, %{healthy: 0, degraded: 0, critical: 0, failed: 0}, fn agg, acc ->
        Map.update!(acc, agg.overall_status, &(&1 + 1))
      end)
      
      overall_health = aggregations
      |> Enum.map(& &1.cluster_health_score)
      |> Enum.sum()
      |> Kernel./(length(aggregations))
      
      # Calculate node health scores
      node_health_scores = aggregations
      |> Enum.flat_map(fn agg -> Map.to_list(agg.node_statuses) end)
      |> Enum.group_by(fn {node, _status} -> node end)
      |> Map.new(fn {node, statuses} ->
        node_scores = Enum.map(statuses, fn {_node, status} -> status.health_score end)
        avg_score = Enum.sum(node_scores) / length(node_scores)
        {node, avg_score}
      end)
      
      %{
        overall_cluster_health: overall_health,
        healthy_providers: status_counts.healthy,
        degraded_providers: status_counts.degraded,
        critical_providers: status_counts.critical,
        failed_providers: status_counts.failed,
        total_providers: length(aggregations),
        node_health_scores: node_health_scores
      }
    end
  end
  
  defp schedule_health_check(interval) do
    Process.send_after(self(), :perform_health_check, interval)
  end
  
  defp schedule_broadcast(interval) do
    Process.send_after(self(), :broadcast_health, interval)
  end
  
  defp schedule_aggregation do
    Process.send_after(self(), :aggregate_health, @aggregation_interval)
  end
end