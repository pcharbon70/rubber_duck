defmodule RubberDuck.StateSynchronizerTest do
  use ExUnit.Case, async: false

  alias RubberDuck.{StateSynchronizer, TransactionWrapper, MnesiaManager}

  setup do
    # Stop the application to control lifecycle in tests
    Application.stop(:rubber_duck)
    
    # Clean up any existing Mnesia schema
    :mnesia.delete_schema([node()])
    
    on_exit(fn -> 
      :mnesia.stop()
      :mnesia.delete_schema([node()])
      Application.start(:rubber_duck) 
    end)
    :ok
  end

  describe "start_link/1" do
    test "starts the StateSynchronizer GenServer" do
      {:ok, pid} = start_mnesia_and_synchronizer()
      assert Process.alive?(pid)
    end

    test "registers with pg groups" do
      {:ok, _pid} = start_mnesia_and_synchronizer()
      
      # Check if the process is in the global sync group
      members = :pg.get_members(:rubber_duck_sync, "state_sync:global")
      assert length(members) > 0
    end
  end

  describe "sync_transaction/2" do
    setup do
      {:ok, pid} = start_mnesia_and_synchronizer()
      %{pid: pid}
    end

    test "executes simple transaction successfully", %{pid: _pid} do
      transaction_fun = fn ->
        :ok
      end

      assert {:ok, :ok} = StateSynchronizer.sync_transaction(transaction_fun)
    end

    test "handles transaction failures with retry", %{pid: _pid} do
      call_count = Agent.start_link(fn -> 0 end)
      
      transaction_fun = fn ->
        count = Agent.get_and_update(call_count, &{&1, &1 + 1})
        if count < 2 do
          :mnesia.abort(:simulated_failure)
        else
          :success
        end
      end

      assert {:ok, :success} = StateSynchronizer.sync_transaction(transaction_fun, retry_count: 3)
    end
  end

  describe "broadcast_change/4" do
    setup do
      {:ok, pid} = start_mnesia_and_synchronizer()
      %{pid: pid}
    end

    test "broadcasts state changes to pg groups", %{pid: _pid} do
      # Subscribe to events
      :pg.join(:rubber_duck_sync, "state_change:sessions", self())
      
      # Broadcast a change
      record = %{session_id: "test", messages: []}
      StateSynchronizer.broadcast_change(:sessions, :create, record, %{test: true})
      
      # Should receive the broadcast
      assert_receive {"state_change:sessions", {:state_change, event}}
      assert event.table == :sessions
      assert event.operation == :create
      assert event.record == record
      assert event.metadata == %{test: true}
    end
  end

  describe "subscribe_to_changes/1" do
    setup do
      {:ok, pid} = start_mnesia_and_synchronizer()
      %{pid: pid}
    end

    test "subscribes to table changes", %{pid: _pid} do
      assert :ok = StateSynchronizer.subscribe_to_changes([:sessions, :models])
      
      # Verify subscription by checking pg membership
      sessions_members = :pg.get_members(:rubber_duck_sync, "state_change:sessions")
      models_members = :pg.get_members(:rubber_duck_sync, "state_change:models")
      
      assert self() in sessions_members
      assert self() in models_members
    end
  end

  describe "reconcile_with_node/1" do
    setup do
      {:ok, pid} = start_mnesia_and_synchronizer()
      %{pid: pid}
    end

    test "handles reconciliation with non-existent node", %{pid: _pid} do
      result = StateSynchronizer.reconcile_with_node(:nonexistent@node)
      assert {:error, _} = result
    end

    test "reconciles with current node", %{pid: _pid} do
      # This should succeed as it's reconciling with self
      result = StateSynchronizer.reconcile_with_node(node())
      assert :ok = result
    end
  end

  describe "get_sync_stats/0" do
    setup do
      {:ok, pid} = start_mnesia_and_synchronizer()
      %{pid: pid}
    end

    test "returns synchronization statistics", %{pid: _pid} do
      stats = StateSynchronizer.get_sync_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :transactions)
      assert Map.has_key?(stats, :conflicts)
      assert Map.has_key?(stats, :broadcasts)
      assert Map.has_key?(stats, :reconciliations)
      assert Map.has_key?(stats, :node_id)
    end
  end

  describe "node monitoring" do
    setup do
      {:ok, pid} = start_mnesia_and_synchronizer()
      %{pid: pid}
    end

    test "handles node up/down events gracefully", %{pid: pid} do
      # Send a fake nodeup message
      send(pid, {:nodeup, :fake_node@test})
      
      # Process should still be alive
      :timer.sleep(100)
      assert Process.alive?(pid)
      
      # Send a fake nodedown message
      send(pid, {:nodedown, :fake_node@test})
      
      # Process should still be alive
      :timer.sleep(100)
      assert Process.alive?(pid)
    end
  end

  describe "state change handling" do
    setup do
      {:ok, pid} = start_mnesia_and_synchronizer()
      %{pid: pid}
    end

    test "processes remote state changes", %{pid: pid} do
      # Simulate a remote state change event
      event = %{
        table: :sessions,
        operation: :create,
        record: %{session_id: "remote_session"},
        metadata: %{},
        timestamp: System.system_time(:microsecond),
        node: :remote_node@test
      }
      
      send(pid, {"state_change:sessions", {:state_change, event}})
      
      # Process should handle it without crashing
      :timer.sleep(100)
      assert Process.alive?(pid)
    end
  end

  # Helper Functions

  defp start_mnesia_and_synchronizer do
    # Start Mnesia first
    {:ok, _} = MnesiaManager.start_link([])
    MnesiaManager.initialize_schema()
    
    # Start StateSynchronizer
    StateSynchronizer.start_link([])
  end
end