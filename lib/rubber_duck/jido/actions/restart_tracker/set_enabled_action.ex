defmodule RubberDuck.Jido.Actions.RestartTracker.SetEnabledAction do
  @moduledoc """
  Action for enabling or disabling the restart tracking and backoff enforcement.
  
  This action allows runtime control of the restart tracker functionality,
  useful for testing or emergency situations where backoff needs to be bypassed.
  """
  
  use Jido.Action,
    name: "set_enabled",
    description: "Enables or disables restart tracking and backoff enforcement",
    schema: [
      enabled: [
        type: :boolean,
        required: true,
        doc: "Whether to enable (true) or disable (false) restart tracking"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{enabled: enabled} = params
    
    previous_state = agent.state.enabled
    
    Logger.info("Setting restart tracker enabled status", 
      enabled: enabled, 
      previous_state: previous_state
    )
    
    # Update enabled state
    state_updates = %{enabled: enabled}
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} ->
        # Emit state change event
        with {:ok, _} <- emit_enabled_changed(updated_agent, enabled, previous_state) do
          {:ok, %{enabled: enabled, previous_state: previous_state}, %{agent: updated_agent}}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions
  
  defp emit_enabled_changed(agent, new_state, previous_state) do
    signal_params = %{
      signal_type: "restart_tracker.enabled.changed",
      data: %{
        enabled: new_state,
        previous_state: previous_state,
        action: if(new_state, do: "enabled", else: "disabled"),
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end