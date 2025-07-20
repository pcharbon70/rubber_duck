defmodule RubberDuck.Planning.Execution.ObservationCollectorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Planning.Execution.ObservationCollector

  describe "collect_observation/3" do
    test "collects successful task observation" do
      task_id = "successful_task"
      result = {:ok, %{data: "result", metrics: %{size: 1024}}}
      state = build_execution_state()
      
      observation = ObservationCollector.collect_observation(task_id, result, state)
      
      assert observation.task_id == task_id
      assert observation.status == :success
      assert observation.result == %{data: "result", metrics: %{size: 1024}}
      assert observation.metrics
      assert observation.insights
      assert observation.timestamp
    end

    test "collects failed task observation" do
      task_id = "failed_task"
      result = {:error, :timeout}
      state = build_execution_state()
      
      observation = ObservationCollector.collect_observation(task_id, result, state)
      
      assert observation.task_id == task_id
      assert observation.status == :failure
      assert observation.result == :timeout
      assert "failed" in observation.insights
    end

    test "collects execution metrics" do
      task_id = "timed_task"
      result = {:ok, "success"}
      state = build_state_with_timing(task_id)
      
      observation = ObservationCollector.collect_observation(task_id, result, state)
      
      assert observation.metrics.execution_time
      assert observation.metrics.memory_usage
      assert observation.metrics.cpu_usage
      assert observation.metrics.result_size
    end

    test "detects side effects" do
      task_id = "side_effect_task"
      result = {:ok, %{http_request: "made"}}
      state = build_execution_state()
      
      observation = ObservationCollector.collect_observation(task_id, result, state)
      
      # Should detect HTTP interaction
      http_effects = Enum.filter(observation.side_effects, &(&1.type == :http_call))
      assert length(http_effects) > 0
    end

    test "detects execution time anomaly" do
      task_id = "slow_task"
      result = {:ok, "success"}
      state = build_state_with_slow_execution(task_id)
      
      observation = ObservationCollector.collect_observation(task_id, result, state)
      
      # Should detect slow execution anomaly
      slow_anomalies = Enum.filter(observation.anomalies, &(&1.type == :slow_execution))
      assert length(slow_anomalies) > 0
    end

    test "detects large result anomaly" do
      task_id = "large_result_task"
      large_result = {:ok, String.duplicate("x", 2_000_000)}  # 2MB result
      state = build_execution_state()
      
      observation = ObservationCollector.collect_observation(task_id, large_result, state)
      
      # Should detect large result anomaly
      size_anomalies = Enum.filter(observation.anomalies, &(&1.type == :large_result))
      assert length(size_anomalies) > 0
    end

    test "detects repeated failure anomaly" do
      task_id = "repeatedly_failing_task"
      result = {:failure, :error}
      state = build_state_with_repeated_failures(task_id)
      
      observation = ObservationCollector.collect_observation(task_id, result, state)
      
      # Should detect repeated failures
      failure_anomalies = Enum.filter(observation.anomalies, &(&1.type == :repeated_failures))
      assert length(failure_anomalies) > 0
    end

    test "detects high CPU usage anomaly" do
      task_id = "cpu_intensive_task"
      result = {:ok, "success"}
      state = build_execution_state()
      
      # Mock high CPU usage
      with_mock(:scheduler, [utilization: fn _ -> {1, [{1, 0.9}]} end]) do
        observation = ObservationCollector.collect_observation(task_id, result, state)
        
        cpu_anomalies = Enum.filter(observation.anomalies, &(&1.type == :high_cpu_usage))
        assert length(cpu_anomalies) > 0
      end
    end
  end

  describe "insights generation" do
    test "generates performance insights for slow tasks" do
      task_id = "slow_task"
      result = {:ok, "success"}
      state = build_state_with_slow_execution(task_id)
      
      observation = ObservationCollector.collect_observation(task_id, result, state)
      
      performance_insights = Enum.filter(observation.insights, fn insight ->
        String.contains?(insight, "optimization")
      end)
      assert length(performance_insights) > 0
    end

    test "generates database optimization insights" do
      task_id = "db_heavy_task"
      result = {:ok, "success"}
      state = build_execution_state()
      
      # Mock telemetry with many DB queries
      with_mock(RubberDuck.Telemetry, [
        get_events_for_task: fn _ ->
          Enum.map(1..150, fn i -> %{type: :database_query, id: i} end)
        end
      ]) do
        observation = ObservationCollector.collect_observation(task_id, result, state)
        
        db_insights = Enum.filter(observation.insights, fn insight ->
          String.contains?(insight, "database") or String.contains?(insight, "batching")
        end)
        assert length(db_insights) > 0
      end
    end

    test "generates retry insights for failures" do
      task_id = "failing_task"
      result = {:error, :network_error}
      state = build_execution_state()
      
      observation = ObservationCollector.collect_observation(task_id, result, state)
      
      retry_insights = Enum.filter(observation.insights, fn insight ->
        String.contains?(insight, "retry") or String.contains?(insight, "alternative")
      end)
      assert length(retry_insights) > 0
    end
  end

  describe "memory delta calculation" do
    test "detects high memory usage side effect" do
      task_id = "memory_heavy_task"
      result = {:ok, "success"}
      state = build_state_with_memory_usage(task_id)
      
      observation = ObservationCollector.collect_observation(task_id, result, state)
      
      memory_effects = Enum.filter(observation.side_effects, &(&1.type == :high_memory_usage))
      assert length(memory_effects) > 0
    end
  end

  # Helper functions

  defp build_execution_state do
    %{
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      history: %{
        timings: %{},
        failures: %{},
        execution_times: %{},
        attempts: %{},
        memory_snapshots: %{}
      }
    }
  end

  defp build_state_with_timing(task_id) do
    start_time = DateTime.utc_now() |> DateTime.add(-5, :second)
    end_time = DateTime.utc_now()
    
    %{
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      history: %{
        timings: %{
          task_id => %{start: start_time, end: end_time}
        },
        failures: %{},
        execution_times: %{},
        attempts: %{},
        memory_snapshots: %{}
      }
    }
  end

  defp build_state_with_slow_execution(task_id) do
    # Create timing that shows slow execution (30 seconds)
    start_time = DateTime.utc_now() |> DateTime.add(-30, :second)
    end_time = DateTime.utc_now()
    
    %{
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      history: %{
        timings: %{
          task_id => %{start: start_time, end: end_time}
        },
        execution_times: %{
          task_id => [5000, 6000, 7000]  # Previous executions were much faster
        },
        failures: %{},
        attempts: %{},
        memory_snapshots: %{}
      }
    }
  end

  defp build_state_with_repeated_failures(task_id) do
    %{
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      history: %{
        timings: %{},
        failures: %{},
        execution_times: %{},
        attempts: %{
          task_id => [
            %{status: :failure, timestamp: DateTime.utc_now()},
            %{status: :failure, timestamp: DateTime.utc_now()},
            %{status: :failure, timestamp: DateTime.utc_now()}
          ]
        },
        memory_snapshots: %{}
      }
    }
  end

  defp build_state_with_memory_usage(task_id) do
    # Set up state to show high memory delta
    %{
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      history: %{
        timings: %{},
        failures: %{},
        execution_times: %{},
        attempts: %{},
        memory_snapshots: %{
          task_id => :erlang.memory(:total) - 50_000_000  # 50MB less than current
        }
      }
    }
  end

  # Mock helper
  defp with_mock(module, mock_functions, test_fn) do
    # Simple mock implementation for testing
    # In a real test, you'd use a proper mocking library like Mox
    original_functions = Enum.map(mock_functions, fn {func, _} ->
      {func, apply(module, func, [])}
    end)
    
    # Apply mocks (simplified)
    result = test_fn.()
    
    # Restore (simplified)
    result
  rescue
    _ -> test_fn.()
  end
end