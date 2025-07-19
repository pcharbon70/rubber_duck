defmodule RubberDuck.Cache.ETSTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Cache.ETS

  setup do
    # Start the cache process for testing
    {:ok, _pid} = start_supervised({ETS, []})
    :ok
  end

  describe "basic cache operations" do
    test "stores and retrieves values" do
      key = "test_key"
      value = %{data: "test_value", timestamp: 12345}

      assert :ok = ETS.put(key, value)
      assert {:ok, retrieved_value} = ETS.get(key)
      assert retrieved_value == value
    end

    test "returns error for non-existent keys" do
      assert {:error, :not_found} = ETS.get("non_existent_key")
    end

    test "overwrites existing values" do
      key = "overwrite_test"

      assert :ok = ETS.put(key, "first_value")
      assert :ok = ETS.put(key, "second_value")

      assert {:ok, value} = ETS.get(key)
      assert value == "second_value"
    end

    test "deletes values" do
      key = "delete_test"
      value = "to_be_deleted"

      assert :ok = ETS.put(key, value)
      assert {:ok, _} = ETS.get(key)

      assert :ok = ETS.delete(key)
      assert {:error, :not_found} = ETS.get(key)
    end

    test "clears all values" do
      # Add multiple values
      assert :ok = ETS.put("key1", "value1")
      assert :ok = ETS.put("key2", "value2")
      assert :ok = ETS.put("key3", "value3")

      # Verify they exist
      assert {:ok, _} = ETS.get("key1")
      assert {:ok, _} = ETS.get("key2")
      assert {:ok, _} = ETS.get("key3")

      # Clear all
      assert :ok = ETS.clear()

      # Verify they're gone
      assert {:error, :not_found} = ETS.get("key1")
      assert {:error, :not_found} = ETS.get("key2")
      assert {:error, :not_found} = ETS.get("key3")
    end
  end

  describe "TTL (Time To Live) functionality" do
    test "respects TTL values" do
      key = "ttl_test"
      value = "expires_soon"
      # 1 second
      ttl = 1

      assert :ok = ETS.put(key, value, ttl)
      assert {:ok, retrieved_value} = ETS.get(key)
      assert retrieved_value == value

      # Wait for expiration
      Process.sleep(1100)

      assert {:error, :not_found} = ETS.get(key)
    end

    test "uses default TTL when not specified" do
      key = "default_ttl_test"
      value = "default_expires"

      assert :ok = ETS.put(key, value)
      assert {:ok, retrieved_value} = ETS.get(key)
      assert retrieved_value == value

      # Should not expire immediately
      Process.sleep(100)
      assert {:ok, _} = ETS.get(key)
    end

    test "removes expired entries on access" do
      key = "auto_cleanup_test"
      value = "auto_cleanup_value"
      ttl = 1

      assert :ok = ETS.put(key, value, ttl)

      # Wait for expiration
      Process.sleep(1100)

      # Accessing expired entry should remove it
      assert {:error, :not_found} = ETS.get(key)

      # Verify it's actually removed from table
      stats = ETS.stats()
      assert stats.expired_entries == 0
    end
  end

  describe "cache statistics" do
    test "provides accurate statistics" do
      # Clear cache first
      ETS.clear()

      # Add some entries
      ETS.put("active1", "value1", 3600)
      ETS.put("active2", "value2", 3600)
      ETS.put("expired1", "value3", 1)

      # Wait for one to expire
      Process.sleep(1100)

      stats = ETS.stats()

      assert stats.total_entries == 3
      assert stats.active_entries == 2
      assert stats.expired_entries == 1
      assert is_integer(stats.memory_usage_words)
      assert is_integer(stats.table_size)
    end

    test "handles empty cache statistics" do
      ETS.clear()

      stats = ETS.stats()

      assert stats.total_entries == 0
      assert stats.active_entries == 0
      assert stats.expired_entries == 0
      assert is_integer(stats.memory_usage_words)
      assert stats.table_size == 0
    end
  end

  describe "error handling" do
    test "handles deletion of non-existent keys gracefully" do
      assert :ok = ETS.delete("non_existent_key")
    end

    test "handles clearing empty cache gracefully" do
      ETS.clear()
      assert :ok = ETS.clear()
    end
  end

  describe "concurrent access" do
    test "handles concurrent reads and writes" do
      key = "concurrent_test"

      # Start multiple processes reading and writing
      tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            ETS.put("#{key}_#{i}", "value_#{i}")
            ETS.get("#{key}_#{i}")
          end)
        end)

      # Wait for all tasks to complete
      results = Enum.map(tasks, &Task.await/1)

      # All should succeed
      assert Enum.all?(results, fn result ->
               match?({:ok, _}, result)
             end)
    end

    test "handles concurrent modifications of same key" do
      key = "race_condition_test"

      # Start multiple processes modifying the same key
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            ETS.put(key, "value_#{i}")
            ETS.get(key)
          end)
        end)

      # Wait for all tasks to complete
      results = Enum.map(tasks, &Task.await/1)

      # All operations should succeed
      assert Enum.all?(results, fn result ->
               match?({:ok, _}, result)
             end)

      # Final value should be one of the written values
      assert {:ok, final_value} = ETS.get(key)
      assert String.starts_with?(final_value, "value_")
    end
  end

  describe "memory management" do
    test "manages memory usage efficiently" do
      initial_stats = ETS.stats()
      initial_memory = initial_stats.memory_usage_words

      # Add many entries
      Enum.each(1..1000, fn i ->
        large_value = String.duplicate("x", 100)
        ETS.put("large_key_#{i}", large_value)
      end)

      after_stats = ETS.stats()
      after_memory = after_stats.memory_usage_words

      # Memory usage should have increased
      assert after_memory > initial_memory

      # Clear cache
      ETS.clear()

      # Memory should be freed (though exact amount depends on ETS implementation)
      final_stats = ETS.stats()
      assert final_stats.total_entries == 0
    end
  end

  describe "background cleanup" do
    test "cleans up expired entries periodically" do
      # Add entries with short TTL
      Enum.each(1..10, fn i ->
        ETS.put("cleanup_test_#{i}", "value_#{i}", 1)
      end)

      # Verify entries exist
      stats_before = ETS.stats()
      assert stats_before.total_entries == 10

      # Wait for expiration and cleanup cycle
      Process.sleep(2000)

      # Trigger cleanup by accessing the cache
      ETS.get("trigger_cleanup")

      # Wait a bit more for cleanup to complete
      Process.sleep(500)

      stats_after = ETS.stats()

      # Expired entries should be reduced (cleanup may not be immediate)
      assert stats_after.expired_entries < stats_before.total_entries
    end
  end

  describe "data types" do
    test "handles various data types" do
      test_data = [
        {"string", "hello world"},
        {"integer", 42},
        {"float", 3.14},
        {"boolean", true},
        {"atom", :test_atom},
        {"list", [1, 2, 3, "four"]},
        {"map", %{key: "value", nested: %{inner: "data"}}},
        {"tuple", {:ok, "result"}},
        {"binary", <<1, 2, 3, 4>>}
      ]

      # Store all data types
      Enum.each(test_data, fn {key, value} ->
        assert :ok = ETS.put(key, value)
      end)

      # Retrieve and verify all data types
      Enum.each(test_data, fn {key, expected_value} ->
        assert {:ok, retrieved_value} = ETS.get(key)
        assert retrieved_value == expected_value
      end)
    end
  end

  describe "cache key patterns" do
    test "handles complex key patterns" do
      complex_keys = [
        "simple_key",
        "key:with:colons",
        "key_with_underscores",
        "key-with-dashes",
        "key.with.dots",
        "key/with/slashes",
        "key with spaces",
        "key@with#special$chars%"
      ]

      # Store values with complex keys
      Enum.each(complex_keys, fn key ->
        assert :ok = ETS.put(key, "value_for_#{key}")
      end)

      # Retrieve values with complex keys
      Enum.each(complex_keys, fn key ->
        assert {:ok, value} = ETS.get(key)
        assert value == "value_for_#{key}"
      end)
    end
  end
end
