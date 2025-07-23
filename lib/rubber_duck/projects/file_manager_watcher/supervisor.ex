defmodule RubberDuck.Projects.FileManagerWatcher.Supervisor do
  @moduledoc """
  DynamicSupervisor for FileManagerWatcher processes.
  
  Manages FileManagerWatcher processes for different projects,
  allowing them to be started and stopped dynamically.
  """
  
  use DynamicSupervisor
  
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end