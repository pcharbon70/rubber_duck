defmodule RubberDuck.EventBroadcasting.MetricsCollectorTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.EventBroadcasting.{MetricsCollector, EventBroadcaster}
  
  setup do
    # Start dependencies
    {:ok, broadcaster_pid} = EventBroadcaster.start_link()
    {:ok, collector_pid} = MetricsCollector.start_link(window_size: 1000, retention_windows: 5)
    
    on_exit(fn ->
      if Process.alive?(collector_pid), do: GenServer.stop(collector_pid)
      if Process.alive?(broadcaster_pid), do: GenServer.stop(broadcaster_pid)
    end)
    
    %{collector: collector_pid, broadcaster: broadcaster_pid}
  end
  
  describe "metric recording" do
    test "records counter metrics" do
      assert :ok = MetricsCollector.record(:counter, "test.counter", 1, %{provider: "test"})
      assert :ok = MetricsCollector.record(:counter, "test.counter", 5, %{provider: "test"})
      
      current_metrics = MetricsCollector.get_current_metrics("test.counter")
      assert length(current_metrics) == 2
      
      # Verify metric structure
      metric = List.first(current_metrics)
      assert metric.name == "test.counter"
      assert metric.type == :counter
      assert metric.value in [1, 5]
      assert metric.node == node()
      assert metric.tags.provider == "test"
    end
    
    test "records gauge metrics" do
      assert :ok = MetricsCollector.record(:gauge, "memory.usage", 0.75, %{component: "load_balancer"})
      
      current_metrics = MetricsCollector.get_current_metrics("memory.usage")
      assert length(current_metrics) == 1
      
      metric = List.first(current_metrics)
      assert metric.type == :gauge
      assert metric.value == 0.75
      assert metric.tags.component == "load_balancer"
    end
    
    test "records histogram metrics" do
      assert :ok = MetricsCollector.record(:histogram, "request.latency", 150, %{endpoint: "/chat"})
      assert :ok = MetricsCollector.record(:histogram, "request.latency", [200, 180, 90], %{endpoint: "/chat"})
      
      current_metrics = MetricsCollector.get_current_metrics("request.latency")
      assert length(current_metrics) == 2
      
      # Check histogram metric
      histogram_metric = Enum.find(current_metrics, fn m -> is_list(m.value) end)
      assert histogram_metric.type == :histogram
      assert histogram_metric.value == [200, 180, 90]
    end
    
    test "records summary metrics" do
      assert :ok = MetricsCollector.record(:summary, "response.time", 95.5, %{percentile: "p95"})
      
      current_metrics = MetricsCollector.get_current_metrics("response.time")
      assert length(current_metrics) == 1
      
      metric = List.first(current_metrics)
      assert metric.type == :summary
      assert metric.value == 95.5
    end
    
    test "batch metric recording" do
      metrics = [
        {:counter, "batch.requests", 1, %{status: "success"}},
        {:gauge, "batch.memory", 0.65, %{node: node()}},
        {:histogram, "batch.latency", 120, %{operation: "process"}}
      ]
      
      assert :ok = MetricsCollector.record_batch(metrics)
      
      # Verify all metrics were recorded
      assert length(MetricsCollector.get_current_metrics("batch.requests")) == 1
      assert length(MetricsCollector.get_current_metrics("batch.memory")) == 1
      assert length(MetricsCollector.get_current_metrics("batch.latency")) == 1
    end
  end
  
  describe "metric aggregation" do
    test "aggregates counter metrics correctly" do
      # Record some counter metrics
      assert :ok = MetricsCollector.record(:counter, "aggregation.counter", 1)
      assert :ok = MetricsCollector.record(:counter, "aggregation.counter", 3)
      assert :ok = MetricsCollector.record(:counter, "aggregation.counter", 2)
      
      # Wait for aggregation window
      Process.sleep(1200)
      
      # Get aggregated metrics
      aggregated = MetricsCollector.get_aggregated_metrics("aggregation.counter", minutes: 1)
      
      assert length(aggregated) >= 1
      
      window_data = List.first(aggregated)
      assert window_data.type == :counter
      assert window_data.total == 6  # 1 + 3 + 2
      assert window_data.count == 3
      assert window_data.rate_per_second > 0
    end
    
    test "aggregates gauge metrics correctly" do
      # Record gauge metrics
      assert :ok = MetricsCollector.record(:gauge, "aggregation.gauge", 0.5)
      assert :ok = MetricsCollector.record(:gauge, "aggregation.gauge", 0.8)
      assert :ok = MetricsCollector.record(:gauge, "aggregation.gauge", 0.3)
      
      # Wait for aggregation
      Process.sleep(1200)
      
      aggregated = MetricsCollector.get_aggregated_metrics("aggregation.gauge", minutes: 1)
      
      assert length(aggregated) >= 1
      
      window_data = List.first(aggregated)
      assert window_data.type == :gauge
      assert window_data.current == 0.3  # Last value
      assert window_data.min == 0.3
      assert window_data.max == 0.8
      assert window_data.avg == (0.5 + 0.8 + 0.3) / 3
      assert window_data.count == 3
    end
    
    test "aggregates histogram metrics correctly" do
      # Record histogram metrics
      assert :ok = MetricsCollector.record(:histogram, "aggregation.histogram", [100, 200, 150])
      assert :ok = MetricsCollector.record(:histogram, "aggregation.histogram", 180)
      assert :ok = MetricsCollector.record(:histogram, "aggregation.histogram", [90, 220])
      
      # Wait for aggregation
      Process.sleep(1200)
      
      aggregated = MetricsCollector.get_aggregated_metrics("aggregation.histogram", minutes: 1)
      
      assert length(aggregated) >= 1
      
      window_data = List.first(aggregated)
      assert window_data.type == :histogram
      assert window_data.count == 6  # Total values: 100,200,150,180,90,220
      assert window_data.min == 90
      assert window_data.max == 220
      assert window_data.p50 > 0
      assert window_data.p95 > 0
      assert window_data.p99 > 0
    end
  end
  
  describe "metric subscriptions" do
    test "subscribes to metric patterns" do
      assert :ok = MetricsCollector.subscribe_to_metrics("provider.*")
      
      # Record a matching metric
      assert :ok = MetricsCollector.record(:counter, "provider.requests", 1)
      
      # Should receive metric update
      assert_receive {:metric, metric}
      assert metric.name == "provider.requests"
      assert metric.type == :counter
      assert metric.value == 1
    end
    
    test "filtered metric subscriptions" do
      filter_fn = fn metric -> metric.value > 100 end
      assert :ok = MetricsCollector.subscribe_to_metrics("filtered.*", filter_fn: filter_fn)
      
      # Should not receive this (value <= 100)
      assert :ok = MetricsCollector.record(:gauge, "filtered.metric", 50)
      refute_receive {:metric, _}, 100
      
      # Should receive this (value > 100)
      assert :ok = MetricsCollector.record(:gauge, "filtered.metric", 150)
      assert_receive {:metric, metric}
      assert metric.value == 150
    end
    
    test "unsubscribe from metrics" do
      assert :ok = MetricsCollector.subscribe_to_metrics("unsub.test")
      
      # Record metric - should receive
      assert :ok = MetricsCollector.record(:counter, "unsub.test", 1)
      assert_receive {:metric, _}
      
      # Unsubscribe
      assert :ok = MetricsCollector.unsubscribe_from_metrics("unsub.test")
      
      # Record metric - should not receive
      assert :ok = MetricsCollector.record(:counter, "unsub.test", 2)
      refute_receive {:metric, _}, 100
    end
  end
  
  describe "cluster summary and statistics" do
    test "generates cluster summary" do
      # Record some provider metrics
      assert :ok = MetricsCollector.record(:gauge, "provider.health_score", 0.95, %{provider: "openai"})
      assert :ok = MetricsCollector.record(:gauge, "provider.health_score", 0.88, %{provider: "anthropic"})
      assert :ok = MetricsCollector.record(:counter, "provider.requests", 100, %{provider: "openai"})
      
      summary = MetricsCollector.get_cluster_summary()
      
      assert is_map(summary)
      assert summary.total_metrics_collected > 0
      assert summary.active_providers >= 0
      assert is_number(summary.cluster_health_score)
      assert is_list(summary.top_metrics)
    end
    
    test "tracks collection statistics" do
      initial_stats = MetricsCollector.get_stats()
      
      # Record some metrics
      assert :ok = MetricsCollector.record(:counter, "stats.test", 1)
      assert :ok = MetricsCollector.record(:gauge, "stats.test2", 0.5)
      
      updated_stats = MetricsCollector.get_stats()
      
      assert updated_stats.total_metrics_collected > initial_stats.total_metrics_collected
      assert updated_stats.current_window_metrics > 0
      assert is_number(updated_stats.memory_usage_mb)
      assert updated_stats.active_windows >= 1
    end
  end
  
  describe "time-windowed aggregation" do
    test "maintains multiple aggregation windows" do
      # Record metrics across time
      assert :ok = MetricsCollector.record(:counter, "windowed.test", 1)
      
      # Wait for first window
      Process.sleep(1200)
      
      assert :ok = MetricsCollector.record(:counter, "windowed.test", 2)
      
      # Wait for second window
      Process.sleep(1200)
      
      # Should have data from multiple windows
      aggregated = MetricsCollector.get_aggregated_metrics("windowed.test", minutes: 5)
      
      # Should have at least one window of data
      assert length(aggregated) >= 1
      
      # Each window should have timing information
      window = List.first(aggregated)
      assert is_integer(window.window_start)
      assert is_integer(window.window_end)
      assert window.window_end > window.window_start
    end
    
    test "respects retention window limits" do
      # This test would need to run longer to verify retention,
      # but we can at least check the configuration is accepted
      {:ok, collector} = MetricsCollector.start_link(retention_windows: 3)
      
      stats = GenServer.call(collector, :get_stats)
      assert stats.active_windows >= 1
      
      GenServer.stop(collector)
    end
  end
  
  describe "event broadcasting integration" do
    test "broadcasts metric events" do
      # Subscribe to metric events via EventBroadcaster
      EventBroadcaster.subscribe("metrics.*")
      
      # Record a metric
      assert :ok = MetricsCollector.record(:counter, "broadcast.test", 1)
      
      # Should receive event broadcast
      assert_receive {:event, event}
      assert event.topic == "metrics.recorded"
      assert event.payload.name == "broadcast.test"
      assert event.payload.type == :counter
      assert event.payload.value == 1
    end
    
    test "broadcasts window completion events" do
      EventBroadcaster.subscribe("metrics.window_completed")
      
      # Record a metric and wait for window completion
      assert :ok = MetricsCollector.record(:counter, "window.test", 1)
      
      # Wait for window to complete
      Process.sleep(1200)
      
      # Should receive window completion event
      assert_receive {:event, event}
      assert event.topic == "metrics.window_completed"
      assert is_integer(event.payload.window_start)
      assert is_integer(event.payload.window_end)
      assert event.payload.metric_count >= 1
    end
    
    test "broadcasts batch recording events" do
      EventBroadcaster.subscribe("metrics.batch_recorded")
      
      metrics = [
        {:counter, "batch1", 1, %{}},
        {:gauge, "batch2", 0.5, %{}}
      ]
      
      assert :ok = MetricsCollector.record_batch(metrics)
      
      # Should receive batch event
      assert_receive {:event, event}
      assert event.topic == "metrics.batch_recorded"
      assert event.payload.count == 2
      assert event.payload.node == node()
    end
  end
  
  describe "pattern matching for metrics" do
    test "wildcard pattern matching" do
      assert :ok = MetricsCollector.subscribe_to_metrics("provider.*")
      
      # Should match
      assert :ok = MetricsCollector.record(:counter, "provider.requests", 1)
      assert_receive {:metric, %{name: "provider.requests"}}
      
      # Should match
      assert :ok = MetricsCollector.record(:gauge, "provider.health", 0.9)
      assert_receive {:metric, %{name: "provider.health"}}
      
      # Should not match
      assert :ok = MetricsCollector.record(:counter, "cluster.nodes", 3)
      refute_receive {:metric, %{name: "cluster.nodes"}}, 100
    end
    
    test "exact pattern matching" do
      assert :ok = MetricsCollector.subscribe_to_metrics("exact.metric.name")
      
      # Should match
      assert :ok = MetricsCollector.record(:counter, "exact.metric.name", 1)
      assert_receive {:metric, %{name: "exact.metric.name"}}
      
      # Should not match
      assert :ok = MetricsCollector.record(:counter, "exact.metric.other", 1)
      refute_receive {:metric, %{name: "exact.metric.other"}}, 100
    end
  end
end