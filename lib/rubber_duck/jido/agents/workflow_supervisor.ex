defmodule RubberDuck.Jido.Agents.WorkflowSupervisor do
  @moduledoc """
  Supervisor for workflow-related processes.
  
  This supervisor manages:
  - WorkflowCoordinator for executing workflows
  - Any workflow-specific processes
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    children = [
      # Workflow Coordinator
      {RubberDuck.Jido.Agents.WorkflowCoordinator, 
        Keyword.merge([
          persist: true,
          telemetry: true,
          cleanup_interval: 300_000  # 5 minutes
        ], opts)}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end