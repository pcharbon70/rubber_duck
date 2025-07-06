defmodule RubberDuck.CoT do
  @moduledoc """
  Chain-of-Thought (CoT) reasoning system for structured LLM reasoning.
  
  Provides a high-level API for executing reasoning chains defined
  using the CoT DSL.
  
  ## Example
  
      # Define a reasoning chain
      defmodule ProblemSolver do
        use RubberDuck.CoT.Chain
        
        reasoning_chain do
          name :problem_solver
          
          step :understand do
            prompt "What is the core problem here?"
          end
          
          step :analyze do
            prompt "What are the key factors?"
            depends_on :understand
          end
          
          step :solve do
            prompt "What's the best solution?"
            depends_on :analyze
          end
        end
      end
      
      # Execute the chain
      {:ok, result} = RubberDuck.CoT.reason(ProblemSolver, "How do I optimize database queries?")
  """
  
  alias RubberDuck.CoT.ConversationManager
  
  @doc """
  Executes a reasoning chain with the given query.
  
  ## Options
  
  - `:user_id` - User ID for context and memory
  - `:format` - Output format (:markdown, :plain, :json, :structured)
  - `:timeout` - Maximum time for reasoning (default: 30 seconds)
  - `:cache` - Whether to use caching (default: true)
  """
  def reason(chain_module, query, opts \\ []) do
    ConversationManager.execute_chain(chain_module, query, opts)
  end
  
  @doc """
  Executes a reasoning chain asynchronously.
  """
  def reason_async(chain_module, query, opts \\ []) do
    Task.async(fn ->
      reason(chain_module, query, opts)
    end)
  end
  
  @doc """
  Gets the history of a reasoning session.
  """
  def get_session(session_id) do
    ConversationManager.get_history(session_id)
  end
  
  @doc """
  Gets reasoning performance statistics.
  """
  def get_stats() do
    ConversationManager.get_stats()
  end
  
  @doc """
  Creates a simple reasoning chain without DSL.
  """
  def simple_reason(query, steps, opts \\ []) when is_list(steps) do
    # Create an anonymous module with the steps
    module_name = :"SimpleReasoning#{System.unique_integer([:positive])}"
    
    ast = quote do
      defmodule unquote(module_name) do
        use RubberDuck.CoT.Chain
        
        reasoning_chain do
          name :simple_reasoning
          
          unquote_splicing(
            Enum.map(steps, fn {name, prompt} ->
              quote do
                step unquote(name) do
                  prompt unquote(prompt)
                end
              end
            end)
          )
        end
      end
    end
    
    # Compile the module
    Code.compile_quoted(ast)
    
    # Execute the chain
    reason(module_name, query, opts)
  end
  
  @doc """
  Validates a reasoning chain module.
  """
  def validate_chain(chain_module) do
    try do
      config = RubberDuck.CoT.Chain.reasoning_chain(chain_module)
      
      if is_list(config) and length(config) > 0 do
        {:ok, :valid}
      else
        {:error, :empty_chain}
      end
    rescue
      _ -> {:error, :invalid_module}
    end
  end
end