defmodule RubberDuck.PluginTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Plugin
  alias RubberDuck.ExamplePlugins.{TextEnhancer, WordCounter}
  
  describe "Plugin behavior validation" do
    test "is_plugin?/1 returns true for valid plugins" do
      assert Plugin.is_plugin?(TextEnhancer) == true
      assert Plugin.is_plugin?(WordCounter) == true
    end
    
    test "is_plugin?/1 returns false for non-plugins" do
      assert Plugin.is_plugin?(String) == false
      assert Plugin.is_plugin?(:not_a_module) == false
      assert Plugin.is_plugin?(nil) == false
    end
    
    test "validate_plugin/1 returns :ok for valid plugins" do
      assert Plugin.validate_plugin(TextEnhancer) == :ok
      assert Plugin.validate_plugin(WordCounter) == :ok
    end
    
    test "validate_plugin/1 returns error for invalid modules" do
      assert {:error, :not_a_module} = Plugin.validate_plugin("not a module")
    end
    
    test "validate_plugin/1 returns error for modules missing callbacks" do
      defmodule IncompletePlugin do
        @behaviour RubberDuck.Plugin
        
        def name, do: :incomplete
        def version, do: "1.0.0"
        # Missing other required callbacks
      end
      
      assert {:error, {:missing_callbacks, callbacks}} = Plugin.validate_plugin(IncompletePlugin)
      assert length(callbacks) > 0
    end
  end
  
  describe "TextEnhancer plugin" do
    test "initializes with default config" do
      assert {:ok, state} = TextEnhancer.init([])
      assert state.prefix == "["
      assert state.suffix == "]"
    end
    
    test "initializes with custom config" do
      assert {:ok, state} = TextEnhancer.init([prefix: "<<", suffix: ">>"])
      assert state.prefix == "<<"
      assert state.suffix == ">>"
    end
    
    test "executes text enhancement" do
      {:ok, state} = TextEnhancer.init([prefix: "**", suffix: "**"])
      assert {:ok, "**hello**", ^state} = TextEnhancer.execute("hello", state)
    end
    
    test "validates text input" do
      assert :ok = TextEnhancer.validate_input("text")
      assert {:error, :not_a_string} = TextEnhancer.validate_input(123)
    end
    
    test "returns error for non-text input" do
      {:ok, state} = TextEnhancer.init([])
      assert {:error, :invalid_input_type, ^state} = TextEnhancer.execute(123, state)
    end
  end
  
  describe "WordCounter plugin" do
    test "counts words correctly" do
      {:ok, state} = WordCounter.init([])
      
      assert {:ok, result1, state1} = WordCounter.execute("hello world", state)
      assert result1.word_count == 2
      assert result1.total_processed == 2
      
      assert {:ok, result2, state2} = WordCounter.execute("one two three", state1)
      assert result2.word_count == 3
      assert result2.total_processed == 5
    end
    
    test "handles empty strings" do
      {:ok, state} = WordCounter.init([])
      assert {:ok, result, _} = WordCounter.execute("", state)
      assert result.word_count == 0
    end
    
    test "handles strings with multiple spaces" do
      {:ok, state} = WordCounter.init([])
      assert {:ok, result, _} = WordCounter.execute("  hello   world  ", state)
      assert result.word_count == 2
    end
  end
end