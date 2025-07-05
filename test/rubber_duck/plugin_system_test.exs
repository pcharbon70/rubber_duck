defmodule RubberDuck.PluginSystemTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.PluginSystem
  alias RubberDuck.ExamplePlugins
  alias RubberDuck.Config
  
  describe "DSL compilation" do
    test "compiles valid plugin configuration" do
      # Config should compile without errors
      assert Code.ensure_loaded?(Config)
    end
    
    test "extracts plugin entities" do
      plugins = PluginSystem.plugins(Config)
      assert length(plugins) == 3
      
      names = Enum.map(plugins, & &1.name)
      assert :text_enhancer in names
      assert :word_counter in names
      assert :text_processor in names
    end
    
    test "gets specific plugin" do
      plugin = PluginSystem.get_plugin(Config, :text_enhancer)
      assert plugin.name == :text_enhancer
      assert plugin.module == ExamplePlugins.TextEnhancer
      assert plugin.priority == 90
      assert plugin.enabled == true
    end
    
    test "returns enabled plugins sorted by priority" do
      plugins = PluginSystem.enabled_plugins(Config)
      priorities = Enum.map(plugins, & &1.priority)
      
      # Should be sorted in descending order
      assert priorities == [90, 80, 70]
    end
    
    test "finds dependent plugins" do
      dependents = PluginSystem.dependent_plugins(Config, :text_enhancer)
      assert length(dependents) == 1
      assert hd(dependents).name == :text_processor
    end
  end
  
  describe "DSL validation" do
    test "validates plugin priorities" do
      assert_raise Spark.Error.DslError, ~r/invalid priority/, fn ->
        defmodule InvalidPriority do
          use RubberDuck.PluginSystem
          
          plugins do
            plugin :bad_priority do
              module ExamplePlugins.TextEnhancer
              priority 150  # Invalid - must be 0-100
            end
          end
        end
      end
    end
    
    test "validates unique plugin names" do
      assert_raise Spark.Error.DslError, ~r/Duplicate plugin name/, fn ->
        defmodule DuplicateNames do
          use RubberDuck.PluginSystem
          
          plugins do
            plugin :same_name do
              module ExamplePlugins.TextEnhancer
            end
            
            plugin :same_name do
              module ExamplePlugins.WordCounter
            end
          end
        end
      end
    end
    
    test "validates module exists" do
      assert_raise Spark.Error.DslError, ~r/cannot be loaded/, fn ->
        defmodule NonExistentModule do
          use RubberDuck.PluginSystem
          
          plugins do
            plugin :missing do
              module DoesNotExist.Module
            end
          end
        end
      end
    end
    
    test "validates plugin behavior" do
      assert_raise Spark.Error.DslError, ~r/does not implement.*behavior/, fn ->
        defmodule NotAPlugin do
          def some_function, do: :ok
        end
        
        defmodule InvalidBehavior do
          use RubberDuck.PluginSystem
          
          plugins do
            plugin :not_plugin do
              module NotAPlugin
            end
          end
        end
      end
    end
  end
  
  describe "dependency resolution" do
    test "validates dependencies exist" do
      assert_raise Spark.Error.DslError, ~r/depends on missing plugins/, fn ->
        defmodule MissingDependency do
          use RubberDuck.PluginSystem
          
          plugins do
            plugin :dependent do
              module ExamplePlugins.TextProcessor
              dependencies [:does_not_exist]
            end
          end
        end
      end
    end
    
    test "detects circular dependencies" do
      assert_raise Spark.Error.DslError, ~r/Circular dependencies detected/, fn ->
        defmodule CircularDeps do
          use RubberDuck.PluginSystem
          
          plugins do
            plugin :plugin_a do
              module ExamplePlugins.TextEnhancer
              dependencies [:plugin_b]
            end
            
            plugin :plugin_b do
              module ExamplePlugins.WordCounter
              dependencies [:plugin_a]
            end
          end
        end
      end
    end
  end
end