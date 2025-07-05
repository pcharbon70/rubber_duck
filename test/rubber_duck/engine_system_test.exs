defmodule RubberDuck.EngineSystemTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.EngineSystem
  
  # Test modules that implement the Engine behavior
  defmodule TestEngine do
    @behaviour RubberDuck.Engine
    
    @impl true
    def init(config), do: {:ok, config}
    
    @impl true
    def execute(_input, state), do: {:ok, state}
    
    @impl true
    def capabilities, do: [:test, :sample]
  end
  
  defmodule AnotherTestEngine do
    @behaviour RubberDuck.Engine
    
    @impl true
    def init(config), do: {:ok, config}
    
    @impl true
    def execute(_input, state), do: {:ok, state}
    
    @impl true
    def capabilities, do: [:another, :sample]
  end
  
  # Test DSL module
  defmodule TestEngines do
    use RubberDuck.EngineSystem
    
    engines do
      engine :test_engine do
        module RubberDuck.EngineSystemTest.TestEngine
        description "A test engine"
        priority 100
        timeout 5_000
        
        config [
          option1: "value1",
          option2: 42
        ]
      end
      
      engine :another_engine do
        module RubberDuck.EngineSystemTest.AnotherTestEngine
        description "Another test engine"
        priority 50
      end
    end
  end
  
  describe "engines/1" do
    test "returns all configured engines" do
      engines = EngineSystem.engines(TestEngines)
      
      assert length(engines) == 2
      assert Enum.map(engines, & &1.name) == [:test_engine, :another_engine]
    end
    
    test "engines have correct attributes" do
      engines = EngineSystem.engines(TestEngines)
      test_engine = Enum.find(engines, & &1.name == :test_engine)
      
      assert test_engine.module == RubberDuck.EngineSystemTest.TestEngine
      assert test_engine.description == "A test engine"
      assert test_engine.priority == 100
      assert test_engine.timeout == 5_000
      assert test_engine.config == [option1: "value1", option2: 42]
    end
    
    test "engines have default values" do
      engines = EngineSystem.engines(TestEngines)
      another_engine = Enum.find(engines, & &1.name == :another_engine)
      
      assert another_engine.priority == 50
      assert another_engine.timeout == 30_000
      assert another_engine.config == []
    end
  end
  
  describe "get_engine/2" do
    test "returns engine by name" do
      engine = EngineSystem.get_engine(TestEngines, :test_engine)
      
      assert engine.name == :test_engine
      assert engine.module == RubberDuck.EngineSystemTest.TestEngine
    end
    
    test "returns nil for non-existent engine" do
      assert EngineSystem.get_engine(TestEngines, :nonexistent) == nil
    end
  end
  
  describe "engines_by_capability/2" do
    test "returns engines with the given capability" do
      engines = EngineSystem.engines_by_capability(TestEngines, :sample)
      
      assert length(engines) == 2
      assert Enum.map(engines, & &1.name) == [:test_engine, :another_engine]
    end
    
    test "returns only matching engines" do
      engines = EngineSystem.engines_by_capability(TestEngines, :test)
      
      assert length(engines) == 1
      assert hd(engines).name == :test_engine
    end
    
    test "returns empty list for non-existent capability" do
      engines = EngineSystem.engines_by_capability(TestEngines, :nonexistent)
      
      assert engines == []
    end
  end
  
  describe "engines_by_priority/1" do
    test "returns engines sorted by priority (highest first)" do
      engines = EngineSystem.engines_by_priority(TestEngines)
      
      assert Enum.map(engines, & &1.name) == [:test_engine, :another_engine]
      assert Enum.map(engines, & &1.priority) == [100, 50]
    end
  end
end