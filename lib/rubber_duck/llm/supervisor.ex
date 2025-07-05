defmodule RubberDuck.LLM.Supervisor do
  @moduledoc """
  Supervisor for the LLM service and related processes.
  """
  
  use Supervisor
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    children = [
      # Start the LLM service
      {RubberDuck.LLM.Service, []},
      
      # Future: Add other LLM-related services here
      # - Embedding service
      # - Token counter service
      # - Cache service
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end