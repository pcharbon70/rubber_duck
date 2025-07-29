defmodule RubberDuck.Jido.Workflows.ValidationWorkflow do
  @moduledoc """
  A simple validation workflow used by composite workflows.
  
  This workflow demonstrates basic data validation.
  """
  
  use Reactor
  
  input :data
  
  step :validate do
    argument :data, input(:data)
    
    run fn arguments ->
      # Simple validation logic
      if is_map(arguments.data) and map_size(arguments.data) > 0 do
        {:ok, :valid}
      else
        {:error, :invalid_data}
      end
    end
  end
  
  return :validate
end