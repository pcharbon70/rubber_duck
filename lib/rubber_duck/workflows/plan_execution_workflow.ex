defmodule RubberDuck.Workflows.PlanExecutionWorkflow do
  @moduledoc """
  Reactor workflow for executing plans with different execution modes.
  
  Supports multiple execution strategies:
  - Sequential: Execute tasks one by one
  - Parallel: Execute independent tasks concurrently
  - Adaptive: Dynamically adjust based on resource availability
  
  ## Inputs
  
  - `:plan` - The plan to execute
  - `:execution_mode` - How to execute (:sequential, :parallel, :adaptive)
  - `:dry_run` - Whether to simulate execution without making changes
  """
  
  use Reactor
  
  alias RubberDuck.Jido.Steps.{ExecuteAgentAction, SendAgentSignal}
  
  input :plan
  input :execution_mode, default: :sequential
  input :dry_run, default: false
  
  # Step 1: Prepare execution
  step :prepare_execution do
    argument :plan, input(:plan)
    argument :mode, input(:execution_mode)
    argument :dry_run, input(:dry_run)
    
    run fn args ->
      prepare_plan_execution(args)
    end
  end
  
  # Step 2: Transition plan to executing
  step :mark_executing, ExecuteAgentAction do
    argument :agent_id, value("plan_manager")
    argument :action, value(RubberDuck.Agents.PlanManagerAgent.TransitionPlanAction)
    argument :params, transform(result(:prepare_execution), &build_transition_params/1)
    
    wait_for result(:prepare_execution)
    
    # Skip in dry run mode
    run_if fn context ->
      not context.dry_run
    end
  end
  
  # Step 3: Execute tasks based on mode
  step :execute_tasks do
    argument :tasks, result(:prepare_execution, [:tasks])
    argument :mode, input(:execution_mode)
    argument :dry_run, input(:dry_run)
    
    wait_for result(:prepare_execution)
    
    run fn args ->
      execute_tasks_by_mode(args)
    end
  end
  
  # Step 4: Collect execution results
  step :collect_results do
    argument :task_results, result(:execute_tasks)
    argument :plan, input(:plan)
    
    wait_for result(:execute_tasks)
    
    run fn args ->
      collect_execution_results(args)
    end
  end
  
  # Step 5: Update plan with results
  step :update_plan, ExecuteAgentAction do
    argument :agent_id, value("plan_manager")
    argument :action, value(RubberDuck.Agents.PlanManagerAgent.UpdatePlanAction)
    argument :params, transform(result(:collect_results), &build_update_params/1)
    
    wait_for result(:collect_results)
    
    # Skip in dry run mode
    run_if fn context ->
      not context.dry_run
    end
  end
  
  # Step 6: Finalize execution
  step :finalize_execution, ExecuteAgentAction do
    argument :agent_id, value("plan_manager")
    argument :action, value(RubberDuck.Agents.PlanManagerAgent.TransitionPlanAction)
    argument :params, transform(result(:collect_results), &build_finalization_params/1)
    
    wait_for result(:update_plan)
    
    # Skip in dry run mode
    run_if fn context ->
      not context.dry_run
    end
  end
  
  # Step 7: Emit completion signal
  step :notify_completion, SendAgentSignal do
    argument :signal_type, value("plan.execution.complete")
    argument :data, result(:collect_results)
    argument :target_agents, value(["monitoring_agent", "metrics_agent"])
    
    wait_for result(:collect_results)
  end
  
  return :collect_results
  
  # Helper functions
  defp prepare_plan_execution(%{plan: plan, mode: mode, dry_run: dry_run}) do
    tasks = extract_tasks_from_plan(plan)
    
    execution_strategy = case mode do
      :sequential -> build_sequential_strategy(tasks)
      :parallel -> build_parallel_strategy(tasks)
      :adaptive -> build_adaptive_strategy(tasks)
    end
    
    {:ok, %{
      plan_id: plan.id,
      tasks: tasks,
      strategy: execution_strategy,
      dry_run: dry_run,
      started_at: DateTime.utc_now()
    }}
  end
  
  defp execute_tasks_by_mode(%{tasks: tasks, mode: mode, dry_run: dry_run}) do
    results = case mode do
      :sequential ->
        execute_sequentially(tasks, dry_run)
      
      :parallel ->
        execute_in_parallel(tasks, dry_run)
      
      :adaptive ->
        execute_adaptively(tasks, dry_run)
    end
    
    {:ok, results}
  end
  
  defp execute_sequentially(tasks, dry_run) do
    Enum.reduce(tasks, [], fn task, acc ->
      result = if dry_run do
        simulate_task_execution(task)
      else
        execute_single_task(task)
      end
      
      [result | acc]
    end)
    |> Enum.reverse()
  end
  
  defp execute_in_parallel(tasks, dry_run) do
    tasks
    |> Enum.map(fn task ->
      Task.async(fn ->
        if dry_run do
          simulate_task_execution(task)
        else
          execute_single_task(task)
        end
      end)
    end)
    |> Task.await_many(30_000)
  end
  
  defp execute_adaptively(tasks, _dry_run) do
    # TODO: Implement adaptive execution based on resource availability
    execute_sequentially(tasks, false)
  end
  
  defp execute_single_task(task) do
    # TODO: Implement actual task execution
    %{
      task_id: task.id,
      status: :completed,
      result: %{},
      executed_at: DateTime.utc_now()
    }
  end
  
  defp simulate_task_execution(task) do
    %{
      task_id: task.id,
      status: :simulated,
      result: %{simulated: true},
      simulated_at: DateTime.utc_now()
    }
  end
  
  defp collect_execution_results(%{task_results: results, plan: plan}) do
    successful = Enum.count(results, & &1.status in [:completed, :simulated])
    failed = Enum.count(results, & &1.status == :failed)
    
    {:ok, %{
      plan_id: plan.id,
      execution_summary: %{
        total_tasks: length(results),
        successful: successful,
        failed: failed,
        success_rate: if(length(results) > 0, do: successful / length(results) * 100, else: 0)
      },
      task_results: results,
      completed_at: DateTime.utc_now()
    }}
  end
  
  defp extract_tasks_from_plan(plan) do
    # TODO: Extract tasks from plan structure
    plan.tasks || []
  end
  
  defp build_sequential_strategy(tasks) do
    %{
      type: :sequential,
      task_order: Enum.map(tasks, & &1.id)
    }
  end
  
  defp build_parallel_strategy(tasks) do
    %{
      type: :parallel,
      task_groups: group_independent_tasks(tasks)
    }
  end
  
  defp build_adaptive_strategy(tasks) do
    %{
      type: :adaptive,
      priority_order: prioritize_tasks(tasks)
    }
  end
  
  defp group_independent_tasks(tasks) do
    # TODO: Group tasks that can run in parallel
    [Enum.map(tasks, & &1.id)]
  end
  
  defp prioritize_tasks(tasks) do
    # TODO: Prioritize tasks based on dependencies and importance
    Enum.map(tasks, & &1.id)
  end
  
  defp build_transition_params(preparation) do
    %{
      plan_id: preparation.plan_id,
      new_status: :executing,
      reason: "Starting plan execution"
    }
  end
  
  defp build_update_params(results) do
    %{
      plan_id: results.plan_id,
      updates: %{
        execution_history: results.task_results,
        last_executed_at: results.completed_at
      }
    }
  end
  
  defp build_finalization_params(results) do
    new_status = if results.execution_summary.failed > 0 do
      :failed
    else
      :completed
    end
    
    %{
      plan_id: results.plan_id,
      new_status: new_status,
      reason: "Execution completed with #{results.execution_summary.successful} successful tasks"
    }
  end
end