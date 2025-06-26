defmodule RubberDuckEngines.EngineTest do
  use ExUnit.Case, async: true

  test "engine behavior defines required callbacks" do
    # This test ensures the Engine behavior exists and defines required callbacks
    assert Code.ensure_loaded?(RubberDuckEngines.Engine)
    
    # Check that behavior callbacks are defined
    callbacks = RubberDuckEngines.Engine.behaviour_info(:callbacks)
    
    assert {:init_engine, 1} in callbacks
    assert {:analyze, 2} in callbacks
    assert {:capabilities, 0} in callbacks
    assert {:health_check, 1} in callbacks
  end

  test "engine manager can be started" do
    # Test that the engine manager module exists and is startable
    assert Code.ensure_loaded?(RubberDuckEngines.EngineManager)
    
    # Test we can start an instance (it may already be running from app)
    case RubberDuckEngines.EngineManager.start_link([name: :test_manager]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end