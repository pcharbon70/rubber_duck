defmodule RubberDuck.EventBroadcasting.ClusterEventCoordinator do
  @moduledoc """
  Cluster event coordination for handling node join/leave events and topology changes.
  
  Monitors cluster topology, coordinates provider redistribution, manages graceful
  failover procedures, and ensures cluster-wide consistency during topology changes.
  Integrates with load balancing and health monitoring systems for automatic adaptation.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.EventBroadcasting.{EventBroadcaster, MetricsCollector}
  alias RubberDuck.LoadBalancing.{LoadBalancer, FailoverManager}
  
  @type node_info :: %{
    node: node(),
    joined_at: non_neg_integer(),
    capabilities: map(),
    status: :joining | :active | :leaving | :failed,
    health_score: float(),
    last_heartbeat: non_neg_integer(),
    provider_count: non_neg_integer()
  }
  
  @type cluster_state :: %{
    nodes: %{node() => node_info()},
    cluster_leader: node() | nil,
    topology_version: non_neg_integer(),
    last_topology_change: non_neg_integer(),
    quorum_size: non_neg_integer()
  }
  
  @heartbeat_interval 30_000
  @node_timeout 90_000
  @leadership_timeout 60_000
  @rebalance_delay 10_000
  
  # Client API
  
  @doc """
  Start the ClusterEventCoordinator GenServer.
  
  ## Examples
  
      {:ok, pid} = ClusterEventCoordinator.start_link()
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get current cluster topology information.
  
  ## Examples
  
      topology = ClusterEventCoordinator.get_cluster_topology()
      # %{
      #   nodes: %{node1: %{status: :active, ...}, ...},
      #   cluster_leader: :node1,
      #   topology_version: 5,
      #   total_nodes: 3,
      #   healthy_nodes: 3
      # }
  """
  def get_cluster_topology do
    GenServer.call(__MODULE__, :get_cluster_topology)
  end
  
  @doc """
  Get information about a specific node.
  
  ## Examples
  
      node_info = ClusterEventCoordinator.get_node_info(:node1)
      # %{node: :node1, status: :active, health_score: 0.95, ...}
  """
  def get_node_info(node) do
    GenServer.call(__MODULE__, {:get_node_info, node})
  end
  
  @doc """
  Announce node capabilities to the cluster.
  
  ## Examples
  
      capabilities = %{
        providers: [:openai, :anthropic],
        max_concurrent_requests: 100,
        preferred_models: ["gpt-4", "claude-3"]
      }
      :ok = ClusterEventCoordinator.announce_capabilities(capabilities)
  """
  def announce_capabilities(capabilities) do
    GenServer.call(__MODULE__, {:announce_capabilities, capabilities})
  end
  
  @doc """
  Initiate graceful shutdown of a node.
  
  ## Examples
  
      :ok = ClusterEventCoordinator.initiate_graceful_shutdown()
      :ok = ClusterEventCoordinator.initiate_graceful_shutdown(:node2)
  """
  def initiate_graceful_shutdown(target_node \\ node()) do
    GenServer.call(__MODULE__, {:initiate_graceful_shutdown, target_node})
  end
  
  @doc """
  Force immediate provider redistribution.
  
  ## Examples
  
      :ok = ClusterEventCoordinator.force_redistribution()
  """
  def force_redistribution do
    GenServer.call(__MODULE__, :force_redistribution)
  end
  
  @doc """
  Check if the current node is the cluster leader.
  
  ## Examples
  
      true = ClusterEventCoordinator.is_leader?()
  """
  def is_leader? do
    GenServer.call(__MODULE__, :is_leader)
  end
  
  @doc """
  Get cluster health and status information.
  
  ## Examples
  
      health = ClusterEventCoordinator.get_cluster_health()
      # %{
      #   overall_health: 0.94,
      #   node_count: 4,
      #   healthy_nodes: 4,
      #   cluster_stability: :stable,
      #   split_brain_risk: :low
      # }
  """
  def get_cluster_health do
    GenServer.call(__MODULE__, :get_cluster_health)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Monitor cluster nodes
    :net_kernel.monitor_nodes(true, [:nodedown_reason])
    
    # Subscribe to events
    EventBroadcaster.subscribe("cluster.*")
    EventBroadcaster.subscribe("provider.*")
    
    # Initialize cluster state
    current_time = System.monotonic_time(:millisecond)
    initial_capabilities = Keyword.get(opts, :initial_capabilities, %{})
    
    state = %{
      cluster_state: %{
        nodes: %{
          node() => create_node_info(node(), current_time, initial_capabilities)
        },
        cluster_leader: nil,
        topology_version: 1,
        last_topology_change: current_time,
        quorum_size: 1
      },
      heartbeat_timer: schedule_heartbeat(),
      leadership_timer: nil,
      pending_redistributions: [],
      node_capabilities: %{node() => initial_capabilities}
    }
    
    # Attempt to join existing cluster or become leader
    updated_state = attempt_cluster_join(state)
    
    Logger.info("ClusterEventCoordinator started on node #{node()}")
    {:ok, updated_state}
  end
  
  @impl true
  def handle_call(:get_cluster_topology, _from, state) do
    topology = build_topology_response(state.cluster_state)
    {:reply, topology, state}
  end
  
  @impl true
  def handle_call({:get_node_info, target_node}, _from, state) do
    node_info = Map.get(state.cluster_state.nodes, target_node)
    {:reply, node_info, state}
  end
  
  @impl true
  def handle_call({:announce_capabilities, capabilities}, _from, state) do
    current_node = node()
    updated_capabilities = Map.put(state.node_capabilities, current_node, capabilities)
    
    # Update node info in cluster state
    updated_nodes = Map.update!(state.cluster_state.nodes, current_node, fn node_info ->
      %{node_info | capabilities: capabilities}
    end)
    
    updated_cluster_state = %{state.cluster_state | nodes: updated_nodes}
    updated_state = %{state | 
      cluster_state: updated_cluster_state,
      node_capabilities: updated_capabilities
    }
    
    # Broadcast capability announcement
    capability_event = %{
      topic: "cluster.capabilities_announced",
      payload: %{
        node: current_node,
        capabilities: capabilities,
        timestamp: System.monotonic_time(:millisecond)
      }
    }
    EventBroadcaster.broadcast_async(capability_event)
    
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call({:initiate_graceful_shutdown, target_node}, _from, state) do
    if target_node == node() do
      # Initiate graceful shutdown of current node
      updated_state = begin_graceful_shutdown(state)
      {:reply, :ok, updated_state}
    else
      # Request graceful shutdown of remote node
      shutdown_event = %{
        topic: "cluster.graceful_shutdown_requested",
        payload: %{
          target_node: target_node,
          requesting_node: node(),
          timestamp: System.monotonic_time(:millisecond)
        }
      }
      EventBroadcaster.broadcast_async(shutdown_event)
      {:reply, :ok, state}
    end
  end
  
  @impl true
  def handle_call(:force_redistribution, _from, state) do
    if is_cluster_leader?(state) do
      updated_state = trigger_provider_redistribution(state, :forced)
      {:reply, :ok, updated_state}
    else
      {:reply, {:error, :not_leader}, state}
    end
  end
  
  @impl true
  def handle_call(:is_leader, _from, state) do
    is_leader = is_cluster_leader?(state)
    {:reply, is_leader, state}
  end
  
  @impl true
  def handle_call(:get_cluster_health, _from, state) do
    health = calculate_cluster_health(state)
    {:reply, health, state}
  end
  
  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("Node joined cluster: #{node}")
    
    current_time = System.monotonic_time(:millisecond)
    new_node_info = create_node_info(node, current_time, %{})
    
    # Update cluster state
    updated_nodes = Map.put(state.cluster_state.nodes, node, new_node_info)
    updated_topology_version = state.cluster_state.topology_version + 1
    
    updated_cluster_state = %{state.cluster_state |
      nodes: updated_nodes,
      topology_version: updated_topology_version,
      last_topology_change: current_time
    }
    
    updated_state = %{state | cluster_state: updated_cluster_state}
    
    # Broadcast node join event
    join_event = %{
      topic: "cluster.node_joined",
      payload: %{
        node: node,
        topology_version: updated_topology_version,
        timestamp: current_time
      }
    }
    EventBroadcaster.broadcast_async(join_event)
    
    # Schedule provider redistribution if we're the leader
    final_state = if is_cluster_leader?(updated_state) do
      schedule_provider_redistribution(updated_state, :node_join)
    else
      updated_state
    end
    
    {:noreply, final_state}
  end
  
  @impl true
  def handle_info({:nodedown, node, reason}, state) do
    Logger.warning("Node left cluster: #{node}, reason: #{inspect(reason)}")
    
    current_time = System.monotonic_time(:millisecond)
    
    # Update cluster state
    updated_nodes = Map.delete(state.cluster_state.nodes, node)
    updated_topology_version = state.cluster_state.topology_version + 1
    
    updated_cluster_state = %{state.cluster_state |
      nodes: updated_nodes,
      topology_version: updated_topology_version,
      last_topology_change: current_time
    }
    
    # Check if we need a new leader
    needs_new_leader = state.cluster_state.cluster_leader == node
    
    updated_cluster_state = if needs_new_leader do
      %{updated_cluster_state | cluster_leader: nil}
    else
      updated_cluster_state
    end
    
    updated_state = %{state | cluster_state: updated_cluster_state}
    
    # Broadcast node leave event
    leave_event = %{
      topic: "cluster.node_left",
      payload: %{
        node: node,
        reason: reason,
        topology_version: updated_topology_version,
        timestamp: current_time
      }
    }
    EventBroadcaster.broadcast_async(leave_event)
    
    # Trigger leadership election if needed
    final_state = if needs_new_leader do
      attempt_leadership_election(updated_state)
    else
      updated_state
    end
    
    # Schedule provider redistribution if we're the leader
    final_state = if is_cluster_leader?(final_state) do
      schedule_provider_redistribution(final_state, :node_leave)
    else
      final_state
    end
    
    {:noreply, final_state}
  end
  
  @impl true
  def handle_info({:event, event}, state) do
    case event.topic do
      "cluster.heartbeat" ->
        handle_heartbeat_event(event, state)
      
      "cluster.leadership_claim" ->
        handle_leadership_claim_event(event, state)
      
      "cluster.graceful_shutdown_requested" ->
        handle_graceful_shutdown_request(event, state)
      
      "provider.health_changed" ->
        handle_provider_health_change(event, state)
      
      _ ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:send_heartbeat, state) do
    # Send heartbeat to cluster
    heartbeat_event = %{
      topic: "cluster.heartbeat",
      payload: %{
        node: node(),
        timestamp: System.monotonic_time(:millisecond),
        status: :active,
        capabilities: Map.get(state.node_capabilities, node(), %{}),
        provider_count: get_local_provider_count()
      }
    }
    
    EventBroadcaster.broadcast_async(heartbeat_event)
    
    # Schedule next heartbeat
    timer = schedule_heartbeat()
    
    {:noreply, %{state | heartbeat_timer: timer}}
  end
  
  @impl true
  def handle_info(:check_node_timeouts, state) do
    current_time = System.monotonic_time(:millisecond)
    timeout_threshold = current_time - @node_timeout
    
    # Find timed out nodes
    {timed_out_nodes, active_nodes} = Enum.split_with(state.cluster_state.nodes, fn {_node, info} ->
      info.last_heartbeat < timeout_threshold
    end)
    
    if length(timed_out_nodes) > 0 do
      Logger.warning("Detected timed out nodes: #{inspect(Enum.map(timed_out_nodes, fn {node, _} -> node end))}")
      
      # Remove timed out nodes
      updated_nodes = Map.new(active_nodes)
      updated_topology_version = state.cluster_state.topology_version + 1
      
      updated_cluster_state = %{state.cluster_state |
        nodes: updated_nodes,
        topology_version: updated_topology_version,
        last_topology_change: current_time
      }
      
      updated_state = %{state | cluster_state: updated_cluster_state}
      
      # Broadcast timeout events
      Enum.each(timed_out_nodes, fn {timed_out_node, _info} ->
        timeout_event = %{
          topic: "cluster.node_timeout",
          payload: %{
            node: timed_out_node,
            timestamp: current_time,
            detected_by: node()
          }
        }
        EventBroadcaster.broadcast_async(timeout_event)
      end)
      
      {:noreply, updated_state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:trigger_redistribution, reason}, state) do
    if is_cluster_leader?(state) do
      updated_state = trigger_provider_redistribution(state, reason)
      {:noreply, updated_state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    if state.heartbeat_timer do
      Process.cancel_timer(state.heartbeat_timer)
    end
    if state.leadership_timer do
      Process.cancel_timer(state.leadership_timer)
    end
    
    # Broadcast graceful shutdown
    shutdown_event = %{
      topic: "cluster.node_shutdown",
      payload: %{
        node: node(),
        timestamp: System.monotonic_time(:millisecond),
        graceful: true
      }
    }
    EventBroadcaster.broadcast_async(shutdown_event)
    
    :ok
  end
  
  # Private Functions
  
  defp create_node_info(node, timestamp, capabilities) do
    %{
      node: node,
      joined_at: timestamp,
      capabilities: capabilities,
      status: :active,
      health_score: 1.0,
      last_heartbeat: timestamp,
      provider_count: 0
    }
  end
  
  defp attempt_cluster_join(state) do
    # Check if there are other nodes in the cluster
    other_nodes = Node.list()
    
    if length(other_nodes) > 0 do
      # Request to join existing cluster
      join_request = %{
        topic: "cluster.join_request",
        payload: %{
          requesting_node: node(),
          timestamp: System.monotonic_time(:millisecond),
          capabilities: Map.get(state.node_capabilities, node(), %{})
        }
      }
      EventBroadcaster.broadcast_async(join_request)
      
      state
    else
      # Become the cluster leader
      become_cluster_leader(state)
    end
  end
  
  defp become_cluster_leader(state) do
    Logger.info("Becoming cluster leader: #{node()}")
    
    updated_cluster_state = %{state.cluster_state | cluster_leader: node()}
    
    # Broadcast leadership claim
    leadership_event = %{
      topic: "cluster.leadership_claimed",
      payload: %{
        leader_node: node(),
        timestamp: System.monotonic_time(:millisecond),
        topology_version: state.cluster_state.topology_version
      }
    }
    EventBroadcaster.broadcast_async(leadership_event)
    
    %{state | cluster_state: updated_cluster_state}
  end
  
  defp attempt_leadership_election(state) do
    # Simple leadership election: node with smallest name becomes leader
    candidate_nodes = Map.keys(state.cluster_state.nodes)
    
    if length(candidate_nodes) > 0 do
      leader_candidate = Enum.min(candidate_nodes)
      
      if leader_candidate == node() do
        become_cluster_leader(state)
      else
        # Wait for leader to be established
        timer = Process.send_after(self(), :check_leadership, @leadership_timeout)
        %{state | leadership_timer: timer}
      end
    else
      state
    end
  end
  
  defp is_cluster_leader?(state) do
    state.cluster_state.cluster_leader == node()
  end
  
  defp schedule_provider_redistribution(state, reason) do
    Process.send_after(self(), {:trigger_redistribution, reason}, @rebalance_delay)
    state
  end
  
  defp trigger_provider_redistribution(state, reason) do
    Logger.info("Triggering provider redistribution due to: #{reason}")
    
    # Get current cluster topology
    active_nodes = get_active_nodes(state.cluster_state.nodes)
    
    # Broadcast redistribution event
    redistribution_event = %{
      topic: "cluster.provider_redistribution",
      payload: %{
        reason: reason,
        active_nodes: active_nodes,
        leader_node: node(),
        timestamp: System.monotonic_time(:millisecond),
        topology_version: state.cluster_state.topology_version
      }
    }
    EventBroadcaster.broadcast_async(redistribution_event)
    
    # Trigger rebalancing in load balancer and failover manager
    spawn(fn ->
      try do
        FailoverManager.rebalance_providers()
      catch
        :exit, :noproc -> :ok  # Service not running
        _, _ -> :ok
      end
    end)
    
    state
  end
  
  defp handle_heartbeat_event(event, state) do
    sender_node = event.payload.node
    current_time = System.monotonic_time(:millisecond)
    
    # Update node info with heartbeat
    updated_nodes = Map.update(state.cluster_state.nodes, sender_node, 
      create_node_info(sender_node, current_time, event.payload.capabilities),
      fn existing_info ->
        %{existing_info |
          last_heartbeat: current_time,
          capabilities: event.payload.capabilities,
          provider_count: event.payload.provider_count,
          status: event.payload.status
        }
      end
    )
    
    updated_cluster_state = %{state.cluster_state | nodes: updated_nodes}
    updated_state = %{state | cluster_state: updated_cluster_state}
    
    {:noreply, updated_state}
  end
  
  defp handle_leadership_claim_event(event, state) do
    claimed_leader = event.payload.leader_node
    
    # Accept leadership claim if we don't have a leader or this is a higher version
    should_accept = state.cluster_state.cluster_leader == nil or
                   event.payload.topology_version > state.cluster_state.topology_version
    
    if should_accept do
      Logger.info("Accepting leadership of node: #{claimed_leader}")
      
      updated_cluster_state = %{state.cluster_state | 
        cluster_leader: claimed_leader,
        topology_version: event.payload.topology_version
      }
      
      updated_state = %{state | cluster_state: updated_cluster_state}
      {:noreply, updated_state}
    else
      {:noreply, state}
    end
  end
  
  defp handle_graceful_shutdown_request(event, state) do
    target_node = event.payload.target_node
    
    if target_node == node() do
      Logger.info("Graceful shutdown requested by #{event.payload.requesting_node}")
      updated_state = begin_graceful_shutdown(state)
      {:noreply, updated_state}
    else
      {:noreply, state}
    end
  end
  
  defp handle_provider_health_change(event, state) do
    # Monitor provider health changes and trigger redistribution if needed
    provider_id = event.payload.provider_id
    health_score = event.payload.health_score
    
    if health_score < 0.5 and is_cluster_leader?(state) do
      # Trigger redistribution for unhealthy provider
      updated_state = schedule_provider_redistribution(state, :provider_health_degraded)
      {:noreply, updated_state}
    else
      {:noreply, state}
    end
  end
  
  defp begin_graceful_shutdown(state) do
    Logger.info("Beginning graceful shutdown sequence")
    
    # Update node status
    current_node = node()
    updated_nodes = Map.update!(state.cluster_state.nodes, current_node, fn node_info ->
      %{node_info | status: :leaving}
    end)
    
    updated_cluster_state = %{state.cluster_state | nodes: updated_nodes}
    
    # Broadcast shutdown intention
    shutdown_event = %{
      topic: "cluster.graceful_shutdown_initiated",
      payload: %{
        node: current_node,
        timestamp: System.monotonic_time(:millisecond)
      }
    }
    EventBroadcaster.broadcast_async(shutdown_event)
    
    # TODO: Trigger provider migration and cleanup
    
    %{state | cluster_state: updated_cluster_state}
  end
  
  defp build_topology_response(cluster_state) do
    active_nodes = get_active_nodes(cluster_state.nodes)
    healthy_nodes = get_healthy_nodes(cluster_state.nodes)
    
    %{
      nodes: cluster_state.nodes,
      cluster_leader: cluster_state.cluster_leader,
      topology_version: cluster_state.topology_version,
      total_nodes: map_size(cluster_state.nodes),
      active_nodes: length(active_nodes),
      healthy_nodes: length(healthy_nodes),
      last_topology_change: cluster_state.last_topology_change
    }
  end
  
  defp get_active_nodes(nodes) do
    nodes
    |> Enum.filter(fn {_node, info} -> info.status == :active end)
    |> Enum.map(fn {node, _info} -> node end)
  end
  
  defp get_healthy_nodes(nodes) do
    nodes
    |> Enum.filter(fn {_node, info} -> info.health_score >= 0.7 end)
    |> Enum.map(fn {node, _info} -> node end)
  end
  
  defp calculate_cluster_health(state) do
    nodes = state.cluster_state.nodes
    node_count = map_size(nodes)
    
    if node_count == 0 do
      %{
        overall_health: 0.0,
        node_count: 0,
        healthy_nodes: 0,
        cluster_stability: :unknown,
        split_brain_risk: :high
      }
    else
      health_scores = Enum.map(nodes, fn {_node, info} -> info.health_score end)
      overall_health = Enum.sum(health_scores) / node_count
      
      healthy_nodes = get_healthy_nodes(nodes)
      healthy_count = length(healthy_nodes)
      
      stability = cond do
        healthy_count == node_count -> :stable
        healthy_count >= node_count * 0.8 -> :mostly_stable
        healthy_count >= node_count * 0.5 -> :unstable
        true -> :critical
      end
      
      split_brain_risk = cond do
        node_count <= 2 -> :high
        healthy_count >= (node_count / 2) + 1 -> :low
        true -> :medium
      end
      
      %{
        overall_health: overall_health,
        node_count: node_count,
        healthy_nodes: healthy_count,
        cluster_stability: stability,
        split_brain_risk: split_brain_risk
      }
    end
  end
  
  defp get_local_provider_count do
    try do
      LoadBalancer.get_provider_stats() |> map_size()
    catch
      :exit, :noproc -> 0
      _, _ -> 0
    end
  end
  
  defp schedule_heartbeat do
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
  end
end