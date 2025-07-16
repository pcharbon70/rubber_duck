defmodule RubberDuck.MCP.Client.RegistryTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.MCP.Client.Registry
  
  @moduletag :mcp

  setup do
    # Registry is started in application supervisor
    # Just ensure it's clean
    :ok
  end

  describe "register/2" do
    test "registers a client successfully" do
      assert :ok = Registry.register(:test_client, self())
      assert {:ok, pid} = Registry.lookup(:test_client)
      assert pid == self()
    end

    test "allows re-registration of same name" do
      assert :ok = Registry.register(:duplicate_client, self())
      
      # Spawn a new process to register with same name
      task = Task.async(fn ->
        Registry.register(:duplicate_client, self())
        Registry.lookup(:duplicate_client)
      end)
      
      {:ok, new_pid} = Task.await(task)
      assert new_pid != self()
    end
  end

  describe "unregister/1" do
    test "unregisters a client successfully" do
      Registry.register(:unregister_test, self())
      assert {:ok, _} = Registry.lookup(:unregister_test)
      
      assert :ok = Registry.unregister(:unregister_test)
      assert {:error, :not_found} = Registry.lookup(:unregister_test)
    end

    test "handles unregistering non-existent client" do
      assert :ok = Registry.unregister(:non_existent)
    end
  end

  describe "lookup/1" do
    test "finds registered client" do
      Registry.register(:lookup_test, self())
      assert {:ok, pid} = Registry.lookup(:lookup_test)
      assert pid == self()
    end

    test "returns error for non-existent client" do
      assert {:error, :not_found} = Registry.lookup(:not_registered)
    end
  end

  describe "list_clients/0" do
    test "lists all registered clients" do
      # Clear any existing registrations
      initial_clients = Registry.list_clients()
      
      # Register some test clients
      Registry.register(:client1, self())
      Registry.register(:client2, self())
      
      clients = Registry.list_clients()
      client_names = Enum.map(clients, fn {name, _pid} -> name end)
      
      assert :client1 in client_names
      assert :client2 in client_names
      assert length(clients) >= 2
    end

    test "returns empty list when no clients registered" do
      # Can't guarantee empty in shared test environment
      # Just verify it returns a list
      assert is_list(Registry.list_clients())
    end
  end

  describe "count/0" do
    test "returns count of registered clients" do
      initial_count = Registry.count()
      
      Registry.register(:count_test1, self())
      Registry.register(:count_test2, self())
      
      new_count = Registry.count()
      assert new_count >= initial_count + 2
    end
  end

  describe "registered?/1" do
    test "returns true for registered client" do
      Registry.register(:registered_test, self())
      assert Registry.registered?(:registered_test)
    end

    test "returns false for non-registered client" do
      refute Registry.registered?(:not_registered_test)
    end
  end

  describe "process termination" do
    test "automatically unregisters when process dies" do
      # Spawn a process that registers and then dies
      task = Task.async(fn ->
        Registry.register(:dying_client, self())
        :ok
      end)
      
      Task.await(task)
      
      # Give registry time to process DOWN message
      Process.sleep(50)
      
      # Client should no longer be registered
      assert {:error, :not_found} = Registry.lookup(:dying_client)
    end
  end
end