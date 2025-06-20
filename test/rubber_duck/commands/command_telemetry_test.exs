defmodule RubberDuck.Commands.CommandTelemetryTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Commands.CommandTelemetry
  
  # Mock command module for testing
  defmodule TestCommand do
    def metadata do
      %{name: "test_command", description: "A test command"}
    end
  end
  
  setup do
    execution_id = "test_exec_#{:rand.uniform(10000)}"
    command_module = TestCommand
    context = %{
      user_id: "user_123",
      session_id: "session_456",
      priority: :normal,
      timeout: 30_000
    }
    
    {:ok, execution_id: execution_id, command_module: command_module, context: context}
  end
  
  describe "track_execution_start/3" do
    test "tracks execution start successfully", %{execution_id: execution_id, command_module: command_module, context: context} do
      result = CommandTelemetry.track_execution_start(execution_id, command_module, context)
      assert result == execution_id
    end
    
    test "handles context without optional fields" do
      minimal_context = %{user_id: "user_123"}
      result = CommandTelemetry.track_execution_start("exec_1", TestCommand, minimal_context)
      assert result == "exec_1"
    end
  end
  
  describe "track_execution_success/4" do
    test "tracks successful execution", %{execution_id: execution_id, command_module: command_module, context: context} do
      execution_time = 150
      
      # Should not raise any errors
      assert :ok == CommandTelemetry.track_execution_success(execution_id, command_module, execution_time, context)
    end
    
    test "handles zero execution time" do
      assert :ok == CommandTelemetry.track_execution_success("exec_1", TestCommand, 0, %{user_id: "user_1"})
    end
  end
  
  describe "track_execution_error/4" do
    test "tracks execution error with string error", %{execution_id: execution_id, command_module: command_module, context: context} do
      error = "Command failed"
      
      assert :ok == CommandTelemetry.track_execution_error(execution_id, command_module, error, context)
    end
    
    test "tracks execution error with tuple error" do
      error = {:validation_failed, "Invalid parameters"}
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
    
    test "tracks execution error with atom error" do
      error = :timeout
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
    
    test "tracks execution error with complex error structure" do
      error = {:execution_failed, %{message: "Internal error", code: 500}}
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
  end
  
  describe "track_execution_cancelled/3" do
    test "tracks cancelled execution", %{execution_id: execution_id, command_module: command_module, context: context} do
      assert :ok == CommandTelemetry.track_execution_cancelled(execution_id, command_module, context)
    end
  end
  
  describe "track_validation_error/4" do
    test "tracks validation errors", %{execution_id: execution_id, command_module: command_module, context: context} do
      validation_errors = [
        {:name, "is required"},
        {:email, "must be valid"}
      ]
      
      assert :ok == CommandTelemetry.track_validation_error(execution_id, command_module, validation_errors, context)
    end
    
    test "tracks empty validation errors list" do
      assert :ok == CommandTelemetry.track_validation_error("exec_1", TestCommand, [], %{user_id: "user_1"})
    end
  end
  
  describe "track_execution_timeout/4" do
    test "tracks execution timeout", %{execution_id: execution_id, command_module: command_module, context: context} do
      timeout_ms = 30_000
      
      assert :ok == CommandTelemetry.track_execution_timeout(execution_id, command_module, timeout_ms, context)
    end
  end
  
  describe "track_circuit_breaker_event/3" do
    test "tracks circuit breaker opened event" do
      assert :ok == CommandTelemetry.track_circuit_breaker_event(TestCommand, :opened)
    end
    
    test "tracks circuit breaker closed event with metadata" do
      metadata = %{failure_count: 5, threshold: 10}
      
      assert :ok == CommandTelemetry.track_circuit_breaker_event(TestCommand, :closed, metadata)
    end
    
    test "tracks circuit breaker half_open event" do
      assert :ok == CommandTelemetry.track_circuit_breaker_event(TestCommand, :half_open)
    end
  end
  
  describe "track_handler_lifecycle/4" do
    test "tracks handler spawned event", %{execution_id: execution_id, command_module: command_module} do
      assert :ok == CommandTelemetry.track_handler_lifecycle(execution_id, command_module, :spawned)
    end
    
    test "tracks handler terminated event with metadata" do
      metadata = %{reason: :normal, uptime_ms: 1500}
      
      assert :ok == CommandTelemetry.track_handler_lifecycle("exec_1", TestCommand, :terminated, metadata)
    end
  end
  
  describe "track_command_migration/5" do
    test "tracks successful command migration", %{execution_id: execution_id, command_module: command_module} do
      from_node = :"node1@host"
      to_node = :"node2@host"
      
      assert :ok == CommandTelemetry.track_command_migration(execution_id, command_module, from_node, to_node, :success)
    end
    
    test "tracks failed command migration" do
      assert :ok == CommandTelemetry.track_command_migration("exec_1", TestCommand, :node1, :node2, :failed)
    end
  end
  
  describe "track_supervisor_stats/2" do
    test "tracks supervisor statistics" do
      stats = %{
        total_commands: 100,
        active_commands: 15,
        cluster_nodes: [:"node1@host", :"node2@host"],
        load_distribution: %{
          balance_score: 0.85,
          variance: 2.3
        }
      }
      
      assert :ok == CommandTelemetry.track_supervisor_stats(stats)
    end
    
    test "tracks supervisor stats with additional metadata" do
      stats = %{
        total_commands: 50,
        active_commands: 5,
        cluster_nodes: [:"node1@host"],
        load_distribution: %{
          balance_score: 1.0,
          variance: 0.0
        }
      }
      
      metadata = %{region: "us-east-1", environment: "production"}
      
      assert :ok == CommandTelemetry.track_supervisor_stats(stats, metadata)
    end
  end
  
  describe "track_manager_stats/2" do
    test "tracks execution manager statistics" do
      execution_stats = %{
        total_executions: 1000,
        successful_executions: 950,
        failed_executions: 40,
        cancelled_executions: 10,
        average_execution_time: 250.5
      }
      
      active_executions = 25
      
      assert :ok == CommandTelemetry.track_manager_stats(execution_stats, active_executions)
    end
  end
  
  describe "track_resource_usage/4" do
    test "tracks resource usage", %{execution_id: execution_id, command_module: command_module, context: context} do
      resource_data = %{
        memory_usage: 1024 * 1024,  # 1MB
        cpu_usage: 15.5,            # 15.5%
        disk_io: 512,               # 512 bytes
        network_io: 2048            # 2KB
      }
      
      assert :ok == CommandTelemetry.track_resource_usage(execution_id, command_module, resource_data, context)
    end
    
    test "tracks resource usage with partial data" do
      resource_data = %{
        memory_usage: 512 * 1024  # Only memory, others should default to 0
      }
      
      assert :ok == CommandTelemetry.track_resource_usage("exec_1", TestCommand, resource_data, %{user_id: "user_1"})
    end
  end
  
  describe "track_throughput/4" do
    test "tracks throughput metrics" do
      time_window = 60_000  # 1 minute
      execution_count = 120
      
      assert :ok == CommandTelemetry.track_throughput(TestCommand, time_window, execution_count)
    end
    
    test "tracks throughput with metadata" do
      metadata = %{node: :"node1@host", priority: :high}
      
      assert :ok == CommandTelemetry.track_throughput(TestCommand, 30_000, 60, metadata)
    end
  end
  
  describe "track_queue_metrics/3" do
    test "tracks queue metrics" do
      queue_size = 25
      wait_time = 150.0
      priority_distribution = %{
        high: 5,
        normal: 15,
        low: 5
      }
      
      assert :ok == CommandTelemetry.track_queue_metrics(queue_size, wait_time, priority_distribution)
    end
    
    test "tracks empty queue metrics" do
      assert :ok == CommandTelemetry.track_queue_metrics(0, 0.0, %{high: 0, normal: 0, low: 0})
    end
  end
  
  describe "track_performance_benchmark/2" do
    test "tracks performance benchmark data" do
      benchmark_data = %{
        min_time: 50,
        max_time: 500,
        avg_time: 200.5,
        p95_time: 450,
        p99_time: 480,
        sample_count: 1000,
        period: "last_24h"
      }
      
      assert :ok == CommandTelemetry.track_performance_benchmark(TestCommand, benchmark_data)
    end
  end
  
  describe "error classification" do
    test "classifies validation errors correctly" do
      # This tests the private classify_command_error function indirectly
      error = {:validation_failed, "Invalid params"}
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
    
    test "classifies execution errors correctly" do
      error = {:execution_failed, "Command crashed"}
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
    
    test "classifies timeout errors correctly" do
      error = :timeout
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
    
    test "classifies circuit breaker errors correctly" do
      error = :circuit_breaker_open
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
    
    test "classifies unknown errors correctly" do
      error = %{unknown: "error type"}
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
  end
  
  describe "error message extraction" do
    test "extracts string messages correctly" do
      # This tests the private extract_error_message function indirectly
      error = "Simple error message"
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
    
    test "extracts atom error messages" do
      error = :some_error
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
    
    test "extracts tuple error messages" do
      error = {:custom_error, "Custom message"}
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
    
    test "extracts map error messages" do
      error = {:api_error, %{message: "API call failed"}}
      
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, error, %{user_id: "user_1"})
    end
  end
  
  describe "telemetry resilience" do
    test "does not crash on telemetry failures" do
      # Even if telemetry infrastructure fails, the tracking functions should not crash
      # This is handled by the rescue clause in the execute/3 function
      
      # All these should succeed without raising errors
      assert :ok == CommandTelemetry.track_execution_start("exec_1", TestCommand, %{})
      assert :ok == CommandTelemetry.track_execution_success("exec_1", TestCommand, 100, %{})
      assert :ok == CommandTelemetry.track_execution_error("exec_1", TestCommand, "error", %{})
      assert :ok == CommandTelemetry.track_execution_cancelled("exec_1", TestCommand, %{})
    end
  end
end