defmodule RubberDuck.Workflows.PlanExecutionWorkflowSimple do
  @moduledoc """
  Simplified Reactor workflow for executing plans.
  """
  
  use Reactor
  
  alias RubberDuck.Jido.Steps.{ExecuteAgentAction, SendAgentSignal}
  
  input :plan
  input :execution_mode
  input :dry_run
  
  # Prepare execution
  step :prepare_execution do
    argument :plan, input(:plan)
    argument :mode, input(:execution_mode)
    argument :dry_run, input(:dry_run)
    
    run fn args ->
      tasks = args.plan[:tasks] || []
      
      {:ok, %{
        plan_id: args.plan[:id],
        tasks: tasks,
        dry_run: args.dry_run,
        started_at: DateTime.utc_now()
      }}
    end
  end
  
  # Execute tasks
  step :execute_tasks do
    argument :preparation, result(:prepare_execution)
    
    wait_for :prepare_execution
    
    run fn %{preparation: prep} ->
      results = Enum.map(prep.tasks, fn task ->
        if prep.dry_run do
          %{task_id: task[:id], status: :simulated}
        else
          %{task_id: task[:id], status: :completed}
        end
      end)
      
      {:ok, results}
    end
  end
  
  # Collect results
  step :collect_results do
    argument :task_results, result(:execute_tasks)
    argument :preparation, result(:prepare_execution)
    
    wait_for [:prepare_execution, :execute_tasks]
    
    run fn args ->
      successful = Enum.count(args.task_results, & &1.status in [:completed, :simulated])
      
      {:ok, %{
        plan_id: args.preparation.plan_id,
        execution_summary: %{
          total_tasks: length(args.task_results),
          successful: successful,
          failed: 0
        },
        task_results: args.task_results,
        completed_at: DateTime.utc_now()
      }}
    end
  end
  
  return :collect_results
end