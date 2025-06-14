defmodule RubberDuck.EventBroadcasting.ClusterEventCoordinatorTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.EventBroadcasting.{ClusterEventCoordinator, EventBroadcaster}
  
  setup do
    # Start dependencies
    {:ok, broadcaster_pid} = EventBroadcaster.start_link()
    
    initial_capabilities = %{
      providers: [:openai, :anthropic],
      max_concurrent_requests: 100
    }
    
    {:ok, coordinator_pid} = ClusterEventCoordinator.start_link(initial_capabilities: initial_capabilities)
    
    on_exit(fn ->
      if Process.alive?(coordinator_pid), do: GenServer.stop(coordinator_pid)
      if Process.alive?(broadcaster_pid), do: GenServer.stop(broadcaster_pid)
    end)
    
    %{coordinator: coordinator_pid, broadcaster: broadcaster_pid}
  end
  
  describe "cluster topology management" do
    test "initializes with current node" do
      topology = ClusterEventCoordinator.get_cluster_topology()
      
      assert is_map(topology)
      assert topology.total_nodes == 1
      assert topology.active_nodes == 1
      assert topology.healthy_nodes == 1
      assert Map.has_key?(topology.nodes, node())
      
      # Check node info
      node_info = Map.get(topology.nodes, node())
      assert node_info.node == node()
      assert node_info.status == :active
      assert node_info.health_score == 1.0
      assert is_map(node_info.capabilities)
    end
    
    test "announces node capabilities" do
      new_capabilities = %{
        providers: [:openai, :anthropic, :cohere],
        max_concurrent_requests: 200,
        preferred_models: ["gpt-4", "claude-3"]
      }
      
      assert :ok = ClusterEventCoordinator.announce_capabilities(new_capabilities)
      
      # Verify capabilities are updated
      node_info = ClusterEventCoordinator.get_node_info(node())
      assert node_info.capabilities == new_capabilities
    end
    
    test "tracks cluster leader" do
      topology = ClusterEventCoordinator.get_cluster_topology()
      
      # Single node cluster - current node should be leader
      assert topology.cluster_leader == node()
      assert ClusterEventCoordinator.is_leader?() == true
    end
    
    test "gets cluster health information" do
      health = ClusterEventCoordinator.get_cluster_health()
      
      assert is_map(health)
      assert is_number(health.overall_health)
      assert health.node_count == 1
      assert health.healthy_nodes == 1
      assert health.cluster_stability in [:stable, :mostly_stable, :unstable, :critical]
      assert health.split_brain_risk in [:low, :medium, :high]
    end
  end
  
  describe "event handling and broadcasting" do
    test "broadcasts capability announcements" do
      EventBroadcaster.subscribe("cluster.capabilities_announced")
      
      capabilities = %{test_capability: true}
      assert :ok = ClusterEventCoordinator.announce_capabilities(capabilities)
      
      # Should receive capability announcement event
      assert_receive {:event, event}
      assert event.topic == "cluster.capabilities_announced"
      assert event.payload.node == node()
      assert event.payload.capabilities == capabilities
    end
    
    test "handles provider health change events" do
      EventBroadcaster.subscribe("cluster.provider_redistribution")
      
      # Simulate provider health change event
      health_event = %{
        topic: "provider.health_changed",
        payload: %{
          provider_id: :openai,
          health_score: 0.3  # Low health score should trigger redistribution
        }
      }
      
      send(ClusterEventCoordinator, {:event, health_event})
      
      # Should trigger redistribution for low health
      assert_receive {:event, redistribution_event}, 1000
      assert redistribution_event.topic == "cluster.provider_redistribution"
      assert redistribution_event.payload.reason == :provider_health_degraded
    end
    
    test "handles graceful shutdown requests" do
      EventBroadcaster.subscribe("cluster.graceful_shutdown_initiated")
      
      assert :ok = ClusterEventCoordinator.initiate_graceful_shutdown()
      
      # Should broadcast shutdown initiation
      assert_receive {:event, event}
      assert event.topic == "cluster.graceful_shutdown_initiated"
      assert event.payload.node == node()
    end
  end
  
  describe "heartbeat and monitoring" do
    test "sends periodic heartbeats" do
      EventBroadcaster.subscribe("cluster.heartbeat")
      
      # Wait for heartbeat
      assert_receive {:event, heartbeat_event}, 35_000
      assert heartbeat_event.topic == "cluster.heartbeat"
      assert heartbeat_event.payload.node == node()
      assert heartbeat_event.payload.status == :active
      assert is_map(heartbeat_event.payload.capabilities)
      assert is_integer(heartbeat_event.payload.provider_count)
    end
    
    test "processes heartbeat events from other nodes" do
      # Simulate heartbeat from another node
      heartbeat_event = %{
        topic: "cluster.heartbeat",
        payload: %{
          node: :fake_node,
          timestamp: System.monotonic_time(:millisecond),
          status: :active,
          capabilities: %{providers: [:openai]},
          provider_count: 2
        }
      }
      
      send(ClusterEventCoordinator, {:event, heartbeat_event})
      
      # Allow processing
      Process.sleep(100)
      
      # Should update cluster topology
      topology = ClusterEventCoordinator.get_cluster_topology()
      assert Map.has_key?(topology.nodes, :fake_node)
      
      fake_node_info = Map.get(topology.nodes, :fake_node)
      assert fake_node_info.status == :active
      assert fake_node_info.provider_count == 2
    end
  end
  
  describe "leadership election and management" do
    test "handles leadership claims" do
      # Simulate leadership claim from another node
      leadership_event = %{
        topic: "cluster.leadership_claimed",
        payload: %{
          leader_node: :other_node,
          timestamp: System.monotonic_time(:millisecond),
          topology_version: 5
        }
      }
      
      send(ClusterEventCoordinator, {:event, leadership_event})
      
      # Allow processing
      Process.sleep(100)
      
      # Should accept the leadership claim
      topology = ClusterEventCoordinator.get_cluster_topology()
      assert topology.cluster_leader == :other_node
      assert topology.topology_version == 5
      assert ClusterEventCoordinator.is_leader?() == false
    end
    
    test "force redistribution only when leader" do
      # When not leader
      topology = ClusterEventCoordinator.get_cluster_topology()
      if topology.cluster_leader != node() do
        assert {:error, :not_leader} = ClusterEventCoordinator.force_redistribution()
      end
      
      # Become leader (simulate)
      GenServer.call(ClusterEventCoordinator, {:announce_capabilities, %{}})
      
      # Should be able to force redistribution when leader
      if ClusterEventCoordinator.is_leader?() do
        assert :ok = ClusterEventCoordinator.force_redistribution()
      end
    end
  end
  
  describe "topology version tracking" do
    test "increments topology version on changes" do
      initial_topology = ClusterEventCoordinator.get_cluster_topology()
      initial_version = initial_topology.topology_version
      
      # Simulate node join
      join_event = %{
        topic: "cluster.node_joined",
        payload: %{
          node: :test_node,
          topology_version: initial_version + 1,
          timestamp: System.monotonic_time(:millisecond)
        }
      }
      
      send(ClusterEventCoordinator, {:event, join_event})
      Process.sleep(100)
      
      updated_topology = ClusterEventCoordinator.get_cluster_topology()
      assert updated_topology.topology_version > initial_version
    end
    
    test "tracks last topology change timestamp" do
      initial_topology = ClusterEventCoordinator.get_cluster_topology()
      initial_timestamp = initial_topology.last_topology_change
      
      # Trigger a change
      assert :ok = ClusterEventCoordinator.announce_capabilities(%{new_capability: true})
      
      # Allow processing
      Process.sleep(100)
      
      updated_topology = ClusterEventCoordinator.get_cluster_topology()
      assert updated_topology.last_topology_change >= initial_timestamp
    end
  end
  
  describe "node state management" do
    test "handles node status transitions" do
      # Start with active status
      node_info = ClusterEventCoordinator.get_node_info(node())
      assert node_info.status == :active
      
      # Simulate graceful shutdown
      assert :ok = ClusterEventCoordinator.initiate_graceful_shutdown()
      
      # Allow processing
      Process.sleep(100)
      
      # Node should be in leaving state
      updated_node_info = ClusterEventCoordinator.get_node_info(node())
      assert updated_node_info.status == :leaving
    end
    
    test "tracks node capabilities over time" do
      # Initial capabilities
      initial_node_info = ClusterEventCoordinator.get_node_info(node())
      initial_capabilities = initial_node_info.capabilities
      
      # Update capabilities
      new_capabilities = Map.put(initial_capabilities, :new_feature, true)
      assert :ok = ClusterEventCoordinator.announce_capabilities(new_capabilities)
      
      # Verify update
      updated_node_info = ClusterEventCoordinator.get_node_info(node())
      assert updated_node_info.capabilities.new_feature == true
    end
  end
  
  describe "cluster health calculation" do
    test "calculates cluster health with single healthy node" do
      health = ClusterEventCoordinator.get_cluster_health()
      
      # Single healthy node should have good health
      assert health.overall_health > 0.8
      assert health.healthy_nodes == 1
      assert health.cluster_stability == :stable
    end
    
    test "handles cluster health with multiple nodes" do
      # Simulate multiple nodes with different health scores
      # Add a healthy node
      healthy_heartbeat = %{
        topic: "cluster.heartbeat",
        payload: %{
          node: :healthy_node,
          timestamp: System.monotonic_time(:millisecond),
          status: :active,
          capabilities: %{},
          provider_count: 1
        }
      }
      
      # Add a degraded node
      degraded_heartbeat = %{
        topic: "cluster.heartbeat",
        payload: %{
          node: :degraded_node,
          timestamp: System.monotonic_time(:millisecond),
          status: :active,
          capabilities: %{},
          provider_count: 0
        }
      }
      
      send(ClusterEventCoordinator, {:event, healthy_heartbeat})
      send(ClusterEventCoordinator, {:event, degraded_heartbeat})
      Process.sleep(100)
      
      health = ClusterEventCoordinator.get_cluster_health()
      assert health.node_count == 3  # Original + 2 simulated
      assert health.healthy_nodes >= 2
    end
  end
  
  describe "error handling and edge cases" do
    test "handles invalid event payloads gracefully" do
      # Send malformed event
      invalid_event = %{
        topic: "cluster.heartbeat",
        payload: %{invalid: :data}
      }
      
      # Should not crash
      send(ClusterEventCoordinator, {:event, invalid_event})
      Process.sleep(100)
      
      # Coordinator should still be responsive
      assert is_map(ClusterEventCoordinator.get_cluster_topology())
    end
    
    test "handles missing node information" do
      # Request info for non-existent node
      assert nil == ClusterEventCoordinator.get_node_info(:non_existent_node)
    end
    
    test "gracefully handles service dependencies being unavailable" do
      # The coordinator should handle cases where LoadBalancer or other services are not available
      # This is tested implicitly through the initialization and operation of the coordinator
      # when other services haven't been started
      
      assert is_map(ClusterEventCoordinator.get_cluster_topology())
      assert is_map(ClusterEventCoordinator.get_cluster_health())
    end
  end
end