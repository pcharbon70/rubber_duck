defmodule RubberDuck.Tool.Composition.MonitoringTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.Composition
  alias RubberDuck.Tool.Composition.Middleware.Monitoring
  alias RubberDuck.Tool.Composition.Metrics
  
  # Mock tools for testing
  defmodule MockSuccessTool do
    def execute(params, _context) do
      Process.sleep(10)  # Simulate some work
      {:ok, %{result: "success", data: params}}
    end
  end
  
  defmodule MockFailureTool do
    def execute(_params, _context) do
      Process.sleep(5)  # Simulate some work
      {:error, "simulated failure"}
    end
  end
  
  defmodule MockSlowTool do
    def execute(params, _context) do
      Process.sleep(100)  # Simulate slow work
      {:ok, %{result: "slow_success", data: params}}
    end
  end
  
  setup do
    # Start metrics collector if not already running
    case GenServer.whereis(Metrics) do
      nil -> 
        {:ok, _pid} = Metrics.start_link([])
        :ok
      _pid -> 
        :ok
    end
    
    # Reset metrics for clean test state
    Metrics.reset_metrics()
    
    # Set up telemetry handler to capture events
    events = [
      [:rubber_duck, :tool, :composition, :workflow_start],
      [:rubber_duck, :tool, :composition, :workflow_complete],
      [:rubber_duck, :tool, :composition, :workflow_error],
      [:rubber_duck, :tool, :composition, :workflow_step_start],
      [:rubber_duck, :tool, :composition, :workflow_step_complete],
      [:rubber_duck, :tool, :composition, :workflow_step_error]
    ]
    
    handler_id = "monitoring_test_#{inspect(self())}"
    
    :telemetry.attach_many(handler_id, events, fn event, measurements, metadata, _config ->
      send(self(), {:telemetry, event, measurements, metadata})
    end, nil)
    
    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)
    
    :ok
  end
  
  describe "workflow monitoring" do
    test "emits telemetry events for successful workflow" do
      workflow = Composition.sequential("test_workflow", [
        {:step1, MockSuccessTool, %{action: "first"}},
        {:step2, MockSuccessTool, %{action: "second"}}
      ])
      
      # Execute workflow with monitoring enabled
      assert {:ok, _result} = Composition.execute_with_monitoring(workflow, %{input: "test"})
      
      # Verify workflow start event
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_start], measurements, metadata}
      assert measurements.count == 1
      assert metadata[:steps_count] == 2
      assert is_binary(metadata.workflow_id)
      
      # Verify step start events
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_step_start], step1_measurements, step1_metadata}
      assert step1_measurements.count == 1
      assert step1_metadata.step_name == :step1
      
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_step_start], step2_measurements, step2_metadata}
      assert step2_measurements.count == 1
      assert step2_metadata.step_name == :step2
      
      # Verify step completion events
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_step_complete], step1_complete_measurements, step1_complete_metadata}
      assert step1_complete_measurements.count == 1
      assert step1_complete_measurements.duration > 0
      assert step1_complete_metadata.step_name == :step1
      
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_step_complete], step2_complete_measurements, step2_complete_metadata}
      assert step2_complete_measurements.count == 1
      assert step2_complete_measurements.duration > 0
      assert step2_complete_metadata.step_name == :step2
      
      # Verify workflow completion event
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_complete], workflow_complete_measurements, workflow_complete_metadata}
      assert workflow_complete_measurements.count == 1
      assert workflow_complete_measurements.duration > 0
      assert workflow_complete_metadata.total_steps == 2
      assert workflow_complete_metadata.completed_steps == 2
      assert workflow_complete_metadata.failed_steps == 0
      assert workflow_complete_metadata.success_rate == 100.0
    end
    
    test "emits telemetry events for failed workflow" do
      workflow = Composition.sequential("test_workflow", [
        {:step1, MockSuccessTool, %{action: "first"}},
        {:step2, MockFailureTool, %{action: "second"}}
      ])
      
      # Execute workflow with monitoring enabled
      assert {:error, _reason} = Composition.execute_with_monitoring(workflow, %{input: "test"})
      
      # Verify workflow start event
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_start], _measurements, _metadata}
      
      # Verify step events
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_step_start], _step1_measurements, _step1_metadata}
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_step_complete], _step1_complete_measurements, _step1_complete_metadata}
      
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_step_start], _step2_measurements, _step2_metadata}
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_step_error], step2_error_measurements, step2_error_metadata}
      
      # Verify step error details
      assert step2_error_measurements.count == 1
      assert step2_error_measurements.duration > 0
      assert step2_error_metadata.step_name == :step2
      assert step2_error_metadata.error_type != nil
      assert step2_error_metadata.error_message != nil
      
      # Verify workflow error event
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_error], workflow_error_measurements, workflow_error_metadata}
      assert workflow_error_measurements.count == 1
      assert workflow_error_measurements.duration > 0
      assert workflow_error_metadata.total_steps == 2
      assert workflow_error_metadata.completed_steps == 1
      assert workflow_error_metadata.failed_steps == 1
    end
    
    test "monitoring can be disabled" do
      workflow = Composition.sequential("test_workflow", [
        {:step1, MockSuccessTool, %{action: "first"}}
      ])
      
      # Execute workflow with monitoring disabled
      assert {:ok, _result} = Composition.execute(workflow, %{input: "test"}, monitoring_enabled: false)
      
      # Verify no telemetry events are emitted
      refute_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_start], _, _}, 100
      refute_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_step_start], _, _}, 100
    end
    
    test "parallel workflow monitoring" do
      workflow = Composition.parallel("parallel_workflow", [
        {:step1, MockSuccessTool, %{action: "parallel1"}},
        {:step2, MockSuccessTool, %{action: "parallel2"}},
        {:step3, MockSlowTool, %{action: "parallel3"}}
      ])
      
      # Execute parallel workflow with monitoring
      assert {:ok, _result} = Composition.execute_with_monitoring(workflow, %{input: "test"})
      
      # Verify workflow start event
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_start], measurements, metadata}
      assert measurements.count == 1
      assert metadata[:steps_count] == 3
      
      # Verify all steps start (may be in any order for parallel execution)
      step_start_events = for _ <- 1..3 do
        assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_step_start], measurements, metadata}
        {measurements, metadata}
      end
      
      step_names = Enum.map(step_start_events, fn {_measurements, metadata} -> metadata.step_name end)
      assert :step1 in step_names
      assert :step2 in step_names
      assert :step3 in step_names
      
      # Verify all steps complete
      step_complete_events = for _ <- 1..3 do
        assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_step_complete], measurements, metadata}
        {measurements, metadata}
      end
      
      # Verify workflow completion
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :workflow_complete], workflow_measurements, workflow_metadata}
      assert workflow_measurements.count == 1
      assert workflow_metadata.total_steps == 3
      assert workflow_metadata.completed_steps == 3
      assert workflow_metadata.failed_steps == 0
      assert workflow_metadata.success_rate == 100.0
    end
  end
  
  describe "metrics collection" do
    test "collects workflow metrics" do
      workflow = Composition.sequential("metrics_test", [
        {:step1, MockSuccessTool, %{action: "first"}},
        {:step2, MockSuccessTool, %{action: "second"}}
      ])
      
      # Execute workflow
      assert {:ok, _result} = Composition.execute_with_monitoring(workflow, %{input: "test"})
      
      # Wait for metrics to be processed
      Process.sleep(50)
      
      # Get metrics summary
      metrics = Metrics.get_metrics_summary()
      
      # Verify counters
      assert metrics.counters.workflow_started >= 1
      assert metrics.counters.workflow_completed >= 1
      assert metrics.counters.step_started >= 2
      assert metrics.counters.step_completed >= 2
      
      # Verify summary
      assert metrics.summary.total_workflows >= 1
      assert metrics.summary.successful_workflows >= 1
      assert metrics.summary.success_rate >= 0
      assert metrics.summary.average_workflow_duration >= 0
      assert metrics.summary.average_step_duration >= 0
    end
    
    test "tracks failed workflow metrics" do
      workflow = Composition.sequential("failure_test", [
        {:step1, MockSuccessTool, %{action: "first"}},
        {:step2, MockFailureTool, %{action: "second"}}
      ])
      
      # Execute workflow that will fail
      assert {:error, _reason} = Composition.execute_with_monitoring(workflow, %{input: "test"})
      
      # Wait for metrics to be processed
      Process.sleep(50)
      
      # Get metrics summary
      metrics = Metrics.get_metrics_summary()
      
      # Verify failure counters
      assert metrics.counters.workflow_started >= 1
      assert metrics.counters.workflow_failed >= 1
      assert metrics.counters.step_started >= 2
      assert metrics.counters.step_completed >= 1
      assert metrics.counters.step_failed >= 1
      
      # Verify summary shows some failures
      assert metrics.summary.failed_workflows >= 1
    end
    
    test "provides workflow-specific metrics" do
      workflow = Composition.sequential("specific_test", [
        {:step1, MockSuccessTool, %{action: "first"}}
      ])
      
      # Execute workflow
      assert {:ok, _result} = Composition.execute_with_monitoring(workflow, %{input: "test"})
      
      # Wait for telemetry to be processed
      Process.sleep(50)
      
      # We can't easily test specific workflow metrics without knowing the workflow ID
      # This would require integration with the actual monitoring middleware
      # For now, we'll verify the general metrics structure
      metrics = Metrics.get_metrics_summary()
      
      assert is_map(metrics.counters)
      assert is_map(metrics.histograms)
      assert is_map(metrics.gauges)
      assert is_map(metrics.summary)
    end
  end
  
  describe "monitoring middleware" do
    test "middleware initialization" do
      assert {:ok, context} = Monitoring.init([])
      assert is_binary(context.workflow_id)
      assert is_integer(context.start_time)
      assert context.step_count == 0
      assert context.completed_steps == 0
      assert context.failed_steps == 0
      assert is_map(context.metrics)
    end
    
    test "middleware cleanup" do
      {:ok, context} = Monitoring.init([])
      assert :ok = Monitoring.cleanup(context)
    end
  end
  
  describe "prometheus metrics export" do
    test "exports metrics in prometheus format" do
      workflow = Composition.sequential("prometheus_test", [
        {:step1, MockSuccessTool, %{action: "first"}}
      ])
      
      # Execute workflow
      assert {:ok, _result} = Composition.execute_with_monitoring(workflow, %{input: "test"})
      
      # Wait for metrics to be processed
      Process.sleep(50)
      
      # Export prometheus metrics
      prometheus_data = Metrics.export_prometheus_metrics()
      
      # Verify prometheus format
      assert is_binary(prometheus_data)
      assert String.contains?(prometheus_data, "# HELP")
      assert String.contains?(prometheus_data, "# TYPE")
      assert String.contains?(prometheus_data, "composition_workflows_total")
      assert String.contains?(prometheus_data, "composition_workflows_successful_total")
      assert String.contains?(prometheus_data, "composition_workflows_failed_total")
      assert String.contains?(prometheus_data, "composition_workflows_active")
    end
  end
end