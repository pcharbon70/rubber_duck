defmodule RubberDuck.Planning.TaskNumbering do
  @moduledoc """
  Handles automatic hierarchical numbering for phases, tasks, and subtasks.
  
  The numbering follows the pattern: phase.task.subtask
  For example:
  - Phase 1: "1"
  - Task 2 in Phase 1: "1.2"
  - Subtask 3 of Task 2 in Phase 1: "1.2.3"
  """

  alias RubberDuck.Planning.{Plan, Phase, Task}
  require Ash.Query

  @doc """
  Assigns numbers to all phases and tasks in a plan.
  """
  def number_plan(%Plan{} = plan, opts \\ []) do
    with {:ok, plan} <- Ash.load(plan, [:phases, tasks: :subtasks], opts),
         {:ok, _} <- number_phases(plan.phases, opts),
         {:ok, _} <- number_orphan_tasks(plan, opts) do
      {:ok, plan}
    end
  end

  @doc """
  Assigns a number to a newly created phase based on its position.
  """
  def assign_phase_number(%Phase{} = phase, opts \\ []) do
    number = to_string(phase.position + 1)
    
    phase
    |> Ash.Changeset.for_update(:update, %{metadata: Map.put(phase.metadata || %{}, "number", number)}, opts)
    |> Ash.update(opts)
  end

  @doc """
  Assigns a number to a newly created task based on its parent and position.
  """
  def assign_task_number(%Task{} = task, opts \\ []) do
    with {:ok, task} <- Ash.load(task, [:phase, :parent], opts),
         {:ok, number} <- calculate_task_number(task, opts) do
      
      task
      |> Ash.Changeset.for_update(:update, %{number: number}, opts)
      |> Ash.update(opts)
    end
  end

  # Private functions

  defp number_phases(phases, opts) do
    phases
    |> Enum.sort_by(& &1.position)
    |> Enum.with_index()
    |> Enum.map(fn {phase, index} ->
      phase_number = to_string(index + 1)
      
      # Update phase metadata with number
      updated_metadata = Map.put(phase.metadata || %{}, "number", phase_number)
      
      with {:ok, updated_phase} <- phase
           |> Ash.Changeset.for_update(:update, %{metadata: updated_metadata}, opts)
           |> Ash.update(opts),
           {:ok, _} <- number_phase_tasks(updated_phase, phase_number, opts) do
        {:ok, updated_phase}
      end
    end)
    |> handle_results()
  end

  defp number_phase_tasks(phase, phase_number, opts) do
    with {:ok, phase} <- Ash.load(phase, :tasks, opts) do
      phase.tasks
      |> Enum.filter(& is_nil(&1.parent_id))  # Only top-level tasks
      |> Enum.sort_by(& &1.position)
      |> Enum.with_index()
      |> Enum.map(fn {task, index} ->
        task_number = "#{phase_number}.#{index + 1}"
        update_task_and_subtasks(task, task_number, opts)
      end)
      |> handle_results()
    end
  end

  defp update_task_and_subtasks(task, number, opts) do
    with {:ok, updated_task} <- task
         |> Ash.Changeset.for_update(:update, %{number: number}, opts)
         |> Ash.update(opts),
         {:ok, updated_task} <- Ash.load(updated_task, :subtasks, opts),
         {:ok, _} <- number_subtasks(updated_task, number, opts) do
      {:ok, updated_task}
    end
  end

  defp number_subtasks(parent_task, parent_number, opts) do
    parent_task.subtasks
    |> Enum.sort_by(& &1.position)
    |> Enum.with_index()
    |> Enum.map(fn {subtask, index} ->
      subtask_number = "#{parent_number}.#{index + 1}"
      
      # Recursively handle deeper levels
      update_task_and_subtasks(subtask, subtask_number, opts)
    end)
    |> handle_results()
  end

  defp number_orphan_tasks(plan, opts) do
    # Number tasks that don't belong to any phase
    with {:ok, orphan_tasks} <- get_orphan_tasks(plan, opts) do
      orphan_tasks
      |> Enum.sort_by(& &1.position)
      |> Enum.with_index()
      |> Enum.map(fn {task, index} ->
        task_number = "0.#{index + 1}"  # Use 0 to indicate no phase
        update_task_and_subtasks(task, task_number, opts)
      end)
      |> handle_results()
    end
  end

  defp get_orphan_tasks(plan, opts) do
    Task
    |> Ash.Query.filter(plan_id == ^plan.id and is_nil(phase_id) and is_nil(parent_id))
    |> Ash.read(opts)
  end

  defp calculate_task_number(task, opts) do
    cond do
      # Subtask - get parent number and append
      task.parent_id && task.parent ->
        with {:ok, parent} <- ensure_parent_numbered(task.parent, opts) do
          parent_number = parent.number || calculate_task_number(parent, opts) |> elem(1)
          position = get_subtask_position(task, opts)
          {:ok, "#{parent_number}.#{position}"}
        end
      
      # Top-level task in a phase
      task.phase_id && task.phase ->
        phase_number = task.phase.metadata["number"] || to_string(task.phase.position + 1)
        position = get_task_position_in_phase(task, opts)
        {:ok, "#{phase_number}.#{position}"}
      
      # Orphan task (no phase, no parent)
      true ->
        position = get_orphan_task_position(task, opts)
        {:ok, "0.#{position}"}
    end
  end

  defp ensure_parent_numbered(parent, opts) do
    if parent.number do
      {:ok, parent}
    else
      assign_task_number(parent, opts)
    end
  end

  defp get_subtask_position(task, opts) do
    case get_sibling_tasks(task, :parent_id, task.parent_id, opts) do
      {:ok, siblings} ->
        siblings
        |> Enum.sort_by(& &1.position)
        |> Enum.find_index(& &1.id == task.id)
        |> case do
          nil -> 1
          index -> index + 1
        end
      
      _ -> 1
    end
  end

  defp get_task_position_in_phase(task, opts) do
    case get_sibling_tasks(task, :phase_id, task.phase_id, opts) do
      {:ok, siblings} ->
        siblings
        |> Enum.filter(& is_nil(&1.parent_id))  # Only top-level tasks
        |> Enum.sort_by(& &1.position)
        |> Enum.find_index(& &1.id == task.id)
        |> case do
          nil -> 1
          index -> index + 1
        end
      
      _ -> 1
    end
  end

  defp get_orphan_task_position(task, opts) do
    case Task
         |> Ash.Query.filter(plan_id == ^task.plan_id and is_nil(phase_id) and is_nil(parent_id))
         |> Ash.read(opts) do
      {:ok, orphans} ->
        orphans
        |> Enum.sort_by(& &1.position)
        |> Enum.find_index(& &1.id == task.id)
        |> case do
          nil -> 1
          index -> index + 1
        end
      
      _ -> 1
    end
  end

  defp get_sibling_tasks(_task, field, value, opts) do
    Task
    |> Ash.Query.filter(^[{field, value}])
    |> Ash.read(opts)
  end

  defp handle_results(results) do
    errors = results
    |> Enum.filter(&match?({:error, _}, &1))
    |> Enum.map(&elem(&1, 1))
    
    if Enum.empty?(errors) do
      {:ok, Enum.map(results, &elem(&1, 1))}
    else
      {:error, errors}
    end
  end
end