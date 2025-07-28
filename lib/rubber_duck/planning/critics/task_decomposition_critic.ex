defmodule RubberDuck.Planning.Critics.TaskDecompositionCritic do
  @moduledoc """
  Soft critic that validates the quality of task decomposition in hierarchical plans.
  
  This critic ensures:
  - Subtasks properly decompose their parent tasks
  - Task granularity is appropriate at each level
  - No orphaned subtasks exist
  - Task complexity decreases with depth
  - Subtask coverage is complete
  """
  
  @behaviour RubberDuck.Planning.Critics.CriticBehaviour
  
  alias RubberDuck.Planning.{Plan, Task}
  alias RubberDuck.Planning.Critics.CriticBehaviour
  require Logger
  
  @impl true
  def name, do: "Task Decomposition Quality Checker"
  
  @impl true
  def type, do: :soft
  
  @impl true
  def priority, do: 110
  
  @impl true
  def validate(%Plan{} = plan, opts) do
    # Load full hierarchy
    plan = ensure_hierarchy_loaded(plan, opts)
    
    # Validate decomposition at all levels
    checks = [
      validate_decomposition_coverage(plan),
      validate_task_granularity(plan),
      validate_complexity_progression(plan),
      validate_subtask_coherence(plan),
      validate_decomposition_balance(plan)
    ]
    
    aggregate_validation_results(checks)
  end
  
  @impl true
  def validate(%Task{} = task, opts) do
    # For individual tasks, check their decomposition
    task = ensure_subtasks_loaded(task, opts)
    
    if has_subtasks?(task) do
      validate_single_task_decomposition(task)
    else
      {:ok, CriticBehaviour.validation_result(:passed, "Task has no subtasks to validate")}
    end
  end
  
  @impl true
  def validate(_, _) do
    {:ok, CriticBehaviour.validation_result(:passed, "Not applicable for this target type")}
  end
  
  # Private functions
  
  defp ensure_hierarchy_loaded(plan, opts) do
    case Ash.load(plan, [
      phases: [tasks: [subtasks: :subtasks]],
      tasks: [subtasks: :subtasks]
    ], opts) do
      {:ok, loaded} -> loaded
      _ -> plan
    end
  end
  
  defp ensure_subtasks_loaded(task, opts) do
    case Ash.load(task, [subtasks: :subtasks], opts) do
      {:ok, loaded} -> loaded
      _ -> task
    end
  end
  
  defp has_subtasks?(%Task{subtasks: subtasks}) when is_list(subtasks), do: not Enum.empty?(subtasks)
  defp has_subtasks?(_), do: false
  
  defp validate_decomposition_coverage(plan) do
    all_tasks = get_all_tasks_hierarchical(plan)
    
    issues = all_tasks
    |> Enum.flat_map(fn {task, level} ->
      if should_have_subtasks?(task, level) and not has_subtasks?(task) do
        ["Task '#{task.name}' (#{task.complexity}) lacks subtasks"]
      else
        check_subtask_coverage(task)
      end
    end)
    
    case issues do
      [] ->
        {:ok, "Task decomposition coverage is complete"}
        
      _ ->
        {:warning, %{
          message: "Incomplete task decomposition",
          issues: issues,
          suggestion: "Consider breaking down complex tasks into subtasks"
        }}
    end
  end
  
  defp should_have_subtasks?(task, level) do
    # Complex tasks at higher levels should have subtasks
    task.complexity in [:complex, :very_complex] and level < 3
  end
  
  defp check_subtask_coverage(task) do
    if has_subtasks?(task) do
      # Check if subtasks fully cover the parent task
      parent_scope = extract_task_scope(task)
      subtask_scopes = Enum.map(task.subtasks || [], &extract_task_scope/1)
      
      missing_coverage = find_missing_coverage(parent_scope, subtask_scopes)
      
      case missing_coverage do
        [] -> []
        missing -> ["Task '#{task.name}' has incomplete subtask coverage: #{Enum.join(missing, ", ")}"]
      end
    else
      []
    end
  end
  
  defp extract_task_scope(task) do
    # Extract key aspects from task description and success criteria
    desc_keywords = if task.description do
      task.description
      |> String.downcase()
      |> String.split(~r/[^\w]+/)
      |> Enum.filter(& String.length(&1) > 3)
      |> Enum.uniq()
    else
      []
    end
    
    # From success criteria
    criteria_keywords = if task.success_criteria && task.success_criteria["criteria"] do
      task.success_criteria["criteria"]
      |> Enum.join(" ")
      |> String.downcase()
      |> String.split(~r/[^\w]+/)
      |> Enum.filter(& String.length(&1) > 3)
      |> Enum.uniq()
    else
      []
    end
    
    MapSet.new(desc_keywords ++ criteria_keywords)
  end
  
  defp find_missing_coverage(parent_scope, subtask_scopes) do
    combined_subtask_scope = Enum.reduce(subtask_scopes, MapSet.new(), &MapSet.union/2)
    
    # Find important words in parent not covered by subtasks
    MapSet.difference(parent_scope, combined_subtask_scope)
    |> MapSet.to_list()
    |> Enum.filter(fn word ->
      # Filter out common words
      word not in ["the", "and", "for", "with", "that", "this", "from", "will", "should"]
    end)
    |> Enum.take(3)  # Limit to top 3 missing aspects
  end
  
  defp validate_task_granularity(plan) do
    all_tasks = get_all_tasks_hierarchical(plan)
    
    issues = all_tasks
    |> Enum.flat_map(fn {task, level} ->
      check_task_granularity(task, level)
    end)
    
    case issues do
      [] ->
        {:ok, "Task granularity is appropriate"}
        
      _ ->
        {:warning, %{
          message: "Task granularity issues",
          issues: issues,
          suggestion: "Ensure tasks are appropriately sized for their hierarchy level"
        }}
    end
  end
  
  defp check_task_granularity(task, level) do
    issues = []
    
    # Check if task is too granular for its level
    if level == 1 and task.complexity == :trivial do
      ["Top-level task '#{task.name}' is too granular (trivial complexity)" | issues]
    else
      issues
    end
    
    # Check if leaf tasks are actionable
    if not has_subtasks?(task) and level > 1 do
      if String.length(task.description || "") < 20 do
        ["Leaf task '#{task.name}' lacks sufficient detail" | issues]
      else
        issues
      end
    else
      issues
    end
  end
  
  defp validate_complexity_progression(plan) do
    all_tasks = get_all_tasks_hierarchical(plan)
    
    # Group by parent-child relationships
    parent_child_groups = build_parent_child_groups(all_tasks)
    
    issues = parent_child_groups
    |> Enum.flat_map(fn {parent, children} ->
      check_complexity_progression(parent, children)
    end)
    
    case issues do
      [] ->
        {:ok, "Complexity progression is logical"}
        
      _ ->
        {:warning, %{
          message: "Complexity progression issues",
          issues: issues,
          suggestion: "Subtasks should generally be simpler than their parent tasks"
        }}
    end
  end
  
  defp build_parent_child_groups(all_tasks) do
    _task_map = all_tasks
    |> Enum.map(fn {task, _level} -> {task.id, task} end)
    |> Map.new()
    
    all_tasks
    |> Enum.filter(fn {task, _} -> has_subtasks?(task) end)
    |> Enum.map(fn {parent, _} ->
      children = parent.subtasks || []
      {parent, children}
    end)
  end
  
  defp check_complexity_progression(parent, children) do
    parent_complexity_value = complexity_to_value(parent.complexity)
    
    children
    |> Enum.filter(fn child ->
      child_value = complexity_to_value(child.complexity)
      child_value > parent_complexity_value
    end)
    |> Enum.map(fn child ->
      "Subtask '#{child.name}' (#{child.complexity}) is more complex than parent '#{parent.name}' (#{parent.complexity})"
    end)
  end
  
  defp complexity_to_value(complexity) do
    case complexity do
      :trivial -> 1
      :simple -> 2
      :medium -> 3
      :complex -> 4
      :very_complex -> 5
      _ -> 3
    end
  end
  
  defp validate_subtask_coherence(plan) do
    all_tasks = get_all_tasks_hierarchical(plan)
    
    issues = all_tasks
    |> Enum.filter(fn {task, _} -> has_subtasks?(task) end)
    |> Enum.flat_map(fn {parent, _} ->
      check_subtask_coherence(parent)
    end)
    
    case issues do
      [] ->
        {:ok, "Subtask coherence is good"}
        
      _ ->
        {:warning, %{
          message: "Subtask coherence issues",
          issues: issues,
          suggestion: "Ensure subtasks are logically related to their parent task"
        }}
    end
  end
  
  defp check_subtask_coherence(parent) do
    parent_keywords = extract_keywords(parent.name)
    
    parent.subtasks
    |> Enum.filter(fn subtask ->
      subtask_keywords = extract_keywords(subtask.name)
      
      # Check if subtask shares any keywords with parent
      MapSet.disjoint?(parent_keywords, subtask_keywords)
    end)
    |> Enum.map(fn subtask ->
      "Subtask '#{subtask.name}' seems unrelated to parent '#{parent.name}'"
    end)
  end
  
  defp extract_keywords(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^\w]+/)
    |> Enum.filter(& String.length(&1) > 3)
    |> Enum.reject(& &1 in ["task", "step", "phase", "implement", "create", "update", "add"])
    |> MapSet.new()
  end
  
  defp validate_decomposition_balance(plan) do
    all_tasks = get_all_tasks_hierarchical(plan)
    
    # Group tasks by parent
    parent_groups = all_tasks
    |> Enum.filter(fn {task, _} -> has_subtasks?(task) end)
    |> Enum.map(fn {parent, _} ->
      {parent, length(parent.subtasks || [])}
    end)
    
    issues = parent_groups
    |> Enum.flat_map(fn {parent, subtask_count} ->
      cond do
        subtask_count == 1 ->
          ["Task '#{parent.name}' has only one subtask - consider merging or adding more subtasks"]
          
        subtask_count > 10 ->
          ["Task '#{parent.name}' has #{subtask_count} subtasks - consider grouping into sub-phases"]
          
        true ->
          []
      end
    end)
    
    case issues do
      [] ->
        {:ok, "Task decomposition is well-balanced"}
        
      _ ->
        {:info, %{
          message: "Task decomposition balance could be improved",
          issues: issues,
          suggestion: "Aim for 3-7 subtasks per parent task"
        }}
    end
  end
  
  defp get_all_tasks_hierarchical(plan) do
    phase_tasks = case plan.phases do
      phases when is_list(phases) ->
        phases
        |> Enum.flat_map(fn phase ->
          case phase.tasks do
            tasks when is_list(tasks) ->
              Enum.flat_map(tasks, &collect_task_hierarchy(&1, 1))
            _ -> []
          end
        end)
      _ -> []
    end
    
    orphan_tasks = case plan.tasks do
      tasks when is_list(tasks) ->
        tasks
        |> Enum.filter(& is_nil(&1.phase_id))
        |> Enum.flat_map(&collect_task_hierarchy(&1, 1))
      _ -> []
    end
    
    phase_tasks ++ orphan_tasks
  end
  
  defp collect_task_hierarchy(task, level) do
    task_entry = {task, level}
    
    subtask_entries = case task.subtasks do
      subtasks when is_list(subtasks) ->
        Enum.flat_map(subtasks, &collect_task_hierarchy(&1, level + 1))
      _ -> []
    end
    
    [task_entry | subtask_entries]
  end
  
  defp validate_single_task_decomposition(task) do
    checks = [
      check_subtask_coverage(task),
      check_subtask_coherence(task),
      check_complexity_progression(task, task.subtasks || [])
    ]
    |> List.flatten()
    
    case checks do
      [] ->
        {:ok, CriticBehaviour.validation_result(:passed, "Task decomposition is valid")}
        
      issues ->
        {:ok, CriticBehaviour.validation_result(
          :warning,
          "Task decomposition has quality issues",
          details: %{issues: issues},
          suggestions: [
            "Ensure subtasks fully cover the parent task scope",
            "Keep subtasks coherent with parent task",
            "Subtasks should be simpler than parent"
          ]
        )}
    end
  end
  
  defp aggregate_validation_results(checks) do
    all_issues = checks
    |> Enum.flat_map(fn
      {:ok, _} -> []
      {:info, data} -> [{:info, data}]
      {:warning, data} -> [{:warning, data}]
      {:error, data} -> [{:error, data}]
    end)
    
    grouped = Enum.group_by(all_issues, &elem(&1, 0))
    
    cond do
      Map.has_key?(grouped, :error) ->
        {:ok, CriticBehaviour.validation_result(
          :failed,
          "Task decomposition validation failed",
          details: format_grouped_issues(grouped),
          suggestions: collect_suggestions(grouped)
        )}
        
      Map.has_key?(grouped, :warning) ->
        {:ok, CriticBehaviour.validation_result(
          :warning,
          "Task decomposition has quality issues",
          details: format_grouped_issues(grouped),
          suggestions: collect_suggestions(grouped)
        )}
        
      Map.has_key?(grouped, :info) ->
        {:ok, CriticBehaviour.validation_result(
          :passed,
          "Task decomposition is acceptable with minor suggestions",
          details: format_grouped_issues(grouped),
          suggestions: collect_suggestions(grouped)
        )}
        
      true ->
        {:ok, CriticBehaviour.validation_result(
          :passed,
          "Task decomposition quality is good"
        )}
    end
  end
  
  defp format_grouped_issues(grouped) do
    grouped
    |> Enum.map(fn {level, items} ->
      issues = items
      |> Enum.flat_map(fn {_, data} -> data.issues || [] end)
      |> Enum.uniq()
      
      {level, issues}
    end)
    |> Map.new()
  end
  
  defp collect_suggestions(grouped) do
    grouped
    |> Map.values()
    |> List.flatten()
    |> Enum.flat_map(fn {_, data} ->
      case data[:suggestion] do
        nil -> []
        suggestion when is_binary(suggestion) -> [suggestion]
        suggestions when is_list(suggestions) -> suggestions
      end
    end)
    |> Enum.uniq()
  end
end