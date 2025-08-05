defmodule RubberDuck.Workflows.PlanCreationWorkflowSimple do
  @moduledoc """
  Simplified Reactor workflow for creating plans.
  """
  
  use Reactor
  
  alias RubberDuck.Jido.Steps.{ExecuteAgentAction, SendAgentSignal}
  
  input :plan
  input :validate
  
  # Validate plan
  step :validate_plan do
    argument :plan, input(:plan)
    argument :should_validate, input(:validate)
    
    run fn args ->
      if args.should_validate do
        # Simple validation
        issues = []
        issues = if is_nil(args.plan[:name]) or args.plan[:name] == "" do
          [{:error, :missing_name, "Plan must have a name"} | issues]
        else
          issues
        end
        
        {:ok, %{
          plan_id: args.plan[:id],
          valid: Enum.empty?(issues),
          issues: issues
        }}
      else
        {:ok, %{
          plan_id: args.plan[:id],
          valid: true,
          issues: []
        }}
      end
    end
  end
  
  # Finalize plan
  step :finalize_plan do
    argument :validation_result, result(:validate_plan)
    
    wait_for :validate_plan
    
    run fn %{validation_result: result} ->
      status = if result.valid, do: :ready, else: :draft
      
      {:ok, %{
        plan_id: result.plan_id,
        status: status,
        validation: result
      }}
    end
  end
  
  return :finalize_plan
end