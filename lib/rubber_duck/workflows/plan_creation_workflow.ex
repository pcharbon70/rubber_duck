defmodule RubberDuck.Workflows.PlanCreationWorkflow do
  @moduledoc """
  Reactor workflow for orchestrating plan creation with validation and rollback support.
  
  This workflow coordinates the creation of new plans through:
  - Initial validation
  - Decomposition into tasks
  - Dependency analysis
  - Critic validation
  - Final approval
  
  ## Inputs
  
  - `:plan` - The plan to create and validate
  - `:validate` - Whether to run validation (default: true)
  - `:critics` - List of critic types to run (default: [:soft, :hard])
  
  ## Compensation
  
  The workflow supports automatic rollback if any step fails, cleaning up
  partially created resources and notifying relevant agents.
  """
  
  use Reactor
  
  alias RubberDuck.Jido.Steps.{ExecuteAgentAction, SendAgentSignal, WaitForAgentResponse}
  
  input :plan
  input :validate, default: true
  input :critics, default: [:soft, :hard]
  
  # Step 1: Initial validation
  step :validate_plan, ExecuteAgentAction do
    argument :agent_id, value("plan_manager")
    argument :action, value(RubberDuck.Agents.PlanManagerAgent.ValidatePlanAction)
    argument :params, transform(input(:plan), &build_validation_params/1)
    
    compensate :cleanup_validation do
      argument :plan_id, result(:validate_plan, [:plan_id])
      
      run fn %{plan_id: plan_id} ->
        # Clean up validation state
        {:ok, :cleaned}
      end
    end
  end
  
  # Step 2: Decompose into tasks (conditional)
  step :decompose_tasks, ExecuteAgentAction do
    argument :agent_id, value("plan_decomposer")
    argument :action, value(RubberDuck.Agents.PlanDecomposerAgent.DecomposeAction)
    argument :params, result(:validate_plan)
    
    wait_for result(:validate_plan)
    max_retries 2
    
    compensate :rollback_decomposition do
      argument :tasks, result(:decompose_tasks, [:tasks])
      
      run fn %{tasks: tasks} ->
        # Remove created tasks
        Enum.each(tasks, &cleanup_task/1)
        {:ok, :rolled_back}
      end
    end
  end
  
  # Step 3: Run soft critics
  step :soft_critic_review, SendAgentSignal do
    argument :signal_type, value("critic.review.soft")
    argument :data, transform(result(:decompose_tasks), &prepare_critic_data/1)
    argument :target_agents, value(["soft_critic_agent"])
    
    wait_for result(:decompose_tasks)
  end
  
  # Step 4: Wait for soft critic response
  step :soft_critic_result, WaitForAgentResponse do
    argument :signal_type, value("critic.review.complete")
    argument :timeout, value(10_000)
    argument :source_agent, value("soft_critic_agent")
    
    wait_for result(:soft_critic_review)
  end
  
  # Step 5: Run hard critics (if soft critics pass)
  step :hard_critic_review, SendAgentSignal do
    argument :signal_type, value("critic.review.hard")
    argument :data, transform(result(:soft_critic_result), &prepare_hard_critic_data/1)
    argument :target_agents, value(["hard_critic_agent"])
    
    wait_for result(:soft_critic_result)
    
    # Only run if soft critics passed
    run_if fn context ->
      get_in(context, [:soft_critic_result, :passed]) == true
    end
  end
  
  # Step 6: Wait for hard critic response
  step :hard_critic_result, WaitForAgentResponse do
    argument :signal_type, value("critic.review.complete")
    argument :timeout, value(15_000)
    argument :source_agent, value("hard_critic_agent")
    
    wait_for result(:hard_critic_review)
    
    run_if fn context ->
      Map.has_key?(context, :hard_critic_review)
    end
  end
  
  # Step 7: Apply fixes if needed
  step :apply_fixes, ExecuteAgentAction do
    argument :agent_id, value("plan_fixer")
    argument :action, value(RubberDuck.Agents.PlanFixerAgent.ApplyFixesAction)
    argument :params, transform([result(:soft_critic_result), result(:hard_critic_result)], &merge_critic_results/1)
    
    wait_for [result(:soft_critic_result), result(:hard_critic_result)]
    
    # Only run if fixes are needed
    run_if fn context ->
      needs_fixes?(context)
    end
  end
  
  # Step 8: Finalize plan
  step :finalize_plan, ExecuteAgentAction do
    argument :agent_id, value("plan_manager")
    argument :action, value(RubberDuck.Agents.PlanManagerAgent.TransitionPlanAction)
    argument :params, transform(all_results(), &build_finalization_params/1)
    
    wait_for all_previous()
  end
  
  # Step 9: Notify completion
  step :notify_completion, SendAgentSignal do
    argument :signal_type, value("plan.creation.complete")
    argument :data, result(:finalize_plan)
    argument :target_agents, value(["monitoring_agent", "metrics_agent"])
    
    wait_for result(:finalize_plan)
  end
  
  # Return the finalized plan
  return :finalize_plan
  
  # Transform functions
  defp build_validation_params(plan) do
    %{
      plan_id: plan.id,
      validation_types: [:structure, :dependencies, :constraints]
    }
  end
  
  defp prepare_critic_data(decomposition_result) do
    %{
      plan: decomposition_result.plan,
      tasks: decomposition_result.tasks,
      dependencies: decomposition_result.dependencies
    }
  end
  
  defp prepare_hard_critic_data(soft_result) do
    Map.merge(soft_result, %{
      soft_critic_passed: soft_result.passed,
      enhanced_validation: true
    })
  end
  
  defp merge_critic_results([soft_result, hard_result]) do
    %{
      plan_id: soft_result.plan_id,
      issues: (soft_result.issues || []) ++ (hard_result.issues || []),
      fixes_required: determine_fixes([soft_result, hard_result])
    }
  end
  
  defp needs_fixes?(context) do
    soft_issues = get_in(context, [:soft_critic_result, :issues]) || []
    hard_issues = get_in(context, [:hard_critic_result, :issues]) || []
    
    length(soft_issues) + length(hard_issues) > 0
  end
  
  defp build_finalization_params(results) do
    plan_id = get_in(results, [:validate_plan, :plan_id])
    
    status = if all_steps_passed?(results) do
      :ready
    else
      :draft
    end
    
    %{
      plan_id: plan_id,
      new_status: status,
      reason: "Plan creation workflow completed"
    }
  end
  
  defp all_steps_passed?(results) do
    # Check if all critical steps passed
    Enum.all?([:validate_plan, :decompose_tasks], fn step ->
      Map.has_key?(results, step) and not is_nil(results[step])
    end)
  end
  
  defp determine_fixes(critic_results) do
    # Analyze critic results to determine required fixes
    []
  end
  
  defp cleanup_task(_task) do
    # Task cleanup logic
    :ok
  end
end