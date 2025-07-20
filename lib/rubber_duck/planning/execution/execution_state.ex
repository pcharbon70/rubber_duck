defmodule RubberDuck.Planning.Execution.ExecutionState do
  @moduledoc """
  Manages the execution state for plan execution.
  
  Tracks task statuses, dependencies, resources, and provides
  state snapshots for checkpointing and rollback.
  """
  
  defstruct [
    :execution_id,
    :plan_id,
    :all_tasks,
    :completed_tasks,
    :failed_tasks,
    :current_tasks,
    :task_dependencies,
    :resource_allocations,
    :metadata,
    :created_at,
    :updated_at
  ]
  
  @type t :: %__MODULE__{
    execution_id: String.t(),
    plan_id: String.t() | nil,
    all_tasks: MapSet.t(),
    completed_tasks: MapSet.t(),
    failed_tasks: MapSet.t(),
    current_tasks: map(),
    task_dependencies: map(),
    resource_allocations: map(),
    metadata: map(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
  
  @doc """
  Creates a new execution state.
  """
  def new(execution_id) do
    %__MODULE__{
      execution_id: execution_id,
      all_tasks: MapSet.new(),
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      current_tasks: %{},
      task_dependencies: %{},
      resource_allocations: %{},
      metadata: %{},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Initializes the execution state with tasks.
  """
  def initialize(state, tasks) do
    task_ids = MapSet.new(tasks, & &1.id)
    dependencies = build_dependency_map(tasks)
    
    %{state |
      all_tasks: task_ids,
      task_dependencies: dependencies,
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Updates the state when a task starts executing.
  """
  def start_task(state, task_id, process_ref) do
    %{state |
      current_tasks: Map.put(state.current_tasks, task_id, %{
        process_ref: process_ref,
        started_at: DateTime.utc_now()
      }),
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Updates the state when a task completes.
  """
  def complete_task(state, task_id, result) do
    %{state |
      completed_tasks: MapSet.put(state.completed_tasks, task_id),
      current_tasks: Map.delete(state.current_tasks, task_id),
      metadata: Map.put(state.metadata, {:task_result, task_id}, result),
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Updates the state when a task fails.
  """
  def fail_task(state, task_id, error) do
    %{state |
      failed_tasks: MapSet.put(state.failed_tasks, task_id),
      current_tasks: Map.delete(state.current_tasks, task_id),
      metadata: Map.put(state.metadata, {:task_error, task_id}, error),
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Allocates resources for a task.
  """
  def allocate_resources(state, task_id, resources) do
    %{state |
      resource_allocations: Map.put(state.resource_allocations, task_id, resources),
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Releases resources for a task.
  """
  def release_resources(state, task_id) do
    %{state |
      resource_allocations: Map.delete(state.resource_allocations, task_id),
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Gets tasks that are ready to execute (dependencies satisfied).
  """
  def get_ready_tasks(state) do
    state.all_tasks
    |> MapSet.to_list()
    |> Enum.filter(fn task_id ->
      not task_executed?(state, task_id) and
      not task_executing?(state, task_id) and
      dependencies_satisfied?(state, task_id)
    end)
  end
  
  @doc """
  Checks if all tasks are completed or failed.
  """
  def execution_complete?(state) do
    executed = MapSet.union(state.completed_tasks, state.failed_tasks)
    MapSet.equal?(executed, state.all_tasks)
  end
  
  @doc """
  Gets the execution progress as a percentage.
  """
  def progress_percentage(state) do
    total = MapSet.size(state.all_tasks)
    if total == 0 do
      100.0
    else
      completed = MapSet.size(state.completed_tasks)
      Float.round(completed / total * 100, 1)
    end
  end
  
  @doc """
  Creates a snapshot of the current state for checkpointing.
  """
  def snapshot(state) do
    %{
      execution_id: state.execution_id,
      plan_id: state.plan_id,
      completed_tasks: MapSet.to_list(state.completed_tasks),
      failed_tasks: MapSet.to_list(state.failed_tasks),
      current_tasks: Map.keys(state.current_tasks),
      resource_allocations: state.resource_allocations,
      metadata: filter_metadata_for_snapshot(state.metadata),
      timestamp: DateTime.utc_now()
    }
  end
  
  @doc """
  Restores state from a snapshot.
  """
  def restore(state, snapshot) do
    %{state |
      completed_tasks: MapSet.new(snapshot.completed_tasks),
      failed_tasks: MapSet.new(snapshot.failed_tasks),
      current_tasks: %{},  # Current tasks need to be re-executed
      resource_allocations: snapshot.resource_allocations,
      metadata: Map.merge(state.metadata, snapshot.metadata),
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Gets statistics about the execution state.
  """
  def get_statistics(state) do
    %{
      total_tasks: MapSet.size(state.all_tasks),
      completed_tasks: MapSet.size(state.completed_tasks),
      failed_tasks: MapSet.size(state.failed_tasks),
      executing_tasks: map_size(state.current_tasks),
      pending_tasks: length(get_ready_tasks(state)),
      progress_percentage: progress_percentage(state),
      resource_usage: calculate_resource_usage(state),
      execution_duration: calculate_duration(state)
    }
  end
  
  # Private functions
  
  defp build_dependency_map(tasks) do
    Enum.reduce(tasks, %{}, fn task, acc ->
      Map.put(acc, task.id, task.dependencies || [])
    end)
  end
  
  defp task_executed?(state, task_id) do
    MapSet.member?(state.completed_tasks, task_id) or
    MapSet.member?(state.failed_tasks, task_id)
  end
  
  defp task_executing?(state, task_id) do
    Map.has_key?(state.current_tasks, task_id)
  end
  
  defp dependencies_satisfied?(state, task_id) do
    case Map.get(state.task_dependencies, task_id, []) do
      [] -> true
      deps -> Enum.all?(deps, &MapSet.member?(state.completed_tasks, &1))
    end
  end
  
  defp filter_metadata_for_snapshot(metadata) do
    # Remove large or transient data from metadata
    metadata
    |> Enum.reject(fn {key, _value} ->
      case key do
        {:task_result, _} -> true
        {:task_error, _} -> true
        _ -> false
      end
    end)
    |> Map.new()
  end
  
  defp calculate_resource_usage(state) do
    state.resource_allocations
    |> Enum.reduce(%{}, fn {_task_id, resources}, acc ->
      Enum.reduce(resources, acc, fn {resource, amount}, acc2 ->
        Map.update(acc2, resource, amount, &(&1 + amount))
      end)
    end)
  end
  
  defp calculate_duration(state) do
    if state.created_at do
      DateTime.diff(DateTime.utc_now(), state.created_at, :second)
    else
      0
    end
  end
end