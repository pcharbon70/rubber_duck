defmodule RubberDuck.Planning.TaskDecomposer do
  @moduledoc """
  Task decomposition engine that breaks down high-level requests into actionable tasks.
  
  This engine uses LLM-guided decomposition with validation to create structured,
  executable task hierarchies. It supports multiple decomposition strategies and
  integrates with the CoT reasoning system.
  """
  
  @behaviour RubberDuck.Engine
  
  alias RubberDuck.CoT
  # alias RubberDuck.Planning.{Plan, Task, TaskDependency}
  alias RubberDuck.LLM.Service, as: LLM
  
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
      {:ok, %{
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
        strategy = response.content
        |> String.trim()
        |> String.downcase()
        |> String.to_existing_atom()
        
        if strategy in @decomposition_strategies do
          {:ok, strategy}
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
    
    case LLM.completion(model: state.llm_config[:model] || "gpt-4", messages: [%{role: "user", content: prompt}], response_format: %{type: "json_object"}) do
      {:ok, response} ->
        tasks = Jason.decode!(response.content)
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
    # Use CoT for hierarchical decomposition
    {:ok, result} = CoT.simple_reason(
      input.query,
      [
        {:analyze, "What are the main components or phases of this request?"},
        {:decompose, "For each component, what are the specific tasks needed?"},
        {:structure, "How should these tasks be organized hierarchically?"}
      ],
      format: :structured
    )
    
    # Convert CoT result to task structure
    tasks = extract_hierarchical_tasks(result, state)
    {:ok, tasks}
  end
  
  defp tree_of_thought_decomposition(input, state) do
    # Generate multiple decomposition approaches
    prompt = """
    Generate 3 different approaches to decompose this request:
    
    Request: #{input.query}
    
    For each approach:
    1. Name the approach
    2. List the tasks in that approach
    3. Explain why this approach might be good
    
    Return as JSON.
    """
    
    case LLM.completion(model: state.llm_config[:model] || "gpt-4", messages: [%{role: "user", content: prompt}], response_format: %{type: "json_object"}) do
      {:ok, response} ->
        approaches = Jason.decode!(response.content)
        
        # Evaluate approaches and select best one
        {:ok, best_approach} = select_best_approach(approaches, input, state)
        
        # Convert to task list
        tasks = best_approach["tasks"]
        |> Enum.with_index()
        |> Enum.map(fn {task, index} ->
          Map.merge(task, %{"position" => index})
        end)
        
        {:ok, tasks}
        
      error ->
        error
    end
  end
  
  # Task refinement
  
  defp refine_tasks(tasks, state) do
    refined = Enum.map(tasks, fn task ->
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
        complexity = response.content
        |> String.trim()
        |> String.downcase()
        |> String.replace("_", "_")
        
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
    
    case LLM.completion(model: state.llm_config[:model] || "gpt-4", messages: [%{role: "user", content: prompt}], response_format: %{type: "json_object"}) do
      {:ok, response} ->
        {:ok, Jason.decode!(response.content)}
        
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
    
    case LLM.completion(model: state.llm_config[:model] || "gpt-4", messages: [%{role: "user", content: prompt}], response_format: %{type: "json_object"}) do
      {:ok, response} ->
        deps = Jason.decode!(response.content)
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
    graph = Enum.reduce(dependencies, %{}, fn %{from: from, to: to}, acc ->
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
    
    result = Enum.find_value(neighbors, fn neighbor ->
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
        {:error, _} = error -> error
        nil -> {:ok, %{tasks: tasks, valid: true}}
      end
    else
      {:ok, %{tasks: tasks, valid: true}}
    end
  end
  
  def validate_task_completeness(tasks) do
    required_fields = ["name", "description", "complexity", "success_criteria"]
    
    incomplete = Enum.filter(tasks, fn task ->
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
    
    invalid_deps = Enum.filter(dependencies, fn %{from: from, to: to} ->
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
    without_criteria = Enum.filter(tasks, fn task ->
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
  
  defp extract_hierarchical_tasks(_cot_result, _state) do
    # Extract tasks from CoT reasoning result
    # This is a simplified version - real implementation would be more sophisticated
    []
  end
  
  defp select_best_approach(approaches, _input, _state) do
    # Use LLM to evaluate and select best approach
    # For now, just select first one
    {:ok, List.first(approaches)}
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