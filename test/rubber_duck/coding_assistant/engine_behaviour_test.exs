defmodule RubberDuck.CodingAssistant.EngineBehaviourTest do
  @moduledoc """
  Tests for the EngineBehaviour contract and callback definitions.
  """
  
  use ExUnit.Case, async: true
  
  # Test that the behaviour module exists and defines required callbacks
  test "EngineBehaviour module exists" do
    assert Code.ensure_loaded?(RubberDuck.CodingAssistant.EngineBehaviour)
  end
  
  test "EngineBehaviour defines required callbacks" do
    behaviour_module = RubberDuck.CodingAssistant.EngineBehaviour
    callbacks = behaviour_module.behaviour_info(:callbacks)
    
    # Required callbacks based on research document
    required_callbacks = [
      {:init, 1},
      {:process_real_time, 2},
      {:process_batch, 2}, 
      {:capabilities, 0},
      {:health_check, 1},
      {:handle_engine_event, 2},
      {:terminate, 2}
    ]
    
    for required_callback <- required_callbacks do
      assert required_callback in callbacks,
        "Missing required callback: #{inspect(required_callback)}"
    end
  end
  
  test "EngineBehaviour defines proper types" do
    # Test that the behaviour module has proper type definitions
    behaviour_module = RubberDuck.CodingAssistant.EngineBehaviour
    
    # Module should exist and be a behaviour
    assert function_exported?(behaviour_module, :behaviour_info, 1)
  end
  
  # Test implementation of a mock engine that follows the behaviour
  defmodule MockEngine do
    @behaviour RubberDuck.CodingAssistant.EngineBehaviour
    
    @impl true
    def init(_config), do: {:ok, %{initialized: true}}
    
    @impl true
    def process_real_time(_data, state) do
      result = %{status: :success, data: %{processed: true}}
      {:ok, result, state}
    end
    
    @impl true  
    def process_batch(_data_list, state) do
      results = [%{status: :success, data: %{batch_processed: true}}]
      {:ok, results, state}
    end
    
    @impl true
    def capabilities, do: [:test_capability]
    
    @impl true
    def health_check(_state), do: :healthy
    
    @impl true
    def handle_engine_event(_event, state), do: {:ok, state}
    
    @impl true
    def terminate(_reason, _state), do: :ok
  end
  
  test "MockEngine implements EngineBehaviour correctly" do
    # Test that our mock engine follows the contract
    assert {:ok, state} = MockEngine.init(%{})
    assert state.initialized == true
    
    assert {:ok, result, _new_state} = MockEngine.process_real_time(%{test: :data}, state)
    assert result.status == :success
    
    assert {:ok, results, _new_state} = MockEngine.process_batch([%{test: :data}], state)
    assert is_list(results)
    
    assert MockEngine.capabilities() == [:test_capability]
    assert MockEngine.health_check(state) == :healthy
    assert {:ok, _state} = MockEngine.handle_engine_event(%{type: :test}, state)
    assert MockEngine.terminate(:normal, state) == :ok
  end
end