defmodule RubberDuck.CoT.Chain do
  @moduledoc """
  Base module for Chain-of-Thought reasoning chains.
  
  Use this module to define a reasoning chain with the CoT DSL.
  
  ## Example
  
      defmodule MyChain do
        use RubberDuck.CoT.Chain
        
        reasoning_chain do
          name :my_chain
          description "My reasoning chain"
          
          step :analyze do
            prompt "Analyze the problem: {{query}}"
          end
          
          step :solve do
            prompt "Solve based on analysis: {{previous_result}}"
            depends_on :analyze
          end
        end
      end
  """
  
  defmacro __using__(_opts) do
    quote do
      use Spark.Dsl, default_extensions: [extensions: [RubberDuck.CoT.Dsl]]
      
      @doc """
      Gets the reasoning chain configuration for this module.
      """
      def reasoning_chain() do
        RubberDuck.CoT.Chain.reasoning_chain(__MODULE__)
      end
    end
  end
  
  @doc """
  Gets the reasoning chain configuration for a given module.
  """
  def reasoning_chain(module) do
    # Get the reasoning chain configuration
    steps = Spark.Dsl.Extension.get_entities(module, [:reasoning_chain, :step]) || []
    
    # Build the configuration map from individual options
    config = %{
      name: Spark.Dsl.Extension.get_opt(module, [:reasoning_chain], :name, :unnamed),
      description: Spark.Dsl.Extension.get_opt(module, [:reasoning_chain], :description, nil),
      max_steps: Spark.Dsl.Extension.get_opt(module, [:reasoning_chain], :max_steps, 10),
      timeout: Spark.Dsl.Extension.get_opt(module, [:reasoning_chain], :timeout, 30_000),
      template: Spark.Dsl.Extension.get_opt(module, [:reasoning_chain], :template, :default),
      cache_ttl: Spark.Dsl.Extension.get_opt(module, [:reasoning_chain], :cache_ttl, 900),
      entities: %{step: steps}
    }
    
    # Return as a list with the configuration
    [config]
  end
end