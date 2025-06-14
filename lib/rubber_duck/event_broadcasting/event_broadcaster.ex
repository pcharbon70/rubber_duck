defmodule RubberDuck.EventBroadcasting.EventBroadcaster do
  @moduledoc """
  Distributed event broadcasting using OTP's native pg (process groups).
  
  Provides reliable, efficient event distribution across cluster nodes without
  external dependencies. Supports topic-based routing, event persistence,
  filtering, and acknowledgment patterns for critical events.
  """
  
  use GenServer
  require Logger
  
  @type event :: %{
    id: String.t(),
    topic: String.t(),
    payload: term(),
    timestamp: non_neg_integer(),
    source_node: node(),
    priority: :low | :normal | :high | :critical,
    metadata: map()
  }
  
  @type subscription :: %{
    subscriber: pid(),
    topic_pattern: String.t(),
    filter_fn: function() | nil,
    ack_required: boolean()
  }
  
  @type broadcast_options :: [
    ack_required: boolean(),
    timeout: non_neg_integer(),
    priority: atom(),
    persist: boolean(),
    filter_fn: function() | nil
  ]
  
  @default_timeout 5_000
  @max_event_history 1000
  @cleanup_interval 60_000
  
  # Client API
  
  @doc """
  Start the EventBroadcaster GenServer.
  
  ## Examples
  
      {:ok, pid} = EventBroadcaster.start_link()
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Subscribe to events for a specific topic pattern.
  
  ## Examples
  
      :ok = EventBroadcaster.subscribe("provider.health.*")
      :ok = EventBroadcaster.subscribe("metrics.performance", ack_required: true)
      :ok = EventBroadcaster.subscribe("cluster.*", filter_fn: fn event -> 
        event.payload.severity == :critical 
      end)
  """
  def subscribe(topic_pattern, opts \\ []) do
    GenServer.call(__MODULE__, {:subscribe, self(), topic_pattern, opts})
  end
  
  @doc """
  Unsubscribe from a topic pattern.
  
  ## Examples
  
      :ok = EventBroadcaster.unsubscribe("provider.health.*")
  """
  def unsubscribe(topic_pattern) do
    GenServer.call(__MODULE__, {:unsubscribe, self(), topic_pattern})
  end
  
  @doc """
  Broadcast an event to all subscribers.
  
  ## Examples
  
      event = %{
        topic: "provider.health.change",
        payload: %{provider_id: :openai, health_score: 0.95},
        priority: :normal
      }
      
      :ok = EventBroadcaster.broadcast(event)
      {:ok, ack_count} = EventBroadcaster.broadcast(event, ack_required: true, timeout: 10_000)
  """
  def broadcast(event_data, opts \\ []) do
    GenServer.call(__MODULE__, {:broadcast, event_data, opts}, 
                   Keyword.get(opts, :timeout, @default_timeout))
  end
  
  @doc """
  Broadcast an event asynchronously (fire-and-forget).
  
  ## Examples
  
      event = %{topic: "metrics.update", payload: %{cpu_usage: 0.45}}
      :ok = EventBroadcaster.broadcast_async(event)
  """
  def broadcast_async(event_data, opts \\ []) do
    GenServer.cast(__MODULE__, {:broadcast_async, event_data, opts})
  end
  
  @doc """
  Send acknowledgment for a received event.
  
  ## Examples
  
      :ok = EventBroadcaster.acknowledge(event_id)
  """
  def acknowledge(event_id) do
    GenServer.cast(__MODULE__, {:acknowledge, event_id, self()})
  end
  
  @doc """
  Get recent event history.
  
  ## Examples
  
      events = EventBroadcaster.get_event_history()
      events = EventBroadcaster.get_event_history(topic: "provider.*", limit: 50)
  """
  def get_event_history(opts \\ []) do
    GenServer.call(__MODULE__, {:get_event_history, opts})
  end
  
  @doc """
  Get current subscription statistics.
  
  ## Examples
  
      stats = EventBroadcaster.get_stats()
      # %{
      #   subscription_count: 15,
      #   total_events_sent: 1250,
      #   pending_acks: 3,
      #   nodes_connected: 4
      # }
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Get list of active subscribers.
  
  ## Examples
  
      subscribers = EventBroadcaster.get_subscribers()
      topic_subscribers = EventBroadcaster.get_subscribers("provider.health.*")
  """
  def get_subscribers(topic_pattern \\ nil) do
    GenServer.call(__MODULE__, {:get_subscribers, topic_pattern})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Join the event broadcasting process group
    # pg should already be started by the application
    group_name = :event_broadcaster
    :pg.join(group_name, self())
    
    # Monitor cluster nodes
    :net_kernel.monitor_nodes(true)
    
    state = %{
      subscriptions: %{},
      event_history: :queue.new(),
      pending_acks: %{},
      stats: %{
        events_sent: 0,
        events_received: 0,
        acks_received: 0,
        subscription_count: 0
      },
      cleanup_timer: schedule_cleanup(),
      group_name: group_name,
      persist_events: Keyword.get(opts, :persist_events, true)
    }
    
    Logger.info("EventBroadcaster started on node #{node()}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:subscribe, subscriber, topic_pattern, opts}, _from, state) do
    monitor_ref = Process.monitor(subscriber)
    
    subscription = %{
      subscriber: subscriber,
      topic_pattern: topic_pattern,
      filter_fn: Keyword.get(opts, :filter_fn),
      ack_required: Keyword.get(opts, :ack_required, false),
      monitor_ref: monitor_ref
    }
    
    subscription_key = {subscriber, topic_pattern}
    updated_subscriptions = Map.put(state.subscriptions, subscription_key, subscription)
    
    updated_stats = %{state.stats | subscription_count: map_size(updated_subscriptions)}
    updated_state = %{state | subscriptions: updated_subscriptions, stats: updated_stats}
    
    Logger.debug("New subscription: #{subscriber |> inspect} -> #{topic_pattern}")
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call({:unsubscribe, subscriber, topic_pattern}, _from, state) do
    subscription_key = {subscriber, topic_pattern}
    
    case Map.get(state.subscriptions, subscription_key) do
      nil ->
        {:reply, :ok, state}
      
      subscription ->
        Process.demonitor(subscription.monitor_ref)
        updated_subscriptions = Map.delete(state.subscriptions, subscription_key)
        updated_stats = %{state.stats | subscription_count: map_size(updated_subscriptions)}
        updated_state = %{state | subscriptions: updated_subscriptions, stats: updated_stats}
        
        Logger.debug("Removed subscription: #{subscriber |> inspect} -> #{topic_pattern}")
        {:reply, :ok, updated_state}
    end
  end
  
  @impl true
  def handle_call({:broadcast, event_data, opts}, _from, state) do
    event = create_event(event_data, opts)
    ack_required = Keyword.get(opts, :ack_required, false)
    
    # Store event in history if persistence is enabled
    updated_state = if state.persist_events do
      add_to_history(state, event)
    else
      state
    end
    
    # Broadcast to local subscribers
    {local_sent, local_acks_expected} = broadcast_to_local_subscribers(event, updated_state)
    
    # Broadcast to remote nodes via pg
    remote_sent = broadcast_to_remote_nodes(event, updated_state)
    
    total_sent = local_sent + remote_sent
    
    final_state = %{updated_state | 
      stats: %{updated_state.stats | events_sent: updated_state.stats.events_sent + total_sent}
    }
    
    if ack_required do
      # Store pending ack info
      ack_info = %{
        event_id: event.id,
        expected_acks: local_acks_expected,
        received_acks: 0,
        timeout: Keyword.get(opts, :timeout, @default_timeout)
      }
      
      pending_acks = Map.put(final_state.pending_acks, event.id, ack_info)
      ack_state = %{final_state | pending_acks: pending_acks}
      
      # Schedule timeout for acks
      Process.send_after(self(), {:ack_timeout, event.id}, ack_info.timeout)
      
      {:reply, {:ok, :ack_pending}, ack_state}
    else
      {:reply, :ok, final_state}
    end
  end
  
  @impl true
  def handle_call({:get_event_history, opts}, _from, state) do
    topic_filter = Keyword.get(opts, :topic)
    limit = Keyword.get(opts, :limit, @max_event_history)
    
    events = state.event_history
    |> :queue.to_list()
    |> Enum.reverse()
    |> filter_events_by_topic(topic_filter)
    |> Enum.take(limit)
    
    {:reply, events, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    enhanced_stats = Map.merge(state.stats, %{
      pending_acks: map_size(state.pending_acks),
      history_size: :queue.len(state.event_history),
      nodes_connected: length(:pg.get_members(state.group_name)) - 1
    })
    
    {:reply, enhanced_stats, state}
  end
  
  @impl true
  def handle_call({:get_subscribers, topic_pattern}, _from, state) do
    subscribers = if topic_pattern do
      state.subscriptions
      |> Enum.filter(fn {{_pid, pattern}, _sub} -> pattern == topic_pattern end)
      |> Enum.map(fn {{pid, _pattern}, sub} -> {pid, sub} end)
    else
      state.subscriptions
      |> Enum.map(fn {{pid, _pattern}, sub} -> {pid, sub} end)
    end
    
    {:reply, subscribers, state}
  end
  
  @impl true
  def handle_cast({:broadcast_async, event_data, opts}, state) do
    event = create_event(event_data, opts)
    
    # Store event in history if persistence is enabled
    updated_state = if state.persist_events do
      add_to_history(state, event)
    else
      state
    end
    
    # Broadcast to local and remote subscribers
    {local_sent, _acks} = broadcast_to_local_subscribers(event, updated_state)
    remote_sent = broadcast_to_remote_nodes(event, updated_state)
    
    total_sent = local_sent + remote_sent
    final_state = %{updated_state | 
      stats: %{updated_state.stats | events_sent: updated_state.stats.events_sent + total_sent}
    }
    
    {:noreply, final_state}
  end
  
  @impl true
  def handle_cast({:acknowledge, event_id, subscriber}, state) do
    case Map.get(state.pending_acks, event_id) do
      nil ->
        {:noreply, state}
      
      ack_info ->
        updated_ack_info = %{ack_info | received_acks: ack_info.received_acks + 1}
        updated_pending_acks = Map.put(state.pending_acks, event_id, updated_ack_info)
        
        updated_stats = %{state.stats | acks_received: state.stats.acks_received + 1}
        
        # Check if all acks received
        final_pending_acks = if updated_ack_info.received_acks >= updated_ack_info.expected_acks do
          Logger.debug("All acks received for event #{event_id}")
          Map.delete(updated_pending_acks, event_id)
        else
          updated_pending_acks
        end
        
        updated_state = %{state | 
          pending_acks: final_pending_acks, 
          stats: updated_stats
        }
        
        {:noreply, updated_state}
    end
  end
  
  @impl true
  def handle_cast({:remote_event, event}, state) do
    # Handle event received from remote node
    {sent_count, _acks} = broadcast_to_local_subscribers(event, state)
    
    updated_stats = %{state.stats | 
      events_received: state.stats.events_received + 1,
      events_sent: state.stats.events_sent + sent_count
    }
    
    updated_state = if state.persist_events do
      add_to_history(%{state | stats: updated_stats}, event)
    else
      %{state | stats: updated_stats}
    end
    
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info({:ack_timeout, event_id}, state) do
    case Map.get(state.pending_acks, event_id) do
      nil ->
        {:noreply, state}
      
      ack_info ->
        Logger.warning("Acknowledgment timeout for event #{event_id}. " <>
                      "Received #{ack_info.received_acks}/#{ack_info.expected_acks} acks")
        
        updated_pending_acks = Map.delete(state.pending_acks, event_id)
        {:noreply, %{state | pending_acks: updated_pending_acks}}
    end
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove subscriptions for dead processes
    updated_subscriptions = state.subscriptions
    |> Enum.reject(fn {{subscriber, _topic}, _sub} -> subscriber == pid end)
    |> Map.new()
    
    updated_stats = %{state.stats | subscription_count: map_size(updated_subscriptions)}
    updated_state = %{state | subscriptions: updated_subscriptions, stats: updated_stats}
    
    Logger.debug("Removed subscriptions for dead process #{inspect(pid)}")
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("Node joined cluster: #{node}")
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.info("Node left cluster: #{node}")
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Cleanup old events from history
    cutoff_time = System.monotonic_time(:millisecond) - (24 * 60 * 60 * 1000)  # 24 hours
    
    cleaned_history = state.event_history
    |> :queue.to_list()
    |> Enum.filter(fn event -> event.timestamp > cutoff_time end)
    |> :queue.from_list()
    
    # Cleanup expired pending acks
    current_time = System.monotonic_time(:millisecond)
    cleaned_pending_acks = state.pending_acks
    |> Enum.reject(fn {_id, ack_info} -> 
      current_time - ack_info.timeout > 60_000  # 1 minute grace period
    end)
    |> Map.new()
    
    updated_state = %{state | 
      event_history: cleaned_history,
      pending_acks: cleaned_pending_acks
    }
    
    # Schedule next cleanup
    timer = schedule_cleanup()
    
    {:noreply, %{updated_state | cleanup_timer: timer}}
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    :pg.leave(state.group_name, self())
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end
    :ok
  end
  
  # Private Functions
  
  defp create_event(event_data, opts) do
    %{
      id: generate_event_id(),
      topic: Map.get(event_data, :topic, ""),
      payload: Map.get(event_data, :payload, %{}),
      timestamp: System.monotonic_time(:millisecond),
      source_node: node(),
      priority: Map.get(event_data, :priority, :normal),
      metadata: Map.get(event_data, :metadata, %{})
    }
  end
  
  defp generate_event_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
  
  defp broadcast_to_local_subscribers(event, state) do
    matching_subscriptions = find_matching_subscriptions(event.topic, state.subscriptions)
    
    {sent_count, acks_expected} = Enum.reduce(matching_subscriptions, {0, 0}, fn subscription, {sent, acks} ->
      if should_deliver_event?(event, subscription) do
        send(subscription.subscriber, {:event, event})
        new_acks = if subscription.ack_required, do: acks + 1, else: acks
        {sent + 1, new_acks}
      else
        {sent, acks}
      end
    end)
    
    {sent_count, acks_expected}
  end
  
  defp broadcast_to_remote_nodes(event, state) do
    remote_members = :pg.get_members(state.group_name)
    |> Enum.reject(&(&1 == self()))
    
    Enum.each(remote_members, fn member ->
      GenServer.cast(member, {:remote_event, event})
    end)
    
    length(remote_members)
  end
  
  defp find_matching_subscriptions(topic, subscriptions) do
    Enum.filter(subscriptions, fn {_key, subscription} ->
      topic_matches?(topic, subscription.topic_pattern)
    end)
    |> Enum.map(fn {_key, subscription} -> subscription end)
  end
  
  defp topic_matches?(topic, pattern) do
    # Simple wildcard matching (* matches any segment)
    topic_parts = String.split(topic, ".")
    pattern_parts = String.split(pattern, ".")
    
    match_parts?(topic_parts, pattern_parts)
  end
  
  defp match_parts?([], []), do: true
  defp match_parts?([], ["*"]), do: true
  defp match_parts?(_topic, []), do: false
  defp match_parts?([], _pattern), do: false
  
  defp match_parts?([topic_part | topic_rest], ["*" | pattern_rest]) do
    match_parts?(topic_rest, pattern_rest)
  end
  
  defp match_parts?([topic_part | topic_rest], [pattern_part | pattern_rest]) 
       when topic_part == pattern_part do
    match_parts?(topic_rest, pattern_rest)
  end
  
  defp match_parts?(_topic, _pattern), do: false
  
  defp should_deliver_event?(event, subscription) do
    case subscription.filter_fn do
      nil -> true
      filter_fn when is_function(filter_fn, 1) ->
        try do
          filter_fn.(event)
        rescue
          _ -> false
        end
      _ -> true
    end
  end
  
  defp add_to_history(state, event) do
    updated_history = :queue.in(event, state.event_history)
    
    # Trim history if it exceeds max size
    final_history = if :queue.len(updated_history) > @max_event_history do
      {_, trimmed_history} = :queue.out(updated_history)
      trimmed_history
    else
      updated_history
    end
    
    %{state | event_history: final_history}
  end
  
  defp filter_events_by_topic(events, nil), do: events
  defp filter_events_by_topic(events, topic_pattern) do
    Enum.filter(events, fn event ->
      topic_matches?(event.topic, topic_pattern)
    end)
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end