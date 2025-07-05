defmodule RubberDuck.EngineSystem do
  @moduledoc """
  Spark DSL for defining and configuring engines in the RubberDuck system.
  
  This module provides a declarative way to configure engines that handle
  various tasks like code completion, generation, and analysis.
  
  ## Example
  
      defmodule MyApp.Engines do
        use RubberDuck.EngineSystem
        
        engines do
          engine :code_completion do
            module MyApp.Engines.CodeCompletion
            description "Provides intelligent code completion"
            priority 100
            timeout 5_000
            
            config do
              max_suggestions 10
              min_confidence 0.7
            end
          end
          
          engine :code_generation do
            module MyApp.Engines.CodeGeneration
            description "Generates code from natural language"
            priority 90
          end
        end
      end
  """
  
  use Spark.Dsl, default_extensions: [extensions: [RubberDuck.EngineSystem.Dsl]]
    
  @doc """
  Get all configured engines.
  
  Returns a list of all engine configurations defined in the DSL.
  """
  @spec engines(module()) :: [RubberDuck.EngineSystem.Engine.t()]
  def engines(module) do
    Spark.Dsl.Extension.get_entities(module, [:engines])
  end
  
  @doc """
  Get an engine by name.
  
  Returns the engine configuration for the given name, or nil if not found.
  """
  @spec get_engine(module(), atom()) :: RubberDuck.EngineSystem.Engine.t() | nil
  def get_engine(module, name) do
    module
    |> engines()
    |> Enum.find(&(&1.name == name))
  end
  
  @doc """
  Get engines by capability.
  
  Returns all engines that provide the given capability.
  """
  @spec engines_by_capability(module(), atom()) :: [RubberDuck.EngineSystem.Engine.t()]
  def engines_by_capability(module, capability) do
    module
    |> engines()
    |> Enum.filter(fn engine ->
      # We'll need to call the module's capabilities/0 function
      # This assumes the module is already loaded
      if Code.ensure_loaded?(engine.module) and 
         function_exported?(engine.module, :capabilities, 0) do
        capability in engine.module.capabilities()
      else
        false
      end
    end)
  end
  
  @doc """
  Get engines sorted by priority.
  
  Returns all engines sorted by priority (highest first).
  """
  @spec engines_by_priority(module()) :: [RubberDuck.EngineSystem.Engine.t()]
  def engines_by_priority(module) do
    module
    |> engines()
    |> Enum.sort_by(& &1.priority, :desc)
  end
end