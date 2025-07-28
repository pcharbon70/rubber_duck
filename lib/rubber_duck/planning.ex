defmodule RubberDuck.Planning do
  @moduledoc """
  Domain for the planning system based on the LLM-Modulo framework.

  This domain manages plans, tasks, constraints, and validation results
  for sophisticated AI-driven planning with external validation critics.

  ## Resources

  - `Plan` - High-level plans with context and metadata
  - `Task` - Individual tasks with dependencies and success criteria
  - `Constraint` - Rules and requirements for plans
  - `Validation` - Results from critic validations

  ## Features

  - Hierarchical task decomposition
  - Dependency management with cycle detection
  - Constraint enforcement (hard and soft)
  - Validation result tracking
  - Authorization policies for plan access
  """

  use Ash.Domain,
    otp_app: :rubber_duck,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain]

  resources do
    resource RubberDuck.Planning.Plan
    resource RubberDuck.Planning.Phase
    resource RubberDuck.Planning.Task
    resource RubberDuck.Planning.TaskDependency
    resource RubberDuck.Planning.Constraint
    resource RubberDuck.Planning.Validation
  end
end
