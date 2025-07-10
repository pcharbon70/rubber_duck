defmodule RubberDuck.Workflows.CacheTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Workflows.Cache

  setup do
    # Cache is already started by the application
    # Clear any existing entries for clean test state
    :ets.delete_all_objects(:workflow_cache)
    :ok
  end

  describe "cleanup_expired/0" do
    test "should handle DateTime comparison in ETS match specifications" do
      # Arrange - Add some entries to the cache with different expiry times
      # 1 hour ago
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      # 1 hour from now
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      # Put items directly into ETS to simulate expired entries
      :ets.insert(:workflow_cache, {"expired_key", "expired_value", past_time})
      :ets.insert(:workflow_cache, {"valid_key", "valid_value", future_time})

      # Act - Trigger cleanup (this currently causes the error)
      # Send the cleanup message directly to the GenServer
      send(Process.whereis(Cache), :cleanup)

      # Give it time to process
      Process.sleep(100)

      # Assert - Check that expired entries are removed and valid ones remain
      assert Cache.get("expired_key") == :miss
      assert {:ok, "valid_value"} = Cache.get("valid_key")
    end
  end

  describe "get/1" do
    test "returns :miss for expired entries" do
      # Put an already expired entry
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      :ets.insert(:workflow_cache, {"expired_key", "value", past_time})

      assert Cache.get("expired_key") == :miss
    end

    test "returns {:ok, value} for valid entries" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      :ets.insert(:workflow_cache, {"valid_key", "value", future_time})

      assert Cache.get("valid_key") == {:ok, "value"}
    end
  end

  describe "cleanup with various entry types" do
    test "cleanup handles mixed entry types safely" do
      # Add various types of entries that might exist in cache
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)

      # Normal entries
      :ets.insert(:workflow_cache, {"valid_key", "value", future_time})
      :ets.insert(:workflow_cache, {"expired_key", "value", past_time})

      # Entry with nil expiry (shouldn't happen but let's be safe)
      :ets.insert(:workflow_cache, {"nil_expiry", "value", nil})

      # Entry with wrong structure (defensive programming)
      :ets.insert(:workflow_cache, {"malformed", "no_expiry"})

      # Trigger cleanup
      send(Process.whereis(Cache), :cleanup)
      Process.sleep(100)

      # Valid entry should remain
      assert {:ok, "value"} = Cache.get("valid_key")

      # Expired entry should be removed
      assert :miss = Cache.get("expired_key")

      # Malformed entries should remain (we don't touch what we don't understand)
      assert [{_, _, _}] = :ets.lookup(:workflow_cache, "nil_expiry")
      assert [{_, _}] = :ets.lookup(:workflow_cache, "malformed")
    end
  end
end
