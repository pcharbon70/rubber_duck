defmodule RubberDuck.Planning.FixTemplates do
  @moduledoc """
  LLM prompt templates for fixing various plan validation failures.
  
  Each template is designed to provide targeted fixes for specific
  types of validation failures while preserving the original plan
  structure and intent as much as possible.
  """
  
  @doc """
  Gets the appropriate fix template for the given fix type.
  """
  def get_template(fix_type, params) do
    case fix_type do
      :syntax_fix ->
        syntax_fix_template(params)
        
      :remove_invalid_dependencies ->
        dependency_removal_template(params)
        
      :break_circular_dependencies ->
        circular_dependency_template(params)
        
      :resolve_constraint_violations ->
        constraint_violation_template(params)
        
      :improve_feasibility ->
        feasibility_improvement_template(params)
        
      :adjust_resources ->
        resource_adjustment_template(params)
        
      _ ->
        raise ArgumentError, "Unknown fix type: #{fix_type}"
    end
  end
  
  defp syntax_fix_template(params) do
    """
    Fix the syntax errors in this plan or its tasks.
    
    Plan: #{params.plan_name} (#{params.plan_type})
    
    Syntax Errors Found:
    #{format_syntax_errors(params.errors)}
    
    Current Plan Structure:
    #{Jason.encode!(params.plan, pretty: true)}
    
    Fix the syntax errors while preserving the original intent. Focus on:
    1. Correcting Elixir syntax in code snippets
    2. Ensuring proper formatting and indentation
    3. Fixing any malformed function calls or module references
    4. Maintaining semantic meaning while fixing syntax
    
    Respond with JSON in one of these formats:
    
    If fixing plan description:
    {
      "fixed_code": "The entire corrected plan description with fixed syntax"
    }
    
    If fixing task descriptions:
    {
      "task_fixes": [
        {
          "task_id": "task-id-here",
          "fixed_description": "Corrected task description"
        }
      ]
    }
    """
  end
  
  defp dependency_removal_template(params) do
    """
    Remove invalid dependencies from tasks in this plan.
    
    Plan: #{params.plan_name} (#{params.plan_type})
    
    Invalid Dependencies Found:
    #{Enum.join(params.invalid_deps, ", ")}
    
    Current Plan Structure:
    #{Jason.encode!(params.plan, pretty: true)}
    
    Remove the invalid dependency IDs from any tasks that reference them.
    Only remove dependencies that don't exist - preserve all valid dependencies.
    
    Respond with JSON:
    {
      "updated_tasks": [
        {
          "task_id": "task-id-here",
          "dependencies": ["valid-dep-1", "valid-dep-2"]
        }
      ]
    }
    
    Only include tasks that need dependency updates.
    """
  end
  
  defp circular_dependency_template(params) do
    """
    Break circular dependencies in this plan.
    
    Plan: #{params.plan_name} (#{params.plan_type})
    
    Circular Dependencies Found:
    #{format_cycles(params.cycles)}
    
    Current Plan Structure:
    #{Jason.encode!(params.plan, pretty: true)}
    
    Break the circular dependencies by:
    1. Identifying which dependencies can be removed without affecting correctness
    2. Reordering tasks if necessary
    3. Considering if some tasks can be made parallel instead of sequential
    
    Respond with JSON:
    {
      "dependency_updates": [
        {
          "task_id": "task-id-here",
          "dependencies": ["updated-dep-list"],
          "reasoning": "Brief explanation of why this change breaks the cycle"
        }
      ]
    }
    """
  end
  
  defp constraint_violation_template(params) do
    """
    Resolve constraint violations in this plan.
    
    Plan: #{params.plan_name} (#{params.plan_type})
    
    Constraint Violations:
    #{format_violations(params.violations)}
    
    Current Plan Structure:
    #{Jason.encode!(params.plan, pretty: true)}
    
    Fix the constraint violations by:
    1. Adjusting task durations or complexity
    2. Modifying resource requirements
    3. Updating dependencies to meet constraints
    4. Adding necessary metadata to satisfy constraints
    
    Respond with JSON:
    {
      "constraint_adjustments": {
        "duration_adjustments": {
          "task-id": "new-duration-in-hours"
        },
        "resource_adjustments": {
          "resource-name": "new-amount"
        },
        "metadata_updates": {
          "key": "value"
        }
      }
    }
    """
  end
  
  defp feasibility_improvement_template(params) do
    """
    Improve the feasibility of this plan by addressing identified issues.
    
    Plan: #{params.plan_name} (#{params.plan_type})
    
    Feasibility Issues:
    Errors: #{format_list(params.errors)}
    Warnings: #{format_list(params.warnings)}
    
    Current Plan Structure:
    #{Jason.encode!(params.plan, pretty: true)}
    
    Improve feasibility by:
    1. Breaking down overly complex tasks
    2. Adjusting unrealistic timelines
    3. Clarifying vague task descriptions
    4. Setting appropriate complexity levels
    
    Respond with JSON:
    {
      "task_updates": [
        {
          "task_id": "task-id-here",
          "description": "More detailed and feasible description",
          "complexity": "simple|medium|complex|very_complex",
          "improvements": ["list", "of", "improvements", "made"]
        }
      ]
    }
    """
  end
  
  defp resource_adjustment_template(params) do
    """
    Adjust resource requirements to resolve resource issues.
    
    Plan: #{params.plan_name} (#{params.plan_type})
    
    Resource Problems:
    #{format_list(params.problems)}
    
    Current Plan Structure:
    #{Jason.encode!(params.plan, pretty: true)}
    
    Fix resource issues by:
    1. Reducing resource requirements where possible
    2. Finding alternative resources
    3. Adjusting task scope to match available resources
    4. Prioritizing critical resource needs
    
    Respond with JSON:
    {
      "resource_updates": {
        "required_resources": {
          "resource-name": "amount-or-specification"
        },
        "optional_resources": {
          "resource-name": "amount-or-specification"
        },
        "alternatives": {
          "original-resource": "alternative-resource"
        }
      }
    }
    """
  end
  
  # Formatting helpers
  
  defp format_syntax_errors(errors) do
    errors
    |> Enum.map(fn error ->
      line = error[:line] || error["line"]
      message = error[:message] || error["message"]
      
      if line do
        "- Line #{line}: #{message}"
      else
        "- #{message}"
      end
    end)
    |> Enum.join("\n")
  end
  
  defp format_cycles(cycles) do
    cycles
    |> Enum.with_index(1)
    |> Enum.map(fn {cycle, index} ->
      "#{index}. #{Enum.join(cycle, " → ")} → #{List.first(cycle)}"
    end)
    |> Enum.join("\n")
  end
  
  defp format_violations(violations) do
    violations
    |> Enum.map(fn violation ->
      if is_binary(violation) do
        "- #{violation}"
      else
        "- #{inspect(violation)}"
      end
    end)
    |> Enum.join("\n")
  end
  
  defp format_list(items) when is_list(items) do
    if Enum.empty?(items) do
      "None"
    else
      items
      |> Enum.map(fn item ->
        if is_binary(item) do
          "- #{item}"
        else
          "- #{inspect(item)}"
        end
      end)
      |> Enum.join("\n")
    end
  end
  
  defp format_list(_), do: "None"
end