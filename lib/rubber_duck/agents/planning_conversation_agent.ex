defmodule RubberDuck.Agents.PlanningConversationAgent do
  @moduledoc """
  Autonomous agent that handles planning conversations through signal-based communication.
  
  This agent:
  - Creates plans from natural language queries
  - Validates plans using the Critics system
  - Manages conversation state for multi-step planning
  - Emits signals for real-time UI updates
  - Supports plan improvement and fixing flows
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "planning_conversation",
    description: "Handles plan creation and validation conversations",
    schema: [
      # Conversation state tracking
      conversation_state: [
        type: :atom,
        default: :idle,
        values: [:idle, :active, :processing]
      ],
      
      # Active conversations map
      active_conversations: [
        type: :map,
        default: %{}
      ],
      
      # Plan creation configuration
      config: [
        type: :map,
        default: %{
          max_tokens: 3000,
          temperature: 0.7,
          timeout: 60_000,
          auto_improve: true,
          auto_fix: true
        }
      ],
      
      # Metrics
      metrics: [
        type: :map,
        default: %{
          total_plans_created: 0,
          active_conversations: 0,
          completed_conversations: 0,
          failed_conversations: 0,
          validation_times: [],
          creation_times: [],
          improvement_count: 0,
          fix_count: 0
        }
      ],
      
      # Validation results cache
      validation_cache: [type: :map, default: %{}]
    ]
  
  require Logger
  
  alias RubberDuck.Planning.Plan
  alias RubberDuck.Planning.Critics.Orchestrator
  alias RubberDuck.Planning.{PlanImprover, PlanFixer}
  alias RubberDuck.LLM.Service, as: LLMService
  
  
  @impl true
  def handle_signal(agent, %{"type" => "plan_creation_request"} = signal) do
    with {:ok, data} <- validate_plan_request(signal["data"]),
         {:ok, conversation} <- start_conversation(data),
         {:ok, agent} <- update_conversation(agent, conversation) do
      
      # Emit conversation started signal
      emit_signal(agent, %{
        "type" => "plan_creation_started",
        "data" => %{
          "conversation_id" => conversation.id,
          "query" => data["query"],
          "user_id" => data["user_id"]
        }
      })
      
      # Start plan extraction asynchronously
      Task.start(fn ->
        extract_and_create_plan(agent.id, conversation)
      end)
      
      {:ok, agent}
    else
      {:error, reason} ->
        handle_plan_error(agent, signal, reason)
    end
  end
  
  def handle_signal(agent, %{"type" => "validate_plan_request"} = signal) do
    data = signal["data"]
    conversation_id = data["conversation_id"]
    plan_id = data["plan_id"]
    
    case get_conversation(agent, conversation_id) do
      {:ok, conversation} ->
        # Update conversation state
        conversation = %{conversation | 
          status: :validating,
          plan_id: plan_id
        }
        
        {:ok, agent} = update_conversation(agent, conversation)
        
        # Start validation asynchronously
        Task.start(fn ->
          validate_plan_async(agent.id, conversation)
        end)
        
        {:ok, agent}
        
      {:error, :not_found} ->
        {:ok, agent}  # Ignore validation for unknown conversations
    end
  end
  
  def handle_signal(agent, %{"type" => "improve_plan_request"} = signal) do
    data = signal["data"]
    conversation_id = data["conversation_id"]
    
    conversation = %{
      id: conversation_id,
      status: :improving,
      plan_id: data["plan_id"],
      validation_results: data["validation_results"]
    }
    
    {:ok, agent} = update_conversation(agent, conversation)
    
    # Start improvement asynchronously
    Task.start(fn ->
      improve_plan_async(agent.id, conversation, data["validation_results"])
    end)
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "complete_conversation"} = signal) do
    data = signal["data"]
    conversation_id = data["conversation_id"]
    
    case get_conversation(agent, conversation_id) do
      {:ok, conversation} ->
        # Update metrics
        metrics = agent.state.metrics
        updated_metrics = %{
          metrics |
          total_plans_created: metrics.total_plans_created + 1,
          completed_conversations: metrics.completed_conversations + 1,
          active_conversations: max(0, metrics.active_conversations - 1)
        }
        
        # Remove conversation
        conversations = Map.delete(agent.state.active_conversations, conversation_id)
        
        agent = update_state(agent, %{
          active_conversations: conversations,
          metrics: updated_metrics
        })
        
        # Emit completion signal
        emit_signal(agent, %{
          "type" => "plan_creation_completed",
          "data" => %{
            "conversation_id" => conversation_id,
            "plan_id" => data["plan_id"],
            "duration" => calculate_duration(conversation)
          }
        })
        
        {:ok, agent}
        
      {:error, :not_found} ->
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "get_planning_metrics"} = _signal) do
    metrics_signal = %{
      "type" => "planning_metrics_response",
      "source" => "agent:#{agent.id}",
      "data" => agent.state.metrics
    }
    
    emit_signal(agent, metrics_signal)
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "plan_created"} = signal) do
    # Internal signal when plan is created
    data = signal["data"]
    conversation_id = data["conversation_id"]
    
    case get_conversation(agent, conversation_id) do
      {:ok, conversation} ->
        conversation = %{conversation | 
          status: :validating,
          plan_id: data["plan_id"]
        }
        
        {:ok, agent} = update_conversation(agent, conversation)
        
        # Start validation
        Task.start(fn ->
          validate_plan_async(agent.id, conversation)
        end)
        
        {:ok, agent}
        
      _ ->
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "plan_validation_complete"} = signal) do
    # Internal signal when validation is complete
    data = signal["data"]
    conversation_id = data["conversation_id"]
    
    case get_conversation(agent, conversation_id) do
      {:ok, conversation} ->
        handle_validation_results(agent, conversation, data["validation_results"])
        
      _ ->
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, signal) do
    # Let parent handle unknown signals
    super(agent, signal)
  end
  
  # Private functions
  
  defp validate_plan_request(data) when is_map(data) do
    required_fields = ["query", "conversation_id", "user_id"]
    
    missing_fields = Enum.filter(required_fields, &(not Map.has_key?(data, &1)))
    
    if Enum.empty?(missing_fields) do
      {:ok, data}
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end
  
  defp validate_plan_request(_), do: {:error, :invalid_request_data}
  
  defp start_conversation(data) do
    conversation = %{
      id: data["conversation_id"],
      user_id: data["user_id"],
      query: data["query"],
      context: data["context"] || %{},
      status: :extracting_plan,
      started_at: DateTime.utc_now(),
      plan_id: nil,
      validation_results: nil
    }
    
    {:ok, conversation}
  end
  
  defp update_conversation(agent, conversation) do
    conversations = Map.put(
      agent.state.active_conversations,
      conversation.id,
      conversation
    )
    
    # Update metrics
    metrics = agent.state.metrics
    active_count = map_size(conversations)
    
    updated_metrics = %{metrics | active_conversations: active_count}
    
    {:ok, update_state(agent, %{
      active_conversations: conversations,
      metrics: updated_metrics,
      conversation_state: if(active_count > 0, do: :active, else: :idle)
    })}
  end
  
  defp get_conversation(agent, conversation_id) do
    case Map.get(agent.state.active_conversations, conversation_id) do
      nil -> {:error, :not_found}
      conversation -> {:ok, conversation}
    end
  end
  
  # Async operations that emit signals back to the agent
  
  defp extract_and_create_plan(agent_id, conversation) do
    result = extract_plan_from_query(conversation)
    
    case result do
      {:ok, plan_data} ->
        # Create the plan
        case create_plan(plan_data) do
          {:ok, plan} ->
            # Emit plan created signal
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
  
  defp validate_plan_async(agent_id, conversation) do
    case validate_plan(conversation.plan_id) do
      {:ok, validation_results} ->
        emit_agent_signal(agent_id, %{
          "type" => "plan_validation_complete",
          "data" => %{
            "conversation_id" => conversation.id,
            "plan_id" => conversation.plan_id,
            "validation_results" => validation_results
          }
        })
        
      {:error, reason} ->
        emit_agent_signal(agent_id, %{
          "type" => "plan_validation_failed",
          "data" => %{
            "conversation_id" => conversation.id,
            "plan_id" => conversation.plan_id,
            "error" => inspect(reason)
          }
        })
    end
  end
  
  defp improve_plan_async(agent_id, conversation, validation_results) do
    case improve_plan(conversation.plan_id, validation_results) do
      {:ok, improved_plan, new_validation} ->
        emit_agent_signal(agent_id, %{
          "type" => "plan_improvement_completed",
          "data" => %{
            "conversation_id" => conversation.id,
            "original_plan_id" => conversation.plan_id,
            "improved_plan_id" => improved_plan.id,
            "new_validation" => new_validation
          }
        })
        
      {:error, _reason} ->
        # Continue with original plan despite improvement failure
        emit_agent_signal(agent_id, %{
          "type" => "complete_conversation",
          "data" => %{
            "conversation_id" => conversation.id,
            "plan_id" => conversation.plan_id,
            "status" => "completed_with_warnings"
          }
        })
    end
  end
  
  defp extract_plan_from_query(conversation) do
    # Similar to PlanningConversation engine but returns result for signal
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
  
  defp improve_plan(plan_id, validation_results) do
    case Ash.get(Plan, plan_id, domain: RubberDuck.Planning) do
      {:ok, plan} ->
        case PlanImprover.improve(plan, validation_results) do
          {:ok, improved_plan, new_validation} ->
            {:ok, improved_plan, new_validation}
            
          error ->
            error
        end
        
      error ->
        error
    end
  end
  
  defp handle_validation_results(agent, conversation, validation_results) do
    summary = validation_results["summary"] || validation_results[:summary]
    
    # Emit validation result signal
    emit_signal(agent, %{
      "type" => "plan_validation_result",
      "data" => %{
        "conversation_id" => conversation.id,
        "plan_id" => conversation.plan_id,
        "validation_summary" => summary,
        "validation_results" => validation_results
      }
    })
    
    # Check if improvement or fixing is needed
    cond do
      agent.state.config.auto_fix && summary in [:failed, "failed"] ->
        # Update conversation state
        conversation = %{conversation | status: :fixing}
        {:ok, agent} = update_conversation(agent, conversation)
        
        # Start fix operation
        Task.start(fn ->
          fix_plan_async(agent.id, conversation, validation_results)
        end)
        
        # Update metrics
        metrics = update_in(agent.state.metrics.fix_count, &(&1 + 1))
        {:ok, update_state(agent, %{metrics: metrics})}
        
      agent.state.config.auto_improve && summary in [:warning, "warning"] ->
        # Update conversation state
        conversation = %{conversation | status: :improving}
        {:ok, agent} = update_conversation(agent, conversation)
        
        # Start improvement operation
        Task.start(fn ->
          improve_plan_async(agent.id, conversation, validation_results)
        end)
        
        # Update metrics
        metrics = update_in(agent.state.metrics.improvement_count, &(&1 + 1))
        {:ok, update_state(agent, %{metrics: metrics})}
        
      true ->
        # Plan is ready, complete the conversation
        complete_conversation(agent, conversation)
    end
  end
  
  defp fix_plan_async(agent_id, conversation, validation_results) do
    case fix_plan(conversation.plan_id, validation_results) do
      {:ok, fixed_plan, new_validation} ->
        emit_agent_signal(agent_id, %{
          "type" => "plan_fix_completed",
          "data" => %{
            "conversation_id" => conversation.id,
            "original_plan_id" => conversation.plan_id,
            "fixed_plan_id" => fixed_plan.id,
            "new_validation" => new_validation
          }
        })
        
      {:error, reason} ->
        # Cannot fix, fail the conversation
        emit_agent_signal(agent_id, %{
          "type" => "plan_creation_failed",
          "data" => %{
            "conversation_id" => conversation.id,
            "error" => "Failed to fix plan: #{inspect(reason)}"
          }
        })
    end
  end
  
  defp fix_plan(plan_id, validation_results) do
    case Ash.get(Plan, plan_id, domain: RubberDuck.Planning) do
      {:ok, plan} ->
        case PlanFixer.fix(plan, validation_results) do
          {:ok, fixed_plan, new_validation} ->
            {:ok, fixed_plan, new_validation}
            
          error ->
            error
        end
        
      error ->
        error
    end
  end
  
  defp complete_conversation(agent, conversation) do
    # Send completion signal
    handle_signal(agent, %{
      "type" => "complete_conversation",
      "data" => %{
        "conversation_id" => conversation.id,
        "plan_id" => conversation.plan_id,
        "status" => "completed"
      }
    })
  end
  
  defp handle_plan_error(agent, signal, reason) do
    Logger.error("Plan creation error: #{inspect(reason)}")
    
    error_signal = %{
      "type" => "plan_creation_error",
      "source" => "agent:#{agent.id}",
      "data" => %{
        "conversation_id" => get_in(signal, ["data", "conversation_id"]),
        "error" => inspect(reason)
      }
    }
    
    emit_signal(agent, error_signal)
    
    # Update failure metrics
    metrics = update_in(agent.state.metrics.failed_conversations, &(&1 + 1))
    {:ok, update_state(agent, %{metrics: metrics})}
  end
  
  defp create_plan(attrs) do
    Plan
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(domain: RubberDuck.Planning)
  end
  
  defp calculate_duration(conversation) do
    if conversation.started_at do
      DateTime.diff(DateTime.utc_now(), conversation.started_at, :millisecond)
    else
      0
    end
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
  
  # Helper to emit signals to the agent (would go through signal router in production)
  defp emit_agent_signal(agent_id, signal) do
    # In production, this would go through the signal router
    # For now, we'll log it
    Logger.info("Agent #{agent_id} would emit signal: #{inspect(signal)}")
  end
end