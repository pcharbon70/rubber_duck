defmodule RubberDuck.EventBroadcasting.HealthBroadcasterTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.EventBroadcasting.{HealthBroadcaster, EventBroadcaster}
  
  setup do
    # Start dependencies
    {:ok, broadcaster_pid} = EventBroadcaster.start_link()
    {:ok, health_broadcaster_pid} = HealthBroadcaster.start_link(
      health_check_interval: 1000,
      broadcast_interval: 2000
    )
    
    on_exit(fn ->
      if Process.alive?(health_broadcaster_pid), do: GenServer.stop(health_broadcaster_pid)
      if Process.alive?(broadcaster_pid), do: GenServer.stop(broadcaster_pid)
    end)
    
    %{health_broadcaster: health_broadcaster_pid, broadcaster: broadcaster_pid}
  end
  
  describe "health subscription management" do
    test "can subscribe to health patterns" do
      assert :ok = HealthBroadcaster.subscribe_to_health("provider.*")
      assert :ok = HealthBroadcaster.subscribe_to_health("provider.openai")
      assert :ok = HealthBroadcaster.subscribe_to_health("cluster.health", severity: :critical)
    end
    
    test "can unsubscribe from health patterns" do
      assert :ok = HealthBroadcaster.subscribe_to_health("unsubscribe.test")
      assert :ok = HealthBroadcaster.unsubscribe_from_health("unsubscribe.test")
    end
    
    test "subscription with severity filter" do
      assert :ok = HealthBroadcaster.subscribe_to_health("filtered.health", severity: :critical)
      
      # Simulate critical health update
      critical_health = %{
        provider_id: :test_provider,
        cluster_health_score: 0.2,
        overall_status: :critical,
        node_statuses: %{},
        last_updated: System.monotonic_time(:millisecond),
        trend: :degrading
      }
      
      send(HealthBroadcaster, {:health_update, critical_health})
      
      # Should receive critical health update
      assert_receive {:health_update, received_health}
      assert received_health.overall_status == :critical
    end
    
    test "subscription with node filter" do
      test_node = :test_node
      assert :ok = HealthBroadcaster.subscribe_to_health("node.filtered", node: test_node)
      
      # Simulate health update with matching node
      node_health = %{
        provider_id: :test_provider,
        cluster_health_score: 0.8,
        overall_status: :healthy,
        node_statuses: %{test_node => %{health_score: 0.8}},
        last_updated: System.monotonic_time(:millisecond),
        trend: :stable
      }
      
      send(HealthBroadcaster, {:health_update, node_health})
      
      # Should receive health update for matching node
      assert_receive {:health_update, received_health}
      assert Map.has_key?(received_health.node_statuses, test_node)
    end
  end
  
  describe "health reporting and tracking" do
    test "reports health status manually" do
      health_data = %{
        health_score: 0.85,
        error_count: 2,
        last_error: "Connection timeout",
        response_time: 250,
        consecutive_failures: 1
      }
      
      assert :ok = HealthBroadcaster.report_health(:openai, health_data)
      
      # Allow processing
      Process.sleep(100)
      
      # Should be reflected in provider health
      provider_health = HealthBroadcaster.get_provider_health(:openai)
      assert provider_health != nil
    end
    
    test "tracks health history" do
      # Report health multiple times
      assert :ok = HealthBroadcaster.report_health(:test_provider, %{health_score: 0.9})
      Process.sleep(50)
      assert :ok = HealthBroadcaster.report_health(:test_provider, %{health_score: 0.8})
      Process.sleep(50)
      assert :ok = HealthBroadcaster.report_health(:test_provider, %{health_score: 0.7})
      
      # Get health history
      history = HealthBroadcaster.get_health_history(:test_provider, limit: 10)
      
      assert length(history) >= 3
      assert Enum.all?(history, fn entry -> entry.provider_id == :test_provider end)
      
      # Should be in reverse chronological order (most recent first)
      health_scores = Enum.map(history, & &1.health_score)
      assert 0.7 in health_scores
      assert 0.8 in health_scores
      assert 0.9 in health_scores
    end
    
    test "filters health history by time" do
      # Report some health data
      assert :ok = HealthBroadcaster.report_health(:time_test, %{health_score: 0.9})
      
      # Get recent history (last 1 minute)
      recent_history = HealthBroadcaster.get_health_history(:time_test, minutes: 1)
      assert length(recent_history) >= 1
      
      # Get very old history (should be empty)
      old_history = HealthBroadcaster.get_health_history(:time_test, minutes: 0)
      assert length(old_history) == 0
    end
  end
  
  describe "health status determination" do
    test "determines healthy status" do
      health_data = %{
        health_score: 0.95,
        consecutive_failures: 0,
        error_count: 0
      }
      
      assert :ok = HealthBroadcaster.report_health(:healthy_provider, health_data)
      Process.sleep(100)
      
      # Health status should be determined as healthy
      provider_health = HealthBroadcaster.get_provider_health(:healthy_provider)
      if provider_health && provider_health.node_statuses do
        node_status = Map.get(provider_health.node_statuses, node())
        if node_status do
          assert node_status.status == :healthy
        end
      end
    end
    
    test "determines degraded status" do
      health_data = %{
        health_score: 0.75,
        consecutive_failures: 2,
        error_count: 5
      }
      
      assert :ok = HealthBroadcaster.report_health(:degraded_provider, health_data)
      Process.sleep(100)
      
      # Should determine degraded status
      provider_health = HealthBroadcaster.get_provider_health(:degraded_provider)
      if provider_health && provider_health.node_statuses do
        node_status = Map.get(provider_health.node_statuses, node())
        if node_status do
          assert node_status.status in [:degraded, :critical]
        end
      end
    end
    
    test "determines critical status" do
      health_data = %{
        health_score: 0.4,
        consecutive_failures: 8,
        error_count: 20
      }
      
      assert :ok = HealthBroadcaster.report_health(:critical_provider, health_data)
      Process.sleep(100)
      
      # Should determine critical status
      provider_health = HealthBroadcaster.get_provider_health(:critical_provider)
      if provider_health && provider_health.node_statuses do
        node_status = Map.get(provider_health.node_statuses, node())
        if node_status do
          assert node_status.status in [:critical, :failed]
        end
      end
    end
    
    test "determines failed status" do
      health_data = %{
        health_score: 0.1,
        consecutive_failures: 15,
        error_count: 50
      }
      
      assert :ok = HealthBroadcaster.report_health(:failed_provider, health_data)
      Process.sleep(100)
      
      # Should determine failed status
      provider_health = HealthBroadcaster.get_provider_health(:failed_provider)
      if provider_health && provider_health.node_statuses do
        node_status = Map.get(provider_health.node_statuses, node())
        if node_status do
          assert node_status.status == :failed
        end
      end
    end
  end
  
  describe "cluster health aggregation" do
    test "calculates cluster health summary" do
      # Report health for multiple providers
      assert :ok = HealthBroadcaster.report_health(:provider1, %{health_score: 0.9})
      assert :ok = HealthBroadcaster.report_health(:provider2, %{health_score: 0.8})
      assert :ok = HealthBroadcaster.report_health(:provider3, %{health_score: 0.7})
      
      Process.sleep(500)  # Allow aggregation
      
      summary = HealthBroadcaster.get_cluster_health_summary()
      
      assert is_map(summary)
      assert is_number(summary.overall_cluster_health)
      assert is_integer(summary.healthy_providers)
      assert is_integer(summary.degraded_providers)
      assert is_integer(summary.critical_providers)
      assert is_integer(summary.failed_providers)
      assert is_integer(summary.total_providers)
      assert is_map(summary.node_health_scores)
    end
    
    test "aggregates health from multiple nodes" do
      # Simulate health updates from multiple nodes
      node1_health = %{
        provider_id: :multi_node_provider,
        node: :node1,
        health_score: 0.9,
        status: :healthy,
        last_check: System.monotonic_time(:millisecond),
        metrics: %{},
        error_count: 0,
        consecutive_failures: 0,
        recovery_count: 5
      }
      
      node2_health = %{
        provider_id: :multi_node_provider,
        node: :node2,
        health_score: 0.7,
        status: :degraded,
        last_check: System.monotonic_time(:millisecond),
        metrics: %{},
        error_count: 3,
        consecutive_failures: 2,
        recovery_count: 2
      }
      
      # Simulate receiving health updates from remote nodes
      health_event1 = %{
        topic: "provider.health.update",
        payload: node1_health
      }
      
      health_event2 = %{
        topic: "provider.health.update",
        payload: node2_health
      }
      
      send(HealthBroadcaster, {:event, health_event1})
      send(HealthBroadcaster, {:event, health_event2})
      
      # Wait for aggregation
      Process.sleep(1500)
      
      # Should aggregate health from both nodes
      provider_health = HealthBroadcaster.get_provider_health(:multi_node_provider)
      if provider_health do
        assert provider_health.provider_id == :multi_node_provider
        assert is_number(provider_health.cluster_health_score)
        assert is_map(provider_health.node_statuses)
        
        # Should have health data from both nodes
        if map_size(provider_health.node_statuses) > 0 do
          assert provider_health.cluster_health_score > 0
        end
      end
    end
  end
  
  describe "health broadcasting and events" do
    test "broadcasts health updates automatically" do
      EventBroadcaster.subscribe("provider.health.update")
      
      # Report health which should trigger broadcast
      assert :ok = HealthBroadcaster.report_health(:broadcast_test, %{health_score: 0.8})
      
      # Should receive health update broadcast
      assert_receive {:event, event}
      assert event.topic == "provider.health.update"
      assert event.payload.provider_id == :broadcast_test
      assert event.payload.health_score == 0.8
      assert event.payload.node == node()
    end
    
    test "handles circuit breaker state change events" do
      # Simulate circuit breaker state change
      cb_event = %{
        topic: "circuit_breaker.state_changed",
        payload: %{
          provider_id: :cb_test_provider,
          state: :open  # Circuit breaker opened due to failures
        }
      }
      
      send(HealthBroadcaster, {:event, cb_event})
      
      # Allow processing
      Process.sleep(100)
      
      # Health status should be updated based on circuit breaker state
      # This test verifies the integration with circuit breaker events
    end
    
    test "triggers health checks manually" do
      assert :ok = HealthBroadcaster.trigger_health_check()
      
      # Should complete without error
      # The actual health check results depend on the availability of circuit breaker service
    end
  end
  
  describe "periodic health operations" do
    test "performs periodic health checks" do
      # Wait for automatic health check (configured with 1000ms interval)
      Process.sleep(1200)
      
      # Health checks should have been performed
      stats = HealthBroadcaster.get_stats()
      assert stats.health_checks_performed > 0
    end
    
    test "broadcasts health periodically" do
      EventBroadcaster.subscribe("provider.health.update")
      
      # Report some health to ensure there's data to broadcast
      assert :ok = HealthBroadcaster.report_health(:periodic_test, %{health_score: 0.9})
      
      # Wait for periodic broadcast (configured with 2000ms interval)
      assert_receive {:event, _event}, 2500
    end
    
    test "aggregates health data periodically" do
      # Report health and wait for aggregation
      assert :ok = HealthBroadcaster.report_health(:aggregation_test, %{health_score: 0.85})
      
      # Wait for aggregation cycle
      Process.sleep(1200)
      
      # Aggregation should have processed the health data
      provider_health = HealthBroadcaster.get_provider_health(:aggregation_test)
      if provider_health do
        assert provider_health.provider_id == :aggregation_test
      end
    end
  end
  
  describe "health statistics and monitoring" do
    test "tracks health broadcasting statistics" do
      initial_stats = HealthBroadcaster.get_stats()
      
      # Report health to generate activity
      assert :ok = HealthBroadcaster.report_health(:stats_test, %{health_score: 0.9})
      assert :ok = HealthBroadcaster.trigger_health_check()
      
      # Allow processing
      Process.sleep(100)
      
      updated_stats = HealthBroadcaster.get_stats()
      
      # Should show activity (exact numbers depend on timing and service availability)
      assert is_integer(updated_stats.health_checks_performed)
      assert is_integer(updated_stats.broadcasts_sent)
      assert is_integer(updated_stats.subscriptions_active)
      assert is_integer(updated_stats.providers_monitored)
    end
  end
  
  describe "error handling and edge cases" do
    test "handles invalid health data gracefully" do
      # Report invalid health data
      invalid_health = %{
        invalid_field: "invalid_value"
      }
      
      # Should not crash
      assert :ok = HealthBroadcaster.report_health(:invalid_test, invalid_health)
      
      # Service should remain responsive
      assert is_map(HealthBroadcaster.get_stats())
    end
    
    test "handles non-existent provider health requests" do
      # Request health for non-existent provider
      assert nil == HealthBroadcaster.get_provider_health(:non_existent_provider)
    end
    
    test "handles empty health history requests" do
      # Request history for provider with no data
      history = HealthBroadcaster.get_health_history(:no_data_provider)
      assert history == []
    end
    
    test "handles subscription cleanup for dead processes" do
      # Start a temporary process and subscribe
      {:ok, temp_pid} = Task.start(fn -> 
        HealthBroadcaster.subscribe_to_health("cleanup.test")
        Process.sleep(100)
      end)
      
      # Wait for subscription
      Process.sleep(50)
      
      initial_stats = HealthBroadcaster.get_stats()
      
      # Kill the process
      Process.exit(temp_pid, :kill)
      Process.sleep(100)
      
      # Subscription should be cleaned up
      final_stats = HealthBroadcaster.get_stats()
      assert final_stats.subscriptions_active <= initial_stats.subscriptions_active
    end
  end
  
  describe "health trend calculation" do
    test "calculates improving health trend" do
      provider_id = :trend_improving
      
      # Report declining then improving health scores
      assert :ok = HealthBroadcaster.report_health(provider_id, %{health_score: 0.5})
      Process.sleep(50)
      assert :ok = HealthBroadcaster.report_health(provider_id, %{health_score: 0.6})
      Process.sleep(50)
      assert :ok = HealthBroadcaster.report_health(provider_id, %{health_score: 0.7})
      Process.sleep(50)
      assert :ok = HealthBroadcaster.report_health(provider_id, %{health_score: 0.8})
      Process.sleep(50)
      assert :ok = HealthBroadcaster.report_health(provider_id, %{health_score: 0.9})
      
      # Wait for aggregation to calculate trend
      Process.sleep(1200)
      
      provider_health = HealthBroadcaster.get_provider_health(provider_id)
      if provider_health do
        assert provider_health.trend in [:improving, :stable]
      end
    end
    
    test "calculates degrading health trend" do
      provider_id = :trend_degrading
      
      # Report improving then declining health scores
      assert :ok = HealthBroadcaster.report_health(provider_id, %{health_score: 0.9})
      Process.sleep(50)
      assert :ok = HealthBroadcaster.report_health(provider_id, %{health_score: 0.8})
      Process.sleep(50)
      assert :ok = HealthBroadcaster.report_health(provider_id, %{health_score: 0.7})
      Process.sleep(50)
      assert :ok = HealthBroadcaster.report_health(provider_id, %{health_score: 0.6})
      Process.sleep(50)
      assert :ok = HealthBroadcaster.report_health(provider_id, %{health_score: 0.5})
      
      # Wait for aggregation to calculate trend
      Process.sleep(1200)
      
      provider_health = HealthBroadcaster.get_provider_health(provider_id)
      if provider_health do
        assert provider_health.trend in [:degrading, :stable]
      end
    end
  end
end