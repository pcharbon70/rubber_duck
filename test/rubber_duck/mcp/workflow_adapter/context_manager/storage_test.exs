defmodule RubberDuck.MCP.WorkflowAdapter.ContextManager.StorageTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.WorkflowAdapter.ContextManager.Storage

  setup do
    # Initialize storage with temporary directory
    temp_dir = System.tmp_dir!() |> Path.join("storage_test_#{:rand.uniform(1000)}")

    {:ok, state} = Storage.init(persistent: true, storage_path: temp_dir)

    on_exit(fn ->
      # Clean up temporary directory
      if File.exists?(temp_dir) do
        File.rm_rf!(temp_dir)
      end
    end)

    %{storage_state: state, temp_dir: temp_dir}
  end

  describe "init/1" do
    test "initializes storage with default options" do
      {:ok, state} = Storage.init([])

      assert state.table == :workflow_contexts
      assert state.persistent == false
      assert state.storage_path == "priv/contexts"
    end

    test "initializes storage with custom options" do
      custom_path = "/tmp/custom_contexts"
      {:ok, state} = Storage.init(persistent: true, storage_path: custom_path)

      assert state.persistent == true
      assert state.storage_path == custom_path
    end

    test "creates ETS table on initialization" do
      {:ok, state} = Storage.init([])

      # Should be able to interact with the ETS table
      assert :ets.info(state.table, :type) == :set
    end
  end

  describe "store_context/2" do
    test "stores context in ETS", %{storage_state: state} do
      context = %{
        id: "test_context_1",
        data: %{"user_id" => "user123"},
        version: 1,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      assert :ok = Storage.store_context(state, context)

      # Verify context was stored
      {:ok, retrieved_context} = Storage.get_context(state, "test_context_1")
      assert retrieved_context.id == "test_context_1"
      assert retrieved_context.data == %{"user_id" => "user123"}
    end

    test "persists context to disk when enabled", %{storage_state: state, temp_dir: temp_dir} do
      context = %{
        id: "persistent_context",
        data: %{"important" => "data"},
        version: 1,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      assert :ok = Storage.store_context(state, context)

      # Check that file was created
      expected_file = Path.join(temp_dir, "persistent_context.json")
      assert File.exists?(expected_file)

      # Verify file contents
      content = File.read!(expected_file)
      parsed = Jason.decode!(content, keys: :atoms)

      assert parsed.id == "persistent_context"
      assert parsed.data == %{"important" => "data"}
    end

    test "handles storage errors gracefully", %{storage_state: state} do
      # Test with invalid context (missing required fields)
      invalid_context = %{
        # Invalid ID
        id: nil,
        data: %{}
      }

      result = Storage.store_context(state, invalid_context)

      # Should handle error gracefully
      assert {:error, _reason} = result
    end

    test "overwrites existing context", %{storage_state: state} do
      context1 = %{
        id: "overwrite_test",
        data: %{"version" => 1},
        version: 1,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      context2 = %{
        id: "overwrite_test",
        data: %{"version" => 2},
        version: 2,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      assert :ok = Storage.store_context(state, context1)
      assert :ok = Storage.store_context(state, context2)

      {:ok, retrieved} = Storage.get_context(state, "overwrite_test")
      assert retrieved.data == %{"version" => 2}
      assert retrieved.version == 2
    end
  end

  describe "get_context/2" do
    test "retrieves stored context", %{storage_state: state} do
      context = %{
        id: "get_test",
        data: %{"test" => "data"},
        version: 1,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      :ok = Storage.store_context(state, context)

      {:ok, retrieved} = Storage.get_context(state, "get_test")

      assert retrieved.id == "get_test"
      assert retrieved.data == %{"test" => "data"}
      assert retrieved.version == 1
    end

    test "returns error for non-existent context", %{storage_state: state} do
      assert {:error, :not_found} = Storage.get_context(state, "non_existent")
    end

    test "retrieves context with complex data", %{storage_state: state} do
      complex_data = %{
        "user" => %{
          "id" => "user123",
          "preferences" => %{
            "theme" => "dark",
            "notifications" => %{
              "email" => true,
              "push" => false
            }
          }
        },
        "session" => %{
          "started_at" => "2023-01-01T00:00:00Z",
          "activities" => ["login", "browse", "purchase"]
        }
      }

      context = %{
        id: "complex_test",
        data: complex_data,
        version: 1,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      :ok = Storage.store_context(state, context)

      {:ok, retrieved} = Storage.get_context(state, "complex_test")
      assert retrieved.data == complex_data
    end
  end

  describe "delete_context/2" do
    test "deletes stored context", %{storage_state: state} do
      context = %{
        id: "delete_test",
        data: %{"to_be_deleted" => true},
        version: 1,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      :ok = Storage.store_context(state, context)

      # Verify context exists
      {:ok, _} = Storage.get_context(state, "delete_test")

      # Delete context
      assert :ok = Storage.delete_context(state, "delete_test")

      # Verify context is deleted
      assert {:error, :not_found} = Storage.get_context(state, "delete_test")
    end

    test "deletes persistent context file", %{storage_state: state, temp_dir: temp_dir} do
      context = %{
        id: "persistent_delete",
        data: %{"will_be_deleted" => true},
        version: 1,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      :ok = Storage.store_context(state, context)

      # Verify file exists
      expected_file = Path.join(temp_dir, "persistent_delete.json")
      assert File.exists?(expected_file)

      # Delete context
      assert :ok = Storage.delete_context(state, "persistent_delete")

      # Verify file is deleted
      assert not File.exists?(expected_file)
    end

    test "handles deletion of non-existent context", %{storage_state: state} do
      # Should not error when deleting non-existent context
      assert :ok = Storage.delete_context(state, "non_existent")
    end
  end

  describe "list_contexts/2" do
    test "lists all stored contexts", %{storage_state: state} do
      contexts = [
        %{
          id: "list_test_1",
          data: %{"type" => "test1"},
          version: 1,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          expires_at: nil,
          access_policy: %{},
          metadata: %{}
        },
        %{
          id: "list_test_2",
          data: %{"type" => "test2"},
          version: 1,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          expires_at: nil,
          access_policy: %{},
          metadata: %{}
        }
      ]

      for context <- contexts do
        :ok = Storage.store_context(state, context)
      end

      all_contexts = Storage.list_contexts(state, [])

      assert length(all_contexts) >= 2

      context_ids = Enum.map(all_contexts, & &1.id)
      assert "list_test_1" in context_ids
      assert "list_test_2" in context_ids
    end

    test "filters contexts by user_id", %{storage_state: state} do
      contexts = [
        %{
          id: "user_filter_1",
          data: %{"user_id" => "user1"},
          version: 1,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          expires_at: nil,
          access_policy: %{},
          metadata: %{}
        },
        %{
          id: "user_filter_2",
          data: %{"user_id" => "user2"},
          version: 1,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          expires_at: nil,
          access_policy: %{},
          metadata: %{}
        }
      ]

      for context <- contexts do
        :ok = Storage.store_context(state, context)
      end

      user1_contexts = Storage.list_contexts(state, user_id: "user1")

      assert length(user1_contexts) == 1
      assert hd(user1_contexts).data["user_id"] == "user1"
    end

    test "filters contexts by session_id", %{storage_state: state} do
      contexts = [
        %{
          id: "session_filter_1",
          data: %{"session_id" => "session1"},
          version: 1,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          expires_at: nil,
          access_policy: %{},
          metadata: %{}
        },
        %{
          id: "session_filter_2",
          data: %{"session_id" => "session2"},
          version: 1,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          expires_at: nil,
          access_policy: %{},
          metadata: %{}
        }
      ]

      for context <- contexts do
        :ok = Storage.store_context(state, context)
      end

      session1_contexts = Storage.list_contexts(state, session_id: "session1")

      assert length(session1_contexts) == 1
      assert hd(session1_contexts).data["session_id"] == "session1"
    end

    test "filters contexts by creation date", %{storage_state: state} do
      base_time = DateTime.utc_now()

      early_context = %{
        id: "early_context",
        data: %{"created" => "early"},
        version: 1,
        created_at: DateTime.add(base_time, -3600, :second),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      late_context = %{
        id: "late_context",
        data: %{"created" => "late"},
        version: 1,
        created_at: DateTime.add(base_time, 3600, :second),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      :ok = Storage.store_context(state, early_context)
      :ok = Storage.store_context(state, late_context)

      # Filter for contexts created after base_time
      recent_contexts = Storage.list_contexts(state, created_after: base_time)

      assert length(recent_contexts) == 1
      assert hd(recent_contexts).data["created"] == "late"
    end

    test "limits number of contexts returned", %{storage_state: state} do
      # Store multiple contexts
      for i <- 1..10 do
        context = %{
          id: "limit_test_#{i}",
          data: %{"index" => i},
          version: 1,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          expires_at: nil,
          access_policy: %{},
          metadata: %{}
        }

        :ok = Storage.store_context(state, context)
      end

      limited_contexts = Storage.list_contexts(state, limit: 3)

      assert length(limited_contexts) == 3
    end

    test "handles empty context list", %{storage_state: state} do
      contexts = Storage.list_contexts(state, [])

      assert is_list(contexts)
      # May be empty or contain contexts from other tests
    end
  end

  describe "cleanup_expired_contexts/1" do
    test "removes expired contexts", %{storage_state: state} do
      current_time = DateTime.utc_now()

      # Create expired context
      expired_context = %{
        id: "expired_test",
        data: %{"expired" => true},
        version: 1,
        created_at: current_time,
        updated_at: current_time,
        # Expired 1 hour ago
        expires_at: DateTime.add(current_time, -3600, :second),
        access_policy: %{},
        metadata: %{}
      }

      # Create non-expired context
      active_context = %{
        id: "active_test",
        data: %{"active" => true},
        version: 1,
        created_at: current_time,
        updated_at: current_time,
        # Expires in 1 hour
        expires_at: DateTime.add(current_time, 3600, :second),
        access_policy: %{},
        metadata: %{}
      }

      :ok = Storage.store_context(state, expired_context)
      :ok = Storage.store_context(state, active_context)

      # Run cleanup
      cleaned_count = Storage.cleanup_expired_contexts(state)

      assert cleaned_count >= 1

      # Verify expired context was removed
      assert {:error, :not_found} = Storage.get_context(state, "expired_test")

      # Verify active context still exists
      assert {:ok, _} = Storage.get_context(state, "active_test")
    end

    test "handles contexts without expiration", %{storage_state: state} do
      # Create context without expiration
      no_expiry_context = %{
        id: "no_expiry_test",
        data: %{"no_expiry" => true},
        version: 1,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      :ok = Storage.store_context(state, no_expiry_context)

      # Run cleanup
      cleaned_count = Storage.cleanup_expired_contexts(state)

      # Context without expiration should not be removed
      assert {:ok, _} = Storage.get_context(state, "no_expiry_test")
    end

    test "returns count of cleaned contexts", %{storage_state: state} do
      current_time = DateTime.utc_now()

      # Create multiple expired contexts
      for i <- 1..5 do
        expired_context = %{
          id: "expired_#{i}",
          data: %{"index" => i},
          version: 1,
          created_at: current_time,
          updated_at: current_time,
          expires_at: DateTime.add(current_time, -3600, :second),
          access_policy: %{},
          metadata: %{}
        }

        :ok = Storage.store_context(state, expired_context)
      end

      cleaned_count = Storage.cleanup_expired_contexts(state)

      assert cleaned_count == 5
    end
  end

  describe "get_stats/1" do
    test "returns storage statistics", %{storage_state: state} do
      # Store some contexts
      for i <- 1..3 do
        context = %{
          id: "stats_test_#{i}",
          data: %{"index" => i},
          version: 1,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          expires_at: nil,
          access_policy: %{},
          metadata: %{}
        }

        :ok = Storage.store_context(state, context)
      end

      stats = Storage.get_stats(state)

      assert Map.has_key?(stats, :total_contexts)
      assert Map.has_key?(stats, :expired_contexts)
      assert Map.has_key?(stats, :active_contexts)
      assert Map.has_key?(stats, :persistent_storage)
      assert Map.has_key?(stats, :storage_path)

      assert stats.total_contexts >= 3
      assert stats.persistent_storage == state.persistent
      assert stats.storage_path == state.storage_path
    end

    test "calculates expired contexts correctly", %{storage_state: state} do
      current_time = DateTime.utc_now()

      # Store active context
      active_context = %{
        id: "active_stats",
        data: %{"active" => true},
        version: 1,
        created_at: current_time,
        updated_at: current_time,
        expires_at: DateTime.add(current_time, 3600, :second),
        access_policy: %{},
        metadata: %{}
      }

      # Store expired context
      expired_context = %{
        id: "expired_stats",
        data: %{"expired" => true},
        version: 1,
        created_at: current_time,
        updated_at: current_time,
        expires_at: DateTime.add(current_time, -3600, :second),
        access_policy: %{},
        metadata: %{}
      }

      :ok = Storage.store_context(state, active_context)
      :ok = Storage.store_context(state, expired_context)

      stats = Storage.get_stats(state)

      assert stats.expired_contexts >= 1
      assert stats.active_contexts >= 1
      assert stats.total_contexts >= 2
    end
  end

  describe "persistent storage" do
    test "loads persisted contexts on initialization", %{temp_dir: temp_dir} do
      # Create a context file manually
      context_data = %{
        id: "persisted_test",
        data: %{"persisted" => true},
        version: 1,
        created_at: DateTime.to_iso8601(DateTime.utc_now()),
        updated_at: DateTime.to_iso8601(DateTime.utc_now()),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      File.mkdir_p!(temp_dir)
      file_path = Path.join(temp_dir, "persisted_test.json")
      File.write!(file_path, Jason.encode!(context_data, pretty: true))

      # Initialize storage - should load the persisted context
      {:ok, state} = Storage.init(persistent: true, storage_path: temp_dir)

      # Verify context was loaded
      {:ok, loaded_context} = Storage.get_context(state, "persisted_test")
      assert loaded_context.data == %{"persisted" => true}
    end

    test "handles corrupted persistence files gracefully", %{temp_dir: temp_dir} do
      # Create a corrupted file
      File.mkdir_p!(temp_dir)
      corrupted_file = Path.join(temp_dir, "corrupted.json")
      File.write!(corrupted_file, "invalid json content")

      # Should initialize without crashing
      {:ok, state} = Storage.init(persistent: true, storage_path: temp_dir)

      # Should still be functional
      assert Storage.get_stats(state).total_contexts >= 0
    end

    test "handles missing storage directory", %{temp_dir: temp_dir} do
      # Use non-existent directory
      non_existent_dir = Path.join(temp_dir, "non_existent")

      # Should initialize without crashing
      {:ok, state} = Storage.init(persistent: true, storage_path: non_existent_dir)

      # Should still be functional
      assert Storage.get_stats(state).total_contexts >= 0
    end
  end

  describe "concurrent access" do
    test "handles concurrent context storage", %{storage_state: state} do
      # Store contexts concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            context = %{
              id: "concurrent_#{i}",
              data: %{"index" => i},
              version: 1,
              created_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now(),
              expires_at: nil,
              access_policy: %{},
              metadata: %{}
            }

            Storage.store_context(state, context)
          end)
        end

      results = Task.await_many(tasks)

      # All storage operations should succeed
      assert Enum.all?(results, fn
               :ok -> true
               _ -> false
             end)

      # All contexts should be retrievable
      for i <- 1..10 do
        assert {:ok, _} = Storage.get_context(state, "concurrent_#{i}")
      end
    end

    test "handles concurrent reads", %{storage_state: state} do
      # Store a context first
      context = %{
        id: "read_test",
        data: %{"shared" => "data"},
        version: 1,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        expires_at: nil,
        access_policy: %{},
        metadata: %{}
      }

      :ok = Storage.store_context(state, context)

      # Read concurrently
      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            Storage.get_context(state, "read_test")
          end)
        end

      results = Task.await_many(tasks)

      # All reads should succeed
      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)
    end
  end
end
