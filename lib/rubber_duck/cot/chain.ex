defmodule RubberDuck.CoT.Chain do
  @moduledoc """
  Utilities for working with Chain-of-Thought reasoning chains.
  """

  @doc """
  Gets the reasoning chain configuration for a given module.
  """
  def reasoning_chain(module) do
    if function_exported?(module, :config, 0) && function_exported?(module, :steps, 0) do
      config = module.config()
      steps = module.steps()

      # Add the chain module reference to each step
      steps_with_module =
        Enum.map(steps, fn step ->
          Map.put(step, :__chain_module__, module)
        end)

      # Return configuration with steps
      [Map.put(config, :entities, %{step: steps_with_module})]
    else
      raise "Module #{inspect(module)} must implement config/0 and steps/0"
    end
  end
end
