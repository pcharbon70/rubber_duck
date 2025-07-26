defmodule RubberDuck.Engine.TaskRegistry do
  @moduledoc """
  Registry for tracking active engine processing tasks.
  
  Provides a centralized way to track, query, and cancel active tasks
  across all engines. Uses ETS for fast concurrent access.
  """
  
  use GenServer
  require Logger
  
  @table_name :engine_task_registry
  @cleanup_interval :timer.seconds(30)
  
  # Client API
  
  @doc """
  Starts the TaskRegistry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a new task for tracking.
  
  ## Parameters
    - task_ref: The Task reference from Task.async
    - conversation_id: The conversation this task belongs to
    - engine_name: The engine executing the task
    - metadata: Additional metadata about the task
  """
  def register_task(task_ref, conversation_id, engine_name, metadata \\ %{}) do
    task_id = generate_task_id()
    entry = %{
      task_id: task_id,
      task_ref: task_ref,
      conversation_id: conversation_id,
      engine_name: engine_name,
      engine_path: metadata[:engine_path] || [engine_name],
      started_at: DateTime.utc_now(),
      metadata: metadata,
      status: :running
    }
    
    :ets.insert(@table_name, {task_id, entry})
    Logger.debug("Registered task #{task_id} for conversation #{conversation_id} on engine #{engine_name}")
    
    {:ok, task_id}
  end
  
  @doc """
  Unregisters a completed or cancelled task.
  """
  def unregister_task(task_id) do
    :ets.delete(@table_name, task_id)
    Logger.debug("Unregistered task #{task_id}")
    :ok
  end
  
  @doc """
  Finds all active tasks for a conversation.
  """
  def find_by_conversation(conversation_id) do
    :ets.match_object(@table_name, {:_, %{conversation_id: conversation_id, status: :running}})
    |> Enum.map(fn {_id, task} -> task end)
  end
  
  @doc """
  Finds a specific task by ID.
  """
  def find_task(task_id) do
    case :ets.lookup(@table_name, task_id) do
      [{^task_id, task}] -> {:ok, task}
      [] -> {:error, :not_found}
    end
  end
  
  @doc """
  Cancels all tasks for a conversation.
  
  Returns {:ok, cancelled_count} or {:error, reason}.
  """
  def cancel_conversation_tasks(conversation_id) do
    tasks = find_by_conversation(conversation_id)
    
    results = Enum.map(tasks, fn task ->
      cancel_task(task.task_id)
    end)
    
    cancelled_count = Enum.count(results, &match?(:ok, &1))
    
    Logger.info("Cancelled #{cancelled_count} tasks for conversation #{conversation_id}")
    
    {:ok, cancelled_count}
  end
  
  @doc """
  Cancels a specific task.
  """
  def cancel_task(task_id) do
    case find_task(task_id) do
      {:ok, task} ->
        # Mark as cancelling first
        update_task_status(task_id, :cancelling)
        
        # Send exit signal to the task
        Process.exit(task.task_ref.pid, :cancelled)
        
        # Mark as cancelled
        update_task_status(task_id, :cancelled)
        
        # Broadcast cancellation status
        if task.conversation_id do
          RubberDuck.Status.engine(
            task.conversation_id,
            "Task cancelled: #{task.engine_name}",
            %{
              task_id: task_id,
              engine: task.engine_name,
              engine_path: task.engine_path,
              cancelled_at: DateTime.utc_now()
            }
          )
        end
        
        Logger.info("Cancelled task #{task_id}")
        :ok
        
      {:error, :not_found} ->
        {:error, :task_not_found}
    end
  end
  
  @doc """
  Gets statistics about active tasks.
  """
  def get_stats do
    all_tasks = :ets.tab2list(@table_name)
    
    %{
      total: length(all_tasks),
      by_status: Enum.group_by(all_tasks, fn {_id, task} -> task.status end) |> Map.new(fn {k, v} -> {k, length(v)} end),
      by_engine: Enum.group_by(all_tasks, fn {_id, task} -> task.engine_name end) |> Map.new(fn {k, v} -> {k, length(v)} end),
      oldest_task: find_oldest_task(all_tasks)
    }
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table
    :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    {:ok, %{}}
  end
  
  @impl true
  def handle_info(:cleanup_stale_tasks, state) do
    cleanup_stale_tasks()
    schedule_cleanup()
    {:noreply, state}
  end
  
  # Private functions
  
  defp generate_task_id do
    "task_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
  
  defp update_task_status(task_id, new_status) do
    case :ets.lookup(@table_name, task_id) do
      [{^task_id, task}] ->
        updated_task = %{task | status: new_status}
        :ets.insert(@table_name, {task_id, updated_task})
        :ok
      [] ->
        {:error, :not_found}
    end
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_stale_tasks, @cleanup_interval)
  end
  
  defp cleanup_stale_tasks do
    # Remove completed/cancelled tasks older than 5 minutes
    cutoff = DateTime.add(DateTime.utc_now(), -300, :second)
    
    # Get all tasks and filter in Elixir since ETS match specs don't work well with maps
    all_tasks = :ets.tab2list(@table_name)
    
    stale_task_ids = all_tasks
    |> Enum.filter(fn {_task_id, task} ->
      task.status != :running && DateTime.compare(task.started_at, cutoff) == :lt
    end)
    |> Enum.map(fn {task_id, _task} -> task_id end)
    
    Enum.each(stale_task_ids, &:ets.delete(@table_name, &1))
    
    if length(stale_task_ids) > 0 do
      Logger.debug("Cleaned up #{length(stale_task_ids)} stale tasks")
    end
  end
  
  defp find_oldest_task([]), do: nil
  defp find_oldest_task(tasks) do
    tasks
    |> Enum.filter(fn {_id, task} -> task.status == :running end)
    |> Enum.min_by(fn {_id, task} -> task.started_at end, DateTime, fn -> nil end)
    |> case do
      {_id, task} -> task
      nil -> nil
    end
  end
end