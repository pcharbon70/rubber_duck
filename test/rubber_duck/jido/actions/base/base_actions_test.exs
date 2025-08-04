defmodule RubberDuck.Jido.Actions.Base.BaseActionsTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido.Actions.Base
  
  describe "Base module" do
    test "lists all available base actions" do
      actions = Base.all_actions()
      
      assert length(actions) == 9
      assert Base.UpdateStateAction in actions
      assert Base.EmitSignalAction in actions
      assert Base.InitializeAgentAction in actions
      assert Base.ComposeAction in actions
      assert Base.RequestAction in actions
      assert Base.ProcessingAction in actions
      assert Base.CoordinationAction in actions
      assert Base.MonitoringAction in actions
      assert Base.UtilityAction in actions
    end
    
    test "creates action chain for common operations" do
      actions = [
        {Base.UpdateStateAction, %{updates: %{status: :active}}},
        {Base.EmitSignalAction, %{signal_type: "test.signal", data: %{}}}
      ]
      
      chain_fn = Base.create_action_chain(actions)
      
      assert is_function(chain_fn, 2)
    end
  end
end