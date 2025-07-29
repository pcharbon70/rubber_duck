defmodule RubberDuck.Jido.Supervisor do
  @moduledoc """
  Main supervisor for Jido integration.
  
  Manages the core Jido infrastructure:
  - AgentRegistry: Stores agents as data
  - SignalRouter: Routes signals to actions
  - Runtime workers: Execute actions (future)
  
  Note: Agents are NOT supervised processes in proper Jido architecture.
  """
  
  use Supervisor
  require Logger
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    children = [
      # Agent registry for storing agent data
      {RubberDuck.Jido.AgentRegistry, []},
      
      # Signal router configuration
      {RubberDuck.Jido.SignalRouter.Config, []},
      
      # Dead letter queue for failed signals
      {RubberDuck.Jido.SignalRouter.DeadLetterQueue, []},
      
      # Signal router for CloudEvents
      {RubberDuck.Jido.SignalRouter, []},
      
      # Future: Worker pool for action execution
      # {RubberDuck.Jido.WorkerPool, [size: 10]}
    ]
    
    Logger.info("Starting Jido supervisor with proper architecture")
    
    Supervisor.init(children, strategy: :rest_for_one)
  end
end