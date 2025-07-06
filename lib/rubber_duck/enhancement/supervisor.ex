defmodule RubberDuck.Enhancement.Supervisor do
  @moduledoc """
  Supervisor for the LLM Enhancement Integration subsystem.
  
  Manages the lifecycle of enhancement-related processes including
  the coordinator and any auxiliary services.
  """
  
  use Supervisor
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    children = [
      # Enhancement Coordinator - manages technique orchestration
      {RubberDuck.Enhancement.Coordinator, []},
      
      # Future: Config Manager for dynamic configuration
      # {RubberDuck.Enhancement.ConfigManager, []},
      
      # Future: A/B Test Runner for experiment management
      # {RubberDuck.Enhancement.ABTestRunner, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end