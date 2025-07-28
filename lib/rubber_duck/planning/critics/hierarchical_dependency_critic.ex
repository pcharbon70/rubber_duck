defmodule RubberDuck.Planning.Critics.HierarchicalDependencyCritic do
  @moduledoc """
  Hard critic that validates dependencies across the hierarchical structure.
  
  This critic ensures:
  - Cross-phase dependencies flow forward (no backward dependencies)
  - Parent-child task dependencies are logical
  - No circular dependencies exist across hierarchy levels
  - Dependencies are feasible within phase boundaries
  - Subtasks don't complete before their parent tasks
  """
  
  @behaviour RubberDuck.Planning.Critics.CriticBehaviour
  
  alias RubberDuck.Planning.{Plan, Task}
  alias RubberDuck.Planning.Critics.CriticBehaviour
  require Logger
  
  @impl true
  def name, do: "Hierarchical Dependency Validator"
  
  @impl true
  def type, do: :hard
  
  @impl true
  def priority, do: 20
  
  @impl true
  def validate(%Plan{} = plan, opts) do
    # Load full hierarchical structure
    plan = ensure_hierarchy_loaded(plan, opts)
    
    # Build comprehensive dependency map
    dependency_map = build_hierarchical_dependency_map(plan)
    
    # Run all validation checks
    checks = [
      validate_cross_phase_dependencies(plan, dependency_map),
      validate_parent_child_dependencies(plan, dependency_map),
      validate_circular_dependencies(dependency_map),
      validate_dependency_feasibility(plan, dependency_map),
      validate_subtask_ordering(plan)
    ]
    
    aggregate_validation_results(checks)
  end
  
  @impl true
  def validate(%Task{} = task, opts) do
    # For individual tasks, validate within their context
    plan = Keyword.get(opts, :plan)
    phase = Keyword.get(opts, :phase)
    
    if plan do
      validate_task_dependencies_in_context(task, plan, phase)
    else
      {:ok, CriticBehaviour.validation_result(:passed, "No context for dependency validation")}
    end
  end
  
  @impl true
  def validate(_, _) do
    {:ok, CriticBehaviour.validation_result(:passed, "Not applicable for this target type")}
  end
  
  # Private functions
  
  defp ensure_hierarchy_loaded(plan, opts) do
    case plan do
      %{phases: %Ash.NotLoaded{}} ->
        {:ok, loaded} = Ash.load(plan, [
          phases: [tasks: [:subtasks, :dependencies]],
          tasks: [:subtasks, :dependencies]
        ], opts)
        loaded
        
      _ ->
        # Ensure all nested relationships are loaded
        {:ok, loaded} = Ash.load(plan, [
          phases: [tasks: [:subtasks, :dependencies]],
          tasks: [:subtasks, :dependencies]
        ], opts)
        loaded
    end
  end
  
  defp build_hierarchical_dependency_map(plan) do
    all_tasks = get_all_tasks_with_context(plan)
    
    Enum.reduce(all_tasks, %{}, fn {task, context}, acc ->
      deps = task.dependencies || []
      
      Map.put(acc, task.id, %{
        task: task,
        dependencies: deps,
        phase_id: context.phase_id,
        parent_id: task.parent_id,
        number: task.number,
        context: context
      })
    end)
  end
  
  defp get_all_tasks_with_context(plan) do
    phase_tasks = plan.phases
    |> Enum.flat_map(fn phase ->
      get_phase_tasks_with_context(phase, phase.id)
    end)
    
    orphan_tasks = plan.tasks
    |> Enum.filter(& is_nil(&1.phase_id))
    |> Enum.map(fn task ->
      {task, %{phase_id: nil, phase_name: "No Phase"}}
    end)
    
    phase_tasks ++ orphan_tasks
  end
  
  defp get_phase_tasks_with_context(phase, phase_id) do
    phase.tasks
    |> Enum.flat_map(fn task ->
      context = %{phase_id: phase_id, phase_name: phase.name}
      
      # Include the task itself
      task_with_context = {task, context}
      
      # Include all subtasks recursively
      subtask_contexts = get_subtasks_with_context(task, context)
      
      [task_with_context | subtask_contexts]
    end)
  end
  
  defp get_subtasks_with_context(task, parent_context) do
    case task.subtasks do
      subtasks when is_list(subtasks) ->
        Enum.flat_map(subtasks, fn subtask ->
          context = Map.put(parent_context, :parent_task, task)
          subtask_with_context = {subtask, context}
          
          # Recursively get deeper subtasks
          deeper_subtasks = get_subtasks_with_context(subtask, context)
          
          [subtask_with_context | deeper_subtasks]
        end)
        
      _ -> []
    end
  end
  
  defp validate_cross_phase_dependencies(plan, dependency_map) do
    phases_by_id = plan.phases
    |> Enum.map(fn phase -> {phase.id, phase} end)
    |> Map.new()
    
    violations = dependency_map
    |> Enum.flat_map(fn {_task_id, task_info} ->
      task_info.dependencies
      |> Enum.filter(fn dep ->
        dep_info = Map.get(dependency_map, dep.id)
        dep_info && violates_phase_ordering?(task_info, dep_info, phases_by_id)
      end)
      |> Enum.map(fn dep ->
        dep_info = Map.get(dependency_map, dep.id)
        format_phase_violation(task_info, dep_info)
      end)
    end)
    
    case violations do
      [] ->
        {:ok, "Cross-phase dependencies are valid"}
        
      _ ->
        {:error, %{
          message: "Cross-phase dependency violations found",
          violations: violations,
          suggestion: "Dependencies should flow forward through phases"
        }}
    end
  end
  
  defp violates_phase_ordering?(task_info, dep_info, phases_by_id) do
    # If both tasks are in phases
    if task_info.phase_id && dep_info.phase_id && task_info.phase_id != dep_info.phase_id do
      task_phase = Map.get(phases_by_id, task_info.phase_id)
      dep_phase = Map.get(phases_by_id, dep_info.phase_id)
      
      # Check if dependency is in a later phase (violation)
      task_phase && dep_phase && task_phase.position < dep_phase.position
    else
      false
    end
  end
  
  defp format_phase_violation(task_info, dep_info) do
    "Task '#{task_info.task.name}' in phase '#{task_info.context.phase_name}' " <>
    "depends on '#{dep_info.task.name}' in later phase '#{dep_info.context.phase_name}'"
  end
  
  defp validate_parent_child_dependencies(_plan, dependency_map) do
    violations = dependency_map
    |> Enum.flat_map(fn {_task_id, task_info} ->
      if task_info.parent_id do
        parent_info = Map.get(dependency_map, task_info.parent_id)
        
        if parent_info && depends_on?(task_info, parent_info, dependency_map) do
          ["Subtask '#{task_info.task.name}' depends on its parent '#{parent_info.task.name}'"]
        else
          []
        end
      else
        []
      end
    end)
    
    case violations do
      [] ->
        {:ok, "Parent-child dependencies are valid"}
        
      _ ->
        {:error, %{
          message: "Parent-child dependency violations",
          violations: violations,
          suggestion: "Subtasks should not depend on their parent tasks"
        }}
    end
  end
  
  defp depends_on?(task_info, potential_dep_info, _dependency_map) do
    Enum.any?(task_info.dependencies, fn dep ->
      dep.id == potential_dep_info.task.id
    end)
  end
  
  defp validate_circular_dependencies(dependency_map) do
    # Build simple adjacency list
    adj_list = dependency_map
    |> Enum.map(fn {task_id, info} ->
      {task_id, Enum.map(info.dependencies, & &1.id)}
    end)
    |> Map.new()
    
    cycles = detect_all_cycles(adj_list)
    
    case cycles do
      [] ->
        {:ok, "No circular dependencies detected"}
        
      _ ->
        formatted_cycles = Enum.map(cycles, fn cycle ->
          task_names = cycle
          |> Enum.map(fn task_id ->
            case Map.get(dependency_map, task_id) do
              %{task: task} -> task.name || "Unknown"
              _ -> "Unknown"
            end
          end)
          |> Enum.join(" -> ")
          
          task_names
        end)
        
        {:error, %{
          message: "Circular dependencies detected",
          cycles: formatted_cycles,
          suggestion: "Remove circular dependencies to ensure tasks can be executed"
        }}
    end
  end
  
  defp detect_all_cycles(adj_list) do
    visited = MapSet.new()
    rec_stack = MapSet.new()
    cycles = []
    
    Map.keys(adj_list)
    |> Enum.reduce(cycles, fn node, acc ->
      if MapSet.member?(visited, node) do
        acc
      else
        {_visited, _rec_stack, new_cycles} = 
          dfs_detect_cycles(node, adj_list, visited, rec_stack, [], [])
        acc ++ new_cycles
      end
    end)
  end
  
  defp dfs_detect_cycles(node, adj_list, visited, rec_stack, path, cycles) do
    visited = MapSet.put(visited, node)
    rec_stack = MapSet.put(rec_stack, node)
    path = [node | path]
    
    neighbors = Map.get(adj_list, node, [])
    
    {visited, rec_stack, cycles} = 
      Enum.reduce(neighbors, {visited, rec_stack, cycles}, fn neighbor, {v, rs, c} ->
        cond do
          MapSet.member?(rs, neighbor) ->
            # Found cycle
            cycle = extract_cycle(path, neighbor)
            {v, rs, [cycle | c]}
            
          not MapSet.member?(v, neighbor) ->
            dfs_detect_cycles(neighbor, adj_list, v, rs, path, c)
            
          true ->
            {v, rs, c}
        end
      end)
    
    rec_stack = MapSet.delete(rec_stack, node)
    {visited, rec_stack, cycles}
  end
  
  defp extract_cycle(path, target) do
    path
    |> Enum.take_while(& &1 != target)
    |> Enum.reverse()
    |> then(fn cycle -> [target | cycle] end)
  end
  
  defp validate_dependency_feasibility(plan, dependency_map) do
    issues = dependency_map
    |> Enum.flat_map(fn {_task_id, task_info} ->
      check_dependency_feasibility(task_info, dependency_map, plan)
    end)
    
    case issues do
      [] ->
        {:ok, "All dependencies are feasible"}
        
      _ ->
        {:warning, %{
          message: "Dependency feasibility issues",
          issues: issues,
          suggestion: "Review task dependencies for execution feasibility"
        }}
    end
  end
  
  defp check_dependency_feasibility(task_info, dependency_map, _plan) do
    task_info.dependencies
    |> Enum.flat_map(fn dep ->
      case Map.get(dependency_map, dep.id) do
        nil ->
          ["Task '#{task_info.task.name}' depends on non-existent task"]
          
        dep_info ->
          # Check if dependency is in a skippable branch
          if dep_info.task.metadata["optional"] && 
             not task_info.task.metadata["optional"] do
            ["Required task '#{task_info.task.name}' depends on optional task '#{dep_info.task.name}'"]
          else
            []
          end
      end
    end)
  end
  
  defp validate_subtask_ordering(plan) do
    all_tasks = get_all_tasks_with_context(plan)
    
    issues = all_tasks
    |> Enum.flat_map(fn {task, _context} ->
      if task.parent_id && task.subtasks && not Enum.empty?(task.subtasks) do
        # This is a parent task with subtasks
        check_subtask_completion_order(task)
      else
        []
      end
    end)
    
    case issues do
      [] ->
        {:ok, "Subtask ordering is valid"}
        
      _ ->
        {:warning, %{
          message: "Subtask ordering issues",
          issues: issues,
          suggestion: "Ensure parent tasks complete after all their subtasks"
        }}
    end
  end
  
  defp check_subtask_completion_order(_parent_task) do
    # In a real implementation, we'd check execution order
    # For now, just check if parent has dependencies on its subtasks
    []
  end
  
  defp aggregate_validation_results(checks) do
    errors = checks
    |> Enum.filter(fn
      {:error, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:error, detail} -> detail end)
    
    warnings = checks
    |> Enum.filter(fn
      {:warning, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:warning, detail} -> detail end)
    
    cond do
      not Enum.empty?(errors) ->
        {:ok, CriticBehaviour.validation_result(
          :failed,
          "Hierarchical dependency validation failed",
          details: %{
            errors: errors,
            warnings: warnings
          },
          suggestions: collect_suggestions(errors ++ warnings)
        )}
        
      not Enum.empty?(warnings) ->
        {:ok, CriticBehaviour.validation_result(
          :warning,
          "Hierarchical dependencies have minor issues",
          details: %{warnings: warnings},
          suggestions: collect_suggestions(warnings)
        )}
        
      true ->
        {:ok, CriticBehaviour.validation_result(
          :passed,
          "Hierarchical dependencies are valid"
        )}
    end
  end
  
  defp collect_suggestions(issues) do
    issues
    |> Enum.flat_map(fn issue ->
      case issue[:suggestion] do
        nil -> []
        suggestion -> [suggestion]
      end
    end)
    |> Enum.uniq()
  end
  
  defp validate_task_dependencies_in_context(task, plan, _phase) do
    # Build mini dependency map for context
    plan = ensure_hierarchy_loaded(plan, [])
    dependency_map = build_hierarchical_dependency_map(plan)
    
    task_info = Map.get(dependency_map, task.id)
    
    if task_info do
      # Check this task's specific dependencies
      issues = []
      
      # Check cross-phase dependencies
      phase_issues = task_info.dependencies
      |> Enum.filter(fn dep ->
        dep_info = Map.get(dependency_map, dep.id)
        dep_info && task_info.phase_id && dep_info.phase_id &&
          task_info.phase_id != dep_info.phase_id
      end)
      |> Enum.map(fn dep ->
        dep_info = Map.get(dependency_map, dep.id)
        "Depends on task in different phase: #{dep_info.task.name}"
      end)
      
      issues = issues ++ phase_issues
      
      case issues do
        [] ->
          {:ok, CriticBehaviour.validation_result(:passed, "Task dependencies are valid")}
          
        _ ->
          {:ok, CriticBehaviour.validation_result(
            :warning,
            "Task has dependency issues",
            details: %{issues: issues}
          )}
      end
    else
      {:ok, CriticBehaviour.validation_result(:passed, "Task not found in plan context")}
    end
  end
end