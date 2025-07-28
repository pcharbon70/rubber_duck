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
  alias RubberDuck.Planning.{Decomposer, PlanImprover, PlanFixer, HierarchicalPlanBuilder}
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
      },
      %{
        role: "user",
        content: validated.query
      }
    ]

    llm_opts = InputValidator.build_llm_opts(validated, messages, state)
    # Add response_format if the provider supports it
    # InputValidator.build_llm_opts returns a keyword list
    llm_opts = Keyword.put(llm_opts, :response_format, %{type: "json_object"})
    
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
      
      # Log the content for debugging
      Logger.debug("LLM response content: #{inspect(String.slice(content, 0, 200))}...")
      
      # Try to parse JSON from the response
      case Jason.decode(content) do
        {:ok, data} when is_map(data) ->
          # Make plan name unique by adding timestamp if needed
          base_name = data["name"] || generate_plan_name(validated.query)
          unique_name = ensure_unique_plan_name(base_name)
          
          plan_data = %{
            name: unique_name,
            description: data["description"] || validated.query,
            type: parse_plan_type(data["type"]) || detect_plan_type(validated.query),
            context: Map.merge(validated.context || %{}, data["context"] || %{}),
            metadata: %{
              created_via: "planning_conversation",
              user_id: validated.user_id,
              initial_tasks: data["tasks"] || []
            }
          }
          
          {:ok, plan_data}
        
        {:ok, _non_map_data} ->
          # JSON decode succeeded but didn't return a map (e.g., returned a string)
          Logger.warning("LLM returned non-JSON response, falling back to basic extraction")
          {:ok, %{
            name: ensure_unique_plan_name(generate_plan_name(validated.query)),
            description: validated.query,
            type: detect_plan_type(validated.query),
            context: validated.context || %{},
            metadata: %{
              created_via: "planning_conversation",
              user_id: validated.user_id,
              fallback_reason: "LLM returned plain text instead of JSON"
            }
          }}
        
        {:error, %Jason.DecodeError{}} ->
          Logger.warning("Failed to parse JSON, falling back to basic extraction")
          # Fallback to basic extraction
          {:ok, %{
            name: ensure_unique_plan_name(generate_plan_name(validated.query)),
            description: validated.query,
            type: detect_plan_type(validated.query),
            context: validated.context || %{},
            metadata: %{
              created_via: "planning_conversation",
              user_id: validated.user_id
            }
          }}
        
        other ->
          Logger.error("Unexpected JSON decode result: #{inspect(other)}")
          {:error, :invalid_json_response}
      end
    rescue
      e ->
        Logger.error("Error parsing plan data: #{inspect(e)}")
        # Still try to create a basic plan instead of failing completely
        {:ok, %{
          name: ensure_unique_plan_name(generate_plan_name(validated.query)),
          description: validated.query,
          type: detect_plan_type(validated.query),
          context: validated.context || %{},
          metadata: %{
            created_via: "planning_conversation", 
            user_id: validated.user_id,
            error: "Failed to parse LLM response"
          }
        }}
    end
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

  defp create_and_validate_plan(plan_data, validated) do
    # Create the plan
    with {:ok, plan} <- create_plan(plan_data),
         {:ok, validation_results} <- validate_plan(plan),
         {:ok, improved_plan, final_validation} <- maybe_improve_plan(plan, validation_results) do
      
      # Update plan with final validation results
      {:ok, updated_plan} = improved_plan
        |> Ash.Changeset.for_update(:add_validation_result, %{
          validation_results: %{"initial" => final_validation}
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
  
  defp maybe_improve_plan(plan, validation_results) do
    # Check if automatic improvement is enabled (default: true)
    auto_improve = Application.get_env(:rubber_duck, :auto_improve_plans, true)
    auto_fix = Application.get_env(:rubber_duck, :auto_fix_plans, true)
    
    validation_summary = validation_results["summary"] || validation_results[:summary]
    
    cond do
      auto_fix && (validation_summary == :failed || validation_summary == "failed") ->
        Logger.info("Plan validation failed, attempting automatic fixes")
        
        case PlanFixer.fix(plan, validation_results) do
          {:ok, fixed_plan, new_validation} ->
            Logger.info("Plan successfully fixed")
            # Mark that the plan was auto-fixed
            updated_fixed_plan = %{fixed_plan | 
              metadata: Map.put(fixed_plan.metadata || %{}, "auto_fixed", true)
            }
            {:ok, updated_fixed_plan, new_validation}
            
          error ->
            Logger.warning("Plan fix failed: #{inspect(error)}, returning failed validation")
            {:ok, plan, validation_results}
        end
        
      auto_improve && (validation_summary == :warning || validation_summary == "warning") ->
        Logger.info("Plan has warnings, attempting automatic improvement")
        
        case PlanImprover.improve(plan, validation_results) do
          {:ok, improved_plan, new_validation} ->
            Logger.info("Plan successfully improved")
            {:ok, improved_plan, new_validation}
            
          error ->
            Logger.warning("Plan improvement failed: #{inspect(error)}, using original plan")
            {:ok, plan, validation_results}
        end
        
      true ->
        # No improvement needed or disabled
        {:ok, plan, validation_results}
    end
  end

  defp create_plan(attrs) do
    Plan
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  defp validate_plan(plan) do
    # Ensure full hierarchical structure is loaded for validation
    plan = case Ash.load(plan, [
      phases: [tasks: [:subtasks, :dependencies]],
      tasks: [:subtasks, :dependencies]
    ], domain: RubberDuck.Planning) do
      {:ok, loaded} -> loaded
      _ -> plan
    end
    
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
          complexity: :medium
          # status is set automatically to :pending by the create action
        }
      end)
    
    # Create tasks in batch
    # Try creating tasks individually to avoid bulk_create domain issues
    created_tasks = tasks
    |> Enum.map(fn task_attrs ->
      case Ash.create(Task, task_attrs, domain: RubberDuck.Planning) do
        {:ok, task} -> task
        {:error, error} -> 
          Logger.error("Failed to create task: #{inspect(error)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    
    if length(created_tasks) > 0 do
      {:ok, %{plan | tasks: created_tasks}}
    else
      Logger.error("Failed to create any tasks")
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
      {:ok, tasks} when is_list(tasks) ->
        # Check if we got hierarchical data (with phases) or just tasks
        # If decomposer returns a list, it's simple tasks
        HierarchicalPlanBuilder.build_tasks_only(plan, tasks, domain: RubberDuck.Planning)
      
      {:ok, decomposition_data} when is_map(decomposition_data) ->
        # Check if we got hierarchical data (with phases)
        has_phases = Map.has_key?(decomposition_data, "phases") || Map.has_key?(decomposition_data, :phases)
        
        if has_phases do
          # Use hierarchical plan builder for phase-based plans
          HierarchicalPlanBuilder.build_plan(plan, decomposition_data, domain: RubberDuck.Planning)
        else
          # Convert map to task list if it has "tasks" key
          tasks = decomposition_data["tasks"] || decomposition_data[:tasks] || []
          HierarchicalPlanBuilder.build_tasks_only(plan, tasks, domain: RubberDuck.Planning)
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


  defp format_planning_response(plan, _validated) do
    validation_summary = plan.validation_results["initial"]
    
    # Check if plan was improved or fixed
    auto_note = cond do
      plan.metadata && Map.get(plan.metadata, "auto_fixed") ->
        "\n🔧 **Note:** This plan was automatically fixed to resolve validation failures."
        
      plan.metadata && Map.get(plan.metadata, "auto_improved") ->
        "\n💡 **Note:** This plan was automatically improved to address validation warnings."
        
      true ->
        ""
    end
    
    response = """
    I've created a #{plan.type} plan: "#{plan.name}"

    #{format_plan_details(plan)}

    #{format_validation_summary(validation_summary)}#{auto_note}

    #{format_next_steps(plan, validation_summary)}
    """
    
    {:ok, String.trim(response)}
  end

  defp format_plan_details(plan) do
    # Load hierarchical structure if needed
    plan = case plan do
      %{phases: %Ash.NotLoaded{}} ->
        case Ash.load(plan, [:phases, :tasks], domain: RubberDuck.Planning) do
          {:ok, loaded} -> loaded
          _ -> plan
        end
      _ -> plan
    end
    
    # Count phases and tasks
    phase_count = case plan.phases do
      phases when is_list(phases) -> length(phases)
      _ -> 0
    end
    
    task_count = case plan.tasks do
      tasks when is_list(tasks) -> length(tasks)
      _ -> 0
    end
    
    details = ["**Plan Details:**"]
    details = details ++ ["- Type: #{plan.type}"]
    details = details ++ ["- Status: #{plan.status}"]
    
    details = if phase_count > 0 do
      details ++ ["- Structure: #{phase_count} phases"]
    else
      details
    end
    
    if task_count > 0 do
      details ++ ["- Tasks: #{task_count} tasks identified"]
    else
      details
    end
    |> Enum.join("\n")
  end

  defp format_validation_summary(validation) when is_map(validation) do
    # Handle both atom and string keys
    summary = validation[:summary] || validation["summary"]
    
    case summary do
      :passed ->
        "✅ **Validation Status:** All checks passed! The plan is ready for execution."
      
      :warning ->
        suggestions = validation[:suggestions] || validation["suggestions"] || []
        """
        ⚠️  **Validation Status:** Passed with warnings
        
        Suggestions for improvement:
        #{format_suggestions(suggestions)}
        """
      
      :failed ->
        issues = validation[:blocking_issues] || validation["blocking_issues"] || []
        """
        ❌ **Validation Status:** Failed - blocking issues found
        
        **Blocking Issues:**
        #{format_blocking_issues(issues)}
        
        These issues must be resolved before the plan can be executed.
        """
      
      "passed" ->
        "✅ **Validation Status:** All checks passed! The plan is ready for execution."
      
      "warning" ->
        suggestions = validation[:suggestions] || validation["suggestions"] || []
        """
        ⚠️  **Validation Status:** Passed with warnings
        
        Suggestions for improvement:
        #{format_suggestions(suggestions)}
        """
      
      "failed" ->
        issues = validation[:blocking_issues] || validation["blocking_issues"] || []
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
  
  defp format_validation_summary(_) do
    "**Validation Status:** No validation data available"
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
    # Load plan with hierarchical structure if not already loaded
    plan = case plan do
      %{phases: %Ash.NotLoaded{}} -> 
        {:ok, loaded} = Ash.load(plan, [phases: [tasks: :subtasks]], domain: RubberDuck.Planning)
        loaded
      _ -> plan
    end
    
    # Serialize phases if they exist
    phases = case plan do
      %{phases: phases} when is_list(phases) and phases != [] ->
        Enum.map(phases, &serialize_phase/1)
      _ -> nil
    end
    
    # Handle case where tasks might not be loaded or are orphan tasks (no phase)
    orphan_tasks = case plan.tasks do
      tasks when is_list(tasks) -> 
        # Only serialize tasks that don't belong to a phase
        tasks
        |> Enum.filter(& is_nil(&1.phase_id))
        |> Enum.map(&serialize_task/1)
      %Ash.NotLoaded{} -> []
      nil -> []
    end
    
    # Calculate total task count across all phases and orphan tasks
    total_task_count = if phases do
      phase_task_count = phases |> Enum.reduce(0, fn phase, acc -> 
        acc + length(phase.tasks || [])
      end)
      phase_task_count + length(orphan_tasks)
    else
      length(orphan_tasks)
    end
    
    %{
      id: plan.id,
      name: plan.name,
      description: plan.description,
      type: plan.type,
      status: plan.status,
      context: plan.context,
      metadata: plan.metadata,
      phases: phases,
      orphan_tasks: orphan_tasks,  # Tasks not belonging to any phase
      task_count: total_task_count,
      created_at: plan.created_at,
      updated_at: plan.updated_at
    }
  end
  
  defp serialize_phase(phase) do
    %{
      id: phase.id,
      name: phase.name,
      description: phase.description,
      position: phase.position,
      number: phase.metadata["number"],
      metadata: phase.metadata,
      tasks: serialize_tasks_with_subtasks(phase.tasks || [])
    }
  end
  
  defp serialize_tasks_with_subtasks(tasks) do
    # Only serialize top-level tasks (those without parent_id)
    tasks
    |> Enum.filter(& is_nil(&1.parent_id))
    |> Enum.map(&serialize_task_with_subtasks/1)
  end
  
  defp serialize_task_with_subtasks(task) do
    base_task = serialize_task(task)
    
    # Add subtasks if they exist
    case task do
      %{subtasks: subtasks} when is_list(subtasks) and subtasks != [] ->
        Map.put(base_task, :subtasks, Enum.map(subtasks, &serialize_task_with_subtasks/1))
      _ ->
        base_task
    end
  end
  
  defp serialize_task(task) do
    %{
      id: task.id,
      name: task.name,
      description: task.description,
      position: task.position,
      number: task.number,
      status: task.status,
      complexity: task.complexity,
      success_criteria: task.success_criteria,
      metadata: task.metadata,
      dependencies: serialize_dependencies(task)
    }
  end
  
  defp serialize_dependencies(task) do
    case task.dependencies do
      deps when is_list(deps) -> deps
      %Ash.NotLoaded{} -> []
      nil -> []
    end
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
  
  defp ensure_unique_plan_name(base_name) do
    # Add a timestamp suffix to make names unique
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    "#{base_name} - #{timestamp}"
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