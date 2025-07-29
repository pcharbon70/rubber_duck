defmodule RubberDuck.Jido.Agents.WorkflowMonitorTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Jido.Agents.WorkflowMonitor

  @workflow_id "test_workflow_123"

  setup do
    # Start the monitor
    {:ok, pid} = start_supervised(WorkflowMonitor)
    
    # Ensure telemetry events are handled
    Process.sleep(50)
    
    {:ok, monitor_pid: pid}
  end

  describe "telemetry event handling" do
    test "tracks workflow started events" do
      # Emit workflow started event
      :telemetry.execute(
        [:workflow, :started],
        %{count: 1},
        %{
          workflow_id: @workflow_id,
          module: TestWorkflow,
          inputs: %{test: "data"}
        }
      )
      
      # Give time for processing
      Process.sleep(50)
      
      # Verify the metric was recorded
      metrics = WorkflowMonitor.get_metrics()
      assert metrics.workflows.started >= 1
      assert Map.has_key?(metrics.workflows.active, @workflow_id)
    end

    test "tracks workflow completed events" do
      # Start a workflow first
      :telemetry.execute(
        [:workflow, :started],
        %{count: 1},
        %{workflow_id: @workflow_id, module: TestWorkflow, inputs: %{}}
      )
      
      # Complete the workflow
      :telemetry.execute(
        [:workflow, :completed],
        %{duration: 1500, count: 1},
        %{
          workflow_id: @workflow_id,
          result: %{success: true}
        }
      )
      
      Process.sleep(50)
      
      metrics = WorkflowMonitor.get_metrics()
      assert metrics.workflows.completed >= 1
      assert not Map.has_key?(metrics.workflows.active, @workflow_id)
      assert metrics.performance.average_duration > 0
    end

    test "tracks workflow failed events" do
      # Start a workflow first
      :telemetry.execute(
        [:workflow, :started],
        %{count: 1},
        %{workflow_id: @workflow_id, module: TestWorkflow, inputs: %{}}
      )
      
      # Fail the workflow
      :telemetry.execute(
        [:workflow, :failed],
        %{duration: 500, count: 1},
        %{
          workflow_id: @workflow_id,
          error: %{reason: :test_error}
        }
      )
      
      Process.sleep(50)
      
      metrics = WorkflowMonitor.get_metrics()
      assert metrics.workflows.failed >= 1
      assert not Map.has_key?(metrics.workflows.active, @workflow_id)
    end

    test "tracks step execution events" do
      # Emit step executed event
      :telemetry.execute(
        [:step, :executed],
        %{duration: 250, count: 1},
        %{
          workflow_id: @workflow_id,
          step_name: "test_step",
          result: %{success: true}
        }
      )
      
      Process.sleep(50)
      
      metrics = WorkflowMonitor.get_metrics()
      assert metrics.steps.total >= 1
      assert Map.has_key?(metrics.steps.by_name, "test_step")
    end

    test "tracks agent selection events" do
      # Emit agent selected event
      :telemetry.execute(
        [:agent, :selected],
        %{selection_time: 50, count: 1},
        %{
          workflow_id: @workflow_id,
          agent_id: "agent_123",
          capabilities: [:test_capability]
        }
      )
      
      Process.sleep(50)
      
      metrics = WorkflowMonitor.get_metrics()
      assert metrics.agents.selections >= 1
      assert Map.has_key?(metrics.agents.by_id, "agent_123")
    end
  end

  describe "get_metrics/0" do
    test "returns current metrics structure" do
      metrics = WorkflowMonitor.get_metrics()
      
      # Verify structure
      assert Map.has_key?(metrics, :workflows)
      assert Map.has_key?(metrics, :steps)
      assert Map.has_key?(metrics, :agents)
      assert Map.has_key?(metrics, :performance)
      
      # Verify workflow metrics
      workflow_metrics = metrics.workflows
      assert Map.has_key?(workflow_metrics, :started)
      assert Map.has_key?(workflow_metrics, :completed)
      assert Map.has_key?(workflow_metrics, :failed)
      assert Map.has_key?(workflow_metrics, :active)
      
      # Verify step metrics
      step_metrics = metrics.steps
      assert Map.has_key?(step_metrics, :total)
      assert Map.has_key?(step_metrics, :by_name)
      
      # Verify agent metrics
      agent_metrics = metrics.agents
      assert Map.has_key?(agent_metrics, :selections)
      assert Map.has_key?(agent_metrics, :by_id)
      
      # Verify performance metrics
      performance_metrics = metrics.performance
      assert Map.has_key?(performance_metrics, :average_duration)
      assert Map.has_key?(performance_metrics, :total_execution_time)
    end

    test "returns zero values for fresh monitor" do
      # Start a fresh monitor
      {:ok, _} = start_supervised({WorkflowMonitor, name: :fresh_monitor})
      
      metrics = GenServer.call(:fresh_monitor, :get_metrics)
      
      assert metrics.workflows.started == 0
      assert metrics.workflows.completed == 0
      assert metrics.workflows.failed == 0
      assert metrics.workflows.active == %{}
      assert metrics.steps.total == 0
      assert metrics.agents.selections == 0
      assert metrics.performance.average_duration == 0
    end
  end

  describe "get_dashboard_data/0" do
    test "returns formatted dashboard data" do
      # Add some test data
      :telemetry.execute(
        [:workflow, :started],
        %{count: 1},
        %{workflow_id: @workflow_id, module: TestWorkflow, inputs: %{}}
      )
      
      :telemetry.execute(
        [:workflow, :completed],
        %{duration: 2000, count: 1},
        %{workflow_id: @workflow_id, result: %{}}
      )
      
      Process.sleep(50)
      
      dashboard_data = WorkflowMonitor.get_dashboard_data()
      
      # Verify structure
      assert Map.has_key?(dashboard_data, :summary)
      assert Map.has_key?(dashboard_data, :active_workflows)
      assert Map.has_key?(dashboard_data, :performance)
      assert Map.has_key?(dashboard_data, :top_steps)
      assert Map.has_key?(dashboard_data, :agent_utilization)
      
      # Verify summary data
      summary = dashboard_data.summary
      assert summary.total_workflows >= 1
      assert summary.success_rate >= 0.0
      assert summary.active_count >= 0
    end

    test "calculates correct success rate" do
      # Start and complete successful workflow
      :telemetry.execute(
        [:workflow, :started],
        %{count: 1},
        %{workflow_id: "success_1", module: TestWorkflow, inputs: %{}}
      )
      
      :telemetry.execute(
        [:workflow, :completed],
        %{duration: 1000, count: 1},
        %{workflow_id: "success_1", result: %{}}
      )
      
      # Start and fail another workflow
      :telemetry.execute(
        [:workflow, :started],
        %{count: 1},
        %{workflow_id: "fail_1", module: TestWorkflow, inputs: %{}}
      )
      
      :telemetry.execute(
        [:workflow, :failed],
        %{duration: 500, count: 1},
        %{workflow_id: "fail_1", error: %{}}
      )
      
      Process.sleep(50)
      
      dashboard_data = WorkflowMonitor.get_dashboard_data()
      
      # Should be 50% success rate (1 success, 1 failure)
      assert dashboard_data.summary.success_rate == 50.0
    end
  end

  describe "reset_metrics/0" do
    test "resets all metrics to initial state" do
      # Add some test data
      :telemetry.execute(
        [:workflow, :started],
        %{count: 1},
        %{workflow_id: @workflow_id, module: TestWorkflow, inputs: %{}}
      )
      
      Process.sleep(50)
      
      # Verify data exists
      metrics_before = WorkflowMonitor.get_metrics()
      assert metrics_before.workflows.started >= 1
      
      # Reset metrics
      :ok = WorkflowMonitor.reset_metrics()
      
      # Verify reset
      metrics_after = WorkflowMonitor.get_metrics()
      assert metrics_after.workflows.started == 0
      assert metrics_after.workflows.completed == 0
      assert metrics_after.workflows.failed == 0
      assert metrics_after.workflows.active == %{}
    end
  end

  describe "monitor process lifecycle" do
    test "monitor can be stopped and restarted" do
      # Stop the monitor
      pid = Process.whereis(WorkflowMonitor)
      :ok = GenServer.stop(pid)
      
      # Verify it's stopped
      refute Process.alive?(pid)
      
      # Start a new one
      {:ok, new_pid} = start_supervised({WorkflowMonitor, []})
      
      # Verify it works
      metrics = GenServer.call(new_pid, :get_metrics)
      assert is_map(metrics)
    end

    test "monitor handles unexpected messages gracefully" do
      # Send an unexpected message
      pid = Process.whereis(WorkflowMonitor)
      send(pid, :unexpected_message)
      
      # Verify monitor still works
      metrics = WorkflowMonitor.get_metrics()
      assert is_map(metrics)
    end
  end
end