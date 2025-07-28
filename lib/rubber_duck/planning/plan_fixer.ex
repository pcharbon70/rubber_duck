defmodule RubberDuck.Planning.PlanFixer do
  @moduledoc """
  Handles targeted fixes for plan validation failures.
  
  This module attempts to fix specific validation failures during plan generation
  rather than regenerating the entire plan. It integrates with the validation
  system to address:
  - Syntax errors in code snippets
  - Missing task dependencies
  - Circular dependencies
  - Constraint violations
  - Vague task descriptions
  - Missing success criteria
  
  Fixes are applied iteratively with a configurable retry limit.
  """
  
  require Logger
  
  alias RubberDuck.Planning.Plan
  alias RubberDuck.Planning.FixTemplates
  alias RubberDuck.LLM.Service, as: LLMService
  
  @default_max_attempts 3
  @fix_timeout 30_000
  
  @doc """
  Attempts to fix validation failures in a plan.
  
  Returns {:ok, fixed_plan, new_validation} if fixes were successful,
  {:error, reason} if fixes failed or weren't possible.
  """
  def fix(%Plan{} = plan, validation_results, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    
    case extract_failures(validation_results) do
      [] ->
        {:error, :no_failures_to_fix}
        
      failures ->
        Logger.info("Attempting to fix #{length(failures)} validation failures")
        attempt_fixes(plan, failures, validation_results, max_attempts)
    end
  end
  
  @doc """
  Checks if a validation failure is fixable.
  """
  def fixable_failure?(failure) do
    failure.critic_name in fixable_critics() or
      failure.type in fixable_failure_types()
  end
  
  # Private functions
  
  defp attempt_fixes(plan, failures, _validation_results, remaining_attempts) when remaining_attempts > 0 do
    # Group failures by type for efficient fixing
    grouped_failures = group_failures_by_type(failures)
    
    # Apply fixes for each failure type
    with {:ok, fixed_plan} <- apply_grouped_fixes(plan, grouped_failures),
         {:ok, new_validation} <- validate_fixed_plan(fixed_plan) do
      
      new_summary = new_validation["summary"] || new_validation[:summary]
      
      case new_summary do
        :passed ->
          Logger.info("All validation failures fixed successfully")
          {:ok, fixed_plan, new_validation}
          
        :warning ->
          # Warnings are acceptable after fixing failures
          Logger.info("Validation failures fixed, some warnings remain")
          {:ok, fixed_plan, new_validation}
          
        :failed ->
          # Check if we made progress
          new_failures = extract_failures(new_validation)
          
          if length(new_failures) < length(failures) do
            Logger.info("Made progress fixing failures, attempting remaining fixes")
            attempt_fixes(fixed_plan, new_failures, new_validation, remaining_attempts - 1)
          else
            Logger.warning("No progress made in fixing failures")
            {:error, :fixes_ineffective}
          end
      end
    else
      error ->
        Logger.error("Failed to apply fixes: #{inspect(error)}")
        {:error, error}
    end
  end
  
  defp attempt_fixes(_plan, _failures, _validation_results, 0) do
    Logger.warning("Max fix attempts reached, returning original validation")
    {:error, :max_attempts_reached}
  end
  
  defp extract_failures(validation_results) do
    hard_critics = validation_results[:hard_critics] || validation_results["hard_critics"] || []
    
    hard_critics
    |> Enum.filter(fn critic ->
      status = critic[:status] || critic["status"]
      status == :failed || status == "failed"
    end)
    |> Enum.map(&normalize_failure/1)
  end
  
  defp normalize_failure(critic) do
    %{
      critic_name: critic[:name] || critic["name"],
      type: detect_failure_type(critic),
      details: critic[:details] || critic["details"] || %{},
      suggestions: critic[:suggestions] || critic["suggestions"] || []
    }
  end
  
  defp detect_failure_type(critic) do
    name = String.downcase(critic[:name] || critic["name"] || "")
    
    cond do
      String.contains?(name, "syntax") -> :syntax_error
      String.contains?(name, "dependency") -> :dependency_issue
      String.contains?(name, "constraint") -> :constraint_violation
      String.contains?(name, "feasibility") -> :feasibility_issue
      String.contains?(name, "resource") -> :resource_issue
      true -> :unknown
    end
  end
  
  defp group_failures_by_type(failures) do
    Enum.group_by(failures, & &1.type)
  end
  
  defp apply_grouped_fixes(plan, grouped_failures) do
    # Apply fixes in a specific order for best results
    fix_order = [
      :syntax_error,
      :dependency_issue,
      :constraint_violation,
      :feasibility_issue,
      :resource_issue,
      :unknown
    ]
    
    Enum.reduce_while(fix_order, {:ok, plan}, fn failure_type, {:ok, current_plan} ->
      case Map.get(grouped_failures, failure_type) do
        nil ->
          {:cont, {:ok, current_plan}}
          
        failures ->
          case apply_fixes_for_type(current_plan, failure_type, failures) do
            {:ok, fixed_plan} ->
              {:cont, {:ok, fixed_plan}}
              
            error ->
              {:halt, error}
          end
      end
    end)
  end
  
  defp apply_fixes_for_type(plan, :syntax_error, failures) do
    fix_syntax_errors(plan, failures)
  end
  
  defp apply_fixes_for_type(plan, :dependency_issue, failures) do
    fix_dependency_issues(plan, failures)
  end
  
  defp apply_fixes_for_type(plan, :constraint_violation, failures) do
    fix_constraint_violations(plan, failures)
  end
  
  defp apply_fixes_for_type(plan, :feasibility_issue, failures) do
    fix_feasibility_issues(plan, failures)
  end
  
  defp apply_fixes_for_type(plan, :resource_issue, failures) do
    fix_resource_issues(plan, failures)
  end
  
  defp apply_fixes_for_type(plan, :unknown, _failures) do
    # Can't fix unknown failure types
    {:ok, plan}
  end
  
  # Fix implementations
  
  defp fix_syntax_errors(plan, failures) do
    Logger.debug("Fixing #{length(failures)} syntax errors")
    
    # Extract all syntax errors from the failures
    syntax_errors = failures
    |> Enum.flat_map(fn failure ->
      errors = failure.details[:errors] || failure.details["errors"] || []
      Enum.map(errors, &parse_syntax_error/1)
    end)
    |> Enum.reject(&is_nil/1)
    
    if Enum.empty?(syntax_errors) do
      {:ok, plan}
    else
      # Use LLM to fix syntax errors
      fix_with_llm(plan, :syntax_fix, %{errors: syntax_errors})
    end
  end
  
  defp parse_syntax_error(error_string) when is_binary(error_string) do
    # Parse error strings like "Syntax error at line 5: unexpected token"
    case Regex.run(~r/line (\d+): (.+)/, error_string) do
      [_, line, message] ->
        %{line: String.to_integer(line), message: message}
      _ ->
        %{line: nil, message: error_string}
    end
  end
  
  defp parse_syntax_error(_), do: nil
  
  defp fix_dependency_issues(plan, failures) do
    Logger.debug("Fixing #{length(failures)} dependency issues")
    
    # Collect all dependency problems
    problems = failures
    |> Enum.reduce(%{missing: [], circular: []}, fn failure, acc ->
      details = failure.details
      
      missing = details[:missing_dependencies] || details["missing_dependencies"] || []
      cycles = details[:cycles] || details["cycles"] || []
      
      %{
        missing: acc.missing ++ missing,
        circular: acc.circular ++ cycles
      }
    end)
    
    # Fix missing dependencies first
    plan = if not Enum.empty?(problems.missing) do
      case add_missing_dependencies(plan, problems.missing) do
        {:ok, updated_plan} -> updated_plan
        _ -> plan
      end
    else
      plan
    end
    
    # Then fix circular dependencies
    if not Enum.empty?(problems.circular) do
      fix_circular_dependencies(plan, problems.circular)
    else
      {:ok, plan}
    end
  end
  
  defp add_missing_dependencies(plan, missing_deps) do
    # For missing dependencies, we need to either:
    # 1. Remove the dependency if it's not valid
    # 2. Create the missing task if it should exist
    
    # For now, we'll remove invalid dependencies
    task_ids = if plan.tasks && plan.tasks != %Ash.NotLoaded{} do
      plan.tasks |> Enum.map(& &1.id) |> MapSet.new()
    else
      MapSet.new()
    end
    
    invalid_deps = Enum.reject(missing_deps, &MapSet.member?(task_ids, &1))
    
    if Enum.empty?(invalid_deps) do
      {:ok, plan}
    else
      # Update tasks to remove invalid dependencies
      fix_with_llm(plan, :remove_invalid_dependencies, %{invalid_deps: invalid_deps})
    end
  end
  
  defp fix_circular_dependencies(plan, cycles) do
    Logger.debug("Fixing #{length(cycles)} circular dependencies")
    
    # Use LLM to restructure dependencies
    fix_with_llm(plan, :break_circular_dependencies, %{cycles: cycles})
  end
  
  defp fix_constraint_violations(plan, failures) do
    Logger.debug("Fixing #{length(failures)} constraint violations")
    
    violations = failures
    |> Enum.flat_map(fn failure ->
      failure.details[:violations] || failure.details["violations"] || []
    end)
    
    if Enum.empty?(violations) do
      {:ok, plan}
    else
      fix_with_llm(plan, :resolve_constraint_violations, %{violations: violations})
    end
  end
  
  defp fix_feasibility_issues(plan, failures) do
    Logger.debug("Fixing #{length(failures)} feasibility issues")
    
    issues = failures
    |> Enum.reduce(%{errors: [], warnings: []}, fn failure, acc ->
      details = failure.details
      errors = details[:errors] || details["errors"] || []
      warnings = details[:warnings] || details["warnings"] || []
      
      %{
        errors: acc.errors ++ errors,
        warnings: acc.warnings ++ warnings
      }
    end)
    
    if Enum.empty?(issues.errors) do
      {:ok, plan}
    else
      fix_with_llm(plan, :improve_feasibility, issues)
    end
  end
  
  defp fix_resource_issues(plan, failures) do
    Logger.debug("Fixing #{length(failures)} resource issues")
    
    resource_problems = failures
    |> Enum.flat_map(fn failure ->
      errors = failure.details[:errors] || failure.details["errors"] || []
      missing = failure.details[:missing] || failure.details["missing"] || []
      errors ++ missing
    end)
    
    if Enum.empty?(resource_problems) do
      {:ok, plan}
    else
      fix_with_llm(plan, :adjust_resources, %{problems: resource_problems})
    end
  end
  
  # LLM integration
  
  defp fix_with_llm(plan, fix_type, context) do
    prompt = FixTemplates.get_template(fix_type, Map.merge(context, %{
      plan: serialize_plan(plan),
      plan_type: plan.type,
      plan_name: plan.name
    }))
    
    messages = [
      %{role: "system", content: system_prompt()},
      %{role: "user", content: prompt}
    ]
    
    llm_opts = [
      messages: messages,
      max_tokens: 2000,
      temperature: 0.3,
      timeout: @fix_timeout,
      response_format: %{type: "json_object"}
    ]
    
    case LLMService.completion(llm_opts) do
      {:ok, response} ->
        apply_llm_fixes(plan, fix_type, response)
        
      {:error, reason} ->
        Logger.error("LLM fix failed: #{inspect(reason)}")
        {:error, {:llm_error, reason}}
    end
  end
  
  defp system_prompt do
    """
    You are a plan fixing assistant. Your role is to make targeted fixes to plans
    that have validation failures. You should:
    
    1. Make minimal changes to fix the specific issues
    2. Preserve the original intent and structure where possible
    3. Ensure fixes don't introduce new problems
    4. Return updates in the exact JSON format requested
    
    Always respond with valid JSON only.
    """
  end
  
  defp apply_llm_fixes(plan, fix_type, response) do
    try do
      content = extract_content(response)
      fixes = Jason.decode!(content)
      
      case fix_type do
        :syntax_fix ->
          apply_syntax_fixes(plan, fixes)
          
        :remove_invalid_dependencies ->
          apply_dependency_removal(plan, fixes)
          
        :break_circular_dependencies ->
          apply_dependency_restructuring(plan, fixes)
          
        :resolve_constraint_violations ->
          apply_constraint_fixes(plan, fixes)
          
        :improve_feasibility ->
          apply_feasibility_improvements(plan, fixes)
          
        :adjust_resources ->
          apply_resource_adjustments(plan, fixes)
          
        _ ->
          {:error, :unknown_fix_type}
      end
    rescue
      e ->
        Logger.error("Failed to apply LLM fixes: #{inspect(e)}")
        {:error, :fix_application_failed}
    end
  end
  
  defp apply_syntax_fixes(plan, %{"fixed_code" => fixed_code}) do
    # Update plan description with fixed code
    updated_plan = %{plan | description: fixed_code}
    {:ok, updated_plan}
  end
  
  defp apply_syntax_fixes(plan, %{"task_fixes" => task_fixes}) when is_list(task_fixes) do
    # Update specific tasks with syntax fixes
    updated_tasks = if plan.tasks && plan.tasks != %Ash.NotLoaded{} do
      Enum.map(plan.tasks, fn task ->
        case Enum.find(task_fixes, &(&1["task_id"] == task.id)) do
          nil -> task
          fix -> %{task | description: fix["fixed_description"]}
        end
      end)
    else
      []
    end
    
    {:ok, %{plan | tasks: updated_tasks}}
  end
  
  defp apply_syntax_fixes(plan, _), do: {:ok, plan}
  
  defp apply_dependency_removal(plan, %{"updated_tasks" => updated_tasks}) do
    # Update tasks to remove invalid dependencies
    task_updates = Map.new(updated_tasks, fn task_update ->
      {task_update["task_id"], task_update["dependencies"] || []}
    end)
    
    updated_plan_tasks = if plan.tasks && plan.tasks != %Ash.NotLoaded{} do
      Enum.map(plan.tasks, fn task ->
        case Map.get(task_updates, task.id) do
          nil -> task
          new_deps -> %{task | dependencies: new_deps}
        end
      end)
    else
      []
    end
    
    {:ok, %{plan | tasks: updated_plan_tasks}}
  end
  
  defp apply_dependency_removal(plan, _), do: {:ok, plan}
  
  defp apply_dependency_restructuring(plan, %{"dependency_updates" => updates}) do
    # Similar to dependency removal but more complex
    apply_dependency_removal(plan, %{"updated_tasks" => updates})
  end
  
  defp apply_dependency_restructuring(plan, _), do: {:ok, plan}
  
  defp apply_constraint_fixes(plan, %{"constraint_adjustments" => adjustments}) do
    # Update plan metadata or constraints based on fixes
    updated_metadata = Map.merge(plan.metadata || %{}, %{
      "constraint_fixes_applied" => true,
      "adjustments" => adjustments
    })
    
    {:ok, %{plan | metadata: updated_metadata}}
  end
  
  defp apply_constraint_fixes(plan, _), do: {:ok, plan}
  
  defp apply_feasibility_improvements(plan, %{"task_updates" => task_updates}) do
    # Update task descriptions, complexity, or timelines
    task_update_map = Map.new(task_updates, fn update ->
      {update["task_id"], update}
    end)
    
    updated_tasks = if plan.tasks && plan.tasks != %Ash.NotLoaded{} do
      Enum.map(plan.tasks, fn task ->
        case Map.get(task_update_map, task.id) do
          nil -> 
            task
            
          update ->
            task
            |> maybe_update_field(:description, update["description"])
            |> maybe_update_field(:complexity, parse_complexity(update["complexity"]))
        end
      end)
    else
      []
    end
    
    {:ok, %{plan | tasks: updated_tasks}}
  end
  
  defp apply_feasibility_improvements(plan, _), do: {:ok, plan}
  
  defp apply_resource_adjustments(plan, %{"resource_updates" => updates}) do
    # Update resource requirements in plan metadata
    updated_metadata = Map.merge(plan.metadata || %{}, %{
      "resource_requirements" => updates
    })
    
    {:ok, %{plan | metadata: updated_metadata}}
  end
  
  defp apply_resource_adjustments(plan, _), do: {:ok, plan}
  
  # Helper functions
  
  defp maybe_update_field(struct, _field, nil), do: struct
  defp maybe_update_field(struct, field, value), do: Map.put(struct, field, value)
  
  defp parse_complexity(nil), do: nil
  defp parse_complexity(complexity) when is_atom(complexity), do: complexity
  defp parse_complexity(complexity) when is_binary(complexity) do
    try do
      String.to_existing_atom(complexity)
    rescue
      ArgumentError -> :medium
    end
  end
  
  defp serialize_plan(plan) do
    tasks = if plan.tasks && plan.tasks != %Ash.NotLoaded{} do
      Enum.map(plan.tasks, &serialize_task/1)
    else
      []
    end
    
    %{
      id: plan.id,
      name: plan.name,
      description: plan.description,
      type: plan.type,
      tasks: tasks,
      metadata: plan.metadata || %{}
    }
  end
  
  defp serialize_task(task) do
    %{
      id: task.id,
      name: task.name,
      description: task.description,
      dependencies: task.dependencies || [],
      complexity: task.complexity,
      metadata: task.metadata || %{}
    }
  end
  
  defp validate_fixed_plan(plan) do
    # Re-run validation on the fixed plan
    alias RubberDuck.Planning.Critics.Orchestrator
    
    orchestrator = Orchestrator.new()
    
    case Orchestrator.validate(orchestrator, plan) do
      {:ok, results} ->
        aggregated = Orchestrator.aggregate_results(results)
        {:ok, aggregated}
        
      error ->
        Logger.error("Validation of fixed plan failed: #{inspect(error)}")
        error
    end
  end
  
  defp fixable_critics do
    [
      "Syntax Validator",
      "Dependency Validator",
      "Constraint Checker",
      "Feasibility Analyzer",
      "Resource Validator"
    ]
  end
  
  defp fixable_failure_types do
    [
      :syntax_error,
      :dependency_issue,
      :constraint_violation,
      :feasibility_issue,
      :resource_issue
    ]
  end
  
  defp extract_content(response) do
    cond do
      is_binary(response) ->
        response
        
      is_struct(response, RubberDuck.LLM.Response) and is_list(response.choices) ->
        response.choices
        |> List.first()
        |> case do
          %{message: %{content: content}} when is_binary(content) -> content
          %{message: %{"content" => content}} when is_binary(content) -> content
          _ -> ""
        end
        
      is_map(response) and Map.has_key?(response, :choices) ->
        response.choices
        |> List.first()
        |> get_in([:message, :content]) || ""
        
      true ->
        ""
    end
  end
end