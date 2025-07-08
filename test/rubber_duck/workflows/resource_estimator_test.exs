defmodule RubberDuck.Workflows.ResourceEstimatorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.ResourceEstimator

  describe "estimate/2" do
    test "provides comprehensive resource estimates for simple tasks" do
      task = %{
        type: :analysis,
        target: "lib/simple.ex",
        code: "defmodule Simple, do: def test, do: :ok"
      }

      estimate = ResourceEstimator.estimate(task)

      assert is_map(estimate)
      assert Map.has_key?(estimate, :memory)
      assert Map.has_key?(estimate, :agents)
      assert Map.has_key?(estimate, :time)
      assert Map.has_key?(estimate, :scaling)

      # Memory estimates
      assert estimate.memory.estimated > 0
      assert estimate.memory.confidence >= 0.0
      assert estimate.memory.confidence <= 1.0
      assert estimate.memory.peak_usage >= estimate.memory.estimated

      # Agent estimates
      assert is_list(estimate.agents.required)
      assert estimate.agents.optimal_count > 0
      assert estimate.agents.concurrent_capacity > 0

      # Time estimates
      assert estimate.time.estimated_duration > 0
      assert estimate.time.best_case <= estimate.time.estimated_duration
      assert estimate.time.worst_case >= estimate.time.estimated_duration
    end

    test "scales estimates based on task complexity" do
      simple_task = %{
        type: :analysis,
        target: "simple.ex"
      }

      complex_task = %{
        type: :architecture_refactoring,
        targets: Enum.map(1..20, &"module#{&1}.ex"),
        options: %{
          deep_analysis: true,
          performance_optimization: true,
          security_audit: true
        },
        code_stats: %{loc: 5000}
      }

      simple_estimate = ResourceEstimator.estimate(simple_task)
      complex_estimate = ResourceEstimator.estimate(complex_task)

      # Complex task should require more resources
      assert complex_estimate.memory.estimated > simple_estimate.memory.estimated
      assert complex_estimate.agents.optimal_count >= simple_estimate.agents.optimal_count
      assert complex_estimate.time.estimated_duration > simple_estimate.time.estimated_duration
    end

    test "incorporates historical data when available" do
      task = %{
        type: :generation,
        description: "Create module"
      }

      historical_data = %{
        execution_times: [
          %{
            task_signature: %{type: :generation, file_count: 1, has_options: false, complexity_category: :medium},
            duration: 25_000
          },
          %{
            task_signature: %{type: :generation, file_count: 1, has_options: false, complexity_category: :medium},
            duration: 30_000
          }
        ],
        resource_usage: [
          %{
            task_signature: %{type: :generation, file_count: 1, has_options: false, complexity_category: :medium},
            memory: 180
          }
        ]
      }

      estimate_without_history = ResourceEstimator.estimate(task)
      estimate_with_history = ResourceEstimator.estimate(task, historical_data)

      # Confidence should be higher with historical data
      assert estimate_with_history.time.confidence > estimate_without_history.time.confidence
      assert estimate_with_history.memory.confidence > estimate_without_history.memory.confidence
    end
  end

  describe "estimate_memory_requirements/2" do
    test "calculates memory based on task characteristics" do
      task = %{
        type: :analysis,
        code_stats: %{loc: 1000},
        targets: ["file1.ex", "file2.ex", "file3.ex"]
      }

      memory_estimate = ResourceEstimator.estimate_memory_requirements(task, nil)

      assert memory_estimate.estimated > 0
      assert Map.has_key?(memory_estimate, :breakdown)
      assert memory_estimate.breakdown.base > 0
      assert memory_estimate.breakdown.data_overhead > 0
      assert memory_estimate.breakdown.agent_overhead > 0
    end

    test "handles large codebases appropriately" do
      small_task = %{
        type: :analysis,
        code_stats: %{loc: 100},
        targets: ["small.ex"]
      }

      large_task = %{
        type: :analysis,
        code_stats: %{loc: 10_000},
        targets: Enum.map(1..50, &"file#{&1}.ex")
      }

      small_memory = ResourceEstimator.estimate_memory_requirements(small_task, nil)
      large_memory = ResourceEstimator.estimate_memory_requirements(large_task, nil)

      assert large_memory.estimated > small_memory.estimated
      assert large_memory.breakdown.data_overhead > small_memory.breakdown.data_overhead
    end

    test "applies historical adjustments when available" do
      task = %{type: :generation, description: "test"}

      historical_data = %{
        resource_usage: [
          %{
            task_signature: %{type: :generation, file_count: 1, has_options: false, complexity_category: :medium},
            memory: 300
          }
        ]
      }

      memory_with_history = ResourceEstimator.estimate_memory_requirements(task, historical_data)
      memory_without_history = ResourceEstimator.estimate_memory_requirements(task, nil)

      # Should have higher confidence with historical data
      assert memory_with_history.confidence > memory_without_history.confidence
    end
  end

  describe "estimate_agent_requirements/2" do
    test "determines required agent types based on task" do
      analysis_task = %{type: :analysis}
      generation_task = %{type: :generation}
      refactoring_task = %{type: :refactoring}

      analysis_agents = ResourceEstimator.estimate_agent_requirements(analysis_task, nil)
      generation_agents = ResourceEstimator.estimate_agent_requirements(generation_task, nil)
      refactoring_agents = ResourceEstimator.estimate_agent_requirements(refactoring_task, nil)

      assert :analysis in analysis_agents.required
      assert :generation in generation_agents.required
      assert :analysis in refactoring_agents.required
      assert :generation in refactoring_agents.required
    end

    test "scales agent count with file complexity" do
      single_file_task = %{
        type: :analysis,
        target: "single.ex"
      }

      multi_file_task = %{
        type: :analysis,
        targets: Enum.map(1..10, &"file#{&1}.ex")
      }

      single_agents = ResourceEstimator.estimate_agent_requirements(single_file_task, nil)
      multi_agents = ResourceEstimator.estimate_agent_requirements(multi_file_task, nil)

      assert multi_agents.optimal_count >= single_agents.optimal_count
    end

    test "includes coordination agent for complex tasks" do
      complex_task = %{
        type: :complex_refactoring,
        targets: Enum.map(1..15, &"file#{&1}.ex"),
        options: %{deep_analysis: true}
      }

      agents = ResourceEstimator.estimate_agent_requirements(complex_task, nil)

      assert :coordination in agents.required
      assert agents.breakdown[:coordination] == 1
    end

    test "calculates agent utilization metrics" do
      task = %{type: :generation}

      agents = ResourceEstimator.estimate_agent_requirements(task, nil)

      assert Map.has_key?(agents, :utilization_estimate)
      assert is_number(agents.utilization_estimate.average_utilization)
      assert agents.utilization_estimate.average_utilization >= 0.0
      assert agents.utilization_estimate.average_utilization <= 1.0
    end
  end

  describe "estimate_execution_time/2" do
    test "provides time estimates with confidence intervals" do
      task = %{type: :review}

      time_estimate = ResourceEstimator.estimate_execution_time(task, nil)

      assert time_estimate.estimated_duration > 0
      assert time_estimate.best_case > 0
      assert time_estimate.worst_case > 0
      assert time_estimate.best_case <= time_estimate.estimated_duration
      assert time_estimate.estimated_duration <= time_estimate.worst_case
      assert is_number(time_estimate.confidence)
    end

    test "adjusts estimates based on complexity" do
      simple_task = %{type: :analysis, target: "simple.ex"}

      complex_task = %{
        type: :complex_refactoring,
        targets: Enum.map(1..10, &"file#{&1}.ex"),
        code_stats: %{loc: 5000},
        options: %{deep: true, security: true, performance: true}
      }

      simple_time = ResourceEstimator.estimate_execution_time(simple_task, nil)
      complex_time = ResourceEstimator.estimate_execution_time(complex_task, nil)

      assert complex_time.estimated_duration > simple_time.estimated_duration
      assert complex_time.factors.complexity_multiplier > simple_time.factors.complexity_multiplier
    end

    test "refines estimates with historical data" do
      task = %{type: :analysis}

      historical_data = %{
        execution_times: [
          %{
            task_signature: %{type: :analysis, file_count: 1, has_options: false, complexity_category: :low},
            duration: 8_000
          },
          %{
            task_signature: %{type: :analysis, file_count: 1, has_options: false, complexity_category: :low},
            duration: 12_000
          }
        ]
      }

      time_with_history = ResourceEstimator.estimate_execution_time(task, historical_data)
      time_without_history = ResourceEstimator.estimate_execution_time(task, nil)

      assert time_with_history.confidence > time_without_history.confidence
    end
  end

  describe "analyze_scaling_characteristics/2" do
    test "calculates parallelization factors" do
      sequential_task = %{
        type: :generation,
        options: %{sequential_required: true}
      }

      parallel_task = %{
        type: :analysis,
        targets: Enum.map(1..5, &"file#{&1}.ex")
      }

      sequential_scaling = ResourceEstimator.analyze_scaling_characteristics(sequential_task, nil)
      parallel_scaling = ResourceEstimator.analyze_scaling_characteristics(parallel_task, nil)

      assert sequential_scaling.parallelization_factor < parallel_scaling.parallelization_factor
    end

    test "identifies potential bottlenecks" do
      io_heavy_task = %{
        type: :analysis,
        targets: Enum.map(1..20, &"file#{&1}.ex")
      }

      memory_heavy_task = %{
        type: :refactoring,
        code_stats: %{loc: 15_000}
      }

      complex_task = %{
        type: :architecture_refactoring,
        scope: %{modules: 30}
      }

      io_scaling = ResourceEstimator.analyze_scaling_characteristics(io_heavy_task, nil)
      memory_scaling = ResourceEstimator.analyze_scaling_characteristics(memory_heavy_task, nil)
      complex_scaling = ResourceEstimator.analyze_scaling_characteristics(complex_task, nil)

      assert :file_io in io_scaling.bottlenecks
      assert :memory_intensive in memory_scaling.bottlenecks
      assert :agent_coordination in complex_scaling.bottlenecks
    end

    test "generates appropriate recommendations" do
      bottleneck_task = %{
        type: :analysis,
        targets: Enum.map(1..25, &"file#{&1}.ex"),
        code_stats: %{loc: 12_000}
      }

      scaling = ResourceEstimator.analyze_scaling_characteristics(bottleneck_task, nil)

      assert length(scaling.recommendations) > 0
      assert Enum.any?(scaling.recommendations, &(&1.category == :io))
      assert Enum.any?(scaling.recommendations, &(&1.type in [:optimization, :resource_allocation]))
    end

    test "estimates scaling efficiency" do
      highly_parallel_task = %{
        type: :analysis,
        targets: Enum.map(1..10, &"file#{&1}.ex")
      }

      sequential_task = %{
        type: :generation,
        description: "Linear generation process"
      }

      parallel_scaling = ResourceEstimator.analyze_scaling_characteristics(highly_parallel_task, nil)
      sequential_scaling = ResourceEstimator.analyze_scaling_characteristics(sequential_task, nil)

      assert parallel_scaling.scaling_efficiency > sequential_scaling.scaling_efficiency
    end
  end

  describe "validate_resource_availability/2" do
    test "validates feasible resource requirements" do
      modest_estimate = %{
        memory: %{estimated: 500},
        agents: %{optimal_count: 3}
      }

      system_constraints = %{
        memory_mb: 4000,
        max_agents: 10
      }

      result = ResourceEstimator.validate_resource_availability(modest_estimate, system_constraints)

      assert {:ok, validation} = result
      assert validation.status == :feasible
      assert Map.has_key?(validation, :resource_utilization)
    end

    test "identifies resource constraint violations" do
      excessive_estimate = %{
        memory: %{estimated: 8000},
        agents: %{optimal_count: 15}
      }

      limited_constraints = %{
        memory_mb: 4000,
        max_agents: 10
      }

      result = ResourceEstimator.validate_resource_availability(excessive_estimate, limited_constraints)

      assert {:error, validation} = result
      assert validation.status == :resource_constraints_violated
      assert length(validation.violations) > 0

      memory_violation = Enum.find(validation.violations, &(&1.type == :memory_exceeded))
      agent_violation = Enum.find(validation.violations, &(&1.type == :agent_limit_exceeded))

      assert memory_violation
      assert agent_violation
    end

    test "uses default constraints when none provided" do
      estimate = %{
        memory: %{estimated: 2000},
        agents: %{optimal_count: 5}
      }

      result = ResourceEstimator.validate_resource_availability(estimate)

      assert {:ok, _validation} = result
    end

    test "calculates resource utilization metrics" do
      estimate = %{
        memory: %{estimated: 1000},
        agents: %{optimal_count: 4}
      }

      constraints = %{
        memory_mb: 4000,
        max_agents: 10
      }

      {:ok, validation} = ResourceEstimator.validate_resource_availability(estimate, constraints)

      assert validation.resource_utilization.memory_utilization == 0.25
      assert validation.resource_utilization.agent_utilization == 0.4
      assert validation.resource_utilization.overall_utilization == 0.4
    end
  end

  describe "edge cases and error handling" do
    test "handles tasks with missing or nil fields" do
      minimal_task = %{type: :analysis}
      empty_task = %{}

      minimal_estimate = ResourceEstimator.estimate(minimal_task)
      empty_estimate = ResourceEstimator.estimate(empty_task)

      # Should not crash and provide reasonable defaults
      assert is_map(minimal_estimate)
      assert is_map(empty_estimate)
      assert minimal_estimate.memory.estimated > 0
      assert empty_estimate.memory.estimated > 0
    end

    test "handles tasks with zero or negative values gracefully" do
      task = %{
        type: :analysis,
        code_stats: %{loc: 0},
        targets: []
      }

      estimate = ResourceEstimator.estimate(task)

      assert estimate.memory.estimated > 0
      assert estimate.agents.optimal_count > 0
      assert estimate.time.estimated_duration > 0
    end

    test "handles historical data with empty or malformed entries" do
      task = %{type: :generation}

      malformed_historical = %{
        execution_times: [
          # Missing task_signature
          %{duration: 1000},
          # Invalid duration
          %{task_signature: %{}, duration: nil}
        ],
        resource_usage: []
      }

      estimate = ResourceEstimator.estimate(task, malformed_historical)

      # Should handle gracefully and not crash
      assert is_map(estimate)
      assert estimate.time.estimated_duration > 0
    end

    test "handles very large numbers appropriately" do
      huge_task = %{
        type: :architecture_refactoring,
        code_stats: %{loc: 1_000_000},
        targets: Enum.map(1..1000, &"file#{&1}.ex")
      }

      estimate = ResourceEstimator.estimate(huge_task)

      # Should cap values at reasonable limits
      # Not unlimited memory
      assert estimate.memory.estimated < 10_000
      # Reasonable agent limit
      assert estimate.agents.optimal_count < 50
    end
  end

  describe "performance and accuracy" do
    test "provides consistent estimates for identical tasks" do
      task = %{
        type: :refactoring,
        targets: ["a.ex", "b.ex"],
        options: %{extract_common: true}
      }

      estimate1 = ResourceEstimator.estimate(task)
      estimate2 = ResourceEstimator.estimate(task)

      assert estimate1.memory.estimated == estimate2.memory.estimated
      assert estimate1.agents.optimal_count == estimate2.agents.optimal_count
      assert estimate1.time.estimated_duration == estimate2.time.estimated_duration
    end

    test "estimates scale reasonably with task size" do
      tasks = [
        %{type: :analysis, targets: ["file1.ex"]},
        %{type: :analysis, targets: Enum.map(1..5, &"file#{&1}.ex")},
        %{type: :analysis, targets: Enum.map(1..15, &"file#{&1}.ex")}
      ]

      estimates = Enum.map(tasks, &ResourceEstimator.estimate/1)

      # Memory should scale with task size
      memory_estimates = Enum.map(estimates, & &1.memory.estimated)
      assert memory_estimates == Enum.sort(memory_estimates)

      # Time should scale with task size
      time_estimates = Enum.map(estimates, & &1.time.estimated_duration)
      assert time_estimates == Enum.sort(time_estimates)
    end

    test "confidence levels are within valid ranges" do
      tasks = [
        %{type: :analysis},
        %{type: :generation},
        %{type: :refactoring},
        %{type: :review}
      ]

      for task <- tasks do
        estimate = ResourceEstimator.estimate(task)

        assert estimate.memory.confidence >= 0.0
        assert estimate.memory.confidence <= 1.0
        assert estimate.time.confidence >= 0.0
        assert estimate.time.confidence <= 1.0
      end
    end
  end
end
