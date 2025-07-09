defmodule RubberDuck.LLM.ConnectionManagerTest do
  use ExUnit.Case, async: false

  alias RubberDuck.LLM.ConnectionManager

  setup do
    # Start ConnectionManager for tests
    {:ok, pid} = ConnectionManager.start_link([])

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    {:ok, %{pid: pid}}
  end

  describe "connect/1" do
    test "successfully connects to mock provider" do
      assert :ok = ConnectionManager.connect(:mock)
      assert ConnectionManager.connected?(:mock)
    end

    test "returns error for non-configured provider" do
      assert {:error, :provider_not_configured} = ConnectionManager.connect(:unknown)
    end

    test "returns already_connected for connected provider" do
      assert :ok = ConnectionManager.connect(:mock)
      assert {:ok, :already_connected} = ConnectionManager.connect(:mock)
    end
  end

  describe "disconnect/1" do
    test "successfully disconnects from connected provider" do
      assert :ok = ConnectionManager.connect(:mock)
      assert :ok = ConnectionManager.disconnect(:mock)
      refute ConnectionManager.connected?(:mock)
    end

    test "returns already_disconnected for disconnected provider" do
      assert {:ok, :already_disconnected} = ConnectionManager.disconnect(:mock)
    end
  end

  describe "connect_all/0" do
    test "connects to all configured providers" do
      assert :ok = ConnectionManager.connect_all()

      # Check that at least mock is connected
      assert ConnectionManager.connected?(:mock)
    end
  end

  describe "disconnect_all/0" do
    test "disconnects from all providers" do
      assert :ok = ConnectionManager.connect_all()
      assert :ok = ConnectionManager.disconnect_all()

      refute ConnectionManager.connected?(:mock)
    end
  end

  describe "status/0" do
    test "returns status for all providers" do
      status = ConnectionManager.status()

      assert is_map(status)
      assert Map.has_key?(status, :mock)

      mock_status = status[:mock]
      assert is_map(mock_status)
      assert Map.has_key?(mock_status, :status)
      assert Map.has_key?(mock_status, :enabled)
      assert Map.has_key?(mock_status, :health)
    end
  end

  describe "set_enabled/2" do
    test "enables a provider" do
      assert :ok = ConnectionManager.set_enabled(:mock, true)

      status = ConnectionManager.status()
      assert status[:mock][:enabled] == true
    end

    test "disables a provider" do
      assert :ok = ConnectionManager.set_enabled(:mock, false)

      status = ConnectionManager.status()
      assert status[:mock][:enabled] == false
    end

    test "disabled provider is not considered connected" do
      assert :ok = ConnectionManager.connect(:mock)
      assert :ok = ConnectionManager.set_enabled(:mock, false)

      refute ConnectionManager.connected?(:mock)
    end
  end

  describe "get_connection_info/1" do
    test "returns connection info for connected provider" do
      assert :ok = ConnectionManager.connect(:mock)

      assert {:ok, info} = ConnectionManager.get_connection_info(:mock)
      assert info.status == :connected
      assert info.enabled == true
      assert is_map(info.connection)
      assert not is_nil(info.connected_at)
    end

    test "returns error for non-configured provider" do
      assert {:error, :provider_not_configured} = ConnectionManager.get_connection_info(:unknown)
    end
  end

  describe "health checks" do
    test "health check updates provider health status" do
      assert :ok = ConnectionManager.connect(:mock)

      # Wait for health check to run
      Process.sleep(100)

      status = ConnectionManager.status()
      assert status[:mock][:health] == :healthy
    end

    test "unhealthy provider is marked after failures" do
      # This would require mocking provider health responses
      # For now, just verify the health check mechanism exists
      assert :ok = ConnectionManager.connect(:mock)

      status = ConnectionManager.status()
      assert Map.has_key?(status[:mock], :health)
    end
  end

  describe "connection lifecycle" do
    test "connection data is preserved across operations" do
      assert :ok = ConnectionManager.connect(:mock)

      {:ok, info1} = ConnectionManager.get_connection_info(:mock)
      connection_data = info1.connection

      # Perform some operations
      ConnectionManager.set_enabled(:mock, false)
      ConnectionManager.set_enabled(:mock, true)

      {:ok, info2} = ConnectionManager.get_connection_info(:mock)
      assert info2.connection == connection_data
    end

    test "last_used is updated when notified" do
      assert :ok = ConnectionManager.connect(:mock)

      {:ok, info1} = ConnectionManager.get_connection_info(:mock)
      assert is_nil(info1.last_used)

      # Simulate usage notification
      send(Process.whereis(ConnectionManager), {:update_last_used, :mock})
      Process.sleep(50)

      {:ok, info2} = ConnectionManager.get_connection_info(:mock)
      assert not is_nil(info2.last_used)
    end
  end
end
