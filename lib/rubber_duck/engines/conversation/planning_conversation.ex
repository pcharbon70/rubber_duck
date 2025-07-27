defmodule RubberDuck.Engines.Conversation.PlanningConversation do
  @moduledoc """
  Engine for handling planning-related conversations.

  This engine handles:
  - Plan creation requests
  - Task decomposition discussions
  - Planning strategy conversations
  - Execution planning
  - Project planning and architecture

  It integrates with the Planning domain to create and manage plans.
  """

  @behaviour RubberDuck.Engine

  require Logger

  alias RubberDuck.Planning.{Plan, Task}
  alias RubberDuck.Planning.Critics.Orchestrator
  alias RubberDuck.Planning.Decomposer
  alias RubberDuck.Engine.InputValidator
  alias RubberDuck.LLM.Service, as: LLMService

  @impl true
  def init(config) do
    state = %{
      config: config,
      max_tokens: config[:max_tokens] || 3000,
      temperature: config[:temperature] || 0.7,
      timeout: config[:timeout] || 60_000
    }

    {:ok, state}
  end

  @impl true
  def execute(input, state) do
    with {:ok, validated} <- validate_input(input),
         {:ok, plan_data} <- extract_plan_from_query(validated, state),
         {:ok, plan} <- create_and_validate_plan(plan_data, validated),
         {:ok, response} <- format_planning_response(plan, validated) do
      
      result = %{
        query: validated.query,
        response: response,
        conversation_type: :planning,
        plan: serialize_plan(plan),
        validation_summary: plan.validation_results["initial"][:summary],
        ready_for_execution: plan_ready?(plan),
        processing_time: System.monotonic_time(:millisecond) - validated.start_time,
        metadata: %{
          provider: validated.provider,
          model: validated.model,
          temperature: validated.temperature || state.temperature,
          max_tokens: validated.max_tokens || state.max_tokens,
          plan_type: plan.type,
          plan_id: plan.id
        }
      }

      Logger.info("Planning conversation completed for plan: #{plan.id}")
      {:ok, result}
    end
  end

  @impl true
  def capabilities do
    [:plan_creation, :task_decomposition, :planning_strategy, :execution_planning, :project_architecture]
  end

  # Private functions

  defp validate_input(%{query: query} = input) when is_binary(query) do
    case InputValidator.validate_llm_input(input, [:query]) do
      {:ok, validated} ->
        {:ok, Map.merge(validated, %{
          query: String.trim(query),
          start_time: System.monotonic_time(:millisecond),
          llm_config: Map.get(input, :llm_config, %{})
        })}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_input(_), do: {:error, :invalid_input}

  defp extract_plan_from_query(validated, state) do
    # Use LLM to extract structured plan information from the query
    messages = [
      %{
        role: "system",
        content: """
        You are a planning assistant. Extract structured plan information from the user's query.
        
        Respond with a JSON object containing:
        - name: A concise name for the plan
        - description: A detailed description of what needs to be done
        - type: One of [feature, refactor, bugfix, analysis, migration]
        - tasks: Initial list of high-level tasks (optional)
        - context: Relevant context from the query
        
        Focus on understanding the user's intent and creating an actionable plan.
        """
      },
      %{
        role: "user",
        content: validated.query
      }
    ]

    llm_opts = InputValidator.build_llm_opts(validated, messages, state)
    
    case LLMService.completion(llm_opts) do
      {:ok, response} ->
        parse_plan_data(response, validated)
      
      {:error, reason} ->
        Logger.error("Failed to extract plan from query: #{inspect(reason)}")
        {:error, {:llm_error, reason}}
    end
  end

  defp parse_plan_data(response, validated) do
    try do
      content = extract_content(response)
      
      # Try to parse JSON from the response
      case Jason.decode(content) do
        {:ok, data} ->
          plan_data = %{
            name: data["name"] || generate_plan_name(validated.query),
            description: data["description"] || validated.query,
            type: String.to_existing_atom(data["type"] || "feature"),
            context: Map.merge(validated.context, data["context"] || %{}),
            metadata: %{
              created_via: "planning_conversation",
              user_id: validated.user_id,
              initial_tasks: data["tasks"] || []
            }
          }
          
          {:ok, plan_data}
        
        {:error, _} ->
          # Fallback to basic extraction
          {:ok, %{
            name: generate_plan_name(validated.query),
            description: validated.query,
            type: detect_plan_type(validated.query),
            context: validated.context,
            metadata: %{
              created_via: "planning_conversation",
              user_id: validated.user_id
            }
          }}
      end
    rescue
      e ->
        Logger.error("Error parsing plan data: #{inspect(e)}")
        {:error, :plan_extraction_failed}
    end
  end

  defp create_and_validate_plan(plan_data, validated) do
    # Create the plan
    with {:ok, plan} <- create_plan(plan_data),
         {:ok, validation_results} <- validate_plan(plan) do
      
      # Update plan with validation results
      {:ok, updated_plan} = plan
        |> Ash.Changeset.for_update(:add_validation_result, %{
          validation_results: %{"initial" => validation_results}
        })
        |> Ash.update()
      
      # If there are initial tasks, decompose and create them
      case plan_data.metadata[:initial_tasks] do
        tasks when is_list(tasks) and tasks != [] ->
          create_initial_tasks(updated_plan, tasks)
        
        _ ->
          # Use TaskDecomposer for complex plans
          if should_decompose?(updated_plan) do
            decompose_plan_tasks(updated_plan, validated)
          else
            {:ok, updated_plan}
          end
      end
    end
  end

  defp create_plan(attrs) do
    Plan
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  defp validate_plan(plan) do
    orchestrator = Orchestrator.new()
    
    case Orchestrator.validate(orchestrator, plan) do
      {:ok, results} ->
        aggregated = Orchestrator.aggregate_results(results)
        {:ok, _} = Orchestrator.persist_results(plan, results)
        {:ok, aggregated}
      
      error ->
        Logger.error("Plan validation failed: #{inspect(error)}")
        error
    end
  end

  defp create_initial_tasks(plan, task_descriptions) do
    tasks = task_descriptions
      |> Enum.with_index()
      |> Enum.map(fn {desc, index} ->
        %{
          plan_id: plan.id,
          name: extract_task_name(desc),
          description: desc,
          position: index,
          complexity: :medium,
          status: :pending
        }
      end)
    
    # Create tasks in batch
    case Ash.bulk_create(Task, tasks, 
      domain: RubberDuck.Planning,
      return_records?: true
    ) do
      %{records: created_tasks} when is_list(created_tasks) ->
        {:ok, %{plan | tasks: created_tasks}}
      
      error ->
        Logger.error("Failed to create tasks: #{inspect(error)}")
        {:ok, plan}  # Continue without tasks
    end
  end

  defp decompose_plan_tasks(plan, validated) do
    context = %{
      plan_type: plan.type,
      user_id: validated.user_id,
      language: validated.context[:language] || "elixir",
      constraints: plan.constraints_data || %{},
      strategy: determine_decomposition_strategy(plan)
    }
    
    # Use the Decomposer to break down the plan into tasks
    case Decomposer.decompose(plan.description, context) do
      {:ok, tasks} ->
        # Convert decomposer output to Task resources
        task_attrs = tasks
          |> Enum.map(fn task ->
            %{
              plan_id: plan.id,
              name: task[:name],
              description: task[:description],
              position: task[:position],
              complexity: ensure_atom(task[:complexity]),
              status: :pending,
              success_criteria: task[:success_criteria],
              validation_rules: task[:validation_rules],
              metadata: task[:metadata] || %{}
            }
          end)
        
        # Create tasks in batch
        case Ash.bulk_create(Task, task_attrs, 
          domain: RubberDuck.Planning,
          return_records?: true, 
          return_errors?: true
        ) do
          %{records: created_tasks} when is_list(created_tasks) ->
            {:ok, %{plan | tasks: created_tasks}}
          
          %{errors: errors} ->
            Logger.error("Failed to create tasks: #{inspect(errors)}")
            {:ok, plan}  # Continue without tasks
          
          error ->
            Logger.error("Failed to create tasks: #{inspect(error)}")
            {:ok, plan}  # Continue without tasks
        end
      
      {:error, reason} ->
        Logger.error("Task decomposition failed for plan #{plan.id}: #{inspect(reason)}")
        {:ok, plan}  # Continue without decomposition
    end
  end
  
  defp determine_decomposition_strategy(plan) do
    case plan.type do
      :feature -> :hierarchical
      :refactor -> :linear
      :bugfix -> :linear
      :analysis -> :tree_of_thought
      :migration -> :linear
      _ -> :hierarchical
    end
  end
  
  defp ensure_atom(value) when is_atom(value), do: value
  defp ensure_atom(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> :medium
    end
  end
  defp ensure_atom(_), do: :medium


  defp format_planning_response(plan, _validated) do
    validation_summary = plan.validation_results["initial"]
    
    response = """
    I've created a #{plan.type} plan: "#{plan.name}"

    #{format_plan_details(plan)}

    #{format_validation_summary(validation_summary)}

    #{format_next_steps(plan, validation_summary)}
    """
    
    {:ok, String.trim(response)}
  end

  defp format_plan_details(plan) do
    task_count = length(plan.tasks || [])
    
    details = ["**Plan Details:**"]
    details = details ++ ["- Type: #{plan.type}"]
    details = details ++ ["- Status: #{plan.status}"]
    
    if task_count > 0 do
      details ++ ["- Tasks: #{task_count} tasks identified"]
    else
      details
    end
    |> Enum.join("\n")
  end

  defp format_validation_summary(%{summary: summary} = validation) do
    case summary do
      :passed ->
        "✅ **Validation Status:** All checks passed! The plan is ready for execution."
      
      :warning ->
        _warnings = validation[:soft_critics] || []
        """
        ⚠️  **Validation Status:** Passed with warnings
        
        Suggestions for improvement:
        #{format_suggestions(validation[:suggestions] || [])}
        """
      
      :failed ->
        issues = validation[:blocking_issues] || []
        """
        ❌ **Validation Status:** Failed - blocking issues found
        
        **Blocking Issues:**
        #{format_blocking_issues(issues)}
        
        These issues must be resolved before the plan can be executed.
        """
      
      _ ->
        "**Validation Status:** Unknown"
    end
  end

  defp format_next_steps(plan, _validation) do
    if plan_ready?(plan) do
      """
      **Next Steps:**
      1. Review the plan details
      2. Execute the plan using the plan ID: `#{plan.id}`
      3. Monitor progress through the planning channel
      """
    else
      """
      **Next Steps:**
      1. Address the validation issues
      2. Update the plan with corrections
      3. Re-validate before execution
      """
    end
  end

  defp format_suggestions(suggestions) when is_list(suggestions) do
    suggestions
    |> Enum.map(fn s -> "- #{s}" end)
    |> Enum.join("\n")
  end
  defp format_suggestions(_), do: "No specific suggestions"

  defp format_blocking_issues(issues) when is_list(issues) do
    issues
    |> Enum.map(fn issue ->
      "- #{issue[:message] || inspect(issue)}"
    end)
    |> Enum.join("\n")
  end
  defp format_blocking_issues(_), do: "No specific issues listed"

  defp serialize_plan(plan) do
    %{
      id: plan.id,
      name: plan.name,
      description: plan.description,
      type: plan.type,
      status: plan.status,
      task_count: length(plan.tasks || []),
      validation_status: plan.validation_results["initial"][:summary]
    }
  end

  defp plan_ready?(%{validation_results: %{"initial" => %{summary: :failed}}}), do: false
  defp plan_ready?(%{status: :ready}), do: true
  defp plan_ready?(%{status: :draft, validation_results: %{"initial" => %{summary: summary}}}) 
    when summary in [:passed, :warning], do: true
  defp plan_ready?(_), do: false

  defp should_decompose?(plan) do
    # Decompose complex plans or those without tasks
    plan.type in [:feature, :refactor, :migration] and 
      (plan.tasks == nil or plan.tasks == [])
  end

  defp generate_plan_name(query) do
    # Extract a concise name from the query
    words = query
      |> String.split()
      |> Enum.take(5)
      |> Enum.join(" ")
    
    "Plan: #{words}"
  end

  defp detect_plan_type(query) do
    query_lower = String.downcase(query)
    
    cond do
      String.contains?(query_lower, ["feature", "implement", "add", "create"]) -> :feature
      String.contains?(query_lower, ["refactor", "improve", "optimize"]) -> :refactor
      String.contains?(query_lower, ["fix", "bug", "error", "issue"]) -> :bugfix
      String.contains?(query_lower, ["analyze", "review", "audit"]) -> :analysis
      String.contains?(query_lower, ["migrate", "upgrade", "update"]) -> :migration
      true -> :feature
    end
  end

  defp extract_task_name(description) when is_binary(description) do
    description
    |> String.split()
    |> Enum.take(4)
    |> Enum.join(" ")
  end
  defp extract_task_name(_), do: "Task"

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