defmodule RubberDuck.Tool do
  @moduledoc """
  Spark DSL for defining and configuring tools in the RubberDuck system.
  
  This module provides a declarative way to define tools with metadata,
  parameters, execution configuration, and security settings.
  
  ## Example
  
      defmodule MyApp.Tools.Calculator do
        use RubberDuck.Tool
        
        tool do
          name :calculator
          description "A simple calculator tool"
          category :math
          version "1.0.0"
          tags [:arithmetic, :basic]
          
          parameter :operation do
            type :string
            required true
            description "The operation to perform: add, subtract, multiply, divide"
            constraints [
              enum: ["add", "subtract", "multiply", "divide"]
            ]
          end
          
          parameter :operands do
            type :list
            required true
            description "List of numbers to operate on"
            constraints [
              min_length: 2
            ]
          end
          
          execution do
            handler &MyApp.Tools.Calculator.execute/2
            timeout 5_000
            async true
          end
          
          security do
            sandbox :restricted
            capabilities [:computation]
          end
        end
        
        def execute(params, _context) do
          # Implementation here
          {:ok, result}
        end
      end
  """
  
  use Spark.Dsl, default_extensions: [extensions: [RubberDuck.Tool.Dsl]]
  
  @doc """
  Get the tool's name.
  """
  @spec name(module()) :: atom()
  def name(module) do
    module.__tool__(:name)
  end
  
  @doc """
  Get the tool's metadata.
  
  Returns a map containing all tool configuration including name, description,
  category, version, tags, parameters, execution config, and security settings.
  """
  @spec metadata(module()) :: map()
  def metadata(module) do
    module.__tool__(:all)
  end
  
  @doc """
  Get the tool's parameters.
  """
  @spec parameters(module()) :: [RubberDuck.Tool.Parameter.t()]
  def parameters(module) do
    module.__tool__(:parameters)
  end
  
  @doc """
  Get the tool's execution configuration.
  """
  @spec execution(module()) :: RubberDuck.Tool.Execution.t() | nil
  def execution(module) do
    module.__tool__(:execution)
  end
  
  @doc """
  Get the tool's security configuration.
  """
  @spec security(module()) :: RubberDuck.Tool.Security.t() | nil
  def security(module) do
    module.__tool__(:security)
  end
  
  @doc """
  Check if a module is a tool.
  """
  @spec is_tool?(module()) :: boolean()
  def is_tool?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__tool__, 1)
  end
end