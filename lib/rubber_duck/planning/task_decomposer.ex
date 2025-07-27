defmodule RubberDuck.Planning.TaskDecomposer do
  @moduledoc """
  Task decomposition engine that breaks down high-level requests into actionable tasks.

  This engine uses LLM-guided decomposition with validation to create structured,
  executable task hierarchies. It supports multiple decomposition strategies and
  integrates with the CoT reasoning system.
  """

  @behaviour RubberDuck.Engine

  # alias RubberDuck.Planning.{Plan, Task, TaskDependency}
  alias RubberDuck.LLM.Service, as: LLM
  alias RubberDuck.Planning.Critics.Orchestrator

  require Logger

  @decomposition_strategies [:linear, :hierarchical, :tree_of_thought]

  defstruct [
    :llm_config,
    :default_strategy,
    :max_depth,
    :min_task_size,
    :validation_enabled,
    :pattern_library
  ]

  @type t :: %__MODULE__{
          llm_config: map(),
          default_strategy: atom(),
          max_depth: pos_integer(),
          min_task_size: pos_integer(),
          validation_enabled: boolean(),
          pattern_library: map()
        }

  @type decomposition_result :: %{
          tasks: [map()],
          dependencies: [%{from: String.t(), to: String.t()}],
          metadata: map()
        }

  # Engine behavior callbacks

  @impl RubberDuck.Engine
  def init(config) do
    state = %__MODULE__{
      llm_config: Keyword.get(config, :llm_config, %{}),
      default_strategy: Keyword.get(config, :default_strategy, :hierarchical),
      max_depth: Keyword.get(config, :max_depth, 5),
      min_task_size: Keyword.get(config, :min_task_size, 1),
      validation_enabled: Keyword.get(config, :validation_enabled, true),
      pattern_library: load_pattern_library()
    }

    {:ok, state}
  end

  @impl RubberDuck.Engine
  def execute(input, state) do
    with {:ok, strategy} <- determine_strategy(input, state),
         {:ok, initial_decomposition} <- decompose_with_strategy(input, strategy, state),
         {:ok, refined_tasks} <- refine_tasks(initial_decomposition, state),
         {:ok, dependencies} <- build_dependency_graph(refined_tasks, state),
         {:ok, validated_result} <- validate_decomposition(refined_tasks, dependencies, state) do
      {:ok,
       %{
         tasks: validated_result.tasks,
         dependencies: dependencies,
         strategy: strategy,
         metadata: %{
           total_tasks: length(validated_result.tasks),
           max_depth: calculate_max_depth(validated_result.tasks),
           complexity_distribution: calculate_complexity_distribution(validated_result.tasks)
         }
       }}
    end
  end

  @impl RubberDuck.Engine
  def capabilities do
    [:task_decomposition, :dependency_analysis, :complexity_estimation]
  end

  # Strategy determination

  defp determine_strategy(%{strategy: strategy}, _state) when strategy in @decomposition_strategies do
    {:ok, strategy}
  end

  defp determine_strategy(input, state) do
    # Use LLM to analyze the request and determine best strategy
    prompt = """
    Analyze this request and determine the best decomposition strategy:

    Request: #{input.query}

    Available strategies:
    - linear: For simple, sequential tasks
    - hierarchical: For complex features with sub-tasks
    - tree_of_thought: For exploratory tasks requiring multiple approaches

    Respond with just the strategy name.
    """

    case LLM.completion(model: state.llm_config[:model] || "gpt-4", messages: [%{role: "user", content: prompt}]) do
      {:ok, response} ->
        # Extract content from LLM response structure
        content = case response do
          %{content: c} when is_binary(c) -> c
          %{choices: [%{message: %{content: c}} | _]} -> c
          _ -> ""
        end
        
        strategy_atom = content
          |> String.trim()
          |> String.downcase()
          |> then(fn s ->
            try do
              String.to_existing_atom(s)
            rescue
              ArgumentError -> nil
            end
          end)

        if strategy_atom in @decomposition_strategies do
          {:ok, strategy_atom}
        else
          {:ok, state.default_strategy}
        end

      {:error, _} ->
        {:ok, state.default_strategy}
    end
  end

  # Decomposition strategies

  defp decompose_with_strategy(input, :linear, state) do
    linear_decomposition(input, state)
  end

  defp decompose_with_strategy(input, :hierarchical, state) do
    hierarchical_decomposition(input, state)
  end

  defp decompose_with_strategy(input, :tree_of_thought, state) do
    tree_of_thought_decomposition(input, state)
  end

  defp linear_decomposition(input, state) do
    prompt = """
    Break down this request into a linear sequence of tasks:

    Request: #{input.query}
    Context: #{inspect(input[:context] || %{})}

    For each task provide:
    - name: Short descriptive name
    - description: What needs to be done
    - complexity: trivial, simple, medium, complex, or very_complex
    - success_criteria: How to know when it's done

    Return as JSON array.
    """

    case LLM.completion(
           model: state.llm_config[:model] || "gpt-4",
           messages: [%{role: "user", content: prompt}],
           response_format: %{type: "json_object"}
         ) do
      {:ok, response} ->
        # Extract content from LLM response structure
        content = case response do
          %{content: c} when is_binary(c) -> c
          %{choices: [%{message: %{content: c}} | _]} -> c
          _ -> "[]"
        end
        
        tasks =
          Jason.decode!(content)
          |> List.wrap()  # Ensure it's a list even if single object returned
          |> Enum.with_index()
          |> Enum.map(fn {task, index} ->
            Map.merge(task, %{
              "position" => index,
              "depends_on" => if(index > 0, do: [index - 1], else: [])
            })
          end)

        {:ok, tasks}

      error ->
        error
    end
  end

  defp hierarchical_decomposition(input, state) do
    alias RubberDuck.Planning.DecompositionTemplates
    
    # Get the hierarchical decomposition template
    prompt = DecompositionTemplates.get_template(:hierarchical_decomposition, %{
      request: input.query,
      context: inspect(input[:context] || %{}),
      scope: input[:scope] || "Complete implementation"
    })

    case LLM.completion(
           model: state.llm_config[:model] || "gpt-4",
           messages: [%{role: "user", content: prompt}],
           response_format: %{type: "json_object"}
         ) do
      {:ok, response} ->
        # Extract content from LLM response structure
        content = case response do
          %{content: c} when is_binary(c) -> c
          %{choices: [%{message: %{content: c}} | _]} -> c
          _ -> "{\"phases\": []}"
        end
        
        # Parse and extract hierarchical tasks
        hierarchical_data = Jason.decode!(content)
        tasks = extract_hierarchical_tasks(hierarchical_data, state)
        {:ok, tasks}

      error ->
        Logger.error("Hierarchical decomposition failed: #{inspect(error)}")
        error
    end
  end

  defp tree_of_thought_decomposition(input, state) do
    alias RubberDuck.Planning.DecompositionTemplates
    
    # Extract goals and constraints from context
    goals = input[:goals] || extract_goals_from_query(input.query)
    constraints = input[:constraints] || input[:context][:constraints] || %{}
    
    # Get the tree-of-thought template
    prompt = DecompositionTemplates.get_template(:tree_of_thought, %{
      request: input.query,
      goals: format_goals(goals),
      constraints: format_constraints(constraints)
    })

    case LLM.completion(
           model: state.llm_config[:model] || "gpt-4",
           messages: [%{role: "user", content: prompt}],
           response_format: %{type: "json_object"}
         ) do
      {:ok, response} ->
        # Extract content from LLM response structure
        content = case response do
          %{content: c} when is_binary(c) -> c
          %{choices: [%{message: %{content: c}} | _]} -> c
          _ -> "[]"
        end
        
        # Parse approaches - expecting an array of approaches
        approaches = case Jason.decode!(content) do
          approaches when is_list(approaches) -> approaches
          %{"approaches" => apps} when is_list(apps) -> apps
          _ -> []
        end

        if length(approaches) == 0 do
          Logger.error("No approaches generated for tree-of-thought decomposition")
          {:error, :no_approaches_generated}
        else
          # Evaluate all approaches and select the best one
          {:ok, best_approach, comparison} = evaluate_and_select_approach(approaches, input, state)

          # Convert selected approach's tasks to our standard format
          tasks = format_approach_tasks(best_approach, comparison)
          
          {:ok, tasks}
        end

      error ->
        Logger.error("Tree-of-thought decomposition failed: #{inspect(error)}")
        error
    end
  end
  
  defp extract_goals_from_query(query) do
    # Simple extraction - in real implementation might use LLM
    cond do
      String.contains?(query, "implement") -> ["Complete implementation", "Working functionality"]
      String.contains?(query, "fix") -> ["Resolve issue", "Prevent regression"]
      String.contains?(query, "optimize") -> ["Improve performance", "Maintain functionality"]
      true -> ["Complete the requested task"]
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
      # Base task structure
      base_task = %{
        "name" => task["name"] || "Task #{index + 1}",
        "description" => task["description"] || "",
        "complexity" => task["complexity"] || "medium",
        "position" => index,
        "depends_on" => task["dependencies"] || (if index > 0, do: [index - 1], else: [])
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

  # Task refinement

  defp refine_tasks(tasks, state) do
    refined =
      Enum.map(tasks, fn task ->
        with {:ok, complexity} <- estimate_complexity(task, state),
             {:ok, criteria} <- generate_success_criteria(task, state),
             {:ok, validation_rules} <- generate_validation_rules(task, state) do
          task
          |> Map.put("complexity", complexity)
          |> Map.put("success_criteria", criteria)
          |> Map.put("validation_rules", validation_rules)
        else
          _ -> task
        end
      end)

    {:ok, refined}
  end

  defp estimate_complexity(task, state) do
    prompt = """
    Estimate the complexity of this task:

    Task: #{task["name"]}
    Description: #{task["description"]}

    Consider factors like:
    - Technical difficulty
    - Time required
    - Dependencies
    - Risk of failure

    Respond with one of: trivial, simple, medium, complex, very_complex
    """

    case LLM.completion(model: state.llm_config[:model] || "gpt-4", messages: [%{role: "user", content: prompt}]) do
      {:ok, response} ->
        # Extract content from LLM response structure
        content = case response do
          %{content: c} when is_binary(c) -> c
          %{choices: [%{message: %{content: c}} | _]} -> c
          _ -> "medium"
        end
        
        complexity =
          content
          |> String.trim()
          |> String.downcase()

        {:ok, complexity}

      _ ->
        {:ok, "medium"}
    end
  end

  defp generate_success_criteria(task, state) do
    prompt = """
    Generate specific, measurable success criteria for this task:

    Task: #{task["name"]}
    Description: #{task["description"]}

    Provide 2-3 clear criteria that indicate successful completion.
    Return as JSON object with 'criteria' array.
    """

    case LLM.completion(
           model: state.llm_config[:model] || "gpt-4",
           messages: [%{role: "user", content: prompt}],
           response_format: %{type: "json_object"}
         ) do
      {:ok, response} ->
        # Extract content from LLM response structure
        content = case response do
          %{content: c} when is_binary(c) -> c
          %{choices: [%{message: %{content: c}} | _]} -> c
          _ -> "{\"criteria\": [\"Task completed successfully\"]}"
        end
        
        {:ok, Jason.decode!(content)}

      _ ->
        {:ok, %{"criteria" => ["Task completed successfully"]}}
    end
  end

  defp generate_validation_rules(_task, _state) do
    # Basic validation rules based on task type
    rules = %{
      "required_fields" => ["name", "description", "status"],
      "status_transitions" => %{
        "pending" => ["ready", "skipped"],
        "ready" => ["in_progress", "skipped"],
        "in_progress" => ["completed", "failed"],
        "completed" => [],
        "failed" => ["ready", "skipped"],
        "skipped" => []
      }
    }

    {:ok, rules}
  end

  # Dependency graph building

  defp build_dependency_graph(tasks, state) do
    # First check for explicit dependencies
    explicit_deps = extract_explicit_dependencies(tasks)

    # Then infer additional dependencies
    {:ok, inferred_deps} = infer_dependencies(tasks, state)

    # Combine and validate
    all_deps = Enum.uniq(explicit_deps ++ inferred_deps)

    # Check for cycles
    case detect_cycles(all_deps, tasks) do
      :ok ->
        {:ok, all_deps}

      {:error, :cycle_detected} = error ->
        error
    end
  end

  defp extract_explicit_dependencies(tasks) do
    tasks
    |> Enum.flat_map(fn task ->
      task_index = task["position"] || 0

      (task["depends_on"] || [])
      |> Enum.map(fn dep_index ->
        %{
          from: "task_#{dep_index}",
          to: "task_#{task_index}"
        }
      end)
    end)
  end

  defp infer_dependencies(tasks, state) do
    prompt = """
    Analyze these tasks and identify dependencies between them:

    #{tasks |> Enum.map(fn t -> "#{t["position"]}: #{t["name"]} - #{t["description"]}" end) |> Enum.join("\n")}

    Return dependencies as JSON array of {from: task_index, to: task_index} objects.
    Only include dependencies not already listed.
    """

    case LLM.completion(
           model: state.llm_config[:model] || "gpt-4",
           messages: [%{role: "user", content: prompt}],
           response_format: %{type: "json_object"}
         ) do
      {:ok, response} ->
        # Extract content from LLM response structure
        content = case response do
          %{content: c} when is_binary(c) -> c
          %{choices: [%{message: %{content: c}} | _]} -> c
          _ -> "[]"
        end
        
        deps =
          content
          |> Jason.decode!()
          |> List.wrap()  # Ensure it's a list
          |> Enum.map(fn dep ->
            %{
              from: "task_#{dep["from"]}",
              to: "task_#{dep["to"]}"
            }
          end)

        {:ok, deps}

      _ ->
        {:ok, []}
    end
  end

  def detect_cycles(dependencies, tasks) do
    # Build adjacency list
    graph =
      Enum.reduce(dependencies, %{}, fn %{from: from, to: to}, acc ->
        Map.update(acc, from, [to], &[to | &1])
      end)

    # Check for cycles using DFS
    all_nodes = tasks |> Enum.map(fn t -> "task_#{t["position"]}" end)

    case find_cycle(all_nodes, graph) do
      nil -> :ok
      _cycle -> {:error, :cycle_detected}
    end
  end

  defp find_cycle(nodes, graph) do
    Enum.find_value(nodes, fn node ->
      case dfs_cycle(node, graph, MapSet.new(), MapSet.new()) do
        {:cycle, path} -> path
        :no_cycle -> nil
      end
    end)
  end

  defp dfs_cycle(node, graph, visited, rec_stack) do
    visited = MapSet.put(visited, node)
    rec_stack = MapSet.put(rec_stack, node)

    neighbors = Map.get(graph, node, [])

    result =
      Enum.find_value(neighbors, fn neighbor ->
        cond do
          MapSet.member?(rec_stack, neighbor) ->
            {:cycle, [node, neighbor]}

          not MapSet.member?(visited, neighbor) ->
            case dfs_cycle(neighbor, graph, visited, rec_stack) do
              {:cycle, path} -> {:cycle, [node | path]}
              :no_cycle -> nil
            end

          true ->
            nil
        end
      end)

    result || :no_cycle
  end

  # Validation

  defp validate_decomposition(tasks, dependencies, state) do
    if state.validation_enabled do
      validations = [
        validate_task_completeness(tasks),
        validate_dependency_consistency(tasks, dependencies),
        validate_complexity_balance(tasks),
        validate_success_criteria(tasks)
      ]

      case Enum.find(validations, &match?({:error, _}, &1)) do
        {:error, _} = error ->
          error

        nil ->
          # If basic validations pass, run critics
          case run_critic_validation(tasks, dependencies, state) do
            :ok -> {:ok, %{tasks: tasks, valid: true}}
            {:error, reason} -> {:error, reason}
          end
      end
    else
      {:ok, %{tasks: tasks, valid: true}}
    end
  end

  defp run_critic_validation(tasks, dependencies, state) do
    orchestrator =
      Orchestrator.new(
        cache_enabled: true,
        parallel_execution: true,
        config: state.llm_config
      )

    # Create a mock plan structure for validation
    plan = %{
      tasks: tasks,
      dependencies: dependencies,
      metadata: %{
        strategy: state.default_strategy,
        created_by: "TaskDecomposer"
      }
    }

    case Orchestrator.validate(orchestrator, plan) do
      {:ok, results} ->
        aggregated = Orchestrator.aggregate_results(results)

        if aggregated.summary == :failed do
          {:error, format_critic_errors(aggregated)}
        else
          :ok
        end

        # Orchestrator.validate always returns {:ok, results}
        # So we don't need this error case
    end
  end

  defp format_critic_errors(aggregated) do
    blocking_messages =
      aggregated.blocking_issues
      |> Enum.map(& &1.message)
      |> Enum.join("; ")

    "Validation failed: #{blocking_messages}"
  end

  def validate_task_completeness(tasks) do
    required_fields = ["name", "description", "complexity", "success_criteria"]

    incomplete =
      Enum.filter(tasks, fn task ->
        Enum.any?(required_fields, fn field ->
          is_nil(task[field]) or task[field] == ""
        end)
      end)

    if Enum.empty?(incomplete) do
      {:ok, :complete}
    else
      {:error, {:incomplete_tasks, incomplete}}
    end
  end

  defp validate_dependency_consistency(tasks, dependencies) do
    task_ids = tasks |> Enum.map(fn t -> "task_#{t["position"]}" end) |> MapSet.new()

    invalid_deps =
      Enum.filter(dependencies, fn %{from: from, to: to} ->
        not (MapSet.member?(task_ids, from) and MapSet.member?(task_ids, to))
      end)

    if Enum.empty?(invalid_deps) do
      {:ok, :consistent}
    else
      {:error, {:invalid_dependencies, invalid_deps}}
    end
  end

  def validate_complexity_balance(tasks) do
    complexity_counts = Enum.frequencies_by(tasks, & &1["complexity"])

    very_complex_ratio = Map.get(complexity_counts, "very_complex", 0) / length(tasks)

    if very_complex_ratio > 0.5 do
      {:error, :too_many_complex_tasks}
    else
      {:ok, :balanced}
    end
  end

  defp validate_success_criteria(tasks) do
    without_criteria =
      Enum.filter(tasks, fn task ->
        criteria = task["success_criteria"]
        is_nil(criteria) or (is_map(criteria) and Enum.empty?(criteria["criteria"] || []))
      end)

    if Enum.empty?(without_criteria) do
      {:ok, :criteria_present}
    else
      {:error, {:missing_success_criteria, without_criteria}}
    end
  end

  # Helper functions

  defp load_pattern_library do
    # TODO: Load from configuration or database
    %{
      "feature_implementation" => %{
        "phases" => ["design", "implement", "test", "document"],
        "typical_dependencies" => "linear"
      },
      "bug_fix" => %{
        "phases" => ["reproduce", "diagnose", "fix", "verify"],
        "typical_dependencies" => "linear"
      },
      "refactoring" => %{
        "phases" => ["analyze", "plan", "refactor", "test"],
        "typical_dependencies" => "mixed"
      }
    }
  end

  defp extract_hierarchical_tasks(hierarchical_data, _state) do
    phases = hierarchical_data["phases"] || []
    dependencies = hierarchical_data["dependencies"] || []
    critical_path = hierarchical_data["critical_path"] || []
    
    # Flatten the hierarchical structure into a task list
    {tasks, _position} = phases
    |> Enum.reduce({[], 0}, fn phase, {acc_tasks, position} ->
      phase_tasks = extract_tasks_from_phase(phase, position, critical_path)
      {acc_tasks ++ phase_tasks, position + length(phase_tasks)}
    end)
    
    # Add dependencies to tasks
    tasks_with_deps = add_dependencies_to_tasks(tasks, dependencies)
    
    tasks_with_deps
  end
  
  defp extract_tasks_from_phase(phase, start_position, critical_path) do
    phase_id = phase["id"]
    phase_name = phase["name"]
    phase_tasks = phase["tasks"] || []
    
    phase_tasks
    |> Enum.with_index()
    |> Enum.flat_map(fn {task, task_index} ->
      task_position = start_position + task_index
      
      # Create the main task
      main_task = %{
        "id" => task["id"],
        "name" => task["name"],
        "description" => task["description"],
        "complexity" => task["complexity"] || "medium",
        "position" => task_position,
        "phase_id" => phase_id,
        "phase_name" => phase_name,
        "hierarchy_level" => 2,
        "is_critical" => task["id"] in critical_path,
        "metadata" => %{
          "phase" => phase_name,
          "hierarchy_level" => 2,
          "is_critical_path" => task["id"] in critical_path
        }
      }
      
      # Extract subtasks if present
      subtasks = task["subtasks"] || []
      if Enum.empty?(subtasks) do
        [main_task]
      else
        subtask_list = subtasks
        |> Enum.with_index()
        |> Enum.map(fn {subtask, subtask_index} ->
          %{
            "id" => subtask["id"],
            "name" => subtask["name"],
            "description" => subtask["description"],
            "complexity" => "simple",  # Subtasks are typically simpler
            "position" => task_position + (subtask_index + 1) * 0.1,  # Decimal positions for subtasks
            "parent_task_id" => task["id"],
            "phase_id" => phase_id,
            "phase_name" => phase_name,
            "hierarchy_level" => 3,
            "metadata" => %{
              "phase" => phase_name,
              "parent_task" => task["name"],
              "hierarchy_level" => 3
            }
          }
        end)
        
        [main_task | subtask_list]
      end
    end)
  end
  
  defp add_dependencies_to_tasks(tasks, dependencies) do
    # Create a map of task IDs to positions for quick lookup
    id_to_position = tasks
    |> Enum.reduce(%{}, fn task, acc ->
      Map.put(acc, task["id"], task["position"])
    end)
    
    # Add dependency information to tasks
    tasks
    |> Enum.map(fn task ->
      # Find dependencies where this task is the "to" task
      task_deps = dependencies
      |> Enum.filter(fn dep -> dep["to"] == task["id"] end)
      |> Enum.map(fn dep -> 
        # Convert from task ID to position
        id_to_position[dep["from"]]
      end)
      |> Enum.filter(&(&1 != nil))
      
      Map.put(task, "depends_on", task_deps)
    end)
  end

  defp evaluate_and_select_approach(approaches, input, state) do
    # Score each approach based on multiple criteria
    scored_approaches = approaches
    |> Enum.map(fn approach ->
      score = calculate_approach_score(approach, input, state)
      {approach, score}
    end)
    |> Enum.sort_by(fn {_approach, score} -> score.total end, :desc)
    
    # Get the best approach
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
      end),
      "alternatives" => Enum.map(tl(scored_approaches), fn {app, _score} ->
        %{
          "name" => app["approach_name"],
          "philosophy" => app["philosophy"],
          "pros" => app["pros"],
          "cons" => app["cons"]
        }
      end)
    }
    
    {:ok, best_approach, comparison}
  end
  
  defp calculate_approach_score(approach, input, _state) do
    # Extract context preferences
    preferences = get_preferences(input)
    
    # Base scores from approach data
    confidence = parse_float(approach["confidence_score"], 0.5)
    risk_score = risk_to_score(approach["risk_level"])
    
    # Calculate component scores
    scores = %{
      confidence: confidence * preferences.confidence_weight,
      risk_alignment: calculate_risk_alignment(risk_score, preferences.risk_tolerance) * preferences.risk_weight,
      effort_efficiency: calculate_effort_efficiency(approach["estimated_total_effort"], preferences.time_constraint) * preferences.effort_weight,
      goal_alignment: calculate_goal_alignment(approach, input[:goals]) * preferences.goal_weight,
      pros_cons_balance: calculate_pros_cons_balance(approach) * 0.1
    }
    
    # Calculate total weighted score
    total = Enum.reduce(scores, 0, fn {_key, value}, acc -> acc + value end)
    
    Map.put(scores, :total, total)
  end
  
  defp get_preferences(input) do
    context = input[:context] || %{}
    
    # Default weights that sum to 1.0
    %{
      confidence_weight: context[:confidence_weight] || 0.3,
      risk_weight: context[:risk_weight] || 0.3,
      effort_weight: context[:effort_weight] || 0.2,
      goal_weight: context[:goal_weight] || 0.2,
      risk_tolerance: context[:risk_tolerance] || :medium,
      time_constraint: context[:time_constraint] || "2w"
    }
  end
  
  defp parse_float(value, _default) when is_float(value), do: value
  defp parse_float(value, _default) when is_integer(value), do: value / 1.0
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
      :low -> risk_score  # Prefer low risk
      :medium -> 0.5 + (risk_score - 0.5) * 0.5  # Moderate preference
      :high -> 1.0 - risk_score  # Prefer high risk/high reward
      _ -> 0.5
    end
  end
  
  defp calculate_effort_efficiency(effort, time_constraint) do
    effort_days = effort_to_days(effort)
    constraint_days = effort_to_days(time_constraint)
    
    if effort_days <= constraint_days do
      # Under time constraint - higher score for faster delivery
      1.0 - (effort_days / constraint_days) * 0.3
    else
      # Over time constraint - penalize
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
    # Simple alignment based on whether approach mentions goals
    # In real implementation, might use semantic similarity
    if goals && approach["best_when"] do
      goals_text = format_goals(goals) |> String.downcase()
      best_when = String.downcase(approach["best_when"])
      
      if String.contains?(best_when, ["fast", "quick"]) && String.contains?(goals_text, ["quick", "fast"]) do
        0.9
      else
        0.7  # Default reasonable alignment
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

  defp calculate_max_depth(_tasks) do
    # Calculate maximum depth in task hierarchy
    # For now, assume flat structure
    1
  end

  defp calculate_complexity_distribution(tasks) do
    tasks
    |> Enum.frequencies_by(& &1["complexity"])
    |> Enum.map(fn {complexity, count} ->
      {complexity, count / length(tasks) * 100}
    end)
    |> Map.new()
  end
end
