defmodule RubberDuck.Jido.Agents.RestartTrackerAgent do
  @moduledoc """
  Restart tracking agent with exponential backoff using the Jido pattern.
  
  This agent prevents restart storms by tracking restart attempts
  and enforcing exponential backoff periods for frequently crashing agents.
  
  ## Available Actions
  
  - `check_restart` - Check if an agent can be restarted
  - `record_restart` - Record a restart attempt
  - `get_stats` - Get restart statistics
  - `clear_history` - Clear restart history for an agent
  - `set_enabled` - Enable/disable backoff enforcement
  """

  use Jido.Agent,
    name: "restart_tracker",
    description: "Tracks agent restarts and implements exponential backoff",
    schema: [
      # Restart tracking data (agent_id => restart_info)
      restart_data: [type: :map, default: %{}],
      
      # Configuration
      enabled: [type: :boolean, default: true],
      config: [type: :map, default: %{
        initial_backoff: 1000,      # 1 second
        max_backoff: 60_000,        # 60 seconds
        multiplier: 2,
        history_window: 300_000,    # 5 minutes
        max_restarts: 5
      }]
    ],
    actions: [
      RubberDuck.Jido.Actions.RestartTracker.CheckRestartAction,
      RubberDuck.Jido.Actions.RestartTracker.RecordRestartAction,
      RubberDuck.Jido.Actions.RestartTracker.GetStatsAction,
      RubberDuck.Jido.Actions.RestartTracker.ClearHistoryAction,
      RubberDuck.Jido.Actions.RestartTracker.SetEnabledAction
    ]

  require Logger

  @impl true
  def mount(agent) do
    # Schedule periodic cleanup
    schedule_cleanup()
    
    Logger.info("Restart Tracker Agent initialized", 
      agent_id: agent.id,
      enabled: agent.state.enabled,
      config: agent.state.config
    )
    
    {:ok, agent}
  end

  @impl true
  def unmount(agent) do
    Logger.info("Restart Tracker Agent terminated", agent_id: agent.id)
    {:ok, agent}
  end

  # Helper functions

  defp schedule_cleanup do
    # Schedule cleanup every 5 minutes
    Process.send_after(self(), :cleanup_old_entries, :timer.minutes(5))
  end

  # In a real Jido agent, this would need to be handled differently
  # as the cleanup would need to be an action or handled by the agent supervisor
  def handle_info(:cleanup_old_entries, agent) do
    # This is a simplified cleanup - in practice would need to be an action
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -agent.state.config.history_window * 2, :millisecond)
    
    cleaned_data = agent.state.restart_data
    |> Enum.filter(fn {_agent_id, info} ->
      case info.last_restart do
        nil -> false
        last_restart -> DateTime.compare(last_restart, cutoff) == :gt
      end
    end)
    |> Map.new()
    
    updated_agent = put_in(agent.state.restart_data, cleaned_data)
    
    schedule_cleanup()
    {:noreply, updated_agent}
  end
end