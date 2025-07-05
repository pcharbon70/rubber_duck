defmodule RubberDuck.EngineTest do
  use ExUnit.Case, async: true
  
  defmodule CompleteEngine do
    @behaviour RubberDuck.Engine
    
    @impl true
    def init(config) do
      {:ok, Map.new(config)}
    end
    
    @impl true
    def execute(input, state) do
      result = Map.merge(state, input)
      {:ok, result}
    end
    
    @impl true
    def capabilities do
      [:complete, :test]
    end
  end
  
  defmodule ErrorEngine do
    @behaviour RubberDuck.Engine
    
    @impl true
    def init(_config) do
      {:error, "Initialization failed"}
    end
    
    @impl true
    def execute(_input, _state) do
      {:error, "Execution failed"}
    end
    
    @impl true
    def capabilities do
      [:error]
    end
  end
  
  describe "Engine behavior" do
    test "init/1 callback works correctly" do
      config = [key: "value", number: 42]
      assert {:ok, state} = CompleteEngine.init(config)
      assert state == %{key: "value", number: 42}
    end
    
    test "init/1 can return errors" do
      assert {:error, "Initialization failed"} = ErrorEngine.init([])
    end
    
    test "execute/2 callback works correctly" do
      {:ok, state} = CompleteEngine.init(initial: "state")
      input = %{new: "data"}
      
      assert {:ok, result} = CompleteEngine.execute(input, state)
      assert result == %{initial: "state", new: "data"}
    end
    
    test "execute/2 can return errors" do
      assert {:error, "Execution failed"} = ErrorEngine.execute(%{}, %{})
    end
    
    test "capabilities/0 returns list of atoms" do
      assert CompleteEngine.capabilities() == [:complete, :test]
      assert ErrorEngine.capabilities() == [:error]
    end
  end
  
  test "behavior callbacks are defined" do
    callbacks = RubberDuck.Engine.behaviour_info(:callbacks)
    
    assert {:init, 1} in callbacks
    assert {:execute, 2} in callbacks
    assert {:capabilities, 0} in callbacks
  end
end