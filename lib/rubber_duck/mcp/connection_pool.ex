defmodule RubberDuck.MCP.ConnectionPool do
  @moduledoc """
  Connection pool manager for MCP clients.
  
  Manages connection pooling for MCP clients, allowing for efficient
  reuse of connections and load balancing across multiple servers.
  """

  use GenServer
  require Logger

  defmodule PoolState do
    @moduledoc false
    defstruct [
      :name,
      :size,
      :overflow,
      :strategy,
      connections: [],
      waiting: :queue.new(),
      monitors: %{},
      stats: %{
        total_connections: 0,
        active_connections: 0,
        waiting_requests: 0,
        total_requests: 0,
        failed_requests: 0
      }
    ]
  end

  # Client API

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Checks out a connection from the pool.
  """
  def checkout(pool \\ __MODULE__, timeout \\ 5000) do
    GenServer.call(pool, :checkout, timeout)
  end

  @doc """
  Returns a connection to the pool.
  """
  def checkin(pool \\ __MODULE__, connection) do
    GenServer.cast(pool, {:checkin, connection})
  end

  @doc """
  Executes a function with a pooled connection.
  """
  def with_connection(pool \\ __MODULE__, fun, timeout \\ 5000) do
    case checkout(pool, timeout) do
      {:ok, conn} ->
        try do
          result = fun.(conn)
          checkin(pool, conn)
          result
        rescue
          exception ->
            checkin(pool, conn)
            reraise exception, __STACKTRACE__
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets pool statistics.
  """
  def stats(pool \\ __MODULE__) do
    GenServer.call(pool, :stats)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %PoolState{
      name: Keyword.get(opts, :pool_name, :default),
      size: Keyword.get(opts, :size, 5),
      overflow: Keyword.get(opts, :overflow, 5),
      strategy: Keyword.get(opts, :strategy, :fifo)
    }

    # Start initial connections
    connections = start_connections(state.size, opts)
    
    {:ok, %{state | connections: connections}}
  end

  @impl true
  def handle_call(:checkout, {from_pid, _ref} = from, state) do
    case find_available_connection(state) do
      {:ok, conn} ->
        # Monitor the caller
        ref = Process.monitor(from_pid)
        monitors = Map.put(state.monitors, ref, {conn, from_pid})
        
        # Update stats
        stats = update_stats(state.stats, :checkout)
        
        {:reply, {:ok, conn}, %{state | monitors: monitors, stats: stats}}
      
      {:error, :no_connections} ->
        # Add to waiting queue if under limit
        if queue_size(state.waiting) < state.overflow do
          waiting = :queue.in(from, state.waiting)
          stats = update_stats(state.stats, :waiting)
          {:noreply, %{state | waiting: waiting, stats: stats}}
        else
          stats = update_stats(state.stats, :rejected)
          {:reply, {:error, :pool_overflow}, %{state | stats: stats}}
        end
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, {:ok, state.stats}, state}
  end

  @impl true
  def handle_cast({:checkin, conn}, state) do
    # Return connection to pool
    connections = [conn | state.connections]
    
    # Check if anyone is waiting
    case :queue.out(state.waiting) do
      {{:value, from}, waiting} ->
        # Give connection to waiting caller
        GenServer.reply(from, {:ok, conn})
        {:noreply, %{state | waiting: waiting}}
      
      {:empty, _} ->
        # Add back to available connections
        {:noreply, %{state | connections: connections}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, ref) do
      {conn, _pid} ->
        # Process died while holding connection, return it to pool
        monitors = Map.delete(state.monitors, ref)
        connections = [conn | state.connections]
        
        {:noreply, %{state | monitors: monitors, connections: connections}}
      
      nil ->
        {:noreply, state}
    end
  end

  # Private functions

  defp start_connections(count, opts) do
    transport = Keyword.fetch!(opts, :transport)
    
    Enum.map(1..count, fn i ->
      name = :"pool_connection_#{i}"
      {:ok, _pid} = RubberDuck.MCP.ClientSupervisor.start_client(
        name: name,
        transport: transport,
        auto_reconnect: true
      )
      name
    end)
  end

  defp find_available_connection(%{connections: [conn | rest]} = state) do
    # Check if connection is healthy
    case RubberDuck.MCP.Client.health_check(conn) do
      {:ok, %{connected: true}} ->
        {:ok, conn}
      
      _ ->
        # Connection unhealthy, try next
        find_available_connection(%{state | connections: rest})
    end
  end

  defp find_available_connection(%{connections: []}) do
    {:error, :no_connections}
  end

  defp queue_size(queue) do
    :queue.len(queue)
  end

  defp update_stats(stats, :checkout) do
    %{stats | 
      active_connections: stats.active_connections + 1,
      total_requests: stats.total_requests + 1
    }
  end

  defp update_stats(stats, :waiting) do
    %{stats | 
      waiting_requests: stats.waiting_requests + 1
    }
  end

  defp update_stats(stats, :rejected) do
    %{stats | 
      failed_requests: stats.failed_requests + 1,
      total_requests: stats.total_requests + 1
    }
  end
end