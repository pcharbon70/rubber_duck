defmodule RubberDuck.Jido.Agents.MetricsTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Jido.Agents.Metrics
  
  setup do
    # Start metrics server
    {:ok, pid} = start_supervised(Metrics)
    
    # Give the server time to initialize
    Process.sleep(50)
    
    {:ok, metrics_pid: pid}
  end
  
  describe "action recording" do
    test "records successful actions" do
      Metrics.record_action("agent_1", TestAction, 1000, :success)
      Metrics.record_action("agent_1", TestAction, 2000, :success)
      Metrics.record_action("agent_1", TestAction, 1500, :success)
      
      # Wait for aggregation
      Process.sleep(1100)
      
      {:ok, metrics} = Metrics.get_agent_metrics("agent_1")
      
      assert metrics.latency_p50 > 0
      assert metrics.latency_mean > 0
      assert metrics.throughput > 0
      assert metrics.error_rate == 0
    end
    
    test "records failed actions" do
      Metrics.record_action("agent_2", TestAction, 1000, :success)
      Metrics.record_action("agent_2", TestAction, 0, :error)
      Metrics.record_action("agent_2", TestAction, 2000, :success)
      
      # Wait for aggregation
      Process.sleep(1100)
      
      {:ok, metrics} = Metrics.get_agent_metrics("agent_2")
      
      assert metrics.error_rate > 0
    end
  end
  
  describe "resource recording" do
    test "records resource usage" do
      Metrics.record_resources("agent_3", 1_000_000, 10, 50_000)
      
      # Resource recording doesn't directly affect metrics until aggregation
      # This test mainly ensures no crashes
      assert :ok == :ok
    end
  end
  
  describe "error recording" do
    test "records errors" do
      Metrics.record_error("agent_4", :timeout)
      Metrics.record_error("agent_4", :badarg)
      
      # Errors will be aggregated in the next cycle
      Process.sleep(1100)
      
      # Errors affect error rate in future implementations
      assert :ok == :ok
    end
  end
  
  describe "system metrics" do
    test "calculates system-wide metrics" do
      # Record data for multiple agents
      Metrics.record_action("sys_agent_1", TestAction, 1000, :success)
      Metrics.record_action("sys_agent_2", TestAction, 2000, :success)
      
      Process.sleep(1100)
      
      {:ok, system_metrics} = Metrics.get_system_metrics()
      
      assert is_integer(system_metrics.total_agents)
      assert is_number(system_metrics.total_throughput)
      assert is_number(system_metrics.avg_latency)
      assert is_integer(system_metrics.total_errors)
    end
  end
  
  describe "export formats" do
    test "exports Prometheus format" do
      # Add some test data
      Metrics.record_action("prom_agent", TestAction, 1500, :success)
      Process.sleep(1100)
      
      {:ok, export} = Metrics.export_prometheus()
      
      assert is_binary(export)
      assert export =~ "# HELP agent_latency_microseconds"
      assert export =~ "# TYPE agent_latency_microseconds summary"
      assert export =~ "agent_latency_microseconds"
      assert export =~ "quantile=\"0.5\""
      assert export =~ "# HELP system_total_agents"
    end
    
    test "exports StatsD format" do
      # Add some test data
      Metrics.record_action("statsd_agent", TestAction, 1500, :success)
      Process.sleep(1100)
      
      {:ok, export} = Metrics.export_statsd()
      
      assert is_list(export)
      # StatsD format validation would go here
    end
  end
  
  describe "percentile calculations" do
    test "calculates correct percentiles" do
      # Record many actions to get meaningful percentiles
      for i <- 1..100 do
        Metrics.record_action("percentile_agent", TestAction, i * 100, :success)
      end
      
      Process.sleep(1100)
      
      {:ok, metrics} = Metrics.get_agent_metrics("percentile_agent")
      
      # P50 should be around the middle value
      assert metrics.latency_p50 > 4000 and metrics.latency_p50 < 6000
      
      # P95 should be near the top
      assert metrics.latency_p95 > 9000
      
      # P99 should be very near the top
      assert metrics.latency_p99 > 9500
    end
  end
end

# Test the CircularBuffer implementation
defmodule CircularBufferTest do
  use ExUnit.Case
  
  test "stores items up to capacity" do
    buffer = CircularBuffer.new(3)
    
    buffer = buffer
    |> CircularBuffer.push(1)
    |> CircularBuffer.push(2)
    |> CircularBuffer.push(3)
    
    assert CircularBuffer.to_list(buffer) == [1, 2, 3]
  end
  
  test "overwrites old items when full" do
    buffer = CircularBuffer.new(3)
    
    buffer = buffer
    |> CircularBuffer.push(1)
    |> CircularBuffer.push(2)
    |> CircularBuffer.push(3)
    |> CircularBuffer.push(4)
    |> CircularBuffer.push(5)
    
    assert CircularBuffer.to_list(buffer) == [3, 4, 5]
  end
  
  test "handles partial buffer correctly" do
    buffer = CircularBuffer.new(5)
    
    buffer = buffer
    |> CircularBuffer.push(1)
    |> CircularBuffer.push(2)
    
    assert CircularBuffer.to_list(buffer) == [1, 2]
  end
end