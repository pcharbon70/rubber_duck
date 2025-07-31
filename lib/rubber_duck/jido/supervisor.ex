defmodule RubberDuck.Jido.Supervisor do
  @moduledoc """
  Main supervisor for Jido integration.
  
  Manages the core Jido infrastructure:
  - AgentRegistry: Stores agents as data
  - Jido.Signal.Bus: Native Jido signal routing
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
      
      # Jido native signal bus for CloudEvents
      {Jido.Signal.Bus, name: RubberDuck.SignalBus},
      
      # Future: Worker pool for action execution
      # {RubberDuck.Jido.WorkerPool, [size: 10]}
    ]
    
    Logger.info("Starting Jido supervisor with native signal bus")
    
    Supervisor.init(children, strategy: :rest_for_one)
  end
end