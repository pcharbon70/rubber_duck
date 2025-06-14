defmodule RubberDuck.ClusterIntegrationTest do
  use ExUnit.Case, async: false

  alias RubberDuck.{ClusterSupervisor, NodeMonitor}

  setup do
    # Ensure application is started for integration tests
    {:ok, _} = Application.ensure_all_started(:rubber_duck)
    on_exit(fn -> Application.stop(:rubber_duck) end)
    :ok
  end

  describe "cluster infrastructure integration" do
    test "ClusterSupervisor and NodeMonitor are supervised together" do
      # Both should be running as part of the application
      cluster_pid = Process.whereis(ClusterSupervisor)
      monitor_pid = Process.whereis(NodeMonitor)
      
      assert cluster_pid != nil
      assert monitor_pid != nil
      assert Process.alive?(cluster_pid)
      assert Process.alive?(monitor_pid)
    end

    test "NodeMonitor can communicate with cluster processes" do
      status = NodeMonitor.get_cluster_status()
      
      # Should have basic cluster information
      assert status.current_node == node()
      assert is_list(status.connected_nodes)
      assert status.total_nodes >= 1  # At least current node
    end

    test "cluster processes restart independently" do
      cluster_pid = Process.whereis(ClusterSupervisor)
      monitor_pid = Process.whereis(NodeMonitor)
      
      # Kill NodeMonitor
      Process.exit(monitor_pid, :kill)
      
      # Give supervisor time to restart
      Process.sleep(200)
      
      # NodeMonitor should be restarted, ClusterSupervisor should still be running
      new_monitor_pid = Process.whereis(NodeMonitor)
      current_cluster_pid = Process.whereis(ClusterSupervisor)
      
      assert new_monitor_pid != nil
      assert new_monitor_pid != monitor_pid
      assert current_cluster_pid == cluster_pid
      assert Process.alive?(new_monitor_pid)
      assert Process.alive?(current_cluster_pid)
    end

    test "cluster configuration is applied correctly" do
      # Should be able to get cluster status without errors
      status = NodeMonitor.get_cluster_status()
      assert status.cluster_health in [:healthy, :degraded, :unhealthy]
      
      # Should be able to get node list
      {:ok, nodes} = NodeMonitor.get_nodes()
      assert node() in nodes
    end
  end

  describe "cluster event propagation" do
    test "NodeMonitor receives cluster events" do
      # Subscribe to events
      :ok = NodeMonitor.subscribe_to_events(NodeMonitor, self())
      
      # In a real multi-node setup, we would test actual node connections
      # For now, verify the subscription mechanism works
      :ok = NodeMonitor.unsubscribe_from_events(NodeMonitor, self())
    end

    test "cluster health monitoring works" do
      initial_status = NodeMonitor.get_cluster_status()
      
      # Health should be determinable
      assert initial_status.cluster_health in [:healthy, :degraded, :unhealthy]
      
      # Should have consistent node counts
      assert initial_status.total_nodes == length([node() | initial_status.connected_nodes])
    end
  end

  describe "configuration and startup" do
    test "cluster infrastructure starts with application" do
      # Stop and restart application to test startup
      Application.stop(:rubber_duck)
      
      # Start should succeed
      assert :ok = Application.start(:rubber_duck)
      
      # Give time for startup
      Process.sleep(100)
      
      # Both components should be running
      assert Process.whereis(ClusterSupervisor) != nil
      assert Process.whereis(NodeMonitor) != nil
      
      # Should be functional
      status = NodeMonitor.get_cluster_status()
      assert status.current_node == node()
    end

    test "cluster processes are properly supervised" do
      # Get supervision tree info
      rubber_duck_supervisor = Process.whereis(RubberDuck.Supervisor)
      children = Supervisor.which_children(rubber_duck_supervisor)
      
      # Should include cluster supervisor
      cluster_supervisor_child = Enum.find(children, fn {id, _pid, _type, _modules} ->
        id == ClusterSupervisor
      end)
      
      assert cluster_supervisor_child != nil
    end
  end

  describe "inter-node communication basics" do
    test "can send messages to local node" do
      # Test basic messaging capability (to self for now)
      test_message = {:test_cluster_message, :hello, node()}
      
      # Send to NodeMonitor process (it will ignore unknown messages)
      send(Process.whereis(NodeMonitor), test_message)
      
      # Give it time to process
      Process.sleep(50)
      
      # NodeMonitor should still be functional after receiving message
      status = NodeMonitor.get_cluster_status()
      assert status.current_node == node()
    end

    test "node information is accessible" do
      {:ok, nodes} = NodeMonitor.get_nodes()
      
      # Should at least include current node
      assert node() in nodes
      
      # Should be able to get detailed status
      status = NodeMonitor.get_cluster_status()
      assert is_map(status)
      assert Map.has_key?(status, :current_node)
      assert Map.has_key?(status, :connected_nodes)
      assert Map.has_key?(status, :cluster_health)
    end
  end
end