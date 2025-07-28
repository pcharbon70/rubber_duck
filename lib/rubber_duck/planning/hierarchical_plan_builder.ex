defmodule RubberDuck.Planning.HierarchicalPlanBuilder do
  @moduledoc """
  Builds hierarchical plans with phases, tasks, and subtasks from decomposed data.
  
  This module takes the output from task decomposition and creates the proper
  database structure with phases and hierarchical tasks.
  """

  alias RubberDuck.Planning.{Plan, Phase, Task, TaskDependency, TaskNumbering}
  require Logger

  @doc """
  Builds a complete hierarchical plan from decomposition data.
  
  ## Parameters
    - plan: The Plan resource to build tasks for
    - decomposition_data: Map containing phases and tasks from decomposition
    - opts: Options for Ash operations
  
  ## Returns
    - {:ok, plan} with fully loaded phases and tasks
    - {:error, reason} if building fails
  """
  def build_plan(%Plan{} = plan, decomposition_data, opts \\ []) do
    Ash.transaction(fn ->
      with {:ok, phases_map} <- create_phases(plan, decomposition_data, opts),
           {:ok, tasks_map} <- create_tasks(plan, decomposition_data, phases_map, opts),
           {:ok, _} <- create_dependencies(decomposition_data, tasks_map, opts),
           {:ok, _} <- TaskNumbering.number_plan(plan, opts),
           {:ok, plan} <- Ash.load(plan, [phases: [tasks: :subtasks]], opts) do
        plan
      else
        {:error, reason} -> 
          Logger.error("Failed to build hierarchical plan: #{inspect(reason)}")
          raise Ash.Error.to_ash_error(reason)
      end
    end, opts)
  end

  @doc """
  Builds tasks from a simple task list (no phases).
  """
  def build_tasks_only(%Plan{} = plan, tasks_data, opts \\ []) do
    Ash.transaction(fn ->
      with {:ok, tasks_map} <- create_tasks_without_phases(plan, tasks_data, opts),
           {:ok, _} <- create_task_dependencies(tasks_data, tasks_map, opts),
           {:ok, _} <- TaskNumbering.number_plan(plan, opts),
           {:ok, plan} <- Ash.load(plan, [tasks: :subtasks], opts) do
        plan
      else
        {:error, reason} -> 
          Logger.error("Failed to build tasks: #{inspect(reason)}")
          raise Ash.Error.to_ash_error(reason)
      end
    end, opts)
  end

  # Private functions

  defp create_phases(plan, decomposition_data, opts) do
    phases = decomposition_data["phases"] || decomposition_data[:phases] || []
    
    if Enum.empty?(phases) do
      {:ok, %{}}
    else
      phases
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, %{}}, fn {{phase_data, index}, _}, {:ok, acc} ->
        attrs = %{
          plan_id: plan.id,
          name: phase_data["name"] || "Phase #{index + 1}",
          description: phase_data["description"],
          position: index,
          metadata: extract_phase_metadata(phase_data)
        }
        
        case Ash.create(Phase, attrs, opts) do
          {:ok, phase} ->
            phase_id = phase_data["id"] || "phase_#{index + 1}"
            {:cont, {:ok, Map.put(acc, phase_id, phase)}}
          
          {:error, error} ->
            {:halt, {:error, error}}
        end
      end)
    end
  end

  defp create_tasks(plan, decomposition_data, phases_map, opts) do
    phases = decomposition_data["phases"] || decomposition_data[:phases] || []
    
    if Enum.empty?(phases) do
      # No phases, create tasks directly
      tasks = decomposition_data["tasks"] || decomposition_data[:tasks] || []
      create_tasks_without_phases(plan, tasks, opts)
    else
      # Create tasks within phases
      phases
      |> Enum.reduce_while({:ok, %{}}, fn phase_data, {:ok, acc} ->
        phase_id = phase_data["id"]
        phase = phases_map[phase_id]
        
        if phase do
          tasks = phase_data["tasks"] || []
          
          case create_phase_tasks(plan, phase, tasks, opts) do
            {:ok, task_map} ->
              {:cont, {:ok, Map.merge(acc, task_map)}}
            
            {:error, error} ->
              {:halt, {:error, error}}
          end
        else
          {:cont, {:ok, acc}}
        end
      end)
    end
  end

  defp create_phase_tasks(plan, phase, tasks, opts) do
    tasks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}}, fn {task_data, index}, {:ok, acc} ->
      attrs = build_task_attrs(task_data, %{
        plan_id: plan.id,
        phase_id: phase.id,
        position: index
      })
      
      case create_task_with_subtasks(attrs, task_data, opts) do
        {:ok, task, subtask_map} ->
          task_id = task_data["id"] || generate_task_id(phase.id, index)
          updated_acc = acc
          |> Map.put(task_id, task)
          |> Map.merge(subtask_map)
          
          {:cont, {:ok, updated_acc}}
        
        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp create_tasks_without_phases(plan, tasks, opts) do
    tasks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}}, fn {task_data, index}, {:ok, acc} ->
      attrs = build_task_attrs(task_data, %{
        plan_id: plan.id,
        position: index
      })
      
      case create_task_with_subtasks(attrs, task_data, opts) do
        {:ok, task, subtask_map} ->
          task_id = task_data["id"] || task_data["position"] || index
          task_id = to_string(task_id)
          
          updated_acc = acc
          |> Map.put(task_id, task)
          |> Map.merge(subtask_map)
          
          {:cont, {:ok, updated_acc}}
        
        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp create_task_with_subtasks(attrs, task_data, opts) do
    case Ash.create(Task, attrs, opts) do
      {:ok, task} ->
        subtasks = task_data["subtasks"] || []
        
        if Enum.empty?(subtasks) do
          {:ok, task, %{}}
        else
          case create_subtasks(task, subtasks, opts) do
            {:ok, subtask_map} ->
              {:ok, task, subtask_map}
            
            {:error, error} ->
              {:error, error}
          end
        end
      
      {:error, error} ->
        {:error, error}
    end
  end

  defp create_subtasks(parent_task, subtasks, opts) do
    subtasks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}}, fn {subtask_data, index}, {:ok, acc} ->
      attrs = build_task_attrs(subtask_data, %{
        plan_id: parent_task.plan_id,
        phase_id: parent_task.phase_id,
        parent_id: parent_task.id,
        position: index
      })
      
      case Ash.create(Task, attrs, opts) do
        {:ok, subtask} ->
          subtask_id = subtask_data["id"] || "#{parent_task.id}_sub_#{index + 1}"
          {:cont, {:ok, Map.put(acc, subtask_id, subtask)}}
        
        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp create_dependencies(decomposition_data, tasks_map, opts) do
    dependencies = decomposition_data["dependencies"] || decomposition_data[:dependencies] || []
    
    dependencies
    |> Enum.reduce_while(:ok, fn dep_data, :ok ->
      from_id = dep_data["from"] || dep_data[:from]
      to_id = dep_data["to"] || dep_data[:to]
      
      from_task = tasks_map[from_id]
      to_task = tasks_map[to_id]
      
      if from_task && to_task do
        attrs = %{
          task_id: to_task.id,
          dependency_id: from_task.id
        }
        
        case Ash.create(TaskDependency, attrs, opts) do
          {:ok, _} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      else
        # Skip dependencies where tasks don't exist
        {:cont, :ok}
      end
    end)
  end

  defp create_task_dependencies(tasks_data, tasks_map, opts) do
    tasks_data
    |> Enum.reduce_while(:ok, fn task_data, :ok ->
      task_id = task_data["id"] || task_data["position"] || 0
      task_id = to_string(task_id)
      task = tasks_map[task_id]
      
      if task do
        deps = task_data["depends_on"] || task_data["dependencies"] || []
        
        deps
        |> Enum.reduce_while(:ok, fn dep_id, :ok ->
          dep_id = to_string(dep_id)
          dep_task = tasks_map[dep_id]
          
          if dep_task do
            attrs = %{
              task_id: task.id,
              dependency_id: dep_task.id
            }
            
            case Ash.create(TaskDependency, attrs, opts) do
              {:ok, _} -> {:cont, :ok}
              {:error, error} -> {:halt, {:error, error}}
            end
          else
            {:cont, :ok}
          end
        end)
      else
        {:cont, :ok}
      end
    end)
  end

  defp build_task_attrs(task_data, base_attrs) do
    Map.merge(base_attrs, %{
      name: task_data["name"] || "Unnamed Task",
      description: task_data["description"],
      complexity: normalize_complexity(task_data["complexity"]),
      success_criteria: format_success_criteria(task_data["success_criteria"]),
      validation_rules: task_data["validation_rules"] || %{},
      metadata: extract_task_metadata(task_data)
    })
  end

  defp extract_phase_metadata(phase_data) do
    %{
      "estimated_duration" => phase_data["estimated_duration"],
      "milestone" => phase_data["milestone"],
      "deliverables" => phase_data["deliverables"] || []
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp extract_task_metadata(task_data) do
    base_metadata = %{
      "estimated_duration" => task_data["estimated_duration"],
      "risks" => task_data["risks"] || [],
      "prerequisites" => task_data["prerequisites"] || [],
      "optional" => task_data["optional"] || false,
      "is_critical" => task_data["is_critical"] || false
    }
    
    # Merge any additional metadata
    additional = task_data["metadata"] || %{}
    
    Map.merge(base_metadata, additional)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_complexity(nil), do: :medium
  defp normalize_complexity(complexity) when is_atom(complexity), do: complexity
  
  defp normalize_complexity(complexity) when is_binary(complexity) do
    case String.downcase(complexity) do
      "trivial" -> :trivial
      "simple" -> :simple
      "medium" -> :medium
      "complex" -> :complex
      "very_complex" -> :very_complex
      _ -> :medium
    end
  end
  
  defp normalize_complexity(_), do: :medium

  defp format_success_criteria(%{"criteria" => criteria}) when is_list(criteria) do
    %{"criteria" => criteria}
  end
  
  defp format_success_criteria(criteria) when is_list(criteria) do
    %{"criteria" => criteria}
  end
  
  defp format_success_criteria(_) do
    %{"criteria" => ["Task completed successfully"]}
  end

  defp generate_task_id(phase_id, index) do
    "#{phase_id}_task_#{index + 1}"
  end
end