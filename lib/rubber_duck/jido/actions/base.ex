defmodule RubberDuck.Jido.Actions.Base do
  @moduledoc """
  Base actions for the Jido pattern transformation.
  
  This module provides fundamental actions that serve as building blocks
  for migrating from GenServer-based agents with handle_signal callbacks
  to the proper Jido pattern where agents are data structures and actions
  perform state transformations.
  
  ## Available Base Actions
  
  - `UpdateStateAction` - Safe state updates with validation
  - `EmitSignalAction` - CloudEvents signal emission
  - `InitializeAgentAction` - Agent initialization with lifecycle hooks
  - `ComposeAction` - Action composition for complex workflows
  
  ## Usage Example
  
      # Update agent state
      RubberDuck.Jido.Actions.Base.UpdateStateAction.run(
        %{updates: %{status: :active}},
        %{agent: agent}
      )
      
      # Emit a signal
      RubberDuck.Jido.Actions.Base.EmitSignalAction.run(
        %{signal_type: "agent.status.changed", data: %{status: :active}},
        %{agent: agent}
      )
  """
  
  alias RubberDuck.Jido.Actions.Base.{
    UpdateStateAction,
    EmitSignalAction,
    InitializeAgentAction,
    ComposeAction
  }
  
  @doc """
  Lists all available base actions.
  """
  def all_actions do
    [
      UpdateStateAction,
      EmitSignalAction,
      InitializeAgentAction,
      ComposeAction
    ]
  end
  
  
  @doc """
  Creates an action chain for common agent operations.
  
  This helper creates a composition of actions for typical
  agent workflows like initialization, state update, and signal emission.
  """
  def create_action_chain(actions) do
    fn agent, _params ->
      ComposeAction.run(
        %{actions: actions, stop_on_error: true},
        %{agent: agent}
      )
    end
  end
end