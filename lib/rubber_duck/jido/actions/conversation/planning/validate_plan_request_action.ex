defmodule RubberDuck.Jido.Actions.Conversation.Planning.ValidatePlanRequestAction do
  @moduledoc """
  Action for handling plan validation requests.
  
  This action manages plan validation by:
  - Finding the conversation and associated plan
  - Starting async validation process
  - Updating conversation status
  - Coordinating with Critics system
  """
  
  use Jido.Action,
    name: "validate_plan_request",
    description: "Handles plan validation requests with Critics system integration",
    schema: [
      conversation_id: [type: :string, required: true, doc: "Conversation identifier"],
      plan_id: [type: :string, required: true, doc: "Plan identifier to validate"]
    ]

  require Logger
  
  alias RubberDuck.Jido.Actions.Base.UpdateStateAction
  alias RubberDuck.Planning.Plan
  alias RubberDuck.Planning.Critics.Orchestrator

  @impl true
  def run(params, context) do
    agent = context.agent
    
    case agent.state.active_conversations[params.conversation_id] do
      nil ->
        Logger.warning("Validation requested for non-existent conversation: #{params.conversation_id}")
        {:ok, %{validated: false, reason: "conversation_not_found"}, %{agent: agent}}
      
      conversation ->
        with {:ok, updated_agent} <- update_conversation_status(agent, params, :validating),
             {:ok, _} <- start_validation_async(updated_agent.id, params, conversation) do
          {:ok, %{
            validation_started: true,
            conversation_id: params.conversation_id,
            plan_id: params.plan_id
          }, %{agent: updated_agent}}
        end
    end
  end

  # Private functions

  defp update_conversation_status(agent, params, status) do
    conversation = agent.state.active_conversations[params.conversation_id]
    
    updated_conversation = %{conversation | 
      status: status,
      plan_id: params.plan_id
    }
    
    state_updates = %{
      active_conversations: Map.put(agent.state.active_conversations, params.conversation_id, updated_conversation)
    }
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_validation_async(agent_id, params, conversation) do
    Task.start(fn ->
      validate_plan_async(agent_id, params, conversation)
    end)
    
    {:ok, :started}
  end

  defp validate_plan_async(agent_id, params, _conversation) do
    case validate_plan(params.plan_id) do
      {:ok, validation_results} ->
        emit_agent_signal(agent_id, %{
          "type" => "plan_validation_complete",
          "data" => %{
            "conversation_id" => params.conversation_id,
            "plan_id" => params.plan_id,
            "validation_results" => validation_results
          }
        })
        
      {:error, reason} ->
        emit_agent_signal(agent_id, %{
          "type" => "plan_validation_failed",
          "data" => %{
            "conversation_id" => params.conversation_id,
            "plan_id" => params.plan_id,
            "error" => inspect(reason)
          }
        })
    end
  end

  defp validate_plan(plan_id) do
    case Ash.get(Plan, plan_id, domain: RubberDuck.Planning) do
      {:ok, plan} ->
        # Load hierarchical structure
        {:ok, plan} = Ash.load(plan, [
          phases: [tasks: [:subtasks, :dependencies]],
          tasks: [:subtasks, :dependencies]
        ], domain: RubberDuck.Planning)
        
        orchestrator = Orchestrator.new()
        
        case Orchestrator.validate(orchestrator, plan) do
          {:ok, results} ->
            aggregated = Orchestrator.aggregate_results(results)
            {:ok, _} = Orchestrator.persist_results(plan, results)
            {:ok, aggregated}
            
          error ->
            error
        end
        
      error ->
        error
    end
  end

  # Helper to emit signals to the agent
  defp emit_agent_signal(agent_id, signal) do
    Logger.info("Agent #{agent_id} would emit signal: #{inspect(signal)}")
  end
end