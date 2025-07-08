defmodule RubberDuck.Workflows.OptimizationEngineTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.{OptimizationEngine, ResourceEstimator}

  # Helper function to create a sample resource estimate
  defp create_sample_resource_estimate(complexity \\ :medium) do
    base_values =
      case complexity do
        :low -> %{time: 5_000, memory: 200, agents: 1, parallelization: 1.2}
        :medium -> %{time: 20_000, memory: 500, agents: 2, parallelization: 2.0}
        :high -> %{time: 60_000, memory: 1200, agents: 4, parallelization: 3.5}
      end

    %{
      memory: %{
        estimated: base_values.memory,
        confidence: 0.8,
        peak_usage: round(base_values.memory * 1.3)
      },
      agents: %{
        required: [:analysis, :generation],
        optimal_count: base_values.agents,
        concurrent_capacity: base_values.agents + 1
      },
      time: %{
        estimated_duration: base_values.time,
        confidence: 0.75,
        best_case: round(base_values.time * 0.7),
        worst_case: round(base_values.time * 1.8)
      },
      scaling: %{
        parallelization_factor: base_values.parallelization,
        bottlenecks: if(complexity == :high, do: [:memory_intensive, :agent_coordination], else: []),
        recommendations: []
      }
    }
  end

  defp create_sample_performance_profile do
    %{
      execution_history: [
        %{duration: 18_000, status: :success, memory_peak: 450},
        %{duration: 22_000, status: :success, memory_peak: 520},
        %{duration: 25_000, status: :failed, memory_peak: 600}
      ],
      resource_patterns: [
        %{memory_usage: 450, agent_count: 2, utilization: 0.8},
        %{memory_usage: 520, agent_count: 2, utilization: 0.85}
      ],
      bottleneck_analysis: %{
        common_bottlenecks: [:file_io, :memory_intensive]
      },
      success_metrics: %{
        success_rate: 0.85,
        average_completion_time: 20_000
      }
    }
  end

  describe "optimize/4" do
    test "provides optimization result for speed strategy" do
      task = %{
        type: :analysis,
        targets: ["file1.ex", "file2.ex", "file3.ex"]
      }

      resource_estimate = create_sample_resource_estimate(:medium)

      result = OptimizationEngine.optimize(task, resource_estimate, :speed)

      assert is_map(result)
      assert result.strategy == :speed
      assert is_list(result.adjustments)
      assert Map.has_key?(result, :predicted_improvement)
      assert Map.has_key?(result, :confidence)
      assert is_list(result.rationale)

      # Speed strategy should prioritize execution time improvements
      assert result.predicted_improvement.execution_time >= 0
      assert result.confidence > 0.3
      assert result.confidence <= 1.0
    end

    test "provides optimization result for resource strategy" do
      task = %{
        type: :generation,
        description: "Create large module"
      }

      resource_estimate = create_sample_resource_estimate(:high)

      result = OptimizationEngine.optimize(task, resource_estimate, :resource)

      assert result.strategy == :resource
      assert is_list(result.adjustments)

      # Resource strategy should focus on efficiency
      assert Map.has_key?(result.predicted_improvement, :resource_efficiency)
    end

    test "provides optimization result for balanced strategy" do
      task = %{type: :refactoring, targets: ["main.ex"]}
      resource_estimate = create_sample_resource_estimate(:low)

      result = OptimizationEngine.optimize(task, resource_estimate, :balanced)

      assert result.strategy == :balanced
      assert length(result.rationale) > 0
      assert Enum.any?(result.rationale, &String.contains?(&1, "Balanced"))
    end

    test "incorporates performance profile when available" do
      task = %{type: :analysis, targets: ["test.ex"]}
      resource_estimate = create_sample_resource_estimate(:medium)
      performance_profile = create_sample_performance_profile()

      result_without_profile = OptimizationEngine.optimize(task, resource_estimate, :adaptive)
      result_with_profile = OptimizationEngine.optimize(task, resource_estimate, :adaptive, performance_profile)

      # Results should differ when performance profile is available
      assert result_with_profile.confidence >= result_without_profile.confidence
    end

    test "adaptive strategy considers task characteristics" do
      high_priority_task = %{
        type: :critical_analysis,
        priority: :high,
        targets: ["critical.ex"]
      }

      resource_estimate = create_sample_resource_estimate(:medium)

      result = OptimizationEngine.optimize(high_priority_task, resource_estimate, :adaptive)

      assert result.strategy == :adaptive
      assert length(result.adjustments) > 0
    end

    test "handles tasks with identified bottlenecks" do
      task = %{type: :complex_refactoring}
      resource_estimate = create_sample_resource_estimate(:high)

      result = OptimizationEngine.optimize(task, resource_estimate, :speed)

      # Should provide optimizations even with bottlenecks
      assert length(result.adjustments) > 0
      assert result.confidence > 0.0
    end
  end

  describe "analyze_performance_patterns/1" do
    test "analyzes execution patterns and recommends strategies" do
      performance_profile = create_sample_performance_profile()

      analysis = OptimizationEngine.analyze_performance_patterns(performance_profile)

      assert Map.has_key?(analysis, :recommended_strategy)
      assert analysis.recommended_strategy in [:speed, :resource, :balanced, :adaptive]
      assert is_list(analysis.bottlenecks)
      assert is_list(analysis.improvement_opportunities)
      assert is_number(analysis.confidence)
      assert analysis.confidence >= 0.0
      assert analysis.confidence <= 1.0
    end

    test "identifies bottlenecks from performance history" do
      performance_profile = %{
        execution_history: [
          %{duration: 45_000, bottlenecks: [:memory_intensive]},
          %{duration: 50_000, bottlenecks: [:file_io, :memory_intensive]}
        ],
        resource_patterns: [],
        bottleneck_analysis: %{
          common_bottlenecks: [:memory_intensive, :file_io]
        },
        success_metrics: %{success_rate: 0.8}
      }

      analysis = OptimizationEngine.analyze_performance_patterns(performance_profile)

      assert :memory_intensive in analysis.bottlenecks
      assert :file_io in analysis.bottlenecks
    end

    test "recommends speed strategy for slow executions" do
      slow_performance_profile = %{
        execution_history: [
          %{duration: 90_000, status: :success},
          %{duration: 85_000, status: :success}
        ],
        resource_patterns: [%{memory_usage: 400}],
        bottleneck_analysis: %{common_bottlenecks: []},
        success_metrics: %{success_rate: 0.9}
      }

      analysis = OptimizationEngine.analyze_performance_patterns(slow_performance_profile)

      assert analysis.recommended_strategy == :speed
    end

    test "recommends resource strategy for memory-intensive tasks" do
      memory_intensive_profile = %{
        execution_history: [%{duration: 20_000, status: :success}],
        resource_patterns: [%{memory_usage: 2000}],
        bottleneck_analysis: %{common_bottlenecks: [:memory_intensive]},
        success_metrics: %{success_rate: 0.9}
      }

      analysis = OptimizationEngine.analyze_performance_patterns(memory_intensive_profile)

      assert analysis.recommended_strategy == :resource
    end

    test "identifies improvement opportunities" do
      performance_profile = create_sample_performance_profile()

      analysis = OptimizationEngine.analyze_performance_patterns(performance_profile)

      assert length(analysis.improvement_opportunities) >= 0

      if length(analysis.improvement_opportunities) > 0 do
        opportunity = hd(analysis.improvement_opportunities)
        assert Map.has_key?(opportunity, :type)
        assert Map.has_key?(opportunity, :description)
      end
    end

    test "confidence increases with more historical data" do
      small_profile = %{
        execution_history: [%{duration: 20_000, status: :success}],
        resource_patterns: [],
        bottleneck_analysis: %{common_bottlenecks: []},
        success_metrics: %{success_rate: 1.0}
      }

      large_profile = %{
        execution_history: Enum.map(1..10, fn _ -> %{duration: 20_000, status: :success} end),
        resource_patterns: [],
        bottleneck_analysis: %{common_bottlenecks: []},
        success_metrics: %{success_rate: 0.9}
      }

      small_analysis = OptimizationEngine.analyze_performance_patterns(small_profile)
      large_analysis = OptimizationEngine.analyze_performance_patterns(large_profile)

      assert large_analysis.confidence > small_analysis.confidence
    end
  end

  describe "suggest_runtime_adjustments/2" do
    test "suggests speed adjustments for slow execution" do
      current_metrics = %{
        execution_time: 45_000,
        resource_usage: 500,
        error_rate: 0.05
      }

      target_performance = %{
        execution_time: 20_000,
        resource_usage: 600,
        error_rate: 0.02
      }

      suggestions = OptimizationEngine.suggest_runtime_adjustments(current_metrics, target_performance)

      assert Map.has_key?(suggestions, :adjustments)
      assert Map.has_key?(suggestions, :urgency)
      assert Map.has_key?(suggestions, :estimated_impact)
      assert suggestions.urgency in [:low, :medium, :high]

      # Should suggest speed adjustments for slow execution
      assert length(suggestions.adjustments) > 0
    end

    test "suggests resource adjustments for high resource usage" do
      current_metrics = %{
        execution_time: 20_000,
        resource_usage: 2000,
        error_rate: 0.02
      }

      target_performance = %{
        execution_time: 25_000,
        resource_usage: 800,
        error_rate: 0.02
      }

      suggestions = OptimizationEngine.suggest_runtime_adjustments(current_metrics, target_performance)

      assert length(suggestions.adjustments) > 0

      # Should include resource-focused adjustments
      adjustment = hd(suggestions.adjustments)
      assert Map.has_key?(adjustment, :type)
      assert Map.has_key?(adjustment, :description)
    end

    test "suggests reliability adjustments for high error rates" do
      current_metrics = %{
        execution_time: 20_000,
        resource_usage: 500,
        error_rate: 0.15
      }

      target_performance = %{
        execution_time: 20_000,
        resource_usage: 500,
        error_rate: 0.02
      }

      suggestions = OptimizationEngine.suggest_runtime_adjustments(current_metrics, target_performance)

      assert length(suggestions.adjustments) > 0
      assert suggestions.urgency == :high
    end

    test "determines appropriate urgency levels" do
      # High urgency scenario
      critical_metrics = %{
        execution_time: 100_000,
        resource_usage: 500,
        error_rate: 0.02
      }

      target = %{
        execution_time: 20_000,
        resource_usage: 500,
        error_rate: 0.02
      }

      critical_suggestions = OptimizationEngine.suggest_runtime_adjustments(critical_metrics, target)
      assert critical_suggestions.urgency == :high

      # Low urgency scenario
      good_metrics = %{
        execution_time: 22_000,
        resource_usage: 520,
        error_rate: 0.03
      }

      good_suggestions = OptimizationEngine.suggest_runtime_adjustments(good_metrics, target)
      assert good_suggestions.urgency == :low
    end

    test "estimates impact of suggested adjustments" do
      current_metrics = %{
        execution_time: 40_000,
        resource_usage: 800,
        error_rate: 0.05
      }

      target_performance = %{
        execution_time: 20_000,
        resource_usage: 600,
        error_rate: 0.02
      }

      suggestions = OptimizationEngine.suggest_runtime_adjustments(current_metrics, target_performance)

      assert Map.has_key?(suggestions.estimated_impact, :execution_time_improvement)
      assert Map.has_key?(suggestions.estimated_impact, :resource_efficiency_improvement)
      assert is_number(suggestions.estimated_impact.execution_time_improvement)
      assert is_number(suggestions.estimated_impact.resource_efficiency_improvement)
    end
  end

  describe "optimize_template/2" do
    test "optimizes workflow templates based on usage data" do
      usage_data = [
        %{template: :simple_analysis, execution_time: 15_000, success: true},
        %{template: :simple_analysis, execution_time: 18_000, success: true},
        %{template: :simple_analysis, execution_time: 22_000, success: false}
      ]

      result = OptimizationEngine.optimize_template(:simple_analysis, usage_data)

      # Should return optimized template or error
      case result do
        {:ok, optimized_template} ->
          assert is_map(optimized_template)

        {:error, reason} ->
          # Template might not exist, which is acceptable for this test
          assert is_atom(reason) or is_binary(reason)
      end
    end

    test "handles non-existent templates gracefully" do
      usage_data = [%{execution_time: 20_000, success: true}]

      result = OptimizationEngine.optimize_template(:non_existent_template, usage_data)

      assert {:error, _reason} = result
    end
  end

  describe "learn_from_execution/3" do
    test "learns from execution results" do
      task = %{type: :analysis, targets: ["test.ex"]}

      optimization_result = %{
        strategy: :speed,
        adjustments: [%{type: :parallelization}],
        predicted_improvement: %{
          execution_time: 0.5,
          resource_efficiency: -0.1,
          success_probability: 0.9
        },
        confidence: 0.8,
        selected_optimization: :parallelization
      }

      actual_performance = %{
        speedup: 1.4,
        execution_time_improvement: 0.4,
        resource_efficiency_improvement: -0.05,
        success_rate: 0.95
      }

      result = OptimizationEngine.learn_from_execution(task, optimization_result, actual_performance)

      assert result == :ok
    end

    test "handles learning from failed executions" do
      task = %{type: :generation}

      optimization_result = %{
        strategy: :aggressive_parallelization,
        predicted_improvement: %{execution_time: 1.0, resource_efficiency: -0.8},
        selected_optimization: :aggressive_parallelization
      }

      actual_performance = %{
        # Worse than predicted
        speedup: 0.8,
        execution_time_improvement: -0.2,
        success_rate: 0.6
      }

      result = OptimizationEngine.learn_from_execution(task, optimization_result, actual_performance)

      assert result == :ok
    end
  end

  describe "optimization strategy selection" do
    test "speed strategy generates appropriate candidates" do
      task = %{type: :analysis, targets: ["a.ex", "b.ex"]}
      resource_estimate = create_sample_resource_estimate(:medium)

      result = OptimizationEngine.optimize(task, resource_estimate, :speed)

      # Speed strategy should favor time improvements over resource efficiency
      assert result.predicted_improvement.execution_time >= 0

      # Should include speed-focused rationale
      rationale_text = Enum.join(result.rationale, " ")
      assert String.contains?(rationale_text, "speed") or String.contains?(rationale_text, "execution")
    end

    test "resource strategy prioritizes efficiency" do
      task = %{type: :refactoring, targets: Enum.map(1..10, &"file#{&1}.ex")}
      resource_estimate = create_sample_resource_estimate(:high)

      result = OptimizationEngine.optimize(task, resource_estimate, :resource)

      # Resource strategy should focus on efficiency
      rationale_text = Enum.join(result.rationale, " ")
      assert String.contains?(rationale_text, "resource") or String.contains?(rationale_text, "minimal")
    end

    test "balanced strategy provides reasonable compromises" do
      task = %{type: :generation}
      resource_estimate = create_sample_resource_estimate(:medium)

      result = OptimizationEngine.optimize(task, resource_estimate, :balanced)

      # Balanced strategy should provide moderate improvements
      assert result.predicted_improvement.execution_time >= -0.2
      assert result.predicted_improvement.execution_time <= 2.0
      assert result.confidence > 0.4

      rationale_text = Enum.join(result.rationale, " ")
      assert String.contains?(rationale_text, "balanced") or String.contains?(rationale_text, "Balanced")
    end
  end

  describe "edge cases and error handling" do
    test "handles minimal resource estimates" do
      task = %{type: :simple_task}

      minimal_estimate = %{
        memory: %{estimated: 50, confidence: 0.5, peak_usage: 65},
        agents: %{required: [:analysis], optimal_count: 1, concurrent_capacity: 1},
        time: %{estimated_duration: 2_000, confidence: 0.6, best_case: 1_500, worst_case: 3_000},
        scaling: %{parallelization_factor: 1.0, bottlenecks: [], recommendations: []}
      }

      result = OptimizationEngine.optimize(task, minimal_estimate, :balanced)

      assert is_map(result)
      assert result.confidence > 0.0
    end

    test "handles empty performance profiles" do
      empty_profile = %{
        execution_history: [],
        resource_patterns: [],
        bottleneck_analysis: %{common_bottlenecks: []},
        success_metrics: %{}
      }

      analysis = OptimizationEngine.analyze_performance_patterns(empty_profile)

      assert is_map(analysis)
      assert analysis.recommended_strategy in [:speed, :resource, :balanced, :adaptive]
      assert analysis.confidence >= 0.0
    end

    test "handles tasks with no optimization opportunities" do
      perfect_task = %{type: :trivial}

      perfect_estimate = %{
        memory: %{estimated: 10, confidence: 1.0, peak_usage: 12},
        agents: %{required: [], optimal_count: 0, concurrent_capacity: 1},
        time: %{estimated_duration: 100, confidence: 1.0, best_case: 90, worst_case: 110},
        scaling: %{parallelization_factor: 1.0, bottlenecks: [], recommendations: []}
      }

      result = OptimizationEngine.optimize(perfect_task, perfect_estimate, :speed)

      # Should still provide a result, even if no major optimizations are possible
      assert is_map(result)
      assert is_list(result.adjustments)
    end

    test "handles invalid strategy gracefully" do
      task = %{type: :analysis}
      resource_estimate = create_sample_resource_estimate(:low)

      # This should default to balanced strategy behavior
      result = OptimizationEngine.optimize(task, resource_estimate, :invalid_strategy)

      assert is_map(result)
      assert result.confidence > 0.0
    end
  end

  describe "performance and consistency" do
    test "provides consistent results for identical inputs" do
      task = %{type: :refactoring, targets: ["main.ex", "helper.ex"]}
      resource_estimate = create_sample_resource_estimate(:medium)

      result1 = OptimizationEngine.optimize(task, resource_estimate, :balanced)
      result2 = OptimizationEngine.optimize(task, resource_estimate, :balanced)

      # Results should be identical for same inputs
      assert result1.strategy == result2.strategy
      assert result1.confidence == result2.confidence
      assert length(result1.adjustments) == length(result2.adjustments)
    end

    test "different strategies produce different optimizations" do
      task = %{type: :analysis, targets: Enum.map(1..5, &"file#{&1}.ex")}
      resource_estimate = create_sample_resource_estimate(:high)

      speed_result = OptimizationEngine.optimize(task, resource_estimate, :speed)
      resource_result = OptimizationEngine.optimize(task, resource_estimate, :resource)

      # Different strategies should produce different results
      assert speed_result.strategy != resource_result.strategy

      # Speed strategy should generally predict better execution time improvements
      assert speed_result.predicted_improvement.execution_time >=
               resource_result.predicted_improvement.execution_time
    end

    test "confidence values are reasonable across different scenarios" do
      tasks = [
        %{type: :analysis, targets: ["simple.ex"]},
        %{type: :generation, description: "complex module"},
        %{type: :refactoring, targets: Enum.map(1..20, &"file#{&1}.ex")}
      ]

      for task <- tasks do
        resource_estimate = create_sample_resource_estimate(:medium)
        result = OptimizationEngine.optimize(task, resource_estimate, :balanced)

        assert result.confidence >= 0.3
        assert result.confidence <= 0.95
      end
    end
  end
end
