defmodule RubberDuck.Workflows.ResourceEstimator do
  @moduledoc """
  Estimates resource requirements for workflow execution based on task characteristics,
  historical data, and system constraints.

  This module provides sophisticated resource prediction to help the dynamic workflow
  system allocate appropriate resources and avoid overcommitting system capacity.

  ## Key Features

  - Memory usage prediction based on task complexity and data size
  - Agent capacity planning for concurrent workflow execution
  - Execution time estimation using historical performance data
  - Resource scaling recommendations for different load scenarios
  - Bottleneck detection and mitigation suggestions
  """

  require Logger

  @type task :: map()
  @type historical_data ::
          %{
            execution_times: [%{task_signature: map(), duration: non_neg_integer()}],
            resource_usage: [%{task_signature: map(), memory: non_neg_integer(), agents: non_neg_integer()}],
            performance_metrics: map()
          }
          | nil

  @type resource_estimate :: %{
          memory: %{
            estimated: non_neg_integer(),
            confidence: float(),
            peak_usage: non_neg_integer()
          },
          agents: %{
            required: [atom()],
            optimal_count: non_neg_integer(),
            concurrent_capacity: non_neg_integer()
          },
          time: %{
            estimated_duration: non_neg_integer(),
            confidence: float(),
            best_case: non_neg_integer(),
            worst_case: non_neg_integer()
          },
          scaling: %{
            parallelization_factor: float(),
            bottlenecks: [atom()],
            recommendations: [map()]
          }
        }

  # Base resource requirements for different agent types (in MB)
  @agent_base_memory %{
    research: 50,
    analysis: 75,
    generation: 100,
    review: 40,
    coordination: 30
  }

  # Default execution time estimates (in milliseconds)
  @base_execution_times %{
    simple_analysis: 5_000,
    deep_analysis: 30_000,
    generation_pipeline: 45_000,
    simple_refactoring: 15_000,
    complex_refactoring: 120_000,
    review_pipeline: 20_000
  }

  @doc """
  Estimates comprehensive resource requirements for a given task.
  """
  @spec estimate(task(), historical_data()) :: resource_estimate()
  def estimate(task, historical_data \\ nil) do
    Logger.debug("Estimating resources for task: #{inspect(task[:type])}")

    %{
      memory: estimate_memory_requirements(task, historical_data),
      agents: estimate_agent_requirements(task, historical_data),
      time: estimate_execution_time(task, historical_data),
      scaling: analyze_scaling_characteristics(task, historical_data)
    }
  end

  @doc """
  Estimates memory usage for the task execution.
  """
  @spec estimate_memory_requirements(task(), historical_data()) :: map()
  def estimate_memory_requirements(task, historical_data) do
    base_memory = calculate_base_memory(task)
    data_overhead = calculate_data_overhead(task)
    agent_memory = calculate_agent_memory_overhead(task)

    total_estimated = base_memory + data_overhead + agent_memory

    # Apply historical adjustments if available
    {adjusted_estimate, confidence} =
      if historical_data do
        apply_historical_memory_adjustments(total_estimated, task, historical_data)
      else
        # Lower confidence without historical data
        {total_estimated, 0.6}
      end

    %{
      estimated: adjusted_estimate,
      confidence: confidence,
      # Account for peak usage
      peak_usage: round(adjusted_estimate * 1.3),
      breakdown: %{
        base: base_memory,
        data_overhead: data_overhead,
        agent_overhead: agent_memory
      }
    }
  end

  @doc """
  Estimates agent requirements for optimal task execution.
  """
  @spec estimate_agent_requirements(task(), historical_data()) :: map()
  def estimate_agent_requirements(task, _historical_data) do
    required_types = determine_required_agent_types(task)
    optimal_counts = calculate_optimal_agent_counts(task, required_types)
    concurrent_capacity = estimate_concurrent_capacity(task, required_types)

    %{
      required: required_types,
      optimal_count: Enum.sum(Map.values(optimal_counts)),
      concurrent_capacity: concurrent_capacity,
      breakdown: optimal_counts,
      utilization_estimate: calculate_agent_utilization(task, optimal_counts)
    }
  end

  @doc """
  Estimates execution time based on task complexity and historical performance.
  """
  @spec estimate_execution_time(task(), historical_data()) :: map()
  def estimate_execution_time(task, historical_data) do
    base_time = get_base_execution_time(task)
    complexity_multiplier = calculate_complexity_multiplier(task)

    estimated_duration = round(base_time * complexity_multiplier)

    {final_estimate, confidence} =
      if historical_data do
        refine_with_historical_data(estimated_duration, task, historical_data)
      else
        {estimated_duration, 0.7}
      end

    %{
      estimated_duration: final_estimate,
      confidence: confidence,
      best_case: round(final_estimate * 0.7),
      worst_case: round(final_estimate * 1.8),
      factors: %{
        base_time: base_time,
        complexity_multiplier: complexity_multiplier
      }
    }
  end

  @doc """
  Analyzes scaling characteristics and provides optimization recommendations.
  """
  @spec analyze_scaling_characteristics(task(), historical_data()) :: map()
  def analyze_scaling_characteristics(task, _historical_data) do
    parallelization_factor = calculate_parallelization_factor(task)
    bottlenecks = identify_potential_bottlenecks(task)
    recommendations = generate_scaling_recommendations(task, bottlenecks)

    %{
      parallelization_factor: parallelization_factor,
      bottlenecks: bottlenecks,
      recommendations: recommendations,
      scaling_efficiency: estimate_scaling_efficiency(task, parallelization_factor)
    }
  end

  @doc """
  Validates if current system resources can handle the estimated requirements.
  """
  @spec validate_resource_availability(resource_estimate(), map()) :: {:ok, map()} | {:error, term()}
  def validate_resource_availability(estimate, system_constraints \\ %{}) do
    # Default 4GB
    memory_available = Map.get(system_constraints, :memory_mb, 4000)
    max_agents = Map.get(system_constraints, :max_agents, 10)

    violations = []

    violations =
      if estimate.memory.estimated > memory_available do
        [%{type: :memory_exceeded, required: estimate.memory.estimated, available: memory_available} | violations]
      else
        violations
      end

    violations =
      if estimate.agents.optimal_count > max_agents do
        [%{type: :agent_limit_exceeded, required: estimate.agents.optimal_count, limit: max_agents} | violations]
      else
        violations
      end

    case violations do
      [] ->
        {:ok, %{status: :feasible, resource_utilization: calculate_utilization(estimate, system_constraints)}}

      violations ->
        {:error, %{status: :resource_constraints_violated, violations: violations}}
    end
  end

  # Private functions

  defp calculate_base_memory(task) do
    case task[:type] do
      :analysis -> 100
      :generation -> 200
      :refactoring -> 150
      :review -> 80
      :complex_refactoring -> 400
      :architecture_refactoring -> 600
      _ -> 120
    end
  end

  defp calculate_data_overhead(task) do
    code_size = get_in(task, [:code_stats, :loc]) || 50
    file_count = length(task[:targets] || task[:files] || [task[:target]] |> Enum.filter(& &1))

    # Estimate based on lines of code and file count
    # Cap at 500MB for code processing
    base_overhead = min(code_size * 0.5, 500)
    # 10MB per file baseline
    file_overhead = file_count * 10

    round(base_overhead + file_overhead)
  end

  defp calculate_agent_memory_overhead(task) do
    agent_types = determine_required_agent_types(task)

    Enum.reduce(agent_types, 0, fn type, acc ->
      acc + Map.get(@agent_base_memory, type, 60)
    end)
  end

  defp apply_historical_memory_adjustments(estimate, task, historical_data) do
    similar_tasks = find_similar_tasks(task, historical_data[:resource_usage] || [])

    case similar_tasks do
      [] ->
        {estimate, 0.6}

      similar ->
        avg_actual =
          similar
          |> Enum.map(& &1.memory)
          |> Enum.sum()
          |> div(length(similar))

        # Adjust estimate based on historical data
        adjustment_factor = avg_actual / Enum.max([estimate, 1])
        adjusted = round(estimate * adjustment_factor)
        confidence = min(0.9, 0.6 + length(similar) * 0.05)

        {adjusted, confidence}
    end
  end

  defp determine_required_agent_types(task) do
    base_types =
      case task[:type] do
        :analysis -> [:analysis]
        :generation -> [:research, :generation]
        :refactoring -> [:analysis, :generation]
        :review -> [:analysis, :review]
        :complex_refactoring -> [:research, :analysis, :generation, :review]
        :architecture_refactoring -> [:research, :analysis, :generation, :review, :coordination]
        _ -> [:analysis]
      end

    # Add additional types based on task characteristics
    additional_types = []

    additional_types =
      if task[:options][:security_check] do
        [:review | additional_types]
      else
        additional_types
      end

    additional_types =
      if length(task[:targets] || task[:files] || []) > 5 do
        [:coordination | additional_types]
      else
        additional_types
      end

    (base_types ++ additional_types) |> Enum.uniq()
  end

  defp calculate_optimal_agent_counts(task, agent_types) do
    file_count = length(task[:targets] || task[:files] || [])
    complexity_score = get_in(task, [:complexity, :score]) || calculate_basic_complexity(task)

    Enum.reduce(agent_types, %{}, fn type, acc ->
      count =
        case type do
          :research -> 1
          :analysis -> max(1, min(file_count, 3))
          :generation -> max(1, min(div(complexity_score, 3), 2))
          :review -> 1
          :coordination -> if file_count > 5, do: 1, else: 0
        end

      Map.put(acc, type, count)
    end)
  end

  defp estimate_concurrent_capacity(task, agent_types) do
    # Estimate how many similar tasks could run concurrently
    base_capacity = length(agent_types)

    # Reduce capacity for resource-intensive tasks
    complexity_factor =
      case task[:type] do
        :architecture_refactoring -> 0.3
        :complex_refactoring -> 0.5
        :generation -> 0.7
        _ -> 1.0
      end

    max(1, round(base_capacity * complexity_factor))
  end

  defp calculate_agent_utilization(task, agent_counts) do
    _total_agents = Enum.sum(Map.values(agent_counts))
    estimated_duration = get_base_execution_time(task)

    # Calculate expected utilization percentage
    base_utilization =
      case task[:type] do
        :analysis -> 0.8
        :generation -> 0.9
        :review -> 0.7
        _ -> 0.75
      end

    %{
      average_utilization: base_utilization,
      peak_utilization: min(1.0, base_utilization * 1.2),
      estimated_idle_time: round(estimated_duration * (1 - base_utilization))
    }
  end

  defp get_base_execution_time(task) do
    workflow_type = task[:suggested_workflow_type] || infer_workflow_type(task)
    Map.get(@base_execution_times, workflow_type, 20_000)
  end

  defp infer_workflow_type(task) do
    case task[:type] do
      :analysis -> :simple_analysis
      :generation -> :generation_pipeline
      :refactoring -> :simple_refactoring
      :complex_refactoring -> :complex_refactoring
      :review -> :review_pipeline
      _ -> :simple_analysis
    end
  end

  defp calculate_complexity_multiplier(task) do
    base_multiplier = 1.0

    # File count factor
    file_count = length(task[:targets] || task[:files] || [])
    file_factor = 1.0 + file_count * 0.1

    # Code size factor  
    loc = get_in(task, [:code_stats, :loc]) || 100
    size_factor = 1.0 + loc / 1000.0

    # Options complexity
    options_factor = if map_size(task[:options] || %{}) > 3, do: 1.2, else: 1.0

    base_multiplier * file_factor * size_factor * options_factor
  end

  defp refine_with_historical_data(estimate, task, historical_data) do
    execution_times = historical_data[:execution_times] || []
    similar_executions = find_similar_tasks(task, execution_times)

    case similar_executions do
      [] ->
        {estimate, 0.7}

      similar ->
        avg_duration =
          similar
          |> Enum.map(& &1.duration)
          |> Enum.sum()
          |> div(length(similar))

        # Weight the historical average with our estimate
        weight = min(0.7, length(similar) * 0.1)
        refined = round(estimate * (1 - weight) + avg_duration * weight)
        confidence = min(0.95, 0.7 + length(similar) * 0.05)

        {refined, confidence}
    end
  end

  defp calculate_parallelization_factor(task) do
    file_count = length(task[:targets] || task[:files] || [])

    base_factor =
      case task[:type] do
        :analysis -> min(3.0, file_count * 0.8)
        :generation -> 1.5
        :refactoring -> min(2.0, file_count * 0.6)
        :review -> min(2.0, file_count * 0.9)
        _ -> 1.0
      end

    # Adjust for task dependencies
    if task[:options][:sequential_required] do
      max(1.0, base_factor * 0.3)
    else
      base_factor
    end
  end

  defp identify_potential_bottlenecks(task) do
    bottlenecks = []

    # I/O bottlenecks
    file_count = length(task[:targets] || task[:files] || [])

    bottlenecks =
      if file_count > 10 do
        [:file_io | bottlenecks]
      else
        bottlenecks
      end

    # Memory bottlenecks
    loc = get_in(task, [:code_stats, :loc]) || 0

    bottlenecks =
      if loc > 10_000 do
        [:memory_intensive | bottlenecks]
      else
        bottlenecks
      end

    # Agent coordination bottlenecks
    complexity = calculate_basic_complexity(task)

    bottlenecks =
      if complexity > 7 do
        [:agent_coordination | bottlenecks]
      else
        bottlenecks
      end

    bottlenecks
  end

  defp generate_scaling_recommendations(_task, bottlenecks) do
    Enum.flat_map(bottlenecks, fn bottleneck ->
      case bottleneck do
        :file_io ->
          [
            %{
              type: :optimization,
              category: :io,
              suggestion: "Consider batching file operations and using stream processing",
              impact: :high
            }
          ]

        :memory_intensive ->
          [
            %{
              type: :resource_allocation,
              category: :memory,
              suggestion: "Increase memory allocation or implement data streaming",
              impact: :medium
            }
          ]

        :agent_coordination ->
          [
            %{
              type: :architecture,
              category: :coordination,
              suggestion: "Implement hierarchical coordination or reduce agent dependencies",
              impact: :high
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp estimate_scaling_efficiency(task, parallelization_factor) do
    # Amdahl's law approximation
    sequential_portion =
      case task[:type] do
        # Generation has more sequential dependencies
        :generation -> 0.4
        :refactoring -> 0.3
        :analysis -> 0.2
        _ -> 0.25
      end

    if parallelization_factor > 1 do
      1 / (sequential_portion + (1 - sequential_portion) / parallelization_factor)
    else
      1.0
    end
  end

  defp find_similar_tasks(task, historical_tasks) do
    task_signature = generate_task_signature(task)

    Enum.filter(historical_tasks, fn historical ->
      similarity = calculate_task_similarity(task_signature, historical.task_signature)
      similarity > 0.7
    end)
  end

  defp generate_task_signature(task) do
    %{
      type: task[:type],
      file_count: length(task[:targets] || task[:files] || []),
      has_options: map_size(task[:options] || %{}) > 0,
      complexity_category: categorize_complexity(task)
    }
  end

  defp calculate_task_similarity(sig1, sig2) do
    type_match = if sig1.type == sig2.type, do: 0.4, else: 0.0
    file_similarity = 1.0 - abs(sig1.file_count - sig2.file_count) / Enum.max([sig1.file_count, sig2.file_count, 1])
    options_match = if sig1.has_options == sig2.has_options, do: 0.2, else: 0.1
    complexity_match = if sig1.complexity_category == sig2.complexity_category, do: 0.3, else: 0.1

    type_match + file_similarity * 0.3 + options_match + complexity_match
  end

  defp categorize_complexity(task) do
    score = calculate_basic_complexity(task)

    cond do
      score <= 3 -> :low
      score <= 6 -> :medium
      score <= 8 -> :high
      true -> :very_high
    end
  end

  defp calculate_basic_complexity(task) do
    base_score =
      case task[:type] do
        :analysis -> 2
        :generation -> 4
        :refactoring -> 3
        :complex_refactoring -> 7
        :architecture_refactoring -> 9
        _ -> 3
      end

    file_factor = min(3, length(task[:targets] || task[:files] || []) * 0.5)
    options_factor = min(2, map_size(task[:options] || %{}) * 0.3)

    round(base_score + file_factor + options_factor)
  end

  defp calculate_utilization(estimate, constraints) do
    memory_util = estimate.memory.estimated / Map.get(constraints, :memory_mb, 4000)
    agent_util = estimate.agents.optimal_count / Map.get(constraints, :max_agents, 10)

    %{
      memory_utilization: memory_util,
      agent_utilization: agent_util,
      overall_utilization: max(memory_util, agent_util)
    }
  end
end
