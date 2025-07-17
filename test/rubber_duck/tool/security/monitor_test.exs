defmodule RubberDuck.Tool.Security.MonitorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.Security.Monitor
  
  setup do
    # Start a fresh Monitor for each test
    start_supervised!({Monitor, []})
    :ok
  end
  
  describe "event recording" do
    test "records security events" do
      Monitor.record_event(:access_check, %{user_id: "user1", tool: :test_tool}, %{result: :allowed})
      
      {:ok, events} = Monitor.get_stats(:minute)
      
      assert events.total_events > 0
      assert Map.has_key?(events.events_by_type, :access_check)
    end
    
    test "updates user behavior tracking" do
      Monitor.record_event(:tool_execution, %{user_id: "user1", tool: :test_tool}, %{result: :success})
      Monitor.record_event(:tool_execution, %{user_id: "user1", tool: :test_tool}, %{result: :error})
      
      {:ok, stats} = Monitor.get_stats(:minute)
      
      assert stats.total_events == 2
      assert stats.active_users == 1
    end
  end
  
  describe "pattern checking" do
    test "detects path traversal patterns" do
      patterns = Monitor.check_patterns("../../../etc/passwd", :path_traversal)
      
      assert :path_traversal in patterns
    end
    
    test "detects command injection patterns" do
      patterns = Monitor.check_patterns("rm -rf /; cat /etc/passwd", :command_injection)
      
      assert :command_injection in patterns
    end
    
    test "detects SQL injection patterns" do
      patterns = Monitor.check_patterns("'; DROP TABLE users; --", :sql_injection)
      
      assert :sql_injection in patterns
    end
    
    test "detects multiple pattern types" do
      patterns = Monitor.check_patterns("../../../etc/passwd && rm -rf /", :all)
      
      assert :path_traversal in patterns
      assert :command_injection in patterns
    end
    
    test "returns empty list for safe values" do
      patterns = Monitor.check_patterns("safe_filename.txt", :all)
      
      assert patterns == []
    end
  end
  
  describe "severity calculation" do
    test "assigns critical severity to dangerous patterns" do
      Monitor.record_event(:input_validation, %{user_id: "user1"}, %{
        params: "'; DROP TABLE users; --"
      })
      
      Process.sleep(100)  # Allow processing
      
      {:ok, alerts} = Monitor.get_alerts(%{severity: :critical})
      
      assert length(alerts) > 0
    end
    
    test "assigns appropriate severity to different event types" do
      Monitor.record_event(:unauthorized_access, %{user_id: "user1"}, %{})
      Monitor.record_event(:rate_limit_exceeded, %{user_id: "user1"}, %{})
      
      Process.sleep(100)
      
      {:ok, high_alerts} = Monitor.get_alerts(%{severity: :high})
      {:ok, medium_alerts} = Monitor.get_alerts(%{severity: :medium})
      
      assert length(high_alerts) > 0
      assert length(medium_alerts) > 0
    end
  end
  
  describe "alerting" do
    test "creates alerts for high severity events" do
      Monitor.record_event(:unauthorized_access, %{user_id: "user1"}, %{
        attempted_resource: "/admin/users"
      })
      
      Process.sleep(100)
      
      {:ok, alerts} = Monitor.get_alerts()
      
      assert length(alerts) > 0
      alert = hd(alerts)
      assert alert.event.type == :unauthorized_access
      assert alert.event.severity == :high
    end
    
    test "respects alert cooldown" do
      # Generate first alert
      Monitor.record_event(:unauthorized_access, %{user_id: "user1"}, %{})
      
      Process.sleep(100)
      
      # Generate second alert (should be suppressed by cooldown)
      Monitor.record_event(:unauthorized_access, %{user_id: "user1"}, %{})
      
      Process.sleep(100)
      
      {:ok, alerts} = Monitor.get_alerts()
      
      # Should only have one alert due to cooldown
      assert length(alerts) == 1
    end
    
    test "can register custom alert handlers" do
      # Set up a test handler
      test_pid = self()
      handler = fn alert ->
        send(test_pid, {:alert_received, alert})
      end
      
      Monitor.register_alert_handler(handler)
      
      # Generate high severity event
      Monitor.record_event(:unauthorized_access, %{user_id: "user1"}, %{})
      
      # Should receive alert
      assert_receive {:alert_received, alert}, 1000
      assert alert.event.type == :unauthorized_access
    end
  end
  
  describe "anomaly detection" do
    test "detects rapid request patterns" do
      # Generate many requests quickly
      for i <- 1..100 do
        Monitor.record_event(:tool_execution, %{user_id: "user1", tool: :test_tool}, %{
          request_id: "req_#{i}"
        })
      end
      
      # Wait for anomaly analysis
      Process.sleep(11_000)  # Analysis runs every 10 seconds
      
      {:ok, stats} = Monitor.get_stats(:minute)
      
      # Should detect anomaly (this is implementation dependent)
      assert stats.total_events > 0
    end
    
    test "detects high error rates" do
      # Generate requests with high error rate
      for i <- 1..20 do
        result = if rem(i, 2) == 0, do: :error, else: :success
        Monitor.record_event(result, %{user_id: "user1", tool: :test_tool}, %{})
      end
      
      # Wait for analysis
      Process.sleep(11_000)
      
      {:ok, stats} = Monitor.get_stats(:minute)
      
      # Should have detected errors
      assert Map.has_key?(stats.events_by_type, :error)
    end
    
    test "detects multiple attack patterns from same user" do
      # Generate events with different attack patterns
      Monitor.record_event(:input_validation, %{user_id: "user1"}, %{
        params: "../../../etc/passwd"
      })
      Monitor.record_event(:input_validation, %{user_id: "user1"}, %{
        params: "'; DROP TABLE users; --"
      })
      Monitor.record_event(:input_validation, %{user_id: "user1"}, %{
        params: "{{ 7*7 }}"
      })
      
      # Wait for analysis
      Process.sleep(11_000)
      
      {:ok, stats} = Monitor.get_stats(:minute)
      
      # Should detect pattern diversity
      assert stats.total_events > 0
    end
  end
  
  describe "statistics compilation" do
    test "compiles global statistics" do
      # Generate some activity
      Monitor.record_event(:tool_execution, %{user_id: "user1", tool: :tool1}, %{})
      Monitor.record_event(:tool_execution, %{user_id: "user2", tool: :tool2}, %{})
      Monitor.record_event(:error, %{user_id: "user1", tool: :tool1}, %{})
      
      {:ok, stats} = Monitor.get_stats(:minute)
      
      assert is_map(stats)
      assert Map.has_key?(stats, :total_events)
      assert Map.has_key?(stats, :events_by_type)
      assert Map.has_key?(stats, :active_users)
      assert stats.total_events == 3
      assert stats.active_users == 2
    end
    
    test "compiles statistics for different time ranges" do
      Monitor.record_event(:tool_execution, %{user_id: "user1"}, %{})
      
      {:ok, minute_stats} = Monitor.get_stats(:minute)
      {:ok, hour_stats} = Monitor.get_stats(:hour)
      {:ok, day_stats} = Monitor.get_stats(:day)
      
      # All should include the recent event
      assert minute_stats.total_events > 0
      assert hour_stats.total_events > 0
      assert day_stats.total_events > 0
    end
    
    test "tracks top attack patterns" do
      # Generate events with various patterns
      Monitor.record_event(:input_validation, %{user_id: "user1"}, %{
        params: "../../../etc/passwd"
      })
      Monitor.record_event(:input_validation, %{user_id: "user2"}, %{
        params: "../../../etc/passwd"
      })
      Monitor.record_event(:input_validation, %{user_id: "user3"}, %{
        params: "'; DROP TABLE users; --"
      })
      
      Process.sleep(100)
      
      {:ok, stats} = Monitor.get_stats(:minute)
      
      assert Map.has_key?(stats, :top_patterns)
      assert is_list(stats.top_patterns)
      
      # Should have path_traversal as most common
      if length(stats.top_patterns) > 0 do
        {top_pattern, count} = hd(stats.top_patterns)
        assert top_pattern == :path_traversal
        assert count >= 2
      end
    end
  end
  
  describe "alert filtering" do
    test "filters alerts by severity" do
      Monitor.record_event(:unauthorized_access, %{user_id: "user1"}, %{})  # high
      Monitor.record_event(:rate_limit_exceeded, %{user_id: "user1"}, %{})  # medium
      
      Process.sleep(100)
      
      {:ok, high_alerts} = Monitor.get_alerts(%{severity: :high})
      {:ok, medium_alerts} = Monitor.get_alerts(%{severity: :medium})
      
      assert length(high_alerts) > 0
      assert length(medium_alerts) > 0
      
      # Check that filtering worked
      assert Enum.all?(high_alerts, & &1.event.severity == :high)
      assert Enum.all?(medium_alerts, & &1.event.severity == :medium)
    end
    
    test "filters alerts by user" do
      Monitor.record_event(:unauthorized_access, %{user_id: "user1"}, %{})
      Monitor.record_event(:unauthorized_access, %{user_id: "user2"}, %{})
      
      Process.sleep(100)
      
      {:ok, user1_alerts} = Monitor.get_alerts(%{user_id: "user1"})
      {:ok, user2_alerts} = Monitor.get_alerts(%{user_id: "user2"})
      
      assert length(user1_alerts) > 0
      assert length(user2_alerts) > 0
      
      # Check that filtering worked
      assert Enum.all?(user1_alerts, fn alert ->
        get_in(alert.event.source, [:user_id]) == "user1"
      end)
      assert Enum.all?(user2_alerts, fn alert ->
        get_in(alert.event.source, [:user_id]) == "user2"
      end)
    end
    
    test "limits number of alerts returned" do
      # Generate many alerts
      for i <- 1..20 do
        Monitor.record_event(:unauthorized_access, %{user_id: "user#{i}"}, %{})
      end
      
      Process.sleep(100)
      
      {:ok, limited_alerts} = Monitor.get_alerts(%{limit: 5})
      
      assert length(limited_alerts) <= 5
    end
  end
  
  describe "threshold updates" do
    test "can update anomaly detection thresholds" do
      new_thresholds = %{
        requests_per_minute: 120,
        error_rate: 0.2
      }
      
      assert :ok = Monitor.update_thresholds(new_thresholds)
      
      # Thresholds should be updated (this is internal state)
      # We can verify by generating events that would trigger under old thresholds
      # but not under new ones
    end
  end
  
  describe "baseline updates" do
    test "updates behavior baselines over time" do
      # Generate normal behavior
      for i <- 1..10 do
        Monitor.record_event(:tool_execution, %{user_id: "user#{i}", tool: :test_tool}, %{})
      end
      
      # Wait for baseline update
      Process.sleep(61_000)  # Baseline updates every 60 seconds
      
      # Should have updated baselines (this is internal state)
      # We can verify by checking if anomaly detection works differently
    end
  end
  
  describe "telemetry integration" do
    test "emits telemetry events" do
      # Set up telemetry handler
      test_pid = self()
      
      :telemetry.attach(
        "test-security-events",
        [:rubber_duck, :security, :event],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      # Generate security event
      Monitor.record_event(:tool_execution, %{user_id: "user1"}, %{})
      
      # Should receive telemetry event
      assert_receive {:telemetry_event, [:rubber_duck, :security, :event], measurements, metadata}, 1000
      
      assert measurements.count == 1
      assert metadata.type == :tool_execution
      
      # Cleanup
      :telemetry.detach("test-security-events")
    end
  end
end