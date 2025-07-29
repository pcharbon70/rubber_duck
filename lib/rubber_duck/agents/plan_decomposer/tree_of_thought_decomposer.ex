defmodule RubberDuck.Agents.PlanDecomposer.TreeOfThoughtDecomposer do
  @moduledoc """
  Tree-of-thought decomposition strategy for exploring multiple approaches.
  
  This strategy is best for exploratory tasks where the approach is uncertain.
  It generates multiple alternative approaches and selects the best one based
  on various criteria.
  """
  
  use Jido.Action,
    name: "tree_of_thought_decomposer",
    description: "Explores multiple decomposition approaches and selects the best",
    schema: [
      query: [type: :string, required: true],
      context: [type: :map, default: %{}],
      constraints: [type: :map, default: %{}],
      goals: [type: {:list, :string}, default: []]
    ]
  
  alias RubberDuck.LLM.Service, as: LLM
  alias RubberDuck.Planning.DecompositionTemplates
  
  require Logger
  
  @impl true
  def run(params, context) do
    state = context[:state] || %{}
    
    # Extract or infer goals
    goals = if Enum.empty?(params.goals) do
      extract_goals_from_query(params.query)
    else
      params.goals
    end
    
    # Get the tree-of-thought template
    prompt = DecompositionTemplates.get_template(:tree_of_thought, %{
      request: params.query,
      goals: format_goals(goals),
      constraints: format_constraints(params.constraints)
    })
    
    case LLM.completion(
      model: state[:llm_config][:model] || "gpt-4",
      messages: [%{role: "user", content: prompt}],
      response_format: %{type: "json_object"}
    ) do
      {:ok, response} ->
        # Extract content from LLM response
        content = extract_content(response)
        
        # Parse approaches
        approaches = parse_approaches(content)
        
        if Enum.empty?(approaches) do
          {:error, "No approaches generated"}
        else
          # Evaluate and select best approach
          {:ok, best_approach, comparison} = evaluate_approaches(approaches, params)
          
          # Convert to standard task format
          tasks = format_approach_tasks(best_approach, comparison)
          
          {:ok, tasks}
        end
        
      {:error, reason} ->
        Logger.error("Tree-of-thought decomposition failed: #{inspect(reason)}")
        {:error, "Failed to decompose: #{inspect(reason)}"}
    end
  end
  
  @doc """
  Entry point for the decomposer matching existing interface.
  """
  def decompose(input, state) do
    params = %{
      query: input.query,
      context: input[:context] || %{},
      constraints: input[:constraints] || %{},
      goals: input[:goals] || []
    }
    
    run(params, %{state: state})
  end
  
  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{choices: [%{message: %{content: content}} | _]}), do: content
  defp extract_content(_), do: "[]"
  
  defp parse_approaches(content) do
    case Jason.decode!(content) do
      approaches when is_list(approaches) -> approaches
      %{"approaches" => apps} when is_list(apps) -> apps
      _ -> []
    end
  end
  
  defp extract_goals_from_query(query) do
    cond do
      String.contains?(query, ["implement", "build", "create"]) -> 
        ["Complete implementation", "Working functionality", "Maintainable code"]
      String.contains?(query, ["fix", "repair", "resolve"]) -> 
        ["Resolve issue", "Prevent regression", "Minimal disruption"]
      String.contains?(query, ["optimize", "improve", "enhance"]) -> 
        ["Improve performance", "Maintain functionality", "Measurable gains"]
      true -> 
        ["Complete the requested task", "High quality result"]
    end
  end
  
  defp format_goals(goals) when is_list(goals), do: Enum.join(goals, ", ")
  defp format_goals(goals) when is_binary(goals), do: goals
  defp format_goals(_), do: "Complete the requested task"
  
  defp format_constraints(constraints) when is_map(constraints) do
    constraints
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(", ")
  end
  defp format_constraints(_), do: "None specified"
  
  defp evaluate_approaches(approaches, params) do
    # Score each approach
    scored_approaches = approaches
    |> Enum.map(fn approach ->
      score = calculate_approach_score(approach, params)
      {approach, score}
    end)
    |> Enum.sort_by(fn {_, score} -> score.total end, :desc)
    
    # Get best approach
    {best_approach, best_score} = List.first(scored_approaches)
    
    # Create comparison data
    comparison = %{
      "selected_approach" => best_approach["approach_name"],
      "selection_reason" => generate_selection_reason(best_approach, best_score, scored_approaches),
      "scores" => Enum.map(scored_approaches, fn {app, score} ->
        %{
          "approach" => app["approach_name"],
          "total_score" => score.total,
          "breakdown" => score
        }
      end)
    }
    
    {:ok, best_approach, comparison}
  end
  
  defp calculate_approach_score(approach, params) do
    # Extract preferences from context
    preferences = get_preferences(params)
    
    # Base scores
    confidence = parse_float(approach["confidence_score"], 0.5)
    risk_score = risk_to_score(approach["risk_level"])
    
    # Calculate component scores
    scores = %{
      confidence: confidence * preferences.confidence_weight,
      risk_alignment: calculate_risk_alignment(risk_score, preferences.risk_tolerance) * preferences.risk_weight,
      effort_efficiency: calculate_effort_efficiency(approach["estimated_total_effort"], preferences.time_constraint) * preferences.effort_weight,
      goal_alignment: calculate_goal_alignment(approach, params[:goals]) * preferences.goal_weight,
      pros_cons_balance: calculate_pros_cons_balance(approach) * 0.1
    }
    
    # Total weighted score
    total = Enum.reduce(scores, 0, fn {_, value}, acc -> acc + value end)
    
    Map.put(scores, :total, total)
  end
  
  defp get_preferences(params) do
    context = params[:context] || %{}
    
    %{
      confidence_weight: context[:confidence_weight] || 0.3,
      risk_weight: context[:risk_weight] || 0.3,
      effort_weight: context[:effort_weight] || 0.2,
      goal_weight: context[:goal_weight] || 0.2,
      risk_tolerance: context[:risk_tolerance] || :medium,
      time_constraint: context[:time_constraint] || "2w"
    }
  end
  
  defp parse_float(value, _) when is_float(value), do: value
  defp parse_float(value, _) when is_integer(value), do: value / 1.0
  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> default
    end
  end
  defp parse_float(_, default), do: default
  
  defp risk_to_score("low"), do: 0.9
  defp risk_to_score("medium"), do: 0.5
  defp risk_to_score("high"), do: 0.2
  defp risk_to_score(_), do: 0.5
  
  defp calculate_risk_alignment(risk_score, tolerance) do
    case tolerance do
      :low -> risk_score
      :medium -> 0.5 + (risk_score - 0.5) * 0.5
      :high -> 1.0 - risk_score
      _ -> 0.5
    end
  end
  
  defp calculate_effort_efficiency(effort, time_constraint) do
    effort_days = effort_to_days(effort)
    constraint_days = effort_to_days(time_constraint)
    
    if effort_days <= constraint_days do
      1.0 - (effort_days / constraint_days) * 0.3
    else
      0.3 * (constraint_days / effort_days)
    end
  end
  
  defp effort_to_days("1d"), do: 1
  defp effort_to_days("2d"), do: 2
  defp effort_to_days("3d"), do: 3
  defp effort_to_days("1w"), do: 5
  defp effort_to_days("2w"), do: 10
  defp effort_to_days("3w"), do: 15
  defp effort_to_days("1m"), do: 20
  defp effort_to_days(_), do: 10
  
  defp calculate_goal_alignment(approach, goals) do
    if goals && approach["best_when"] do
      goals_text = format_goals(goals) |> String.downcase()
      best_when = String.downcase(approach["best_when"])
      
      if String.contains?(best_when, ["fast", "quick"]) && String.contains?(goals_text, ["quick", "fast"]) do
        0.9
      else
        0.7
      end
    else
      0.7
    end
  end
  
  defp calculate_pros_cons_balance(approach) do
    pros_count = length(approach["pros"] || [])
    cons_count = length(approach["cons"] || [])
    
    if pros_count + cons_count > 0 do
      pros_count / (pros_count + cons_count)
    else
      0.5
    end
  end
  
  defp generate_selection_reason(approach, score, all_scored) do
    other_names = all_scored
    |> Enum.drop(1)
    |> Enum.map(fn {app, _} -> app["approach_name"] end)
    |> Enum.join(", ")
    
    "Selected '#{approach["approach_name"]}' (score: #{Float.round(score.total, 2)}) due to " <>
    "#{approach["philosophy"]}. This approach offers the best balance of " <>
    "confidence (#{approach["confidence_score"]}), risk (#{approach["risk_level"]}), " <>
    "and effort (#{approach["estimated_total_effort"]}). " <>
    if(length(all_scored) > 1, do: "Alternative approaches considered: #{other_names}.", else: "")
  end
  
  defp format_approach_tasks(approach, comparison) do
    tasks = approach["tasks"] || []
    approach_metadata = %{
      "approach_name" => approach["approach_name"],
      "philosophy" => approach["philosophy"],
      "risk_level" => approach["risk_level"],
      "confidence_score" => approach["confidence_score"],
      "selection_reason" => comparison["selection_reason"]
    }
    
    tasks
    |> Enum.with_index()
    |> Enum.map(fn {task, index} ->
      base_task = %{
        "id" => task["id"] || "task_#{index}",
        "name" => task["name"] || "Task #{index + 1}",
        "description" => task["description"] || "",
        "complexity" => task["complexity"] || "medium",
        "position" => index,
        "depends_on" => task["dependencies"] || (if index > 0, do: ["task_#{index - 1}"], else: [])
      }
      
      # Add approach metadata
      metadata = Map.merge(
        task["metadata"] || %{},
        Map.merge(approach_metadata, %{
          "approach_confidence" => approach["confidence_score"],
          "task_risk" => task["risk"] || approach["risk_level"]
        })
      )
      
      Map.put(base_task, "metadata", metadata)
    end)
  end
end