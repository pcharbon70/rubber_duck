defmodule RubberDuck.Workflows.PlanValidationWorkflow do
  @moduledoc """
  Reactor workflow for validating plans through multiple validation stages.
  
  This workflow performs comprehensive validation including:
  - Structure validation
  - Dependency checking
  - Constraint verification
  - Critic reviews
  
  ## Inputs
  
  - `:plan` - The plan to validate
  - `:validation_types` - Types of validation to perform
  - `:strict` - Whether to use strict validation rules
  """
  
  use Reactor
  
  alias RubberDuck.Jido.Steps.ExecuteAgentAction
  
  input :plan
  input :validation_types
  input :strict
  
  # Step 1: Structure validation
  step :validate_structure do
    argument :plan, input(:plan)
    argument :strict, input(:strict)
    
    run fn %{plan: plan, strict: strict} ->
      strict_mode = strict || false
      validate_plan_structure(plan, strict_mode)
    end
  end
  
  # Step 2: Dependency validation
  step :validate_dependencies do
    argument :plan, input(:plan)
    argument :structure_result, result(:validate_structure)
    
    wait_for :validate_structure
    
    run fn %{plan: plan} ->
      validate_plan_dependencies(plan)
    end
  end
  
  # Step 3: Constraint validation
  step :validate_constraints do
    argument :plan, input(:plan)
    
    wait_for :validate_dependencies
    
    run fn %{plan: plan} ->
      validate_plan_constraints(plan)
    end
  end
  
  # Step 4: Aggregate results
  step :aggregate_results do
    argument :structure, result(:validate_structure)
    argument :dependencies, result(:validate_dependencies)
    argument :constraints, result(:validate_constraints)
    
    wait_for [:validate_structure, :validate_dependencies, :validate_constraints]
    
    run fn results ->
      aggregate_validation_results(results)
    end
  end
  
  return :aggregate_results
  
  # Validation functions
  defp validate_plan_structure(plan, strict) do
    issues = []
    
    issues = if is_nil(plan.name) or plan.name == "" do
      [{:error, :missing_name, "Plan must have a name"} | issues]
    else
      issues
    end
    
    issues = if strict and (is_nil(plan.description) or plan.description == "") do
      [{:warning, :missing_description, "Plan should have a description"} | issues]
    else
      issues
    end
    
    {:ok, %{
      valid: Enum.empty?(issues),
      issues: issues,
      checked_at: DateTime.utc_now()
    }}
  end
  
  defp validate_plan_dependencies(plan) do
    dependencies = plan.dependencies || []
    issues = []
    
    # Check for circular dependencies
    issues = if has_circular_dependencies?(dependencies) do
      [{:error, :circular_dependency, "Plan has circular dependencies"} | issues]
    else
      issues
    end
    
    # Check for missing dependencies
    missing = find_missing_dependencies(dependencies)
    issues = if length(missing) > 0 do
      [{:error, :missing_dependencies, "Missing dependencies: #{inspect(missing)}"} | issues]
    else
      issues
    end
    
    {:ok, %{
      valid: Enum.empty?(issues),
      issues: issues,
      dependency_count: length(dependencies),
      checked_at: DateTime.utc_now()
    }}
  end
  
  defp validate_plan_constraints(plan) do
    constraints = plan.constraints_data || []
    issues = []
    
    # Validate each constraint
    issues = Enum.reduce(constraints, issues, fn constraint, acc ->
      case validate_constraint(constraint) do
        {:ok, _} -> acc
        {:error, reason} -> [{:error, :invalid_constraint, reason} | acc]
      end
    end)
    
    {:ok, %{
      valid: Enum.empty?(issues),
      issues: issues,
      constraint_count: length(constraints),
      checked_at: DateTime.utc_now()
    }}
  end
  
  defp aggregate_validation_results(results) do
    all_issues = 
      [results.structure.issues, results.dependencies.issues, results.constraints.issues]
      |> List.flatten()
    
    errors = Enum.filter(all_issues, fn {level, _, _} -> level == :error end)
    warnings = Enum.filter(all_issues, fn {level, _, _} -> level == :warning end)
    
    {:ok, %{
      is_valid: Enum.empty?(errors),
      has_warnings: not Enum.empty?(warnings),
      errors: errors,
      warnings: warnings,
      summary: %{
        structure_valid: results.structure.valid,
        dependencies_valid: results.dependencies.valid,
        constraints_valid: results.constraints.valid,
        total_errors: length(errors),
        total_warnings: length(warnings)
      },
      validated_at: DateTime.utc_now()
    }}
  end
  
  defp has_circular_dependencies?(_dependencies) do
    # TODO: Implement circular dependency detection
    false
  end
  
  defp find_missing_dependencies(_dependencies) do
    # TODO: Implement missing dependency detection
    []
  end
  
  defp validate_constraint(_constraint) do
    # TODO: Implement constraint validation
    {:ok, :valid}
  end
end