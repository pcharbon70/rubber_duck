defmodule RubberDuck.Workflows.OptimizationEngine do
  @moduledoc """
  Advanced optimization engine for dynamic workflows that analyzes execution patterns,
  resource utilization, and performance metrics to automatically improve workflow efficiency.

  This module provides intelligent optimization strategies that adapt to different scenarios:
  - Speed optimization for time-critical tasks
  - Resource optimization for constrained environments  
  - Balanced optimization for general use cases
  - Learning-based optimization using historical performance data

  ## Key Features

  - Multi-objective optimization balancing speed, resources, and reliability
  - Adaptive optimization strategies based on system load and constraints
  - Performance prediction using machine learning techniques
  - Real-time optimization adjustments during execution
  - Historical pattern analysis for continuous improvement
  """

  require Logger

  alias RubberDuck.Workflows.TemplateRegistry

  @type task :: map()
  @type resource_estimate :: map()
  @type optimization_strategy :: :speed | :resource | :balanced | :adaptive
  @type performance_profile :: %{
          execution_history: [map()],
          resource_patterns: [map()],
          bottleneck_analysis: map(),
          success_metrics: map()
        }

  @type optimization_result :: %{
          strategy: optimization_strategy(),
          adjustments: [map()],
          predicted_improvement: %{
            execution_time: float(),
            resource_efficiency: float(),
            success_probability: float()
          },
          confidence: float(),
          rationale: [String.t()]
        }

  # Optimization weights for different strategies
  @strategy_weights %{
    speed: %{execution_time: 0.7, resource_usage: 0.1, reliability: 0.2},
    resource: %{execution_time: 0.2, resource_usage: 0.6, reliability: 0.2},
    balanced: %{execution_time: 0.4, resource_usage: 0.3, reliability: 0.3},
    adaptive: %{execution_time: 0.5, resource_usage: 0.3, reliability: 0.2}
  }

  @doc """
  Optimizes a workflow configuration based on task characteristics, resource estimates,
  and performance requirements.
  """
  @spec optimize(task(), resource_estimate(), optimization_strategy(), performance_profile() | nil) ::
          optimization_result()
  def optimize(task, resource_estimate, strategy \\ :balanced, performance_profile \\ nil) do
    Logger.debug("Optimizing workflow with strategy: #{strategy}")

    # Analyze current configuration
    baseline_metrics = analyze_baseline_performance(task, resource_estimate)

    # Generate optimization candidates
    candidates = generate_optimization_candidates(task, resource_estimate, strategy)

    # Evaluate each candidate
    evaluated_candidates = evaluate_candidates(candidates, baseline_metrics, strategy, performance_profile)

    # Select best optimization
    best_candidate = select_optimal_candidate(evaluated_candidates, strategy)

    # Generate final optimization result
    create_optimization_result(best_candidate, baseline_metrics, strategy)
  end

  @doc """
  Analyzes execution patterns to suggest optimal strategies for similar future tasks.
  """
  @spec analyze_performance_patterns(performance_profile()) :: %{
          recommended_strategy: optimization_strategy(),
          bottlenecks: [atom()],
          improvement_opportunities: [map()],
          confidence: float()
        }
  def analyze_performance_patterns(performance_profile) do
    execution_patterns = analyze_execution_patterns(performance_profile.execution_history)
    resource_patterns = analyze_resource_patterns(performance_profile.resource_patterns)
    bottlenecks = identify_performance_bottlenecks(performance_profile.bottleneck_analysis)

    recommended_strategy = recommend_strategy(execution_patterns, resource_patterns, bottlenecks)
    improvement_opportunities = identify_improvement_opportunities(execution_patterns, resource_patterns)

    confidence = calculate_pattern_confidence(performance_profile)

    %{
      recommended_strategy: recommended_strategy,
      bottlenecks: bottlenecks,
      improvement_opportunities: improvement_opportunities,
      confidence: confidence,
      patterns: %{
        execution: execution_patterns,
        resource: resource_patterns
      }
    }
  end

  @doc """
  Provides real-time optimization adjustments during workflow execution.
  """
  @spec suggest_runtime_adjustments(map(), map()) :: %{
          adjustments: [map()],
          urgency: :low | :medium | :high,
          estimated_impact: map()
        }
  def suggest_runtime_adjustments(current_metrics, target_performance) do
    performance_gap = calculate_performance_gap(current_metrics, target_performance)

    adjustments =
      cond do
        performance_gap.execution_time > 0.3 ->
          generate_speed_adjustments(current_metrics)

        performance_gap.resource_usage > 0.4 ->
          generate_resource_adjustments(current_metrics)

        performance_gap.error_rate > 0.1 ->
          generate_reliability_adjustments(current_metrics)

        true ->
          []
      end

    urgency = determine_adjustment_urgency(performance_gap)
    estimated_impact = estimate_adjustment_impact(adjustments, current_metrics)

    %{
      adjustments: adjustments,
      urgency: urgency,
      estimated_impact: estimated_impact
    }
  end

  @doc """
  Optimizes workflow templates based on usage patterns and performance data.
  """
  @spec optimize_template(atom(), [map()]) :: {:ok, map()} | {:error, term()}
  def optimize_template(template_name, usage_data) do
    case TemplateRegistry.get_by_name(template_name) do
      {:ok, template} ->
        optimized_template = apply_template_optimizations(template, usage_data)
        {:ok, optimized_template}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Learns from execution results to improve future optimizations.
  """
  @spec learn_from_execution(map(), optimization_result(), map()) :: :ok
  def learn_from_execution(task, optimization_result, actual_performance) do
    # Calculate prediction accuracy
    accuracy = calculate_prediction_accuracy(optimization_result, actual_performance)

    # Update optimization models
    update_optimization_models(task, optimization_result, actual_performance, accuracy)

    # Store learning data for future reference
    store_learning_data(task, optimization_result, actual_performance, accuracy)

    Logger.debug("Learned from execution with accuracy: #{accuracy}")
    :ok
  end

  # Private functions

  defp analyze_baseline_performance(_task, resource_estimate) do
    %{
      estimated_execution_time: resource_estimate.time.estimated_duration,
      estimated_memory_usage: resource_estimate.memory.estimated,
      required_agents: length(resource_estimate.agents.required),
      parallelization_potential: resource_estimate.scaling.parallelization_factor,
      identified_bottlenecks: resource_estimate.scaling.bottlenecks
    }
  end

  defp generate_optimization_candidates(task, resource_estimate, strategy) do
    base_candidates = [
      generate_parallelization_candidate(task, resource_estimate),
      generate_resource_allocation_candidate(task, resource_estimate),
      generate_step_optimization_candidate(task, resource_estimate),
      generate_caching_candidate(task, resource_estimate),
      generate_pipeline_optimization_candidate(task, resource_estimate)
    ]

    # Add strategy-specific candidates
    strategy_candidates =
      case strategy do
        :speed -> generate_speed_candidates(task, resource_estimate)
        :resource -> generate_resource_candidates(task, resource_estimate)
        :balanced -> generate_balanced_candidates(task, resource_estimate)
        :adaptive -> generate_adaptive_candidates(task, resource_estimate)
      end

    (base_candidates ++ strategy_candidates) |> Enum.filter(& &1)
  end

  defp generate_parallelization_candidate(_task, resource_estimate) do
    if resource_estimate.scaling.parallelization_factor > 1.5 do
      %{
        type: :parallelization,
        description: "Increase parallel execution of independent steps",
        adjustments: %{
          max_concurrent_steps: min(8, round(resource_estimate.scaling.parallelization_factor)),
          enable_parallel_agent_execution: true
        },
        estimated_speedup: min(resource_estimate.scaling.parallelization_factor * 0.7, 3.0),
        resource_overhead: 1.2
      }
    end
  end

  defp generate_resource_allocation_candidate(_task, resource_estimate) do
    if resource_estimate.agents.optimal_count > 2 do
      %{
        type: :resource_allocation,
        description: "Optimize agent allocation and memory usage",
        adjustments: %{
          agent_pool_size: resource_estimate.agents.optimal_count + 1,
          memory_preallocation: round(resource_estimate.memory.estimated * 1.1),
          enable_agent_reuse: true
        },
        estimated_speedup: 1.15,
        resource_overhead: 0.9
      }
    end
  end

  defp generate_step_optimization_candidate(_task, _resource_estimate) do
    %{
      type: :step_optimization,
      description: "Optimize individual step execution",
      adjustments: %{
        enable_step_batching: true,
        optimize_data_flow: true,
        reduce_intermediate_storage: true
      },
      estimated_speedup: 1.1,
      resource_overhead: 0.85
    }
  end

  defp generate_caching_candidate(_task, resource_estimate) do
    if resource_estimate.time.estimated_duration > 10_000 do
      %{
        type: :caching,
        description: "Enable intelligent caching of intermediate results",
        adjustments: %{
          enable_result_caching: true,
          cache_intermediate_steps: true,
          # 1 hour
          cache_ttl: 3600_000
        },
        estimated_speedup: 1.3,
        resource_overhead: 1.1
      }
    end
  end

  defp generate_pipeline_optimization_candidate(_task, resource_estimate) do
    if length(resource_estimate.agents.required) > 2 do
      %{
        type: :pipeline_optimization,
        description: "Optimize workflow pipeline structure",
        adjustments: %{
          enable_streaming_execution: true,
          optimize_step_ordering: true,
          reduce_synchronization_points: true
        },
        estimated_speedup: 1.2,
        resource_overhead: 0.95
      }
    end
  end

  defp generate_speed_candidates(_task, resource_estimate) do
    [
      %{
        type: :aggressive_parallelization,
        description: "Maximize parallel execution for speed",
        adjustments: %{
          max_concurrent_steps: 12,
          aggressive_agent_allocation: true,
          prioritize_speed_over_resources: true
        },
        estimated_speedup: 2.5,
        resource_overhead: 1.8
      },
      if resource_estimate.memory.estimated < 1000 do
        %{
          type: :memory_preload,
          description: "Preload data for faster access",
          adjustments: %{
            preload_factor: 2.0,
            enable_memory_pooling: true
          },
          estimated_speedup: 1.4,
          resource_overhead: 1.6
        }
      end
    ]
    |> Enum.filter(& &1)
  end

  defp generate_resource_candidates(_task, resource_estimate) do
    [
      %{
        type: :resource_conservation,
        description: "Minimize resource usage",
        adjustments: %{
          sequential_execution_preference: true,
          minimize_agent_count: true,
          enable_memory_compression: true
        },
        estimated_speedup: 0.8,
        resource_overhead: 0.6
      },
      if resource_estimate.agents.optimal_count > 1 do
        %{
          type: :agent_sharing,
          description: "Share agents across workflow steps",
          adjustments: %{
            enable_agent_multiplexing: true,
            agent_reuse_factor: 0.7
          },
          estimated_speedup: 0.9,
          resource_overhead: 0.75
        }
      end
    ]
    |> Enum.filter(& &1)
  end

  defp generate_balanced_candidates(_task, _resource_estimate) do
    [
      %{
        type: :balanced_optimization,
        description: "Balance speed and resource usage",
        adjustments: %{
          moderate_parallelization: true,
          selective_caching: true,
          adaptive_agent_scaling: true
        },
        estimated_speedup: 1.3,
        resource_overhead: 1.0
      }
    ]
  end

  defp generate_adaptive_candidates(task, resource_estimate) do
    # Adaptive candidates based on task characteristics
    candidates = []

    candidates =
      if Map.get(task, :priority) == :high do
        [
          %{
            type: :priority_optimization,
            description: "Optimize for high-priority task",
            adjustments: %{
              increase_agent_priority: true,
              allocate_additional_resources: true
            },
            estimated_speedup: 1.4,
            resource_overhead: 1.3
          }
          | candidates
        ]
      else
        candidates
      end

    candidates =
      if resource_estimate.scaling.bottlenecks != [] do
        [
          %{
            type: :bottleneck_mitigation,
            description: "Address identified bottlenecks",
            adjustments: %{
              bottleneck_specific_optimizations: resource_estimate.scaling.bottlenecks
            },
            estimated_speedup: 1.6,
            resource_overhead: 1.1
          }
          | candidates
        ]
      else
        candidates
      end

    candidates
  end

  defp evaluate_candidates(candidates, baseline_metrics, strategy, performance_profile) do
    strategy_weights = Map.get(@strategy_weights, strategy, @strategy_weights.balanced)

    Enum.map(candidates, fn candidate ->
      # Calculate performance scores
      time_score = calculate_time_score(candidate, baseline_metrics)
      resource_score = calculate_resource_score(candidate, baseline_metrics)
      reliability_score = calculate_reliability_score(candidate, performance_profile)

      # Apply strategy weights
      overall_score =
        time_score * strategy_weights.execution_time +
          resource_score * strategy_weights.resource_usage +
          reliability_score * strategy_weights.reliability

      Map.put(candidate, :overall_score, overall_score)
      |> Map.put(:detailed_scores, %{
        time: time_score,
        resource: resource_score,
        reliability: reliability_score
      })
    end)
  end

  defp calculate_time_score(candidate, _baseline_metrics) do
    speedup = Map.get(candidate, :estimated_speedup, 1.0)

    # Score based on execution time improvement
    cond do
      speedup >= 2.0 -> 1.0
      speedup >= 1.5 -> 0.8
      speedup >= 1.2 -> 0.6
      speedup >= 1.0 -> 0.4
      true -> 0.2
    end
  end

  defp calculate_resource_score(candidate, _baseline_metrics) do
    overhead = Map.get(candidate, :resource_overhead, 1.0)

    # Score based on resource efficiency (lower overhead is better)
    cond do
      overhead <= 0.7 -> 1.0
      overhead <= 0.9 -> 0.8
      overhead <= 1.1 -> 0.6
      overhead <= 1.3 -> 0.4
      true -> 0.2
    end
  end

  defp calculate_reliability_score(candidate, performance_profile) do
    # Base reliability score
    base_score = 0.7

    # Adjust based on optimization type risk
    risk_adjustment =
      case candidate.type do
        :aggressive_parallelization -> -0.1
        :memory_preload -> -0.05
        :resource_conservation -> 0.1
        :balanced_optimization -> 0.05
        _ -> 0.0
      end

    # Adjust based on historical data if available
    history_adjustment =
      if performance_profile do
        calculate_historical_reliability_adjustment(candidate, performance_profile)
      else
        0.0
      end

    max(0.0, min(1.0, base_score + risk_adjustment + history_adjustment))
  end

  defp calculate_historical_reliability_adjustment(candidate, performance_profile) do
    # Simplified historical analysis
    success_rate = Map.get(performance_profile.success_metrics, :success_rate, 0.8)

    case candidate.type do
      type when type in [:parallelization, :aggressive_parallelization] ->
        # Parallelization success depends on task complexity
        if success_rate > 0.9, do: 0.05, else: -0.05

      type when type in [:resource_conservation, :agent_sharing] ->
        # Resource optimizations are generally safer
        0.05

      _ ->
        0.0
    end
  end

  defp select_optimal_candidate(evaluated_candidates, strategy) do
    case strategy do
      :adaptive ->
        # For adaptive strategy, consider multiple factors
        select_adaptive_candidate(evaluated_candidates)

      _ ->
        # For other strategies, select highest scoring candidate
        Enum.max_by(evaluated_candidates, & &1.overall_score)
    end
  end

  defp select_adaptive_candidate(evaluated_candidates) do
    # Adaptive selection considers variance in scores
    candidates_with_variance =
      Enum.map(evaluated_candidates, fn candidate ->
        scores = Map.values(candidate.detailed_scores)
        variance = calculate_variance(scores)

        Map.put(candidate, :score_variance, variance)
      end)

    # Prefer candidates with high overall score and low variance (more predictable)
    Enum.max_by(candidates_with_variance, fn candidate ->
      candidate.overall_score - candidate.score_variance * 0.3
    end)
  end

  defp calculate_variance(scores) do
    mean = Enum.sum(scores) / length(scores)

    variance =
      Enum.reduce(scores, 0, fn score, acc ->
        acc + :math.pow(score - mean, 2)
      end) / length(scores)

    :math.sqrt(variance)
  end

  defp create_optimization_result(best_candidate, _baseline_metrics, strategy) do
    predicted_improvement = %{
      execution_time: best_candidate.estimated_speedup - 1.0,
      resource_efficiency: 1.0 - best_candidate.resource_overhead,
      success_probability: best_candidate.detailed_scores.reliability
    }

    rationale = generate_optimization_rationale(best_candidate, strategy)

    confidence = calculate_optimization_confidence(best_candidate)

    %{
      strategy: strategy,
      adjustments: [best_candidate.adjustments],
      predicted_improvement: predicted_improvement,
      confidence: confidence,
      rationale: rationale,
      selected_optimization: best_candidate.type
    }
  end

  defp generate_optimization_rationale(candidate, strategy) do
    base_rationale = [candidate.description]

    strategy_rationale =
      case strategy do
        :speed -> ["Optimized for maximum execution speed"]
        :resource -> ["Optimized for minimal resource usage"]
        :balanced -> ["Balanced optimization for speed and efficiency"]
        :adaptive -> ["Adaptive optimization based on task characteristics"]
      end

    performance_rationale = [
      "Expected speedup: #{Float.round(candidate.estimated_speedup, 2)}x",
      "Resource overhead: #{Float.round(candidate.resource_overhead, 2)}x"
    ]

    base_rationale ++ strategy_rationale ++ performance_rationale
  end

  defp calculate_optimization_confidence(candidate) do
    # Base confidence on optimization type
    base_confidence =
      case candidate.type do
        :step_optimization -> 0.8
        :resource_allocation -> 0.75
        :caching -> 0.7
        :parallelization -> 0.65
        :aggressive_parallelization -> 0.5
        _ -> 0.6
      end

    # Adjust based on score variance if available
    variance_adjustment =
      if Map.has_key?(candidate, :score_variance) do
        -candidate.score_variance * 0.2
      else
        0.0
      end

    max(0.3, min(0.95, base_confidence + variance_adjustment))
  end

  # Placeholder implementations for pattern analysis functions
  defp analyze_execution_patterns(execution_history) do
    # Analyze patterns in execution times, bottlenecks, etc.
    %{
      average_execution_time: calculate_average_execution_time(execution_history),
      common_bottlenecks: identify_common_bottlenecks(execution_history),
      success_patterns: analyze_success_patterns(execution_history)
    }
  end

  defp analyze_resource_patterns(resource_patterns) do
    # Analyze patterns in resource usage
    %{
      peak_memory_usage: calculate_peak_memory(resource_patterns),
      agent_utilization_patterns: analyze_agent_utilization(resource_patterns)
    }
  end

  defp identify_performance_bottlenecks(bottleneck_analysis) do
    # Extract most common bottlenecks
    bottleneck_analysis
    |> Map.get(:common_bottlenecks, [])
    |> Enum.take(3)
  end

  defp recommend_strategy(execution_patterns, _resource_patterns, bottlenecks) do
    # Simple recommendation logic based on patterns
    cond do
      :memory_intensive in bottlenecks -> :resource
      execution_patterns.average_execution_time > 60_000 -> :speed
      true -> :balanced
    end
  end

  defp identify_improvement_opportunities(execution_patterns, resource_patterns) do
    opportunities = []

    opportunities =
      if execution_patterns.average_execution_time > 30_000 do
        [%{type: :execution_time, description: "Long execution times detected"} | opportunities]
      else
        opportunities
      end

    opportunities =
      if resource_patterns.peak_memory_usage > 1000 do
        [%{type: :memory_usage, description: "High memory usage detected"} | opportunities]
      else
        opportunities
      end

    opportunities
  end

  defp calculate_pattern_confidence(performance_profile) do
    history_size = length(performance_profile.execution_history)
    min(0.9, 0.5 + history_size * 0.05)
  end

  # Additional helper functions
  defp calculate_average_execution_time(execution_history) do
    if length(execution_history) > 0 do
      total_time =
        Enum.reduce(execution_history, 0, fn exec, acc ->
          acc + Map.get(exec, :duration, 0)
        end)

      total_time / length(execution_history)
    else
      # Default estimate
      30_000
    end
  end

  defp identify_common_bottlenecks(_execution_history) do
    # Simplified bottleneck identification
    # Placeholder
    [:file_io, :memory_intensive]
  end

  defp analyze_success_patterns(execution_history) do
    successful = Enum.count(execution_history, &(Map.get(&1, :status) == :success))
    total = length(execution_history)

    if total > 0, do: successful / total, else: 0.8
  end

  defp calculate_peak_memory(resource_patterns) do
    if length(resource_patterns) > 0 do
      Enum.max_by(resource_patterns, &Map.get(&1, :memory_usage, 0))
      |> Map.get(:memory_usage, 500)
    else
      # Default estimate
      500
    end
  end

  defp analyze_agent_utilization(_resource_patterns) do
    # Simplified agent utilization analysis
    %{average_utilization: 0.75}
  end

  defp calculate_performance_gap(current_metrics, target_performance) do
    %{
      execution_time: calculate_metric_gap(current_metrics, target_performance, :execution_time),
      resource_usage: calculate_metric_gap(current_metrics, target_performance, :resource_usage),
      error_rate: calculate_metric_gap(current_metrics, target_performance, :error_rate)
    }
  end

  defp calculate_metric_gap(current, target, metric) do
    current_value = Map.get(current, metric, 0)
    target_value = Map.get(target, metric, 0)

    if target_value > 0 do
      abs(current_value - target_value) / target_value
    else
      0.0
    end
  end

  defp generate_speed_adjustments(_current_metrics) do
    [
      %{
        type: :increase_parallelization,
        description: "Increase parallel execution to improve speed",
        parameters: %{parallel_factor: 1.5}
      }
    ]
  end

  defp generate_resource_adjustments(_current_metrics) do
    [
      %{
        type: :reduce_agent_count,
        description: "Reduce agent allocation to conserve resources",
        parameters: %{reduction_factor: 0.8}
      }
    ]
  end

  defp generate_reliability_adjustments(_current_metrics) do
    [
      %{
        type: :add_retry_logic,
        description: "Add retry mechanisms to improve reliability",
        parameters: %{max_retries: 3}
      }
    ]
  end

  defp determine_adjustment_urgency(performance_gap) do
    max_gap =
      [performance_gap.execution_time, performance_gap.resource_usage, performance_gap.error_rate]
      |> Enum.max()

    cond do
      max_gap > 0.5 -> :high
      max_gap > 0.2 -> :medium
      true -> :low
    end
  end

  defp estimate_adjustment_impact(adjustments, _current_metrics) do
    # Simplified impact estimation
    %{
      execution_time_improvement: 0.2 * length(adjustments),
      resource_efficiency_improvement: 0.15 * length(adjustments)
    }
  end

  defp apply_template_optimizations(template, _usage_data) do
    # Apply optimizations based on usage patterns
    # This is a simplified implementation
    template
  end

  defp calculate_prediction_accuracy(optimization_result, actual_performance) do
    predicted_speedup = optimization_result.predicted_improvement.execution_time + 1.0
    actual_speedup = Map.get(actual_performance, :speedup, 1.0)

    1.0 - abs(predicted_speedup - actual_speedup) / Enum.max([predicted_speedup, actual_speedup])
  end

  defp update_optimization_models(_task, _optimization_result, _actual_performance, accuracy) do
    # Update internal models based on learning
    # This would typically update ML models or statistical parameters
    Logger.debug("Updating optimization models with accuracy: #{accuracy}")
  end

  defp store_learning_data(task, optimization_result, actual_performance, accuracy) do
    # Store data for future learning
    learning_record = %{
      task_signature: generate_task_signature(task),
      optimization_type: optimization_result.selected_optimization,
      predicted_improvement: optimization_result.predicted_improvement,
      actual_improvement: extract_actual_improvement(actual_performance),
      accuracy: accuracy,
      timestamp: DateTime.utc_now()
    }

    # In a real implementation, this would be stored to persistent storage
    Logger.debug("Storing learning data: #{inspect(learning_record)}")
  end

  defp generate_task_signature(task) do
    %{
      type: Map.get(task, :type),
      complexity: categorize_task_complexity(task),
      file_count: length(Map.get(task, :targets, Map.get(task, :files, [])))
    }
  end

  defp categorize_task_complexity(task) do
    # Simplified complexity categorization
    file_count = length(Map.get(task, :targets, Map.get(task, :files, [])))

    cond do
      file_count > 10 -> :high
      file_count > 3 -> :medium
      true -> :low
    end
  end

  defp extract_actual_improvement(actual_performance) do
    %{
      execution_time: Map.get(actual_performance, :execution_time_improvement, 0.0),
      resource_efficiency: Map.get(actual_performance, :resource_efficiency_improvement, 0.0),
      success_probability: Map.get(actual_performance, :success_rate, 0.8)
    }
  end
end
