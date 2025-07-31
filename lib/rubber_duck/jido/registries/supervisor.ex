defmodule RubberDuck.Jido.Registries.Supervisor do
  @moduledoc """
  Supervisor for Jido registry processes.
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      RubberDuck.Jido.Registries.SignalActionRegistry
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end