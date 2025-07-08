defmodule RubberDuck.Workflows.ComplexityAnalyzer do
  @moduledoc """
  Analyzes task complexity to determine optimal workflow construction.

  Examines various factors including:
  - Task type and size
  - Code complexity metrics
  - Resource requirements
  - Dependency relationships
  - Historical performance data
  """

  require Logger

  @type task :: map()
  @type analysis_result :: %{
          complexity_score: float(),
          task_type: atom(),
          size_category: :small | :medium | :large,
          resource_requirements: %{
            agents: list(atom()),
            memory: :low | :medium | :high,
            estimated_time: integer()
          },
          parallelization_strategy: atom(),
          suggested_workflow_type: atom(),
          dependency_graph: map(),
          warnings: list(atom())
        }

  # Complexity scoring weights
  @loc_weight 0.001
  @complexity_weight 0.1
  @file_count_weight 2.0
  @option_weight 1.5

  # Time estimation constants (ms)
  @base_time 10_000
  @time_per_loc 10
  @time_per_file 5_000

  @doc """
  Analyzes a task and returns workflow requirements.
  """
  @spec analyze(task(), map() | nil) :: analysis_result()
  def analyze(task, historical_data \\ nil) do
    %{
      complexity_score: calculate_complexity(task),
      task_type: Map.get(task, :type, :unknown),
      size_category: categorize_size(task),
      resource_requirements: estimate_resources(task, historical_data),
      parallelization_strategy: analyze_dependencies(task),
      suggested_workflow_type: suggest_workflow_type(task),
      dependency_graph: build_dependency_graph(task),
      warnings: validate_task(task)
    }
  end

  @doc """
  Calculates a complexity score for the task.
  """
  @spec calculate_complexity(task()) :: float()
  def calculate_complexity(task) do
    base_score = get_base_complexity(Map.get(task, :type))

    # Add code complexity if available
    code_score =
      if stats = task[:code_stats] do
        loc_score = Map.get(stats, :loc, 0) * @loc_weight
        complexity_score = Map.get(stats, :cyclomatic_complexity, 0) * @complexity_weight
        function_score = Map.get(stats, :functions, 0) * 0.5

        loc_score + complexity_score + function_score
      else
        0
      end

    # Add file count complexity
    file_score =
      case task do
        %{targets: targets} when is_list(targets) ->
          length(targets) * @file_count_weight

        %{target: _} ->
          @file_count_weight

        _ ->
          0
      end

    # Add option complexity
    option_score =
      if options = task[:options] do
        Enum.count(options, fn {_k, v} -> v == true end) * @option_weight
      else
        0
      end

    total = base_score + code_score + file_score + option_score

    # Clamp between 0 and 10
    min(10, max(0, total))
  end

  @doc """
  Estimates resource requirements for the task.
  """
  @spec estimate_resources(task(), map() | nil) :: map()
  def estimate_resources(task, historical_data \\ nil) do
    agents = determine_required_agents(task)
    memory = estimate_memory_usage(task)
    time = estimate_execution_time(task, historical_data)

    %{
      agents: agents,
      memory: memory,
      estimated_time: time
    }
  end

  @doc """
  Analyzes task dependencies to determine parallelization strategy.
  """
  @spec analyze_dependencies(task()) :: atom()
  def analyze_dependencies(task) do
    cond do
      # Check for explicit subtasks
      subtasks = task[:subtasks] ->
        analyze_subtask_dependencies(subtasks)

      # Check for file dependencies
      deps = task[:dependencies] ->
        analyze_file_dependencies(deps)

      # Check for multiple targets
      targets = task[:targets] ->
        if length(targets) > 1, do: :parallel_analysis, else: :sequential

      # Default based on task type
      true ->
        default_strategy_for_type(task[:type])
    end
  end

  # Private functions

  defp get_base_complexity(type) do
    case type do
      :analysis -> 3.0
      :generation -> 5.0
      :refactoring -> 7.0
      :review -> 4.0
      :optimization -> 8.0
      # default medium complexity
      _ -> 5.0
    end
  end

  defp categorize_size(task) do
    size_indicators = [
      get_loc_size(task),
      get_file_count_size(task),
      get_complexity_size(task)
    ]

    # Take the maximum size category
    size_priority = %{small: 1, medium: 2, large: 3}

    size_indicators
    |> Enum.max_by(&Map.get(size_priority, &1, 1))
  end

  defp get_loc_size(task) do
    case get_in(task, [:code_stats, :loc]) do
      nil -> :small
      loc when loc < 200 -> :small
      loc when loc < 1000 -> :medium
      _ -> :large
    end
  end

  defp get_file_count_size(task) do
    count =
      case task do
        %{targets: targets} -> length(targets)
        %{target: _} -> 1
        _ -> 0
      end

    cond do
      count <= 1 -> :small
      count <= 5 -> :medium
      true -> :large
    end
  end

  defp get_complexity_size(task) do
    case get_in(task, [:code_stats, :cyclomatic_complexity]) do
      nil -> :small
      cc when cc < 20 -> :small
      cc when cc < 50 -> :medium
      _ -> :large
    end
  end

  defp determine_required_agents(task) do
    base_agents =
      case Map.get(task, :type) do
        :analysis ->
          [:analysis] ++ maybe_add_research(task)

        :generation ->
          [:research, :generation, :review]

        :refactoring ->
          [:research, :analysis, :generation, :review]

        :review ->
          [:analysis, :review]

        :optimization ->
          [:research, :analysis, :generation, :review]

        _ ->
          [:research, :analysis]
      end

    # Add specialized agents based on options
    add_specialized_agents(base_agents, task[:options] || %{})
  end

  defp maybe_add_research(task) do
    if task[:options][:deep_analysis] || task[:options][:security_check] do
      [:research]
    else
      []
    end
  end

  defp add_specialized_agents(agents, options) do
    agents
    |> maybe_add_agent(:security, options[:security_check])
    |> maybe_add_agent(:performance, options[:performance_analysis])
    |> Enum.uniq()
  end

  defp maybe_add_agent(agents, agent_type, true), do: agents ++ [agent_type]
  defp maybe_add_agent(agents, _agent_type, _), do: agents

  defp estimate_memory_usage(task) do
    size = categorize_size(task)
    agent_count = length(determine_required_agents(task))

    cond do
      size == :large || agent_count > 4 -> :high
      size == :medium || agent_count > 2 -> :medium
      true -> :low
    end
  end

  defp estimate_execution_time(task, historical_data) do
    # Use historical data if available
    if historical_data && historical_data[:similar_tasks] do
      historical_average(historical_data.similar_tasks)
    else
      # Estimate based on task characteristics
      estimate_time_from_task(task)
    end
  end

  defp historical_average(similar_tasks) do
    durations = Enum.map(similar_tasks, & &1.duration)

    if length(durations) > 0 do
      (Enum.sum(durations) / length(durations))
      |> round()
    else
      @base_time
    end
  end

  defp estimate_time_from_task(task) do
    base = @base_time

    # Add time for lines of code
    loc_time =
      case get_in(task, [:code_stats, :loc]) do
        nil -> 0
        loc -> loc * @time_per_loc
      end

    # Add time for multiple files
    file_time =
      case task do
        %{targets: targets} -> length(targets) * @time_per_file
        %{target: _} -> @time_per_file
        _ -> 0
      end

    # Add time for complex operations
    option_time =
      if options = task[:options] do
        option_count = Enum.count(options, fn {_k, v} -> v == true end)
        option_count * 10_000
      else
        0
      end

    base + loc_time + file_time + option_time
  end

  defp analyze_subtask_dependencies(subtasks) do
    dep_counts =
      Enum.map(subtasks, fn task ->
        length(Map.get(task, :depends_on, []))
      end)

    max_deps = Enum.max(dep_counts, fn -> 0 end)

    cond do
      max_deps == 0 -> :fully_parallel
      max_deps == length(subtasks) - 1 -> :sequential
      true -> :mixed_parallel
    end
  end

  defp analyze_file_dependencies(deps) when is_map(deps) do
    if has_circular_dependencies?(deps) do
      # Safe fallback
      :sequential
    else
      :dependency_aware
    end
  end

  defp analyze_file_dependencies(_), do: :sequential

  defp has_circular_dependencies?(deps) do
    # Simple cycle detection - could be enhanced
    Enum.any?(deps, fn {file, file_deps} ->
      Enum.any?(file_deps, fn dep ->
        Map.get(deps, dep, []) |> Enum.member?(file)
      end)
    end)
  end

  defp default_strategy_for_type(type) do
    case type do
      :analysis -> :parallel_analysis
      :generation -> :pipeline
      :refactoring -> :parallel_analysis
      _ -> :sequential
    end
  end

  defp suggest_workflow_type(task) do
    complexity = calculate_complexity(task)

    case {task[:type], complexity} do
      {:analysis, score} when score < 4 -> :simple_analysis
      {:analysis, _} -> :deep_analysis
      {:generation, _} -> :generation_pipeline
      {:refactoring, score} when score < 6 -> :simple_refactoring
      {:refactoring, _} -> :complex_refactoring
      {:review, _} -> :review_pipeline
      {:custom, _} -> :adaptive
      _ -> :adaptive
    end
  end

  defp build_dependency_graph(task) do
    cond do
      deps = task[:dependencies] -> deps
      subtasks = task[:subtasks] -> build_subtask_graph(subtasks)
      true -> %{}
    end
  end

  defp build_subtask_graph(subtasks) do
    Enum.reduce(subtasks, %{}, fn task, acc ->
      Map.put(acc, task.id, Map.get(task, :depends_on, []))
    end)
  end

  defp validate_task(task) do
    warnings = []

    warnings = if !task[:type], do: [:missing_type | warnings], else: warnings
    warnings = if !task[:target] && !task[:targets], do: [:missing_target | warnings], else: warnings

    warnings
  end
end
