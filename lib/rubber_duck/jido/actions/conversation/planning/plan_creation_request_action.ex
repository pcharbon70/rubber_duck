defmodule RubberDuck.Jido.Actions.Conversation.Planning.PlanCreationRequestAction do
  @moduledoc """
  Action for handling plan creation requests.
  
  This action manages the initial phase of plan creation by:
  - Validating plan request data
  - Starting conversation tracking
  - Initiating async plan extraction and creation
  - Emitting creation started signals
  """
  
  use Jido.Action,
    name: "plan_creation_request",
    description: "Handles plan creation requests with validation and async processing",
    schema: [
      query: [type: :string, required: true, doc: "Natural language query for plan creation"],
      conversation_id: [type: :string, required: true, doc: "Unique conversation identifier"],
      user_id: [type: :string, required: true, doc: "User identifier"],
      context: [type: :map, default: %{}, doc: "Additional context for plan creation"],
      preferences: [type: :map, default: %{}, doc: "User preferences for plan creation"]
    ]

  require Logger
  
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  alias RubberDuck.Planning.Plan
  alias RubberDuck.LLM.Service, as: LLMService

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, validated_data} <- validate_plan_request(params),
         {:ok, conversation} <- start_conversation(validated_data),
         {:ok, updated_agent} <- update_conversation_state(agent, conversation),
         {:ok, _} <- emit_creation_started_signal(updated_agent, conversation) do
      
      # Start plan extraction asynchronously
      Task.start(fn ->
        extract_and_create_plan_async(updated_agent.id, conversation)
      end)
      
      {:ok, %{
        conversation_started: true,
        conversation_id: conversation.id,
        status: "extracting_plan"
      }, %{agent: updated_agent}}
    else
      {:error, reason} ->
        handle_plan_error(agent, params, reason)
    end
  end

  # Private functions

  defp validate_plan_request(params) do
    required_fields = [:query, :conversation_id, :user_id]
    
    missing_fields = Enum.filter(required_fields, fn field ->
      case Map.get(params, field) do
        nil -> true
        "" -> true
        _ -> false
      end
    end)
    
    if Enum.empty?(missing_fields) do
      {:ok, params}
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end

  defp start_conversation(data) do
    conversation = %{
      id: data.conversation_id,
      user_id: data.user_id,
      query: data.query,
      context: data.context,
      preferences: data.preferences,
      status: :extracting_plan,
      started_at: DateTime.utc_now(),
      plan_id: nil,
      validation_results: nil
    }
    
    {:ok, conversation}
  end

  defp update_conversation_state(agent, conversation) do
    conversations = Map.put(
      agent.state.active_conversations,
      conversation.id,
      conversation
    )
    
    # Update metrics
    active_count = map_size(conversations)
    updated_metrics = %{agent.state.metrics | active_conversations: active_count}
    
    state_updates = %{
      active_conversations: conversations,
      metrics: updated_metrics,
      conversation_state: if(active_count > 0, do: :active, else: :idle)
    }
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
      {:error, reason} -> {:error, reason}
    end
  end

  defp emit_creation_started_signal(agent, conversation) do
    signal_params = %{
      signal_type: "conversation.plan.creation_started",
      data: %{
        conversation_id: conversation.id,
        query: conversation.query,
        user_id: conversation.user_id,
        preferences: conversation.preferences,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp extract_and_create_plan_async(agent_id, conversation) do
    result = extract_plan_from_query(conversation)
    
    case result do
      {:ok, plan_data} ->
        case create_plan(plan_data) do
          {:ok, plan} ->
            emit_agent_signal(agent_id, %{
              "type" => "plan_created",
              "data" => %{
                "conversation_id" => conversation.id,
                "plan_id" => plan.id,
                "plan_name" => plan.name,
                "plan_type" => plan.type
              }
            })
            
          {:error, reason} ->
            emit_agent_signal(agent_id, %{
              "type" => "plan_creation_failed",
              "data" => %{
                "conversation_id" => conversation.id,
                "error" => inspect(reason)
              }
            })
        end
        
      {:error, reason} ->
        emit_agent_signal(agent_id, %{
          "type" => "plan_extraction_failed",
          "data" => %{
            "conversation_id" => conversation.id,
            "error" => inspect(reason)
          }
        })
    end
  end

  defp extract_plan_from_query(conversation) do
    messages = [
      %{
        role: "system",
        content: get_plan_extraction_prompt()
      },
      %{
        role: "user",
        content: conversation.query
      }
    ]
    
    llm_opts = [
      messages: messages,
      max_tokens: 2000,
      temperature: 0.7,
      response_format: %{type: "json_object"}
    ]
    
    case LLMService.completion(llm_opts) do
      {:ok, response} ->
        parse_plan_data(response, conversation)
        
      {:error, reason} ->
        {:error, {:llm_error, reason}}
    end
  end

  defp get_plan_extraction_prompt do
    """
    You are a planning assistant. Extract structured plan information from the user's query.
    
    You MUST respond with ONLY a valid JSON object (no other text) containing:
    - name: A concise name for the plan (string)
    - description: A detailed description of what needs to be done (string)
    - type: One of exactly these values: "feature", "refactor", "bugfix", "analysis", or "migration" (string)
    - tasks: Initial list of high-level tasks (array of strings, optional)
    - context: Relevant context from the query (object, optional)
    
    Example response format:
    {
      "name": "Implement User Authentication",
      "description": "Add JWT-based authentication to the Phoenix application",
      "type": "feature",
      "tasks": ["Set up JWT library", "Create auth context", "Add login endpoint"],
      "context": {"technology": "JWT", "framework": "Phoenix"}
    }
    
    Focus on understanding the user's intent and creating an actionable plan.
    IMPORTANT: Reply with ONLY the JSON object, no explanations or other text.
    """
  end

  defp parse_plan_data(response, conversation) do
    try do
      content = extract_content(response)
      
      case Jason.decode(content) do
        {:ok, data} when is_map(data) ->
          plan_data = %{
            name: ensure_unique_plan_name(data["name"] || "Untitled Plan"),
            description: data["description"] || conversation.query,
            type: parse_plan_type(data["type"]) || :feature,
            context: Map.merge(conversation.context, data["context"] || %{}),
            metadata: %{
              created_via: "planning_conversation_agent",
              conversation_id: conversation.id,
              user_id: conversation.user_id,
              initial_tasks: data["tasks"] || []
            }
          }
          
          {:ok, plan_data}
          
        _ ->
          {:error, :invalid_json_response}
      end
    rescue
      e ->
        Logger.error("Error parsing plan data: #{inspect(e)}")
        {:error, :parse_error}
    end
  end

  defp create_plan(attrs) do
    Plan
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(domain: RubberDuck.Planning)
  end

  defp ensure_unique_plan_name(base_name) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    "#{base_name} - #{timestamp}"
  end

  defp parse_plan_type(nil), do: nil
  defp parse_plan_type(type) when is_atom(type), do: type
  defp parse_plan_type(type) when is_binary(type) do
    case String.downcase(type) do
      "feature" -> :feature
      "refactor" -> :refactor
      "bugfix" -> :bugfix
      "analysis" -> :analysis
      "migration" -> :migration
      _ -> nil
    end
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

  defp handle_plan_error(agent, params, reason) do
    Logger.error("Plan creation error: #{inspect(reason)}")
    
    # Update failure metrics
    metrics_updates = %{
      metrics: update_in(agent.state.metrics.failed_conversations, &(&1 + 1))
    }
    
    with {:ok, _, %{agent: updated_agent}} <- UpdateStateAction.run(%{updates: metrics_updates}, %{agent: agent}),
         {:ok, _} <- emit_error_signal(updated_agent, params, reason) do
      {:error, reason}
    else
      {:error, update_error} ->
        Logger.error("Failed to update metrics after plan error: #{inspect(update_error)}")
        {:error, reason}
    end
  end

  defp emit_error_signal(agent, params, reason) do
    signal_params = %{
      signal_type: "conversation.plan.creation_error",
      data: %{
        conversation_id: params.conversation_id,
        error: inspect(reason),
        query: params.query,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  # Helper to emit signals to the agent (would go through signal router in production)
  defp emit_agent_signal(agent_id, signal) do
    # In production, this would go through the signal router
    Logger.info("Agent #{agent_id} would emit signal: #{inspect(signal)}")
  end
end