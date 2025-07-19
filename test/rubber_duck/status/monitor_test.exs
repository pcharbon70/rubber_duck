defmodule RubberDuck.Status.MonitorTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Status.Monitor
  
  setup do
    # Ensure Monitor is started
    case Process.whereis(Monitor) do
      nil -> {:ok, _} = Monitor.start_link()
      _ -> :ok
    end
    
    # Clear any existing alerts
    Monitor.clear_alerts()
    
    :ok
  end
  
  describe "health_status/0" do
    test "returns health status information" do
      assert {:ok, status} = Monitor.health_status()
      
      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :uptime)
      assert Map.has_key?(status, :active_alerts)
      assert Map.has_key?(status, :metrics)
      
      assert status.status in [:healthy, :degraded, :unhealthy]
      assert is_integer(status.uptime)
      assert is_integer(status.active_alerts)
      assert is_map(status.metrics)
    end
  end
  
  describe "record_metric/2" do
    test "records queue depth metric" do
      Monitor.record_metric(:queue_depth, 100)
      
      {:ok, summary} = Monitor.metrics_summary()
      assert Map.has_key?(summary, :queue_depth)
      
      stats = summary.queue_depth
      assert stats.current == 100
      assert stats.count >= 1
    end
    
    test "records throughput metric" do
      Monitor.record_metric(:throughput, 150.5)
      
      {:ok, summary} = Monitor.metrics_summary()
      assert Map.has_key?(summary, :throughput)
      
      stats = summary.throughput
      assert stats.current == 150.5
    end
    
    test "records latency metric" do
      Monitor.record_metric(:latency, 25)
      
      {:ok, summary} = Monitor.metrics_summary()
      assert Map.has_key?(summary, :latency)
      
      stats = summary.latency
      assert stats.current == 25
    end
    
    test "records error rate metric" do
      Monitor.record_metric(:error_rate, 0.02)
      
      {:ok, summary} = Monitor.metrics_summary()
      assert Map.has_key?(summary, :error_rate)
      
      stats = summary.error_rate
      assert stats.current == 0.02
    end
  end
  
  describe "metrics_summary/0" do
    test "returns comprehensive statistics" do
      # Record multiple values
      for i <- 1..10 do
        Monitor.record_metric(:queue_depth, i * 10)
      end
      
      {:ok, summary} = Monitor.metrics_summary()
      queue_stats = summary.queue_depth
      
      assert queue_stats.count == 10
      assert queue_stats.current == 100  # Last value
      assert queue_stats.min == 10
      assert queue_stats.max == 100
      assert queue_stats.average == 55.0
      assert Map.has_key?(queue_stats, :p95)
      assert Map.has_key?(queue_stats, :p99)
    end
    
    test "handles empty metrics gracefully" do
      {:ok, summary} = Monitor.metrics_summary()
      
      # May have empty or populated metrics depending on state
      assert is_map(summary)
    end
  end
  
  describe "recent_alerts/1" do
    test "returns empty list when no alerts" do
      assert {:ok, []} = Monitor.recent_alerts()
    end
    
    test "limits returned alerts" do
      # This would require triggering actual alerts
      # For now, just verify the function works
      assert {:ok, alerts} = Monitor.recent_alerts(5)
      assert is_list(alerts)
      assert length(alerts) <= 5
    end
  end
  
  describe "update_thresholds/3" do
    test "updates warning and critical thresholds" do
      assert :ok = Monitor.update_thresholds(:queue_depth, 500, 1000)
      
      # Verify by triggering metrics that would create alerts
      Monitor.record_metric(:queue_depth, 600)
      
      # Give time for processing
      Process.sleep(100)
      
      {:ok, alerts} = Monitor.recent_alerts()
      
      # Should have warning alert
      assert Enum.any?(alerts, fn alert ->
        alert.metric_type == :queue_depth and alert.level == :warning
      end)
    end
  end
  
  describe "clear_alerts/0" do
    test "removes all alerts" do
      # Trigger some alerts by exceeding thresholds
      Monitor.record_metric(:error_rate, 0.1)  # 10% error rate
      
      Process.sleep(100)
      
      {:ok, alerts_before} = Monitor.recent_alerts()
      assert length(alerts_before) > 0
      
      Monitor.clear_alerts()
      
      {:ok, alerts_after} = Monitor.recent_alerts()
      assert alerts_after == []
    end
  end
  
  describe "telemetry integration" do
    test "processes telemetry events" do
      # Emit a telemetry event that Monitor should handle
      :telemetry.execute(
        [:rubber_duck, :status, :batch, :processed],
        %{batch_size: 10, throughput: 200},
        %{}
      )
      
      Process.sleep(100)
      
      {:ok, summary} = Monitor.metrics_summary()
      
      # Should have recorded throughput
      assert Map.has_key?(summary, :throughput)
      assert summary.throughput.current == 200
    end
  end
  
  describe "health status determination" do
    test "reports healthy when no alerts" do
      Monitor.clear_alerts()
      
      {:ok, status} = Monitor.health_status()
      assert status.status == :healthy
    end
    
    test "reports degraded with multiple warnings" do
      # Trigger multiple warning alerts
      Monitor.record_metric(:queue_depth, 1500)  # Warning level
      Monitor.record_metric(:latency, 150)       # Warning level
      Monitor.record_metric(:throughput, 80)     # Warning level
      
      Process.sleep(100)
      
      {:ok, status} = Monitor.health_status()
      assert status.status == :degraded
    end
    
    test "reports unhealthy with critical alerts" do
      # Trigger critical alert
      Monitor.record_metric(:error_rate, 0.1)  # 10% - critical
      
      Process.sleep(100)
      
      {:ok, status} = Monitor.health_status()
      assert status.status == :unhealthy
    end
  end
end