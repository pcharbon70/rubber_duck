defmodule RubberDuck.Jido.Workflows.SimplePipeline do
  @moduledoc """
  A simple pipeline workflow that processes data through multiple agents sequentially.
  
  This workflow demonstrates:
  - Sequential agent execution
  - Error handling and compensation
  - State passing between steps
  
  ## Inputs
  
  - `:data` - The data to process
  - `:pipeline_config` - Configuration for the pipeline steps
  
  ## Example
  
      {:ok, result} = WorkflowCoordinator.execute_workflow(
        SimplePipeline,
        %{
          data: %{items: [1, 2, 3]},
          pipeline_config: %{
            steps: [:validate, :transform, :store]
          }
        }
      )
  """
  
  use Reactor
  
  alias RubberDuck.Jido.Steps.{ExecuteAgentAction, SelectAgent}
  
  input :data
  input :pipeline_config
  
  # Select validator agent
  step :select_validator, SelectAgent do
    argument :criteria, value({:capability, :validation})
    argument :strategy, value(:least_loaded)
  end
  
  # Validate data
  step :validate, ExecuteAgentAction do
    argument :agent_id, result(:select_validator)
    argument :action, value(RubberDuck.Actions.ValidateAction)
    argument :params, input(:data)
  end
  
  # Select transformer agent
  step :select_transformer, SelectAgent do
    argument :criteria, value({:capability, :transformation})
    argument :strategy, value(:least_loaded)
    
    # Only run if validation passed
    wait_for :validate
  end
  
  # Transform data
  step :transform, ExecuteAgentAction do
    argument :agent_id, result(:select_transformer)
    argument :action, value(RubberDuck.Actions.TransformAction)
    argument :params, result(:validate)
  end
  
  # Select storage agent
  step :select_storage, SelectAgent do
    argument :criteria, value({:capability, :storage})
    argument :strategy, value(:least_loaded)
    
    wait_for :transform
  end
  
  # Store results
  step :store, ExecuteAgentAction do
    argument :agent_id, result(:select_storage)
    argument :action, value(RubberDuck.Actions.StoreAction)
    argument :params, result(:transform)
  end
  
  # Return the storage result
  return :store
end