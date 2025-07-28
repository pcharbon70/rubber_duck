defmodule RubberDuck.Planning.Critics.HierarchicalCompletenessCritic do
  @moduledoc """
  Hard critic that validates the completeness of the hierarchical plan structure.
  
  This critic ensures:
  - All phases have at least one task
  - Complex tasks have subtasks or justification
  - Leaf tasks are actionable and concrete
  - Task numbering is consistent throughout hierarchy
  - No missing hierarchy levels
  - All required metadata is present
  """
  
  @behaviour RubberDuck.Planning.Critics.CriticBehaviour
  
  alias RubberDuck.Planning.{Plan, Task, Phase}
  alias RubberDuck.Planning.Critics.CriticBehaviour
  require Logger
  
  @impl true
  def name, do: "Hierarchical Completeness Validator"
  
  @impl true
  def type, do: :hard
  
  @impl true
  def priority, do: 30
  
  @impl true
  def validate(%Plan{} = plan, opts) do
    # Load full hierarchy
    plan = ensure_hierarchy_loaded(plan, opts)
    
    # Run completeness checks
    checks = [
      validate_phase_completeness(plan),
      validate_task_completeness(plan),
      validate_leaf_tasks(plan),
      validate_numbering_consistency(plan),
      validate_hierarchy_levels(plan),
      validate_required_metadata(plan)
    ]
    
    aggregate_validation_results(checks)
  end
  
  @impl true
  def validate(%Phase{} = phase, opts) do
    phase = ensure_phase_loaded(phase, opts)
    validate_single_phase_completeness(phase)
  end
  
  @impl true
  def validate(%Task{} = task, opts) do
    task = ensure_task_loaded(task, opts)
    validate_single_task_completeness(task)
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
  
  defp ensure_phase_loaded(phase, opts) do
    case Ash.load(phase, [tasks: [subtasks: :subtasks]], opts) do
      {:ok, loaded} -> loaded
      _ -> phase
    end
  end
  
  defp ensure_task_loaded(task, opts) do
    case Ash.load(task, [subtasks: :subtasks], opts) do
      {:ok, loaded} -> loaded
      _ -> task
    end
  end
  
  defp validate_phase_completeness(plan) do
    case plan.phases do
      [] ->
        # Plans without phases are valid (backward compatibility)
        {:ok, "No phases to validate"}
        
      phases ->
        empty_phases = phases
        |> Enum.filter(fn phase ->
          case phase.tasks do
            tasks when is_list(tasks) -> Enum.empty?(tasks)
            _ -> true
          end
        end)
        |> Enum.map(& &1.name)
        
        case empty_phases do
          [] ->
            {:ok, "All phases contain tasks"}
            
          phase_names ->
            {:error, %{
              message: "Empty phases found",
              phases: phase_names,
              suggestion: "Add tasks to empty phases or remove them"
            }}
        end
    end
  end
  
  defp validate_task_completeness(plan) do
    all_tasks = get_all_tasks(plan)
    
    issues = []
    
    # Check for tasks without names
    nameless = all_tasks
    |> Enum.filter(& is_nil(&1.name) or &1.name == "")
    |> Enum.map(& "Task #{&1.id} has no name")
    
    issues = issues ++ nameless
    
    # Check complex tasks without subtasks
    complex_without_subtasks = all_tasks
    |> Enum.filter(fn task ->
      task.complexity in [:complex, :very_complex] and
      not has_subtasks?(task) and
      not has_decomposition_justification?(task)
    end)
    |> Enum.map(& "Complex task '#{&1.name}' lacks subtasks or justification")
    
    issues = issues ++ complex_without_subtasks
    
    # Check for tasks without success criteria
    without_criteria = all_tasks
    |> Enum.filter(fn task ->
      is_nil(task.success_criteria) or
      (is_map(task.success_criteria) and Enum.empty?(task.success_criteria["criteria"] || []))
    end)
    |> Enum.map(& "Task '#{&1.name}' lacks success criteria")
    
    issues = issues ++ without_criteria
    
    case issues do
      [] ->
        {:ok, "All tasks are complete"}
        
      _ ->
        {:error, %{
          message: "Incomplete tasks found",
          issues: issues,
          suggestion: "Ensure all tasks have names, success criteria, and appropriate decomposition"
        }}
    end
  end
  
  defp validate_leaf_tasks(plan) do
    leaf_tasks = get_all_tasks(plan)
    |> Enum.filter(fn task -> not has_subtasks?(task) end)
    
    issues = leaf_tasks
    |> Enum.flat_map(fn task ->
      check_leaf_task_actionability(task)
    end)
    
    case issues do
      [] ->
        {:ok, "All leaf tasks are actionable"}
        
      _ ->
        {:warning, %{
          message: "Leaf task actionability issues",
          issues: issues,
          suggestion: "Ensure leaf tasks are concrete and implementable"
        }}
    end
  end
  
  defp check_leaf_task_actionability(task) do
    issues = []
    
    # Check description length
    issues = if is_nil(task.description) or String.length(task.description) < 20 do
      ["Leaf task '#{task.name}' has insufficient description" | issues]
    else
      issues
    end
    
    # Check for vague task names
    vague_words = ["handle", "manage", "process", "deal with", "work on"]
    issues = if Enum.any?(vague_words, & String.contains?(String.downcase(task.name), &1)) do
      ["Leaf task '#{task.name}' has vague name" | issues]
    else
      issues
    end
    
    # Check complexity
    issues = if task.complexity in [:complex, :very_complex] do
      ["Leaf task '#{task.name}' is too complex - should be decomposed" | issues]
    else
      issues
    end
    
    issues
  end
  
  defp validate_numbering_consistency(plan) do
    all_tasks = get_all_tasks_with_metadata(plan)
    
    issues = []
    
    # Check for tasks without numbers
    without_numbers = all_tasks
    |> Enum.filter(fn {task, _} -> is_nil(task.number) or task.number == "" end)
    |> Enum.map(fn {task, _} -> "Task '#{task.name}' lacks hierarchical number" end)
    
    issues = issues ++ without_numbers
    
    # Check numbering format consistency
    numbering_issues = all_tasks
    |> Enum.filter(fn {task, _} -> not is_nil(task.number) end)
    |> Enum.flat_map(fn {task, metadata} ->
      check_number_format(task, metadata)
    end)
    
    issues = issues ++ numbering_issues
    
    case issues do
      [] ->
        {:ok, "Task numbering is consistent"}
        
      _ ->
        {:warning, %{
          message: "Task numbering inconsistencies",
          issues: issues,
          suggestion: "Run task numbering update to fix inconsistencies"
        }}
    end
  end
  
  defp check_number_format(task, metadata) do
    expected_dots = case metadata do
      %{level: 1} -> 1  # Phase level: "1.2"
      %{level: 2} -> 2  # Subtask level: "1.2.3"
      %{level: n} -> n  # Deeper levels
      _ -> 1
    end
    
    actual_dots = task.number |> String.split(".") |> length() |> Kernel.-(1)
    
    if actual_dots != expected_dots do
      ["Task '#{task.name}' number '#{task.number}' doesn't match hierarchy level"]
    else
      []
    end
  end
  
  defp validate_hierarchy_levels(plan) do
    all_tasks = get_all_tasks_with_metadata(plan)
    
    # Check for excessive nesting
    max_level = all_tasks
    |> Enum.map(fn {_, metadata} -> metadata[:level] || 1 end)
    |> Enum.max(fn -> 1 end)
    
    issues = if max_level > 5 do
      ["Hierarchy depth exceeds 5 levels - consider flattening structure"]
    else
      []
    end
    
    # Check for inconsistent depth within phases
    phase_depth_issues = if plan.phases do
      plan.phases
      |> Enum.flat_map(fn phase ->
        check_phase_depth_consistency(phase)
      end)
    else
      []
    end
    
    issues = issues ++ phase_depth_issues
    
    case issues do
      [] ->
        {:ok, "Hierarchy levels are appropriate"}
        
      _ ->
        {:warning, %{
          message: "Hierarchy level issues",
          issues: issues,
          suggestion: "Maintain consistent hierarchy depth within phases"
        }}
    end
  end
  
  defp check_phase_depth_consistency(phase) do
    task_depths = phase.tasks
    |> Enum.map(&calculate_task_depth/1)
    
    if Enum.empty?(task_depths) do
      []
    else
      min_depth = Enum.min(task_depths)
      max_depth = Enum.max(task_depths)
      
      if max_depth - min_depth > 2 do
        ["Phase '#{phase.name}' has inconsistent task depths (#{min_depth}-#{max_depth})"]
      else
        []
      end
    end
  end
  
  defp calculate_task_depth(task) do
    if has_subtasks?(task) do
      1 + (task.subtasks |> Enum.map(&calculate_task_depth/1) |> Enum.max(fn -> 0 end))
    else
      1
    end
  end
  
  defp validate_required_metadata(plan) do
    issues = []
    
    # Check plan metadata
    plan_metadata_issues = check_plan_metadata(plan)
    issues = issues ++ plan_metadata_issues
    
    # Check phase metadata
    phase_metadata_issues = if plan.phases do
      plan.phases
      |> Enum.flat_map(&check_phase_metadata/1)
    else
      []
    end
    
    issues = issues ++ phase_metadata_issues
    
    # Check critical task metadata
    all_tasks = get_all_tasks(plan)
    task_metadata_issues = all_tasks
    |> Enum.flat_map(&check_task_metadata/1)
    
    issues = issues ++ task_metadata_issues
    
    case issues do
      [] ->
        {:ok, "All required metadata is present"}
        
      _ ->
        {:info, %{
          message: "Missing recommended metadata",
          issues: issues,
          suggestion: "Add metadata to improve plan tracking and execution"
        }}
    end
  end
  
  defp check_plan_metadata(plan) do
    issues = []
    
    # Check for execution strategy
    if not Map.has_key?(plan.metadata || %{}, "execution_strategy") do
      ["Plan lacks execution strategy metadata" | issues]
    else
      issues
    end
  end
  
  defp check_phase_metadata(phase) do
    metadata = phase.metadata || %{}
    issues = []
    
    # Check for deliverables
    issues = if not Map.has_key?(metadata, "deliverables") do
      ["Phase '#{phase.name}' lacks deliverables definition" | issues]
    else
      issues
    end
    
    # Check for milestone
    if not Map.has_key?(metadata, "milestone") do
      ["Phase '#{phase.name}' lacks milestone definition" | issues]
    else
      issues
    end
  end
  
  defp check_task_metadata(task) do
    metadata = task.metadata || %{}
    issues = []
    
    # For complex tasks, check for risk assessment
    if task.complexity in [:complex, :very_complex] and 
       not Map.has_key?(metadata, "risks") do
      ["Complex task '#{task.name}' lacks risk assessment" | issues]
    else
      issues
    end
  end
  
  defp has_subtasks?(task) do
    case task.subtasks do
      subtasks when is_list(subtasks) -> not Enum.empty?(subtasks)
      _ -> false
    end
  end
  
  defp has_decomposition_justification?(task) do
    case task.metadata do
      %{"no_decomposition_reason" => reason} when is_binary(reason) -> true
      _ -> false
    end
  end
  
  defp get_all_tasks(plan) do
    phase_tasks = case plan.phases do
      phases when is_list(phases) ->
        phases
        |> Enum.flat_map(fn phase ->
          case phase.tasks do
            tasks when is_list(tasks) ->
              Enum.flat_map(tasks, &collect_task_tree/1)
            _ -> []
          end
        end)
      _ -> []
    end
    
    orphan_tasks = case plan.tasks do
      tasks when is_list(tasks) ->
        tasks
        |> Enum.filter(& is_nil(&1.phase_id))
        |> Enum.flat_map(&collect_task_tree/1)
      _ -> []
    end
    
    phase_tasks ++ orphan_tasks
  end
  
  defp get_all_tasks_with_metadata(plan) do
    phase_tasks = case plan.phases do
      phases when is_list(phases) ->
        phases
        |> Enum.flat_map(fn phase ->
          case phase.tasks do
            tasks when is_list(tasks) ->
              tasks |> Enum.flat_map(&collect_task_with_level(&1, 1))
            _ -> []
          end
        end)
      _ -> []
    end
    
    orphan_tasks = case plan.tasks do
      tasks when is_list(tasks) ->
        tasks
        |> Enum.filter(& is_nil(&1.phase_id))
        |> Enum.flat_map(&collect_task_with_level(&1, 1))
      _ -> []
    end
    
    phase_tasks ++ orphan_tasks
  end
  
  defp collect_task_tree(task) do
    subtasks = case task.subtasks do
      subs when is_list(subs) -> Enum.flat_map(subs, &collect_task_tree/1)
      _ -> []
    end
    
    [task | subtasks]
  end
  
  defp collect_task_with_level(task, level) do
    task_entry = {task, %{level: level}}
    
    subtask_entries = case task.subtasks do
      subs when is_list(subs) ->
        Enum.flat_map(subs, &collect_task_with_level(&1, level + 1))
      _ -> []
    end
    
    [task_entry | subtask_entries]
  end
  
  defp validate_single_phase_completeness(phase) do
    issues = []
    
    # Check if phase has tasks
    issues = case phase.tasks do
      [] -> ["Phase has no tasks" | issues]
      nil -> ["Phase has no tasks" | issues]
      _ -> issues
    end
    
    # Check phase metadata
    metadata_issues = check_phase_metadata(phase)
    issues = issues ++ metadata_issues
    
    case issues do
      [] ->
        {:ok, CriticBehaviour.validation_result(:passed, "Phase is complete")}
        
      _ ->
        {:ok, CriticBehaviour.validation_result(
          :failed,
          "Phase is incomplete",
          details: %{issues: issues},
          suggestions: ["Add tasks to phase", "Define deliverables and milestones"]
        )}
    end
  end
  
  defp validate_single_task_completeness(task) do
    issues = check_leaf_task_actionability(task) ++ check_task_metadata(task)
    
    # Check basic completeness
    issues = if is_nil(task.name) or task.name == "" do
      ["Task has no name" | issues]
    else
      issues
    end
    
    issues = if is_nil(task.success_criteria) do
      ["Task lacks success criteria" | issues]
    else
      issues
    end
    
    case issues do
      [] ->
        {:ok, CriticBehaviour.validation_result(:passed, "Task is complete")}
        
      _ ->
        {:ok, CriticBehaviour.validation_result(
          :warning,
          "Task has completeness issues",
          details: %{issues: issues},
          suggestions: ["Add missing task details", "Define clear success criteria"]
        )}
    end
  end
  
  defp aggregate_validation_results(checks) do
    all_results = checks
    |> Enum.map(fn
      {:ok, _message} -> {:ok, nil}
      {:info, data} -> {:info, data}
      {:warning, data} -> {:warning, data}
      {:error, data} -> {:error, data}
    end)
    
    errors = Enum.filter(all_results, &match?({:error, _}, &1))
    warnings = Enum.filter(all_results, &match?({:warning, _}, &1))
    infos = Enum.filter(all_results, &match?({:info, _}, &1))
    
    cond do
      not Enum.empty?(errors) ->
        error_details = errors |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1)
        {:ok, CriticBehaviour.validation_result(
          :failed,
          "Hierarchical completeness validation failed",
          details: %{errors: error_details, warnings: warnings |> Enum.map(&elem(&1, 1))},
          suggestions: collect_all_suggestions(error_details ++ (warnings |> Enum.map(&elem(&1, 1))))
        )}
        
      not Enum.empty?(warnings) ->
        warning_details = warnings |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1)
        {:ok, CriticBehaviour.validation_result(
          :warning,
          "Hierarchical structure has completeness issues",
          details: %{warnings: warning_details, info: infos |> Enum.map(&elem(&1, 1))},
          suggestions: collect_all_suggestions(warning_details)
        )}
        
      not Enum.empty?(infos) ->
        info_details = infos |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1)
        {:ok, CriticBehaviour.validation_result(
          :passed,
          "Hierarchical structure is complete with suggestions",
          details: %{info: info_details},
          suggestions: collect_all_suggestions(info_details)
        )}
        
      true ->
        {:ok, CriticBehaviour.validation_result(
          :passed,
          "Hierarchical structure is complete"
        )}
    end
  end
  
  defp collect_all_suggestions(details) do
    details
    |> Enum.flat_map(fn detail ->
      case detail[:suggestion] do
        nil -> []
        suggestion when is_binary(suggestion) -> [suggestion]
        suggestions when is_list(suggestions) -> suggestions
      end
    end)
    |> Enum.uniq()
  end
end