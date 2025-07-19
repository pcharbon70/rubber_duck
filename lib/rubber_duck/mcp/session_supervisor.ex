defmodule RubberDuck.MCP.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for managing MCP client sessions.

  Each client connection gets its own supervised Session process.
  This provides fault isolation - if one session crashes, others
  continue running unaffected.
  """

  use DynamicSupervisor

  alias RubberDuck.MCP.Session

  # Client API

  @doc """
  Starts the session supervisor.
  """
  def start_link(init_arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a new session under supervision.

  ## Options

  - `:id` - Unique session identifier (required)
  - `:server_pid` - PID of the MCP server (required)
  - `:transport` - Transport PID (required)
  - `:transport_mod` - Transport module (required)
  - `:client_info` - Client information map
  """
  def start_session(supervisor \\ __MODULE__, opts) do
    spec = %{
      id: {:session, opts[:id]},
      start: {Session, :start_link, [opts]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(supervisor, spec)
  end

  @doc """
  Lists all active sessions.
  """
  def list_sessions(supervisor \\ __MODULE__) do
    children = DynamicSupervisor.which_children(supervisor)

    Enum.map(children, fn
      {{:session, _id}, pid, :worker, [Session]} ->
        case Session.get_info(pid) do
          {:ok, info} -> info
          _ -> nil
        end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Counts active sessions.
  """
  def count_sessions(supervisor \\ __MODULE__) do
    %{active: active} = DynamicSupervisor.count_children(supervisor)
    active
  end

  @doc """
  Terminates a specific session.
  """
  def terminate_session(supervisor \\ __MODULE__, session_id) do
    children = DynamicSupervisor.which_children(supervisor)

    case Enum.find(children, fn
           {{:session, id}, _pid, _type, _modules} -> id == session_id
           _ -> false
         end) do
      {{:session, ^session_id}, pid, _, _} ->
        DynamicSupervisor.terminate_child(supervisor, pid)

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Terminates all sessions gracefully.
  """
  def terminate_all_sessions(supervisor \\ __MODULE__) do
    children = DynamicSupervisor.which_children(supervisor)

    Enum.each(children, fn
      {_, pid, _, _} when is_pid(pid) ->
        Session.notify_shutdown(pid)
    end)

    # Give sessions time to shut down gracefully
    Process.sleep(1000)

    # Then terminate any remaining
    Enum.each(children, fn
      {_, pid, _, _} when is_pid(pid) ->
        DynamicSupervisor.terminate_child(supervisor, pid)
    end)

    :ok
  end

  # Server callbacks

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 60
    )
  end
end
