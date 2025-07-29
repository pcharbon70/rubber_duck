defmodule RubberDuck.Jido.Agents.RestartTracker do
  @moduledoc """
  Tracks agent restarts and implements exponential backoff.
  
  This module prevents restart storms by tracking restart attempts
  and enforcing exponential backoff periods for frequently crashing agents.
  """
  
  use GenServer
  require Logger
  
  @initial_backoff 1000      # 1 second
  @max_backoff 60_000        # 60 seconds
  @backoff_multiplier 2
  @history_window 300_000    # 5 minutes
  @max_restarts_in_window 5
  
  @type restart_info :: %{
    count: non_neg_integer(),
    last_restart: DateTime.t(),
    backoff_until: DateTime.t() | nil,
    history: [DateTime.t()]
  }
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Checks if an agent can be restarted based on its restart history.
  
  Returns `:ok` if the agent can be restarted, or `{:error, :backoff}` if it's
  still in the backoff period.
  """
  def check_restart(agent_id) do
    GenServer.call(__MODULE__, {:check_restart, agent_id})
  end
  
  @doc """
  Records a restart attempt for an agent.
  """
  def record_restart(agent_id) do
    GenServer.cast(__MODULE__, {:record_restart, agent_id})
  end
  
  @doc """
  Gets restart statistics for all agents or a specific agent.
  """
  def get_stats(agent_id \\ nil) do
    GenServer.call(__MODULE__, {:get_stats, agent_id})
  end
  
  @doc """
  Clears restart history for an agent.
  """
  def clear_history(agent_id) do
    GenServer.call(__MODULE__, {:clear_history, agent_id})
  end
  
  @doc """
  Enables or disables backoff enforcement (useful for testing).
  """
  def set_enabled(enabled) when is_boolean(enabled) do
    GenServer.call(__MODULE__, {:set_enabled, enabled})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Create ETS table for restart tracking
    table = :ets.new(:agent_restart_tracker, [
      :set,
      :protected,
      read_concurrency: true
    ])
    
    state = %{
      table: table,
      enabled: Keyword.get(opts, :enabled, true),
      config: %{
        initial_backoff: Keyword.get(opts, :initial_backoff, @initial_backoff),
        max_backoff: Keyword.get(opts, :max_backoff, @max_backoff),
        multiplier: Keyword.get(opts, :multiplier, @backoff_multiplier),
        history_window: Keyword.get(opts, :history_window, @history_window),
        max_restarts: Keyword.get(opts, :max_restarts, @max_restarts_in_window)
      }
    }
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:check_restart, agent_id}, _from, state) do
    if not state.enabled do
      {:reply, :ok, state}
    else
      now = DateTime.utc_now()
      
      reply = case get_restart_info(state.table, agent_id) do
        nil ->
          :ok
          
        %{backoff_until: nil} ->
          :ok
          
        %{backoff_until: backoff_until} ->
          if DateTime.compare(now, backoff_until) == :gt do
            :ok
          else
            remaining = DateTime.diff(backoff_until, now, :millisecond)
            Logger.warning("Agent #{agent_id} still in backoff for #{remaining}ms")
            {:error, :backoff}
          end
      end
      
      {:reply, reply, state}
    end
  end
  
  @impl true
  def handle_call({:get_stats, nil}, _from, state) do
    stats = :ets.tab2list(state.table)
    |> Enum.map(fn {agent_id, info} ->
      {agent_id, format_restart_info(info)}
    end)
    |> Map.new()
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:get_stats, agent_id}, _from, state) do
    stats = case get_restart_info(state.table, agent_id) do
      nil -> nil
      info -> format_restart_info(info)
    end
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:clear_history, agent_id}, _from, state) do
    :ets.delete(state.table, agent_id)
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:set_enabled, enabled}, _from, state) do
    {:reply, :ok, %{state | enabled: enabled}}
  end
  
  @impl true
  def handle_cast({:record_restart, agent_id}, state) do
    now = DateTime.utc_now()
    info = get_restart_info(state.table, agent_id) || new_restart_info()
    
    # Clean old history
    recent_history = Enum.filter(info.history, fn timestamp ->
      DateTime.diff(now, timestamp, :millisecond) <= state.config.history_window
    end)
    
    # Add current restart
    updated_history = [now | recent_history]
    restart_count = length(updated_history)
    
    # Calculate backoff if needed
    backoff_until = if restart_count >= state.config.max_restarts do
      backoff_ms = calculate_backoff(restart_count - state.config.max_restarts, state.config)
      DateTime.add(now, backoff_ms, :millisecond)
    else
      nil
    end
    
    # Update info
    updated_info = %{
      count: info.count + 1,
      last_restart: now,
      backoff_until: backoff_until,
      history: updated_history
    }
    
    :ets.insert(state.table, {agent_id, updated_info})
    
    if backoff_until do
      Logger.warning("Agent #{agent_id} has restarted #{restart_count} times in window, " <>
                    "enforcing backoff until #{backoff_until}")
    end
    
    # Send telemetry
    :telemetry.execute(
      [:rubber_duck, :jido, :agent, :restart_recorded],
      %{
        restart_count: restart_count,
        backoff_ms: if(backoff_until, do: DateTime.diff(backoff_until, now, :millisecond), else: 0)
      },
      %{agent_id: agent_id}
    )
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Remove entries with no recent activity
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -state.config.history_window * 2, :millisecond)
    
    :ets.tab2list(state.table)
    |> Enum.each(fn {agent_id, info} ->
      if DateTime.compare(info.last_restart, cutoff) == :lt do
        :ets.delete(state.table, agent_id)
      end
    end)
    
    schedule_cleanup()
    {:noreply, state}
  end
  
  # Private functions
  
  defp get_restart_info(table, agent_id) do
    case :ets.lookup(table, agent_id) do
      [{^agent_id, info}] -> info
      [] -> nil
    end
  end
  
  defp new_restart_info do
    %{
      count: 0,
      last_restart: nil,
      backoff_until: nil,
      history: []
    }
  end
  
  defp calculate_backoff(excess_restarts, config) do
    backoff = config.initial_backoff * :math.pow(config.multiplier, excess_restarts)
    min(round(backoff), config.max_backoff)
  end
  
  defp format_restart_info(info) do
    %{
      total_restarts: info.count,
      last_restart: info.last_restart,
      backoff_until: info.backoff_until,
      recent_restart_count: length(info.history),
      in_backoff: info.backoff_until && DateTime.compare(DateTime.utc_now(), info.backoff_until) == :lt
    }
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, :timer.minutes(5))
  end
end