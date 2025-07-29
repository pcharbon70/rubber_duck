defmodule RubberDuck.Jido.Agents.PoolManager do
  @moduledoc """
  Manages pools of agents for efficient resource usage.
  
  Features:
  - Configurable pool sizes (min, max, target)
  - Multiple pooling strategies (round-robin, least-loaded, random)
  - Dynamic scaling based on load
  - Overflow handling with queueing
  - Pool warmup on startup
  - Back-pressure mechanisms
  
  ## Usage
  
      # Start a pool
      {:ok, pool} = PoolManager.start_pool(MyAgent, 
        name: :my_pool,
        min_size: 2,
        max_size: 10,
        target_size: 5,
        strategy: :least_loaded
      )
      
      # Get an agent from the pool
      {:ok, agent} = PoolManager.checkout(:my_pool)
      
      # Return agent to pool
      :ok = PoolManager.checkin(:my_pool, agent)
      
      # Execute work on pool
      {:ok, result} = PoolManager.execute(:my_pool, MyAction, %{param: "value"})
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Jido.Agents.{Supervisor, Registry}
  
  @default_opts [
    min_size: 1,
    max_size: 10,
    target_size: 5,
    strategy: :least_loaded,
    overflow: :queue,
    max_overflow: 50,
    idle_timeout: 300_000,  # 5 minutes
    scale_up_threshold: 0.8,
    scale_down_threshold: 0.2,
    scale_interval: 10_000,  # 10 seconds
    cooldown_period: 30_000  # 30 seconds
  ]
  
  # Client API
  
  @doc """
  Starts a new agent pool.
  """
  def start_pool(agent_module, opts \\ []) do
    name = Keyword.get(opts, :name) || :"#{agent_module}_pool"
    GenServer.start_link(__MODULE__, {agent_module, opts}, name: name)
  end
  
  @doc """
  Stops a pool gracefully.
  """
  def stop_pool(pool) do
    GenServer.stop(pool, :normal, 5000)
  end
  
  @doc """
  Checks out an agent from the pool.
  """
  def checkout(pool, timeout \\ 5000) do
    GenServer.call(pool, :checkout, timeout)
  end
  
  @doc """
  Returns an agent to the pool.
  """
  def checkin(pool, agent) do
    GenServer.cast(pool, {:checkin, agent})
  end
  
  @doc """
  Executes an action on a pooled agent.
  """
  def execute(pool, action, params \\ %{}, timeout \\ 5000) do
    GenServer.call(pool, {:execute, action, params}, timeout)
  end
  
  @doc """
  Gets pool statistics.
  """
  def stats(pool) do
    GenServer.call(pool, :stats)
  end
  
  @doc """
  Manually scales the pool.
  """
  def scale(pool, new_size) do
    GenServer.call(pool, {:scale, new_size})
  end
  
  @doc """
  Updates pool configuration.
  """
  def update_config(pool, updates) do
    GenServer.call(pool, {:update_config, updates})
  end
  
  # Server callbacks
  
  @impl true
  def init({agent_module, opts}) do
    Process.flag(:trap_exit, true)
    
    config = @default_opts
    |> Keyword.merge(opts)
    |> Map.new()
    
    state = %{
      agent_module: agent_module,
      config: config,
      pool_name: Keyword.get(opts, :name) || :"#{agent_module}_pool",
      agents: [],
      available: [],
      busy: MapSet.new(),
      queue: :queue.new(),
      stats: %{
        checkouts: 0,
        checkins: 0,
        executions: 0,
        queue_size: 0,
        max_queue_size: 0,
        total_wait_time: 0,
        scaling_events: 0,
        last_scale: nil
      },
      scaling_state: %{
        last_scale_time: nil,
        cooldown_until: nil,
        load_history: []
      }
    }
    
    # Start initial pool
    {:ok, state, {:continue, :warmup}}
  end
  
  @impl true
  def handle_continue(:warmup, state) do
    Logger.info("Warming up pool #{state.pool_name} with target size #{state.config.target_size}")
    
    # Start target number of agents
    new_state = Enum.reduce(1..state.config.target_size, state, fn _, acc ->
      case start_agent(acc) do
        {:ok, updated_state} -> updated_state
        {:error, _} -> acc
      end
    end)
    
    # Start scaling timer
    Process.send_after(self(), :check_scaling, state.config.scale_interval)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call(:checkout, from, state) do
    case get_available_agent(state) do
      {:ok, agent, new_state} ->
        # Track checkout
        stats = Map.update!(new_state.stats, :checkouts, &(&1 + 1))
        new_state = %{new_state | stats: stats}
        
        {:reply, {:ok, agent}, new_state}
        
      {:error, :no_agents} ->
        # Handle based on overflow strategy
        handle_no_agents(from, state)
    end
  end
  
  @impl true
  def handle_call({:execute, action, params}, from, state) do
    case get_available_agent(state) do
      {:ok, agent, new_state} ->
        # Execute asynchronously
        pool_pid = self()
        Task.start_link(fn ->
          result = execute_on_agent(agent, action, params)
          GenServer.reply(from, result)
          checkin(pool_pid, agent)
        end)
        
        # Update stats
        stats = new_state.stats
        |> Map.update!(:executions, &(&1 + 1))
        |> Map.update!(:checkouts, &(&1 + 1))
        
        {:noreply, %{new_state | stats: stats}}
        
      {:error, :no_agents} ->
        # Queue the execution request
        handle_no_agents({:execute, from, action, params}, state)
    end
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    stats = Map.merge(state.stats, %{
      pool_size: length(state.agents),
      available: length(state.available),
      busy: MapSet.size(state.busy),
      queue_depth: :queue.len(state.queue),
      current_load: calculate_load(state)
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:scale, new_size}, _from, state) do
    new_size = max(state.config.min_size, min(new_size, state.config.max_size))
    current_size = length(state.agents)
    
    new_state = cond do
      new_size > current_size ->
        scale_up(state, new_size - current_size)
        
      new_size < current_size ->
        scale_down(state, current_size - new_size)
        
      true ->
        state
    end
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:update_config, updates}, _from, state) do
    new_config = Map.merge(state.config, Map.new(updates))
    {:reply, :ok, %{state | config: new_config}}
  end
  
  @impl true
  def handle_cast({:checkin, agent}, state) do
    new_state = case MapSet.member?(state.busy, agent.id) do
      true ->
        # Return to available pool
        busy = MapSet.delete(state.busy, agent.id)
        available = [agent | state.available]
        stats = Map.update!(state.stats, :checkins, &(&1 + 1))
        
        state = %{state | 
          busy: busy, 
          available: available,
          stats: stats
        }
        
        # Process any queued requests
        process_queue(state)
        
      false ->
        # Agent wasn't checked out, ignore
        state
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:check_scaling, state) do
    # Calculate current load
    load = calculate_load(state)
    
    # Update load history
    load_history = [load | Enum.take(state.scaling_state.load_history, 11)]
    scaling_state = %{state.scaling_state | load_history: load_history}
    state = %{state | scaling_state: scaling_state}
    
    # Check if we should scale
    new_state = if should_scale?(state) do
      perform_scaling(state, load)
    else
      state
    end
    
    # Schedule next check
    Process.send_after(self(), :check_scaling, state.config.scale_interval)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    # Handle agent crash
    Logger.warning("Pool agent crashed: #{inspect(reason)}")
    
    # Remove from pool
    new_state = remove_agent(state, pid)
    
    # Start replacement if below min size
    new_state = if length(new_state.agents) < state.config.min_size do
      case start_agent(new_state) do
        {:ok, updated_state} -> updated_state
        {:error, _} -> new_state
      end
    else
      new_state
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Stop all agents gracefully
    Enum.each(state.agents, fn agent ->
      try do
        Supervisor.stop_agent(agent.id)
      catch
        :exit, _ -> :ok
      end
    end)
    
    :ok
  end
  
  # Private functions
  
  defp start_agent(state) do
    agent_id = "#{state.pool_name}_#{System.unique_integer([:positive])}"
    
    case Supervisor.start_agent(state.agent_module, %{}, 
           id: agent_id,
           tags: [:pooled, state.pool_name],
           metadata: %{pool: state.pool_name}) do
      {:ok, _pid} ->
        # Get agent info from registry
        case Registry.get_agent(agent_id) do
          {:ok, agent} ->
            agents = [agent | state.agents]
            available = [agent | state.available]
            {:ok, %{state | agents: agents, available: available}}
            
          _ ->
            {:error, :registry_error}
        end
        
      error ->
        error
    end
  end
  
  defp get_available_agent(state) do
    case {state.available, state.config.strategy} do
      {[], _} ->
        {:error, :no_agents}
        
      {available, :round_robin} ->
        [agent | rest] = available
        busy = MapSet.put(state.busy, agent.id)
        {:ok, agent, %{state | available: rest, busy: busy}}
        
      {available, :random} ->
        agent = Enum.random(available)
        rest = List.delete(available, agent)
        busy = MapSet.put(state.busy, agent.id)
        {:ok, agent, %{state | available: rest, busy: busy}}
        
      {available, :least_loaded} ->
        # Get load info from registry
        agent = Enum.min_by(available, fn a ->
          case Registry.get_agent(a.id) do
            {:ok, info} -> Map.get(info.metadata, :load, 0)
            _ -> 0
          end
        end)
        
        rest = List.delete(available, agent)
        busy = MapSet.put(state.busy, agent.id)
        {:ok, agent, %{state | available: rest, busy: busy}}
    end
  end
  
  defp handle_no_agents(from, state) do
    case state.config.overflow do
      :queue ->
        if :queue.len(state.queue) < state.config.max_overflow do
          # Queue the request
          queue = :queue.in({from, System.monotonic_time()}, state.queue)
          stats = state.stats
          |> Map.update!(:queue_size, &(&1 + 1))
          |> Map.update!(:max_queue_size, &max(&1, :queue.len(queue)))
          
          {:noreply, %{state | queue: queue, stats: stats}}
        else
          {:reply, {:error, :queue_full}, state}
        end
        
      :error ->
        {:reply, {:error, :no_agents_available}, state}
        
      :spawn ->
        # Try to spawn new agent if under max
        if length(state.agents) < state.config.max_size do
          case start_agent(state) do
            {:ok, new_state} ->
              # Retry checkout with new agent
              case get_available_agent(new_state) do
                {:ok, agent, final_state} ->
                  {:reply, {:ok, agent}, final_state}
                  
                _ ->
                  {:reply, {:error, :spawn_failed}, new_state}
              end
              
            {:error, _} ->
              {:reply, {:error, :spawn_failed}, state}
          end
        else
          {:reply, {:error, :pool_at_max_size}, state}
        end
    end
  end
  
  defp execute_on_agent(agent, action, params) do
    case RubberDuck.Jido.Agents.Server.execute_action(agent.pid, action, params) do
      {:ok, _result} = success -> success
      error -> error
    end
  end
  
  defp process_queue(state) do
    case :queue.out(state.queue) do
      {{:value, {from, enqueue_time}}, new_queue} when is_tuple(from) ->
        # Simple checkout request
        wait_time = System.monotonic_time() - enqueue_time
        stats = Map.update!(state.stats, :total_wait_time, &(&1 + wait_time))
        
        case get_available_agent(%{state | queue: new_queue, stats: stats}) do
          {:ok, agent, new_state} ->
            GenServer.reply(from, {:ok, agent})
            new_state
            
          _ ->
            state
        end
        
      {{:value, {{:execute, from, action, params}, enqueue_time}}, new_queue} ->
        # Execute request
        wait_time = System.monotonic_time() - enqueue_time
        stats = Map.update!(state.stats, :total_wait_time, &(&1 + wait_time))
        
        case get_available_agent(%{state | queue: new_queue, stats: stats}) do
          {:ok, agent, new_state} ->
            pool_pid = self()
            Task.start_link(fn ->
              result = execute_on_agent(agent, action, params)
              GenServer.reply(from, result)
              checkin(pool_pid, agent)
            end)
            
            new_state
            
          _ ->
            state
        end
        
      {:empty, _} ->
        state
    end
  end
  
  defp calculate_load(state) do
    total = length(state.agents)
    if total == 0 do
      0.0
    else
      busy = MapSet.size(state.busy)
      queued = :queue.len(state.queue)
      
      # Load = (busy + queued) / total
      (busy + min(queued, total)) / total
    end
  end
  
  defp should_scale?(state) do
    now = System.monotonic_time(:millisecond)
    cooldown_until = state.scaling_state.cooldown_until || 0
    
    now > cooldown_until
  end
  
  defp perform_scaling(state, _load) do
    current_size = length(state.agents)
    avg_load = calculate_average_load(state.scaling_state.load_history)
    
    cond do
      avg_load > state.config.scale_up_threshold and current_size < state.config.max_size ->
        # Scale up
        increment = min(
          ceil(current_size * 0.2),  # 20% increase
          state.config.max_size - current_size
        )
        new_state = scale_up(state, increment)
        update_scaling_state(new_state, :scale_up)
        
      avg_load < state.config.scale_down_threshold and current_size > state.config.min_size ->
        # Scale down
        decrement = min(
          ceil(current_size * 0.1),  # 10% decrease
          current_size - state.config.min_size
        )
        new_state = scale_down(state, decrement)
        update_scaling_state(new_state, :scale_down)
        
      true ->
        state
    end
  end
  
  defp scale_up(state, count) do
    Logger.info("Scaling up pool #{state.pool_name} by #{count} agents")
    
    Enum.reduce(1..count, state, fn _, acc ->
      case start_agent(acc) do
        {:ok, updated} -> updated
        _ -> acc
      end
    end)
  end
  
  defp scale_down(state, count) do
    Logger.info("Scaling down pool #{state.pool_name} by #{count} agents")
    
    # Remove idle agents first
    {to_remove, remaining} = Enum.split(state.available, count)
    
    # Stop the agents
    Enum.each(to_remove, fn agent ->
      Supervisor.stop_agent(agent.id)
    end)
    
    # Update state
    agents = Enum.reject(state.agents, fn a -> a.id in Enum.map(to_remove, & &1.id) end)
    %{state | agents: agents, available: remaining}
  end
  
  defp remove_agent(state, pid) do
    agents = Enum.reject(state.agents, fn a -> a.pid == pid end)
    available = Enum.reject(state.available, fn a -> a.pid == pid end)
    busy = Enum.reduce(state.agents, state.busy, fn agent, acc ->
      if agent.pid == pid do
        MapSet.delete(acc, agent.id)
      else
        acc
      end
    end)
    
    %{state | agents: agents, available: available, busy: busy}
  end
  
  defp calculate_average_load(history) do
    case history do
      [] -> 0.0
      loads -> Enum.sum(loads) / length(loads)
    end
  end
  
  defp update_scaling_state(state, event) do
    now = System.monotonic_time(:millisecond)
    
    scaling_state = %{state.scaling_state |
      last_scale_time: now,
      cooldown_until: now + state.config.cooldown_period
    }
    
    stats = state.stats
    |> Map.update!(:scaling_events, &(&1 + 1))
    |> Map.put(:last_scale, {event, DateTime.utc_now()})
    
    %{state | scaling_state: scaling_state, stats: stats}
  end
end