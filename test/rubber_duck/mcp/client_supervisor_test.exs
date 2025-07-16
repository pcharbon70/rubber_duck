defmodule RubberDuck.MCP.ClientSupervisorTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.MCP.ClientSupervisor
  alias RubberDuck.MCP.Client
  
  @moduletag :mcp

  setup do
    # ClientSupervisor is started in application
    :ok
  end

  describe "start_client/1" do
    test "starts a client under supervision" do
      opts = [
        name: :supervised_client,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      assert {:ok, pid} = ClientSupervisor.start_client(opts)
      assert is_pid(pid)
      assert Process.alive?(pid)
      
      # Clean up
      Client.stop(:supervised_client)
    end

    test "restarts client on crash" do
      opts = [
        name: :crash_test_client,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      {:ok, original_pid} = ClientSupervisor.start_client(opts)
      
      # Force crash the client
      Process.exit(original_pid, :kill)
      
      # Give supervisor time to restart
      Process.sleep(100)
      
      # Client should be restarted with new PID
      assert {:ok, new_pid} = RubberDuck.MCP.Client.Registry.lookup(:crash_test_client)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
      
      # Clean up
      Client.stop(:crash_test_client)
    end

    test "respects max restart limit" do
      opts = [
        name: :restart_limit_client,
        transport: {:stdio, command: "false", args: []},  # Will always fail
        capabilities: [:tools],
        auto_reconnect: false
      ]
      
      {:ok, _pid} = ClientSupervisor.start_client(opts)
      
      # Wait for it to exceed restart limit
      Process.sleep(1000)
      
      # Should no longer be registered after exceeding restarts
      assert {:error, :not_found} = RubberDuck.MCP.Client.Registry.lookup(:restart_limit_client)
    end
  end

  describe "stop_client/1" do
    test "stops a supervised client" do
      opts = [
        name: :stop_test_client,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      {:ok, pid} = ClientSupervisor.start_client(opts)
      assert Process.alive?(pid)
      
      assert :ok = ClientSupervisor.stop_client(:stop_test_client)
      refute Process.alive?(pid)
    end

    test "returns error for non-existent client" do
      assert {:error, :not_found} = ClientSupervisor.stop_client(:non_existent_client)
    end
  end

  describe "list_clients/0" do
    test "lists all supervised clients" do
      # Start some test clients
      opts1 = [
        name: :list_test_client1,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      opts2 = [
        name: :list_test_client2,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      {:ok, pid1} = ClientSupervisor.start_client(opts1)
      {:ok, pid2} = ClientSupervisor.start_client(opts2)
      
      clients = ClientSupervisor.list_clients()
      assert pid1 in clients
      assert pid2 in clients
      
      # Clean up
      Client.stop(:list_test_client1)
      Client.stop(:list_test_client2)
    end
  end

  describe "count_clients/0" do
    test "returns count of active clients" do
      initial_count = ClientSupervisor.count_clients()
      
      opts = [
        name: :count_test_client,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      {:ok, _pid} = ClientSupervisor.start_client(opts)
      
      new_count = ClientSupervisor.count_clients()
      assert new_count.active == initial_count.active + 1
      
      # Clean up
      Client.stop(:count_test_client)
    end
  end

  describe "supervision strategies" do
    test "isolates client failures" do
      # Start two clients
      opts1 = [
        name: :isolation_client1,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      opts2 = [
        name: :isolation_client2,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      {:ok, pid1} = ClientSupervisor.start_client(opts1)
      {:ok, pid2} = ClientSupervisor.start_client(opts2)
      
      # Crash one client
      Process.exit(pid1, :kill)
      
      # Other client should still be alive
      assert Process.alive?(pid2)
      
      # Clean up
      Client.stop(:isolation_client2)
    end
  end
end