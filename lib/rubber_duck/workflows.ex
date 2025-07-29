defmodule RubberDuck.Workflows do
  @moduledoc """
  Domain for managing Reactor workflow execution and persistence.
  
  This domain provides resources for storing workflow state, checkpoints,
  and version information using Ash's data layer.
  """
  
  use Ash.Domain,
    otp_app: :rubber_duck
  
  resources do
    resource RubberDuck.Workflows.Workflow
    resource RubberDuck.Workflows.Checkpoint
    resource RubberDuck.Workflows.Version
  end
end