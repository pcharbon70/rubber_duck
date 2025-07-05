defmodule RubberDuck.ExampleEngines do
  @moduledoc """
  Example usage of the EngineSystem DSL.
  
  This module demonstrates how to define engines using the Spark DSL.
  """
  
  use RubberDuck.EngineSystem
  
  engines do
    engine :echo do
      module RubberDuck.ExampleEngines.Echo
      description "Simple echo engine for testing"
      priority 10
      timeout 1_000
      pool_size 1  # Single instance
      
      config [
        prefix: "[ECHO]"
      ]
    end
    
    engine :reverse do
      module RubberDuck.ExampleEngines.Reverse
      description "Reverses input text"
      priority 20
      timeout 2_000
      pool_size 3          # Pool of 3 workers
      max_overflow 2       # Allow 2 extra workers under load
      checkout_timeout 5_000
    end
  end
end

defmodule RubberDuck.ExampleEngines.Echo do
  @moduledoc "Simple echo engine implementation"
  
  @behaviour RubberDuck.Engine
  
  @impl true
  def init(config) do
    {:ok, Map.new(config)}
  end
  
  @impl true
  def execute(%{text: text} = _input, %{prefix: prefix} = _state) do
    {:ok, "#{prefix} #{text}"}
  end
  def execute(%{text: text}, _state) do
    {:ok, text}
  end
  def execute(_input, _state) do
    {:error, "Missing required :text key in input"}
  end
  
  @impl true
  def capabilities do
    [:echo, :text_processing]
  end
end

defmodule RubberDuck.ExampleEngines.Reverse do
  @moduledoc "Text reversal engine implementation"
  
  @behaviour RubberDuck.Engine
  
  @impl true
  def init(config) do
    {:ok, Map.new(config)}
  end
  
  @impl true
  def execute(%{text: text}, _state) when is_binary(text) do
    reversed = String.reverse(text)
    {:ok, reversed}
  end
  def execute(_input, _state) do
    {:error, "Missing required :text key in input or text is not a string"}
  end
  
  @impl true
  def capabilities do
    [:reverse, :text_processing]
  end
end