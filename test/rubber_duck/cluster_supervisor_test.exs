defmodule RubberDuck.ClusterSupervisorTest do
  use ExUnit.Case, async: false

  alias RubberDuck.ClusterSupervisor

  setup do
    # Stop the application to control supervisor lifecycle in tests
    Application.stop(:rubber_duck)
    on_exit(fn -> Application.start(:rubber_duck) end)
    :ok
  end

  describe "start_link/1" do
    test "starts the ClusterSupervisor" do
      assert {:ok, pid} = ClusterSupervisor.start_link([])
      assert Process.alive?(pid)
    end

    test "registers the process with its module name" do
      assert {:ok, _pid} = ClusterSupervisor.start_link([])
      assert Process.whereis(ClusterSupervisor) != nil
    end

    test "accepts configuration options" do
      config = [strategies: [{Cluster.Strategy.Gossip, []}]]
      assert {:ok, pid} = ClusterSupervisor.start_link(config)
      assert Process.alive?(pid)
    end
  end

  describe "supervision" do
    setup do
      {:ok, pid} = ClusterSupervisor.start_link([])
      %{pid: pid}
    end

    test "supervises libcluster", %{pid: pid} do
      children = Supervisor.which_children(pid)
      assert length(children) >= 1
      
      # Should have the Cluster.Supervisor child
      cluster_child = Enum.find(children, fn {id, _pid, _type, _modules} ->
        id == Cluster.Supervisor
      end)
      assert cluster_child != nil
    end

    test "restarts failed children", %{pid: pid} do
      children = Supervisor.which_children(pid)
      {_id, child_pid, _type, _modules} = hd(children)
      
      # Kill the child process
      Process.exit(child_pid, :kill)
      
      # Give supervisor time to restart
      Process.sleep(100)
      
      # Check that a new child is running
      new_children = Supervisor.which_children(pid)
      {_id, new_child_pid, _type, _modules} = hd(new_children)
      
      assert new_child_pid != child_pid
      assert Process.alive?(new_child_pid)
    end
  end

  describe "configuration" do
    test "supports gossip strategy configuration" do
      config = [
        strategies: [
          {Cluster.Strategy.Gossip, [
            port: 45892,
            if_addr: "0.0.0.0",
            multicast_addr: "230.1.1.251",
            broadcast_only: true
          ]}
        ]
      ]
      
      assert {:ok, pid} = ClusterSupervisor.start_link(config)
      assert Process.alive?(pid)
    end

    test "supports multiple strategies" do
      config = [
        strategies: [
          {Cluster.Strategy.Gossip, [port: 45892]},
          {Cluster.Strategy.Epmd, [hosts: [:node1@localhost, :node2@localhost]]}
        ]
      ]
      
      assert {:ok, pid} = ClusterSupervisor.start_link(config)
      assert Process.alive?(pid)
    end
  end

  describe "graceful shutdown" do
    test "handles normal shutdown gracefully" do
      {:ok, pid} = ClusterSupervisor.start_link([])
      
      # Shutdown should complete without error
      assert :ok = Supervisor.stop(pid, :normal)
      refute Process.alive?(pid)
    end
  end
end