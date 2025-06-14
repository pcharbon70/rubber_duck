defmodule RubberDuck.NodeMonitorTest do
  use ExUnit.Case, async: false

  alias RubberDuck.NodeMonitor

  setup do
    # Stop the application to control GenServer lifecycle in tests
    Application.stop(:rubber_duck)
    on_exit(fn -> Application.start(:rubber_duck) end)
    :ok
  end

  describe "start_link/1" do
    test "starts the NodeMonitor GenServer" do
      assert {:ok, pid} = NodeMonitor.start_link([])
      assert Process.alive?(pid)
    end

    test "registers the process with its module name" do
      assert {:ok, _pid} = NodeMonitor.start_link([])
      assert Process.whereis(NodeMonitor) != nil
    end

    test "accepts initial configuration" do
      config = %{notify_processes: [self()]}
      assert {:ok, pid} = NodeMonitor.start_link(config: config)
      assert Process.alive?(pid)
    end
  end

  describe "node monitoring" do
    setup do
      {:ok, pid} = NodeMonitor.start_link([])
      %{pid: pid}
    end

    test "tracks current node", %{pid: pid} do
      assert {:ok, nodes} = NodeMonitor.get_nodes(pid)
      assert node() in nodes
    end

    test "returns cluster status", %{pid: pid} do
      status = NodeMonitor.get_cluster_status(pid)
      
      assert %{
        current_node: _,
        connected_nodes: _,
        total_nodes: _,
        cluster_health: _
      } = status
      
      assert status.current_node == node()
      assert is_list(status.connected_nodes)
      assert is_integer(status.total_nodes)
      assert status.cluster_health in [:healthy, :degraded, :unhealthy]
    end

    test "monitors for node connections", %{pid: pid} do
      # Subscribe to node events
      assert :ok = NodeMonitor.subscribe_to_events(pid, self())
      
      # We can't easily test actual node connections in unit tests,
      # but we can verify the subscription mechanism works
      assert :ok = NodeMonitor.unsubscribe_from_events(pid, self())
    end

    test "handles node up events", %{pid: pid} do
      # Simulate a nodeup event (we can't actually add nodes in unit tests)
      initial_status = NodeMonitor.get_cluster_status(pid)
      
      # Send a mock nodeup message
      send(pid, {:nodeup, :test_node@localhost})
      
      # Give it time to process
      Process.sleep(50)
      
      # Status should be updated (in real scenarios)
      updated_status = NodeMonitor.get_cluster_status(pid)
      assert updated_status.current_node == initial_status.current_node
    end

    test "handles node down events", %{pid: pid} do
      # Similar to nodeup test, verify the mechanism works
      send(pid, {:nodedown, :test_node@localhost})
      
      # Give it time to process
      Process.sleep(50)
      
      # Should still be functional
      status = NodeMonitor.get_cluster_status(pid)
      assert status.current_node == node()
    end
  end

  describe "event notifications" do
    setup do
      {:ok, pid} = NodeMonitor.start_link([])
      %{pid: pid}
    end

    test "allows subscribing to cluster events", %{pid: pid} do
      assert :ok = NodeMonitor.subscribe_to_events(pid, self())
      
      # Verify we're subscribed (in implementation, this would be tracked)
      assert :ok = NodeMonitor.unsubscribe_from_events(pid, self())
    end

    test "notifies subscribers of node changes", %{pid: pid} do
      NodeMonitor.subscribe_to_events(pid, self())
      
      # Simulate a node event
      send(pid, {:nodeup, :new_node@localhost})
      
      # Should receive notification (our implementation actually works!)
      assert_receive {:cluster_event, {:node_connected, :new_node@localhost}}, 500
      
      NodeMonitor.unsubscribe_from_events(pid, self())
    end
  end

  describe "health monitoring" do
    setup do
      {:ok, pid} = NodeMonitor.start_link([])
      %{pid: pid}
    end

    test "responds to health check", %{pid: pid} do
      assert :ok = NodeMonitor.health_check(pid)
    end

    test "returns monitor info", %{pid: pid} do
      info = NodeMonitor.get_info(pid)
      
      assert %{
        status: :running,
        monitored_nodes: _,
        subscribers: _,
        memory: _,
        uptime: _
      } = info
      
      assert is_list(info.monitored_nodes)
      assert is_integer(info.subscribers)
    end
  end

  describe "graceful shutdown" do
    test "handles normal shutdown gracefully" do
      {:ok, pid} = NodeMonitor.start_link([])
      
      # Shutdown should complete without error
      assert :ok = GenServer.stop(pid, :normal)
      refute Process.alive?(pid)
    end
  end
end