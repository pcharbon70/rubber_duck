defmodule RubberDuck.Tool.Composition.ConditionalReturn do
  @moduledoc """
  Special step for handling conditional workflow returns.
  
  This step determines which result to return based on the condition step result.
  It's used internally by conditional workflows to return the appropriate result
  from either the success or failure branch.
  """
  
  use RubberDuck.Workflows.Step
  
  @doc """
  Returns the appropriate result based on the condition outcome.
  
  ## Arguments
  
  - `condition_result` - The result from the condition step
  - `success_result` - The result from the success branch
  - `failure_result` - The result from the failure branch
  
  ## Returns
  
  The result from the branch that was executed based on the condition.
  """
  @impl true
  def run(arguments, _context) do
    condition_result = Map.get(arguments, :condition_result)
    success_result = Map.get(arguments, :success_result)
    failure_result = Map.get(arguments, :failure_result)
    
    case condition_result do
      {:ok, _} ->
        # Condition succeeded, return success result
        case success_result do
          {:ok, result} -> {:ok, result}
          {:error, _} = error -> error
          result -> {:ok, result}
        end
        
      {:error, _} ->
        # Condition failed, return failure result
        case failure_result do
          {:ok, result} -> {:ok, result}
          {:error, _} = error -> error
          result -> {:ok, result}
        end
        
      result ->
        # Condition returned a non-standard result
        # Treat as success if truthy, failure if falsy
        if result do
          case success_result do
            {:ok, result} -> {:ok, result}
            {:error, _} = error -> error
            result -> {:ok, result}
          end
        else
          case failure_result do
            {:ok, result} -> {:ok, result}
            {:error, _} = error -> error
            result -> {:ok, result}
          end
        end
    end
  end
  
  @doc """
  No compensation needed for conditional return.
  """
  @impl true
  def compensate(_arguments, _result, _context) do
    :ok
  end
end