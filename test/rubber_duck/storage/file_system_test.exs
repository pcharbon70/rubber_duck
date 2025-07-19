defmodule RubberDuck.Storage.FileSystemTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Storage.FileSystem

  @test_storage_dir "test/fixtures/storage"

  setup do
    # Clean up test directory before each test
    if File.exists?(@test_storage_dir) do
      File.rm_rf!(@test_storage_dir)
    end

    # Set up test directory
    File.mkdir_p!(@test_storage_dir)

    # Override storage directory for testing
    Application.put_env(:rubber_duck, :storage_dir, @test_storage_dir)

    on_exit(fn ->
      # Clean up after test
      if File.exists?(@test_storage_dir) do
        File.rm_rf!(@test_storage_dir)
      end
    end)

    :ok
  end

  describe "basic storage operations" do
    test "stores and retrieves data" do
      key = "test/key/123"

      data = %{
        output: "test result",
        metadata: %{tool: :test_tool, user: "test_user"},
        timestamp: 1_234_567_890
      }

      assert :ok = FileSystem.store(key, data)
      assert {:ok, retrieved_data} = FileSystem.retrieve(key)
      assert retrieved_data == data
    end

    test "handles non-existent keys" do
      assert {:error, :not_found} = FileSystem.retrieve("non/existent/key")
    end

    test "overwrites existing data" do
      key = "overwrite/test"
      original_data = %{value: "original"}
      new_data = %{value: "updated"}

      assert :ok = FileSystem.store(key, original_data)
      assert {:ok, retrieved} = FileSystem.retrieve(key)
      assert retrieved == original_data

      assert :ok = FileSystem.store(key, new_data)
      assert {:ok, retrieved} = FileSystem.retrieve(key)
      assert retrieved == new_data
    end

    test "deletes stored data" do
      key = "delete/test"
      data = %{value: "to_be_deleted"}

      assert :ok = FileSystem.store(key, data)
      assert {:ok, _} = FileSystem.retrieve(key)

      assert :ok = FileSystem.delete(key)
      assert {:error, :not_found} = FileSystem.retrieve(key)
    end

    test "handles deletion of non-existent keys gracefully" do
      assert :ok = FileSystem.delete("non/existent/key")
    end
  end

  describe "key handling" do
    test "handles complex key structures" do
      complex_keys = [
        "simple_key",
        "results/tool_name/execution_id/timestamp",
        "cache/user_123/tool_456/hash_789",
        "nested/very/deep/key/structure",
        "key_with_underscores",
        "key-with-dashes",
        "key.with.dots"
      ]

      data = %{test: "data"}

      # Store data with complex keys
      Enum.each(complex_keys, fn key ->
        assert :ok = FileSystem.store(key, Map.put(data, :key, key))
      end)

      # Retrieve data with complex keys
      Enum.each(complex_keys, fn key ->
        assert {:ok, retrieved} = FileSystem.retrieve(key)
        assert retrieved.key == key
      end)
    end

    test "handles keys with special characters" do
      special_keys = [
        "key with spaces",
        "key@with#special$chars%",
        "key:with:colons",
        "key/with/slashes",
        "key\\with\\backslashes"
      ]

      data = %{test: "special"}

      # Store and retrieve with special character keys
      Enum.each(special_keys, fn key ->
        assert :ok = FileSystem.store(key, Map.put(data, :key, key))
        assert {:ok, retrieved} = FileSystem.retrieve(key)
        assert retrieved.key == key
      end)
    end
  end

  describe "data types" do
    test "handles various data types" do
      test_data = [
        {"string_data", "hello world"},
        {"integer_data", 42},
        {"float_data", 3.14159},
        {"boolean_data", true},
        {"atom_data", :test_atom},
        {"list_data", [1, 2, 3, "four", :five]},
        {"map_data", %{key: "value", nested: %{inner: "data"}}},
        {"tuple_data", {:ok, "result", 123}},
        {"complex_data",
         %{
           results: [
             %{id: 1, name: "first"},
             %{id: 2, name: "second"}
           ],
           metadata: %{
             tool: :test_tool,
             user: "test_user",
             execution_time: 1500
           }
         }}
      ]

      # Store all data types
      Enum.each(test_data, fn {key, value} ->
        assert :ok = FileSystem.store(key, value)
      end)

      # Retrieve and verify all data types
      Enum.each(test_data, fn {key, expected_value} ->
        assert {:ok, retrieved_value} = FileSystem.retrieve(key)
        assert retrieved_value == expected_value
      end)
    end
  end

  describe "listing operations" do
    test "lists all stored keys" do
      # Store multiple items
      test_items = [
        {"item1", %{data: "first"}},
        {"item2", %{data: "second"}},
        {"item3", %{data: "third"}}
      ]

      Enum.each(test_items, fn {key, data} ->
        FileSystem.store(key, data)
      end)

      assert {:ok, keys} = FileSystem.list()
      assert length(keys) == 3

      # All keys should be present
      Enum.each(test_items, fn {key, _data} ->
        assert key in keys
      end)
    end

    test "handles empty storage" do
      assert {:ok, keys} = FileSystem.list()
      assert keys == []
    end

    test "lists results for specific tool" do
      # Store items for different tools
      FileSystem.store("results/tool1/exec1/123", %{tool: :tool1})
      FileSystem.store("results/tool1/exec2/456", %{tool: :tool1})
      FileSystem.store("results/tool2/exec1/789", %{tool: :tool2})
      FileSystem.store("other/data/key", %{tool: :other})

      assert {:ok, tool1_keys} = FileSystem.list_for_tool("tool1")
      assert length(tool1_keys) == 2

      assert Enum.all?(tool1_keys, fn key ->
               String.starts_with?(key, "results/tool1/")
             end)

      assert {:ok, tool2_keys} = FileSystem.list_for_tool("tool2")
      assert length(tool2_keys) == 1

      assert Enum.all?(tool2_keys, fn key ->
               String.starts_with?(key, "results/tool2/")
             end)

      # Non-existent tool should return empty list
      assert {:ok, empty_keys} = FileSystem.list_for_tool("non_existent_tool")
      assert empty_keys == []
    end
  end

  describe "statistics" do
    test "provides storage statistics" do
      # Store some data
      FileSystem.store("stats_test1", %{data: "first"})
      FileSystem.store("stats_test2", %{data: "second"})
      FileSystem.store("stats_test3", %{data: "third"})

      stats = FileSystem.stats()

      assert stats.total_files == 3
      assert is_integer(stats.total_size_bytes)
      assert stats.total_size_bytes > 0
      assert is_binary(stats.storage_directory)
    end

    test "handles empty storage statistics" do
      stats = FileSystem.stats()

      assert stats.total_files == 0
      assert stats.total_size_bytes == 0
      assert is_binary(stats.storage_directory)
    end
  end

  describe "cleanup operations" do
    test "cleans up old results" do
      # Store some data
      FileSystem.store("old_result1", %{data: "old1"})
      FileSystem.store("old_result2", %{data: "old2"})
      FileSystem.store("old_result3", %{data: "old3"})

      # Wait a moment
      Process.sleep(100)

      # Cleanup files older than 0 seconds (should clean all)
      assert {:ok, deleted_count} = FileSystem.cleanup_old_results(0)
      assert deleted_count == 3

      # Verify files are deleted
      assert {:ok, keys} = FileSystem.list()
      assert keys == []
    end

    test "preserves recent results during cleanup" do
      # Store some data
      FileSystem.store("recent_result1", %{data: "recent1"})
      FileSystem.store("recent_result2", %{data: "recent2"})

      # Cleanup files older than 1 hour (should preserve recent files)
      assert {:ok, deleted_count} = FileSystem.cleanup_old_results(3600)
      assert deleted_count == 0

      # Verify files are still there
      assert {:ok, keys} = FileSystem.list()
      assert length(keys) == 2
    end

    test "handles cleanup of non-existent directory" do
      # Remove storage directory
      File.rm_rf!(@test_storage_dir)

      # Cleanup should handle missing directory gracefully
      assert {:ok, deleted_count} = FileSystem.cleanup_old_results(0)
      assert deleted_count == 0
    end
  end

  describe "error handling" do
    test "handles encoding errors gracefully" do
      # Data that can't be JSON encoded
      problematic_data = %{
        # Functions can't be JSON encoded
        function: &String.upcase/1,
        # PIDs can't be JSON encoded
        pid: self()
      }

      assert {:error, {:encoding_failed, _reason}} = FileSystem.store("problem_key", problematic_data)
    end

    test "handles corrupted data gracefully" do
      # Manually write corrupted data to file
      key = "corrupted_key"
      file_path = Path.join(@test_storage_dir, Base.encode64(key, padding: false) <> ".json")
      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, "{ invalid json content")

      assert {:error, {:decoding_failed, _reason}} = FileSystem.retrieve(key)
    end

    test "handles file system errors" do
      # Try to store in a location that doesn't exist and can't be created
      original_dir = Application.get_env(:rubber_duck, :storage_dir)

      # Set invalid storage directory
      Application.put_env(:rubber_duck, :storage_dir, "/invalid/path/that/cannot/exist")

      result = FileSystem.store("test_key", %{data: "test"})

      # Should return error
      assert match?({:error, _}, result)

      # Restore original directory
      Application.put_env(:rubber_duck, :storage_dir, original_dir)
    end
  end

  describe "concurrent operations" do
    test "handles concurrent reads and writes" do
      # Start multiple processes storing and retrieving data
      tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            key = "concurrent_test_#{i}"
            data = %{value: "data_#{i}", process: i}

            # Store data
            :ok = FileSystem.store(key, data)

            # Retrieve data
            {:ok, retrieved} = FileSystem.retrieve(key)
            retrieved
          end)
        end)

      # Wait for all tasks to complete
      results = Enum.map(tasks, &Task.await/1)

      # All should succeed and return correct data
      assert length(results) == 10

      Enum.with_index(results, 1, fn result, i ->
        assert result.value == "data_#{i}"
        assert result.process == i
      end)
    end

    test "handles concurrent modifications of same key" do
      key = "race_condition_test"

      # Start multiple processes modifying the same key
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            data = %{value: "value_#{i}", process: i}
            FileSystem.store(key, data)
            FileSystem.retrieve(key)
          end)
        end)

      # Wait for all tasks to complete
      results = Enum.map(tasks, &Task.await/1)

      # All operations should succeed
      assert Enum.all?(results, fn result ->
               match?({:ok, _}, result)
             end)

      # Final state should be consistent
      assert {:ok, final_data} = FileSystem.retrieve(key)
      assert String.starts_with?(final_data.value, "value_")
    end
  end

  describe "file system integration" do
    test "creates necessary directories" do
      deep_key = "very/deep/nested/key/structure"
      data = %{test: "directory_creation"}

      assert :ok = FileSystem.store(deep_key, data)
      assert {:ok, retrieved} = FileSystem.retrieve(deep_key)
      assert retrieved == data

      # Verify directory structure was created
      encoded_key = Base.encode64(String.replace(deep_key, "/", "_"), padding: false)
      expected_file = Path.join(@test_storage_dir, "#{encoded_key}.json")
      assert File.exists?(expected_file)
    end

    test "handles file permissions correctly" do
      key = "permissions_test"
      data = %{test: "permissions"}

      assert :ok = FileSystem.store(key, data)

      # File should be readable
      assert {:ok, retrieved} = FileSystem.retrieve(key)
      assert retrieved == data
    end
  end
end
