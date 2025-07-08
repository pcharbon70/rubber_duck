defmodule RubberDuck.Workflows.Supervisor do
  @moduledoc """
  Supervisor for workflow-related processes.

  This supervisor manages all workflow execution processes, caching,
  and other workflow-related services.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Workflow cache
      {RubberDuck.Workflows.Cache, []},

      # Workflow registry
      {RubberDuck.Workflows.Registry, []},

      # Dynamic workflow task supervisor
      {Task.Supervisor, name: RubberDuck.Workflows.TaskSupervisor},

      # Workflow executor pool
      {RubberDuck.Workflows.ExecutorPool, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule RubberDuck.Workflows.ExecutorPool do
  @moduledoc """
  Pool of workflow executor processes.

  Manages a pool of executor processes for concurrent workflow execution.
  """

  use GenServer

  @pool_size 10

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets an available executor from the pool.
  """
  def checkout do
    GenServer.call(__MODULE__, :checkout)
  end

  @doc """
  Returns an executor to the pool.
  """
  def checkin(executor_pid) do
    GenServer.cast(__MODULE__, {:checkin, executor_pid})
  end

  @impl true
  def init(_opts) do
    # Start executor processes
    executors =
      for _ <- 1..@pool_size do
        {:ok, pid} = GenServer.start_link(RubberDuck.Workflows.ExecutorWorker, [])
        pid
      end

    {:ok, %{available: executors, busy: MapSet.new()}}
  end

  @impl true
  def handle_call(:checkout, {from_pid, _}, state) do
    case state.available do
      [executor | rest] ->
        # Monitor the caller
        ref = Process.monitor(from_pid)

        new_state = %{
          available: rest,
          busy: MapSet.put(state.busy, {executor, ref, from_pid})
        }

        {:reply, {:ok, executor}, new_state}

      [] ->
        {:reply, {:error, :no_executors_available}, state}
    end
  end

  @impl true
  def handle_cast({:checkin, executor_pid}, state) do
    # Find and remove from busy set
    busy_entry = Enum.find(state.busy, fn {pid, _, _} -> pid == executor_pid end)

    case busy_entry do
      {executor, ref, _from_pid} ->
        Process.demonitor(ref, [:flush])

        new_state = %{
          available: [executor | state.available],
          busy: MapSet.delete(state.busy, busy_entry)
        }

        {:noreply, new_state}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, from_pid, _reason}, state) do
    # A caller died, return their executor to the pool
    busy_entry = Enum.find(state.busy, fn {_, _, pid} -> pid == from_pid end)

    case busy_entry do
      {executor, _, _} = entry ->
        new_state = %{
          available: [executor | state.available],
          busy: MapSet.delete(state.busy, entry)
        }

        {:noreply, new_state}

      nil ->
        {:noreply, state}
    end
  end
end

defmodule RubberDuck.Workflows.ExecutorWorker do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    {:ok, %{}}
  end

  # Placeholder for actual executor implementation
  # This would handle workflow execution requests
end
