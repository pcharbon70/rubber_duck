defmodule RubberDuck.TelemetryTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Telemetry

  describe "telemetry supervisor" do
    test "telemetry supervisor starts successfully" do
      # The telemetry supervisor should already be started by the application
      # Let's verify it's running
      assert Process.whereis(RubberDuck.Telemetry) != nil
    end

    test "telemetry supervisor has correct children" do
      children = Supervisor.which_children(RubberDuck.Telemetry)
      
      # Should have at least the console reporter and poller
      assert length(children) >= 2
      
      # Check for specific children
      child_ids = Enum.map(children, fn {id, _, _, _} -> id end)
      
      assert :console_reporter in child_ids
      assert :telemetry_poller in child_ids
    end

    test "telemetry metrics are defined" do
      metrics = Telemetry.metrics()
      
      assert is_list(metrics)
      assert length(metrics) > 0
      
      # Verify we have the expected metric types
      metric_names = Enum.map(metrics, & &1.name)
      
      # VM metrics
      assert [:vm, :memory, :total] in metric_names
      assert [:vm, :memory, :processes] in metric_names
      assert [:vm, :memory, :binary] in metric_names
      assert [:vm, :memory, :ets] in metric_names
      
      # HTTP metrics (when Phoenix is added)
      assert [:phoenix, :router_dispatch, :stop, :duration] in metric_names
      
      # Database metrics
      assert [:rubber_duck, :repo, :query, :total_time] in metric_names
    end
  end

  describe "telemetry measurements" do
    test "VM measurements are dispatched" do
      # Set up a test handler to capture events
      test_pid = self()
      handler_id = :test_vm_handler
      
      :telemetry.attach(
        handler_id,
        [:vm, :memory],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      # Trigger measurements
      RubberDuck.Telemetry.Measurements.dispatch_vm_measurements()
      
      # Should receive the event
      assert_receive {:telemetry_event, [:vm, :memory], measurements, _metadata}, 1000
      
      # Verify measurements
      assert is_integer(measurements.total)
      assert measurements.total > 0
      assert is_integer(measurements.processes)
      assert is_integer(measurements.binary)
      assert is_integer(measurements.ets)
      
      # Clean up
      :telemetry.detach(handler_id)
    end

    test "run queue measurements are dispatched" do
      # Set up a test handler
      test_pid = self()
      handler_id = :test_run_queue_handler
      
      :telemetry.attach(
        handler_id,
        [:vm, :run_queue],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      # Trigger measurements
      RubberDuck.Telemetry.Measurements.dispatch_run_queue_measurements()
      
      # Should receive the event
      assert_receive {:telemetry_event, [:vm, :run_queue], measurements, _metadata}, 1000
      
      # Verify measurements
      assert is_integer(measurements.length)
      assert measurements.length >= 0
      
      # Clean up
      :telemetry.detach(handler_id)
    end
  end

  describe "telemetry reporter" do
    test "console reporter logs metrics when enabled" do
      # This is harder to test directly since it outputs to console
      # We'll just verify the reporter module exists and has the expected function
      assert function_exported?(RubberDuck.Telemetry.Reporter, :handle_event, 4)
    end
  end

  describe "ash telemetry integration" do
    test "ash handler is properly configured" do
      # Verify the Ash telemetry handler module exists
      assert function_exported?(RubberDuck.Telemetry.AshHandler, :handle_event, 4)
    end
  end
end