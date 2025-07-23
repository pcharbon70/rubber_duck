defmodule RubberDuck.Projects.CollaborationSupervisor do
  @moduledoc """
  Supervisor for managing collaborative sessions per project.
  
  Ensures that collaboration processes are started on-demand and
  properly supervised for fault tolerance.
  """
  
  use DynamicSupervisor
  
  alias RubberDuck.Projects.FileCollaboration
  
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  
  @doc """
  Starts or ensures a collaboration session exists for a project.
  """
  def start_collaboration(project_id) do
    child_spec = %{
      id: {FileCollaboration, project_id},
      start: {FileCollaboration, :start_link, [[project_id: project_id]]},
      restart: :temporary
    }
    
    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end
  
  @doc """
  Stops a collaboration session for a project.
  """
  def stop_collaboration(project_id) do
    case Registry.lookup(RubberDuck.CollaborationRegistry, project_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] ->
        :ok
    end
  end
  
  @doc """
  Checks if a collaboration session is running for a project.
  """
  def collaboration_running?(project_id) do
    case Registry.lookup(RubberDuck.CollaborationRegistry, project_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end
  
  @doc """
  Lists all active collaboration sessions.
  """
  def list_active_sessions do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} ->
      case Registry.keys(RubberDuck.CollaborationRegistry, pid) do
        [project_id] -> {project_id, pid}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end