defmodule RubberDuck.Jido.Actions.RestartTracker.RecordRestartAction do
  @moduledoc """
  Action for recording a restart attempt for an agent.
  
  This action updates the restart history, calculates backoff periods,
  and emits telemetry events for monitoring restart behavior.
  """
  
  use Jido.Action,
    name: "record_restart",
    description: "Records a restart attempt and updates backoff calculations",
    schema: [
      agent_id: [
        type: :string,
        required: true,
        doc: "ID of the agent that is being restarted"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{agent_id: agent_id} = params
    
    Logger.info("Recording restart attempt", agent_id: agent_id)
    
    now = DateTime.utc_now()
    info = get_restart_info(agent.state.restart_data, agent_id) || new_restart_info()
    
    # Clean old history
    recent_history = Enum.filter(info.history, fn timestamp ->
      DateTime.diff(now, timestamp, :millisecond) <= agent.state.config.history_window
    end)
    
    # Add current restart
    updated_history = [now | recent_history]
    restart_count = length(updated_history)
    
    # Calculate backoff if needed
    backoff_until = if restart_count >= agent.state.config.max_restarts do
      backoff_ms = calculate_backoff(restart_count - agent.state.config.max_restarts, agent.state.config)
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
    
    # Update state
    new_restart_data = Map.put(agent.state.restart_data, agent_id, updated_info)
    state_updates = %{restart_data: new_restart_data}
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} ->
        # Log backoff warning if applicable
        if backoff_until do
          Logger.warning("Agent #{agent_id} has restarted #{restart_count} times in window, " <>
                        "enforcing backoff until #{backoff_until}")
        end
        
        # Emit telemetry and result
        with {:ok, _} <- emit_telemetry(agent_id, restart_count, backoff_until, now),
             {:ok, _} <- emit_restart_recorded(updated_agent, agent_id, updated_info) do
          {:ok, %{restart_recorded: true, backoff_until: backoff_until}, %{agent: updated_agent}}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions
  
  defp get_restart_info(restart_data, agent_id) do
    Map.get(restart_data, agent_id)
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
  
  defp emit_telemetry(agent_id, restart_count, backoff_until, now) do
    try do
      :telemetry.execute(
        [:rubber_duck, :jido, :agent, :restart_recorded],
        %{
          restart_count: restart_count,
          backoff_ms: if(backoff_until, do: DateTime.diff(backoff_until, now, :millisecond), else: 0)
        },
        %{agent_id: agent_id}
      )
      {:ok, :telemetry_emitted}
    rescue
      error ->
        Logger.warning("Failed to emit telemetry: #{inspect(error)}")
        {:ok, :telemetry_failed}
    end
  end
  
  defp emit_restart_recorded(agent, agent_id, restart_info) do
    signal_params = %{
      signal_type: "restart_tracker.restart.recorded",
      data: %{
        agent_id: agent_id,
        restart_count: restart_info.count,
        recent_restarts: length(restart_info.history),
        backoff_until: restart_info.backoff_until,
        in_backoff: restart_info.backoff_until != nil,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end