defmodule RubberDuck.NodeMonitor do
  @moduledoc """
  Monitors cluster membership and node health.

  This GenServer tracks node connections/disconnections, maintains
  cluster health status, and notifies subscribers of cluster events.
  """
  use GenServer

  # Client API

  @doc """
  Starts the NodeMonitor GenServer.
  
  ## Options
    * `:config` - Initial configuration map
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the list of connected nodes including current node.
  """
  def get_nodes(server \\ __MODULE__) do
    GenServer.call(server, :get_nodes)
  end

  @doc """
  Gets comprehensive cluster status information.
  """
  def get_cluster_status(server \\ __MODULE__) do
    GenServer.call(server, :get_cluster_status)
  end

  @doc """
  Subscribes a process to cluster events.
  """
  def subscribe_to_events(server \\ __MODULE__, pid \\ self()) do
    GenServer.call(server, {:subscribe_to_events, pid})
  end

  @doc """
  Unsubscribes a process from cluster events.
  """
  def unsubscribe_from_events(server \\ __MODULE__, pid \\ self()) do
    GenServer.call(server, {:unsubscribe_from_events, pid})
  end

  @doc """
  Performs a health check on the GenServer.
  """
  def health_check(server \\ __MODULE__) do
    GenServer.call(server, :health_check)
  end

  @doc """
  Gets information about the NodeMonitor state.
  """
  def get_info(server \\ __MODULE__) do
    GenServer.call(server, :get_info)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :config, %{})
    
    # Monitor node connections/disconnections
    :net_kernel.monitor_nodes(true)
    
    state = %{
      connected_nodes: [node() | Node.list()],
      subscribers: MapSet.new(),
      node_history: [],
      config: config,
      start_time: System.monotonic_time(:millisecond)
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call(:get_nodes, _from, state) do
    {:reply, {:ok, state.connected_nodes}, state}
  end

  @impl true
  def handle_call(:get_cluster_status, _from, state) do
    current_node = node()
    connected_nodes = Node.list()
    total_nodes = length([current_node | connected_nodes])
    
    cluster_health = determine_cluster_health(total_nodes, length(connected_nodes))
    
    status = %{
      current_node: current_node,
      connected_nodes: connected_nodes,
      total_nodes: total_nodes,
      cluster_health: cluster_health
    }
    
    {:reply, status, state}
  end

  @impl true
  def handle_call({:subscribe_to_events, pid}, _from, state) do
    new_subscribers = MapSet.put(state.subscribers, pid)
    new_state = %{state | subscribers: new_subscribers}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe_from_events, pid}, _from, state) do
    new_subscribers = MapSet.delete(state.subscribers, pid)
    new_state = %{state | subscribers: new_subscribers}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      status: :running,
      monitored_nodes: state.connected_nodes,
      subscribers: MapSet.size(state.subscribers),
      memory: :erlang.process_info(self(), :memory) |> elem(1),
      uptime: System.monotonic_time(:millisecond) - state.start_time
    }
    {:reply, info, state}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    new_connected_nodes = [node | state.connected_nodes] |> Enum.uniq()
    event = {:cluster_event, {:node_connected, node}}
    
    # Notify subscribers
    notify_subscribers(state.subscribers, event)
    
    # Update node history
    history_entry = {DateTime.utc_now(), :nodeup, node}
    new_history = [history_entry | state.node_history] |> Enum.take(100)
    
    new_state = %{state | 
      connected_nodes: new_connected_nodes,
      node_history: new_history
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    new_connected_nodes = List.delete(state.connected_nodes, node)
    event = {:cluster_event, {:node_disconnected, node}}
    
    # Notify subscribers
    notify_subscribers(state.subscribers, event)
    
    # Update node history
    history_entry = {DateTime.utc_now(), :nodedown, node}
    new_history = [history_entry | state.node_history] |> Enum.take(100)
    
    new_state = %{state | 
      connected_nodes: new_connected_nodes,
      node_history: new_history
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    # Ignore unknown messages
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    # Stop monitoring nodes
    :net_kernel.monitor_nodes(false)
    :ok
  end

  # Private Functions

  defp determine_cluster_health(total_nodes, connected_count) do
    cond do
      total_nodes == 1 -> :healthy  # Single node is healthy
      connected_count >= total_nodes * 0.8 -> :healthy
      connected_count >= total_nodes * 0.5 -> :degraded
      true -> :unhealthy
    end
  end

  defp notify_subscribers(subscribers, event) do
    Enum.each(subscribers, fn pid ->
      if Process.alive?(pid) do
        send(pid, event)
      end
    end)
  end
end