defmodule RubberDuck.RAG.Supervisor do
  @moduledoc """
  Supervisor for the RAG (Retrieval Augmented Generation) subsystem.
  
  Manages the lifecycle of RAG-related processes including:
  - Metrics collection
  - Background indexing workers
  - Cache management
  """
  
  use Supervisor
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    children = [
      # Metrics server for tracking RAG performance
      {RubberDuck.RAG.Metrics, []},
      
      # Task supervisor for parallel processing
      {Task.Supervisor, name: RubberDuck.RAG.TaskSupervisor},
      
      # Dynamic supervisor for background indexing jobs
      {DynamicSupervisor, name: RubberDuck.RAG.IndexingSupervisor, strategy: :one_for_one}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Starts a background indexing job under supervision.
  """
  def start_indexing_job(documents, opts \\ []) do
    spec = %{
      id: {:indexing_job, System.unique_integer()},
      start: {Task, :start_link, [fn ->
        RubberDuck.RAG.Pipeline.index_documents(documents, opts)
      end]},
      restart: :transient
    }
    
    DynamicSupervisor.start_child(RubberDuck.RAG.IndexingSupervisor, spec)
  end
end