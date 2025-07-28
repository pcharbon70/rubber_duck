defmodule RubberDuck.Planning.PlanImprover do
  @moduledoc """
  Automatically improves plans based on validation warnings from critics.
  
  This module analyzes validation results and applies targeted improvements
  to address specific warnings, creating higher-quality plans that are more
  likely to execute successfully.
  """
  
  alias RubberDuck.Planning.{Plan, Critics.Orchestrator}
  alias RubberDuck.Planning.ImprovementTemplates
  alias RubberDuck.LLM.Service, as: LLMService
  
  require Logger
  
  @doc """
  Attempts to improve a plan based on validation warnings.
  
  Returns the improved plan if validation improves, otherwise returns the original.
  """
  @spec improve(Plan.t(), map()) :: {:ok, Plan.t(), map()} | {:error, term()}
  def improve(%Plan{} = plan, validation_results) do
    with {:ok, warnings} <- extract_warnings(validation_results),
         true <- should_improve?(warnings),
         {:ok, improved_plan} <- apply_improvements(plan, warnings, validation_results),
         {:ok, new_validation} <- validate_improved_plan(improved_plan) do
      
      if better_validation?(new_validation, validation_results) do
        Logger.info("Plan improved successfully, validation changed from #{validation_results["summary"]} to #{new_validation["summary"]}")
        # Mark the plan as improved
        final_plan = %{improved_plan | 
          metadata: Map.put(improved_plan.metadata || %{}, "auto_improved", true)
        }
        {:ok, final_plan, new_validation}
      else
        Logger.info("Improvement attempt did not improve validation, keeping original plan")
        {:ok, plan, validation_results}
      end
    else
      {:error, reason} ->
        Logger.warning("Plan improvement failed: #{inspect(reason)}, keeping original plan")
        {:ok, plan, validation_results}
      
      false ->
        # No need to improve
        {:ok, plan, validation_results}
      
      _ ->
        {:ok, plan, validation_results}
    end
  end
  
  defp extract_warnings(validation_results) do
    _warnings = []
    
    # Extract warnings from hard critics
    hard_warnings = validation_results["hard_critics"]
      |> Enum.filter(fn critic -> 
        critic["status"] == "warning" || critic[:status] == :warning 
      end)
      |> Enum.map(fn critic ->
        %{
          type: :hard,
          critic: critic["critic"] || critic[:critic],
          message: critic["message"] || critic[:message],
          details: critic["details"] || critic[:details],
          suggestions: extract_suggestions(validation_results)
        }
      end)
    
    # Extract warnings from soft critics
    soft_warnings = validation_results["soft_critics"]
      |> Enum.filter(fn critic ->
        critic["status"] == "warning" || critic[:status] == :warning
      end)
      |> Enum.map(fn critic ->
        %{
          type: :soft,
          critic: critic["critic"] || critic[:critic],
          message: critic["message"] || critic[:message],
          details: critic["details"] || critic[:details],
          suggestions: extract_suggestions(validation_results)
        }
      end)
    
    {:ok, hard_warnings ++ soft_warnings}
  rescue
    _ -> {:ok, []}
  end
  
  defp extract_suggestions(validation_results) do
    validation_results["suggestions"] || validation_results[:suggestions] || []
  end
  
  defp should_improve?(warnings) do
    # Only improve if there are warnings but not too many (avoiding endless loops)
    length(warnings) > 0 && length(warnings) <= 10
  end
  
  defp apply_improvements(plan, warnings, validation_results) do
    # Group warnings by type for batch processing
    grouped_warnings = group_warnings_by_type(warnings)
    
    # Apply improvements for each warning type
    improved_plan = Enum.reduce(grouped_warnings, plan, fn {warning_type, warnings}, current_plan ->
      case apply_improvement_for_type(current_plan, warning_type, warnings, validation_results) do
        {:ok, updated_plan} -> updated_plan
        _ -> current_plan
      end
    end)
    
    {:ok, improved_plan}
  end
  
  defp group_warnings_by_type(warnings) do
    warnings
    |> Enum.group_by(&categorize_warning/1)
    |> Enum.reject(fn {type, _} -> type == :unknown end)
  end
  
  defp categorize_warning(%{message: message}) do
    message_lower = String.downcase(message)
    
    cond do
      String.contains?(message_lower, "vague") || String.contains?(message_lower, "description") ->
        :vague_description
        
      String.contains?(message_lower, "security") || String.contains?(message_lower, "authentication") ->
        :security_missing
        
      String.contains?(message_lower, "style") || String.contains?(message_lower, "documentation") ->
        :style_issues
        
      String.contains?(message_lower, "best practice") || String.contains?(message_lower, "testing") ->
        :best_practices
        
      String.contains?(message_lower, "feasibility") ->
        :feasibility_concerns
        
      true ->
        :unknown
    end
  end
  
  defp apply_improvement_for_type(plan, :vague_description, warnings, _validation_results) do
    Logger.info("Improving vague descriptions for #{length(warnings)} warnings")
    improve_task_descriptions(plan, warnings)
  end
  
  defp apply_improvement_for_type(plan, :security_missing, warnings, _validation_results) do
    Logger.info("Adding security requirements for #{length(warnings)} warnings")
    add_security_requirements(plan, warnings)
  end
  
  defp apply_improvement_for_type(plan, :style_issues, warnings, _validation_results) do
    Logger.info("Fixing style issues for #{length(warnings)} warnings")
    fix_style_issues(plan, warnings)
  end
  
  defp apply_improvement_for_type(plan, :best_practices, warnings, _validation_results) do
    Logger.info("Adding best practices for #{length(warnings)} warnings")
    add_best_practices(plan, warnings)
  end
  
  defp apply_improvement_for_type(plan, :feasibility_concerns, warnings, _validation_results) do
    Logger.info("Addressing feasibility concerns for #{length(warnings)} warnings")
    address_feasibility_concerns(plan, warnings)
  end
  
  defp apply_improvement_for_type(plan, _, _, _) do
    {:ok, plan}
  end
  
  defp improve_task_descriptions(plan, _warnings) do
    # Get tasks that need improvement
    tasks_to_improve = plan.tasks
    |> Enum.filter(fn task ->
      word_count = String.split(task.description || "") |> length()
      word_count < 10 || !String.ends_with?(task.description || "", ".")
    end)
    
    if Enum.empty?(tasks_to_improve) do
      # If no tasks to improve, enhance the plan description
      improve_plan_description(plan)
    else
      # Improve each task description
      improved_tasks = Enum.map(tasks_to_improve, fn task ->
        case enhance_task_description(task, plan) do
          {:ok, improved_task} -> improved_task
          _ -> task
        end
      end)
      
      # Update the plan with improved tasks
      update_plan_tasks(plan, improved_tasks)
    end
  end
  
  defp improve_plan_description(plan) do
    prompt = ImprovementTemplates.plan_description_enhancement_template(%{
      name: plan.name,
      current_description: plan.description,
      type: plan.type,
      context: plan.context
    })
    
    case call_llm_for_improvement(prompt) do
      {:ok, improved_description} ->
        {:ok, %{plan | description: improved_description}}
      _ ->
        {:ok, plan}
    end
  end
  
  defp enhance_task_description(task, plan) do
    prompt = ImprovementTemplates.task_description_enhancement_template(%{
      task_name: task.name,
      current_description: task.description,
      plan_context: plan.description,
      task_position: task.position
    })
    
    case call_llm_for_improvement(prompt) do
      {:ok, improvement_data} ->
        updated_task = %{task | 
          description: improvement_data["description"] || task.description,
          success_criteria: improvement_data["success_criteria"] || task.success_criteria || [],
          validation_rules: improvement_data["validation_rules"] || task.validation_rules || []
        }
        {:ok, updated_task}
      _ ->
        {:error, :enhancement_failed}
    end
  end
  
  defp add_security_requirements(plan, _warnings) do
    # Check if this is an authentication-related plan
    if involves_authentication?(plan) do
      security_metadata = %{
        "security_requirements" => [
          "Use secure password hashing (bcrypt or argon2)",
          "Implement JWT token expiration and refresh",
          "Add rate limiting for authentication endpoints",
          "Store sensitive data encrypted",
          "Use HTTPS for all authentication endpoints"
        ],
        "authentication_required" => true,
        "security_level" => "high"
      }
      
      updated_metadata = Map.merge(plan.metadata || %{}, security_metadata)
      updated_plan = %{plan | metadata: updated_metadata}
      
      # Also update relevant tasks
      updated_tasks = Enum.map(plan.tasks || [], fn task ->
        if involves_authentication_task?(task) do
          task_security_meta = %{
            "security_critical" => true,
            "requires_security_review" => true
          }
          %{task | metadata: Map.merge(task.metadata || %{}, task_security_meta)}
        else
          task
        end
      end)
      
      {:ok, %{updated_plan | tasks: updated_tasks}}
    else
      {:ok, plan}
    end
  end
  
  defp fix_style_issues(plan, _warnings) do
    # Ensure all tasks have required fields
    updated_tasks = Enum.map(plan.tasks || [], fn task ->
      %{task |
        success_criteria: ensure_success_criteria(task),
        validation_rules: ensure_validation_rules(task),
        description: ensure_proper_description(task.description)
      }
    end)
    
    {:ok, %{plan | tasks: updated_tasks}}
  end
  
  defp add_best_practices(plan, _warnings) do
    # Add testing strategy to metadata
    testing_strategy = %{
      "testing_strategy" => %{
        "unit_tests" => "Required for all new functions",
        "integration_tests" => "Required for API endpoints",
        "test_coverage_target" => "80%",
        "testing_framework" => "ExUnit"
      },
      "error_handling_approach" => "Use {:ok, result} | {:error, reason} tuples",
      "milestones" => generate_milestones(plan)
    }
    
    updated_metadata = Map.merge(plan.metadata || %{}, testing_strategy)
    {:ok, %{plan | metadata: updated_metadata}}
  end
  
  defp address_feasibility_concerns(plan, warnings) do
    # For vague descriptions, we've already handled in improve_task_descriptions
    # Here we can add time estimates and complexity adjustments
    
    feasibility_metadata = %{
      "time_estimate" => estimate_plan_duration(plan),
      "risk_level" => assess_risk_level(plan, warnings),
      "prerequisites" => identify_prerequisites(plan)
    }
    
    updated_metadata = Map.merge(plan.metadata || %{}, feasibility_metadata)
    {:ok, %{plan | metadata: updated_metadata}}
  end
  
  defp update_plan_tasks(plan, improved_tasks) do
    # Create a map of improved tasks by ID
    improved_map = Map.new(improved_tasks, &{&1.id, &1})
    
    # Update only the improved tasks, keep others as is
    all_tasks = Enum.map(plan.tasks || [], fn task ->
      Map.get(improved_map, task.id, task)
    end)
    
    {:ok, %{plan | tasks: all_tasks}}
  end
  
  defp validate_improved_plan(plan) do
    orchestrator = Orchestrator.new()
    
    case Orchestrator.validate(orchestrator, plan) do
      {:ok, results} ->
        aggregated = Orchestrator.aggregate_results(results)
        {:ok, aggregated}
      error ->
        error
    end
  end
  
  defp better_validation?(new_validation, old_validation) do
    old_summary = old_validation["summary"] || old_validation[:summary]
    new_summary = new_validation["summary"] || new_validation[:summary]
    
    case {old_summary, new_summary} do
      {"failed", _} -> true  # Any improvement from failed is good
      {:failed, _} -> true
      {"warning", "passed"} -> true
      {:warning, :passed} -> true
      {same, same} -> count_warnings(new_validation) < count_warnings(old_validation)
      _ -> false
    end
  end
  
  defp count_warnings(validation) do
    hard_count = length(Enum.filter(validation["hard_critics"] || [], &(&1["status"] == "warning")))
    soft_count = length(Enum.filter(validation["soft_critics"] || [], &(&1["status"] == "warning")))
    hard_count + soft_count
  end
  
  defp call_llm_for_improvement(prompt) do
    messages = [
      %{
        role: "system",
        content: "You are a planning improvement assistant. Provide improvements in JSON format."
      },
      %{
        role: "user",
        content: prompt
      }
    ]
    
    llm_opts = [
      provider: :openai,
      model: "gpt-4",
      messages: messages,
      temperature: 0.3,
      response_format: %{type: "json_object"}
    ]
    
    case LLMService.completion(llm_opts) do
      {:ok, response} ->
        content = extract_content(response)
        Jason.decode(content)
      error ->
        Logger.error("LLM improvement call failed: #{inspect(error)}")
        {:error, :llm_failed}
    end
  end
  
  defp extract_content(%{choices: [%{message: %{content: content}} | _]}), do: content
  defp extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}), do: content
  defp extract_content(_), do: ""
  
  # Helper functions
  
  defp involves_authentication?(plan) do
    desc_lower = String.downcase(plan.description || "")
    name_lower = String.downcase(plan.name || "")
    
    auth_keywords = ["auth", "login", "jwt", "token", "session", "password", "user"]
    Enum.any?(auth_keywords, fn keyword ->
      String.contains?(desc_lower, keyword) || String.contains?(name_lower, keyword)
    end)
  end
  
  defp involves_authentication_task?(task) do
    desc_lower = String.downcase(task.description || "")
    name_lower = String.downcase(task.name || "")
    
    auth_keywords = ["auth", "login", "jwt", "token", "password", "user", "security"]
    Enum.any?(auth_keywords, fn keyword ->
      String.contains?(desc_lower, keyword) || String.contains?(name_lower, keyword)
    end)
  end
  
  defp ensure_success_criteria(task) do
    if Enum.empty?(task.success_criteria || []) do
      generate_success_criteria(task)
    else
      task.success_criteria
    end
  end
  
  defp generate_success_criteria(task) do
    [
      "#{task.name} is fully implemented",
      "All tests pass",
      "Code follows project conventions"
    ]
  end
  
  defp ensure_validation_rules(task) do
    if Enum.empty?(task.validation_rules || []) do
      ["Code compiles without warnings", "Follows style guide"]
    else
      task.validation_rules
    end
  end
  
  defp ensure_proper_description(nil), do: "Task needs detailed description."
  defp ensure_proper_description(desc) do
    desc = String.trim(desc)
    if String.ends_with?(desc, ".") do
      desc
    else
      desc <> "."
    end
  end
  
  defp generate_milestones(plan) do
    task_count = length(plan.tasks || [])
    
    cond do
      task_count <= 3 ->
        ["Complete all tasks", "Validate implementation"]
        
      task_count <= 8 ->
        [
          "Complete initial setup tasks",
          "Implement core functionality",
          "Add tests and documentation",
          "Final validation"
        ]
        
      true ->
        [
          "Complete 25% - Foundation tasks",
          "Complete 50% - Core implementation", 
          "Complete 75% - Integration and testing",
          "Complete 100% - Final validation"
        ]
    end
  end
  
  defp estimate_plan_duration(plan) do
    task_count = length(plan.tasks || [])
    
    # Simple estimation based on task count and complexity
    base_hours = task_count * 2
    
    complexity_multiplier = case plan.type do
      :migration -> 1.5
      :refactor -> 1.3
      _ -> 1.0
    end
    
    estimated_hours = round(base_hours * complexity_multiplier)
    
    %{
      "estimated_hours" => estimated_hours,
      "estimated_days" => Float.ceil(estimated_hours / 8)
    }
  end
  
  defp assess_risk_level(_plan, warnings) do
    warning_count = length(warnings)
    
    cond do
      warning_count >= 5 -> "high"
      warning_count >= 3 -> "medium"
      true -> "low"
    end
  end
  
  defp identify_prerequisites(plan) do
    # Basic prerequisites based on plan type and content
    prereqs = []
    
    prereqs = if involves_authentication?(plan) do
      prereqs ++ ["User model/schema defined", "Database configured"]
    else
      prereqs
    end
    
    prereqs = if String.contains?(String.downcase(plan.description || ""), "api") do
      prereqs ++ ["API routes configured", "Phoenix endpoint setup"]
    else
      prereqs
    end
    
    if Enum.empty?(prereqs) do
      ["Project setup complete", "Dependencies installed"]
    else
      prereqs
    end
  end
end