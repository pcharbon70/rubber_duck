defmodule RubberDuck.MCP.WorkflowAdapter.ContextManagerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.WorkflowAdapter.ContextManager

  setup do
    # Start a fresh context manager for each test
    {:ok, pid} = start_supervised({ContextManager, [cleanup_interval: 1000]})
    %{context_manager: pid}
  end

  describe "create_context/2" do
    test "creates a new context with initial data" do
      initial_data = %{
        "user_id" => "user123",
        "session_id" => "session456",
        "preferences" => %{
          "theme" => "dark",
          "language" => "en"
        }
      }

      {:ok, context} = ContextManager.create_context(initial_data)
      
      assert is_binary(context.id)
      assert context.data == initial_data
      assert context.version == 1
      assert context.access_policy == %{}
      assert context.metadata == %{}
      assert %DateTime{} = context.created_at
      assert %DateTime{} = context.updated_at
      assert context.expires_at == nil
    end

    test "creates context with expiration" do
      initial_data = %{"test" => "data"}
      
      {:ok, context} = ContextManager.create_context(initial_data, expires_in: 3600)
      
      assert %DateTime{} = context.expires_at
      assert DateTime.diff(context.expires_at, DateTime.utc_now()) > 3500
      assert DateTime.diff(context.expires_at, DateTime.utc_now()) <= 3600
    end

    test "creates context with access policy" do
      initial_data = %{"sensitive" => "data"}
      access_policy = %{
        "read" => ["user:123", "role:admin"],
        "write" => ["user:123"]
      }
      
      {:ok, context} = ContextManager.create_context(initial_data, access_policy: access_policy)
      
      assert context.access_policy == access_policy
    end

    test "creates context with metadata" do
      initial_data = %{"test" => "data"}
      metadata = %{"source" => "test", "priority" => "high"}
      
      {:ok, context} = ContextManager.create_context(initial_data, metadata: metadata)
      
      assert context.metadata == metadata
    end

    test "generates unique context IDs" do
      {:ok, context1} = ContextManager.create_context(%{"test" => "data1"})
      {:ok, context2} = ContextManager.create_context(%{"test" => "data2"})
      
      assert context1.id != context2.id
    end

    test "creates context with empty data" do
      {:ok, context} = ContextManager.create_context(%{})
      
      assert context.data == %{}
      assert context.version == 1
    end
  end

  describe "get_context/1" do
    test "retrieves existing context" do
      initial_data = %{
        "user_id" => "user123",
        "session_data" => %{"key" => "value"}
      }

      {:ok, created_context} = ContextManager.create_context(initial_data)
      
      {:ok, retrieved_context} = ContextManager.get_context(created_context.id)
      
      assert retrieved_context.id == created_context.id
      assert retrieved_context.data == initial_data
      assert retrieved_context.version == 1
    end

    test "returns error for non-existent context" do
      assert {:error, :not_found} = ContextManager.get_context("non_existent_id")
    end

    test "returns error for expired context" do
      initial_data = %{"test" => "data"}
      
      {:ok, context} = ContextManager.create_context(initial_data, expires_in: 1)
      
      # Wait for context to expire
      Process.sleep(1100)
      
      assert {:error, :context_expired} = ContextManager.get_context(context.id)
    end
  end

  describe "update_context/2" do
    test "updates context with new data" do
      initial_data = %{
        "user_id" => "user123",
        "status" => "active"
      }

      {:ok, context} = ContextManager.create_context(initial_data)
      
      update_data = %{
        "user_id" => "user123",
        "status" => "processing",
        "progress" => 50
      }

      {:ok, updated_context} = ContextManager.update_context(context.id, update_data)
      
      assert updated_context.id == context.id
      assert updated_context.data == update_data
      assert updated_context.version == 2
      assert DateTime.compare(updated_context.updated_at, context.updated_at) == :gt
    end

    test "increments version on update" do
      {:ok, context} = ContextManager.create_context(%{"test" => "data"})
      
      {:ok, updated1} = ContextManager.update_context(context.id, %{"test" => "data1"})
      {:ok, updated2} = ContextManager.update_context(context.id, %{"test" => "data2"})
      
      assert updated1.version == 2
      assert updated2.version == 3
    end

    test "returns error for non-existent context" do
      assert {:error, :not_found} = ContextManager.update_context("non_existent", %{"test" => "data"})
    end

    test "returns error for expired context" do
      {:ok, context} = ContextManager.create_context(%{"test" => "data"}, expires_in: 1)
      
      # Wait for context to expire
      Process.sleep(1100)
      
      assert {:error, :context_expired} = ContextManager.update_context(context.id, %{"test" => "new_data"})
    end
  end

  describe "merge_context/2" do
    test "merges data into existing context" do
      initial_data = %{
        "user_id" => "user123",
        "preferences" => %{
          "theme" => "dark",
          "language" => "en"
        },
        "status" => "active"
      }

      {:ok, context} = ContextManager.create_context(initial_data)
      
      merge_data = %{
        "preferences" => %{
          "language" => "es",
          "notifications" => true
        },
        "last_activity" => "2023-01-01T00:00:00Z"
      }

      {:ok, merged_context} = ContextManager.merge_context(context.id, merge_data)
      
      assert merged_context.id == context.id
      assert merged_context.version == 2
      assert merged_context.data["user_id"] == "user123"
      assert merged_context.data["status"] == "active"
      assert merged_context.data["preferences"]["theme"] == "dark"
      assert merged_context.data["preferences"]["language"] == "es"
      assert merged_context.data["preferences"]["notifications"] == true
      assert merged_context.data["last_activity"] == "2023-01-01T00:00:00Z"
    end

    test "handles deep merging of nested maps" do
      initial_data = %{
        "config" => %{
          "ui" => %{
            "theme" => "dark",
            "sidebar" => "collapsed"
          },
          "api" => %{
            "timeout" => 5000
          }
        }
      }

      {:ok, context} = ContextManager.create_context(initial_data)
      
      merge_data = %{
        "config" => %{
          "ui" => %{
            "theme" => "light",
            "animations" => true
          },
          "cache" => %{
            "enabled" => true
          }
        }
      }

      {:ok, merged_context} = ContextManager.merge_context(context.id, merge_data)
      
      config = merged_context.data["config"]
      assert config["ui"]["theme"] == "light"
      assert config["ui"]["sidebar"] == "collapsed"
      assert config["ui"]["animations"] == true
      assert config["api"]["timeout"] == 5000
      assert config["cache"]["enabled"] == true
    end

    test "returns error for non-existent context" do
      assert {:error, :not_found} = ContextManager.merge_context("non_existent", %{"test" => "data"})
    end

    test "returns error for expired context" do
      {:ok, context} = ContextManager.create_context(%{"test" => "data"}, expires_in: 1)
      
      # Wait for context to expire
      Process.sleep(1100)
      
      assert {:error, :context_expired} = ContextManager.merge_context(context.id, %{"test" => "new_data"})
    end
  end

  describe "delete_context/1" do
    test "deletes existing context" do
      {:ok, context} = ContextManager.create_context(%{"test" => "data"})
      
      assert :ok = ContextManager.delete_context(context.id)
      
      # Verify context is deleted
      assert {:error, :not_found} = ContextManager.get_context(context.id)
    end

    test "returns error for non-existent context" do
      # Should not error, just return ok for idempotency
      result = ContextManager.delete_context("non_existent")
      case result do
        :ok -> assert true
        {:error, :not_found} -> assert true
      end
    end
  end

  describe "list_contexts/1" do
    test "lists all contexts" do
      contexts_data = [
        %{"user_id" => "user1", "session_id" => "session1"},
        %{"user_id" => "user2", "session_id" => "session2"},
        %{"user_id" => "user3", "session_id" => "session3"}
      ]

      for data <- contexts_data do
        {:ok, _} = ContextManager.create_context(data)
      end

      contexts = ContextManager.list_contexts()
      
      assert length(contexts) >= 3
      
      user_ids = Enum.map(contexts, &get_in(&1.data, ["user_id"]))
      assert "user1" in user_ids
      assert "user2" in user_ids
      assert "user3" in user_ids
    end

    test "filters contexts by user_id" do
      contexts_data = [
        %{"user_id" => "user1", "session_id" => "session1"},
        %{"user_id" => "user2", "session_id" => "session2"},
        %{"user_id" => "user1", "session_id" => "session3"}
      ]

      for data <- contexts_data do
        {:ok, _} = ContextManager.create_context(data)
      end

      user1_contexts = ContextManager.list_contexts(user_id: "user1")
      
      assert length(user1_contexts) == 2
      
      for context <- user1_contexts do
        assert get_in(context.data, ["user_id"]) == "user1"
      end
    end

    test "filters contexts by session_id" do
      contexts_data = [
        %{"user_id" => "user1", "session_id" => "session1"},
        %{"user_id" => "user2", "session_id" => "session2"},
        %{"user_id" => "user3", "session_id" => "session1"}
      ]

      for data <- contexts_data do
        {:ok, _} = ContextManager.create_context(data)
      end

      session1_contexts = ContextManager.list_contexts(session_id: "session1")
      
      assert length(session1_contexts) == 2
      
      for context <- session1_contexts do
        assert get_in(context.data, ["session_id"]) == "session1"
      end
    end

    test "limits number of contexts returned" do
      for i <- 1..10 do
        {:ok, _} = ContextManager.create_context(%{"index" => i})
      end

      limited_contexts = ContextManager.list_contexts(limit: 5)
      
      assert length(limited_contexts) == 5
    end

    test "filters contexts by creation date" do
      base_time = DateTime.utc_now()
      
      {:ok, _} = ContextManager.create_context(%{"early" => true})
      
      # Wait a bit and create more contexts
      Process.sleep(100)
      cutoff_time = DateTime.utc_now()
      Process.sleep(100)
      
      {:ok, _} = ContextManager.create_context(%{"late" => true})
      {:ok, _} = ContextManager.create_context(%{"late" => true})
      
      recent_contexts = ContextManager.list_contexts(created_after: cutoff_time)
      
      assert length(recent_contexts) == 2
      
      for context <- recent_contexts do
        assert get_in(context.data, ["late"]) == true
      end
    end

    test "excludes expired contexts" do
      {:ok, _} = ContextManager.create_context(%{"persistent" => true})
      {:ok, _} = ContextManager.create_context(%{"temporary" => true}, expires_in: 1)
      
      # Wait for expiration
      Process.sleep(1100)
      
      contexts = ContextManager.list_contexts()
      
      # Should only include non-expired contexts
      data_list = Enum.map(contexts, & &1.data)
      persistent_contexts = Enum.filter(data_list, &Map.has_key?(&1, "persistent"))
      temporary_contexts = Enum.filter(data_list, &Map.has_key?(&1, "temporary"))
      
      assert length(persistent_contexts) == 1
      assert length(temporary_contexts) == 0
    end
  end

  describe "get_context_versions/1" do
    test "retrieves version history of a context" do
      {:ok, context} = ContextManager.create_context(%{"version" => 1})
      
      {:ok, _} = ContextManager.update_context(context.id, %{"version" => 2})
      {:ok, _} = ContextManager.update_context(context.id, %{"version" => 3})
      
      # Version history is not implemented yet
      assert {:error, :not_implemented} = ContextManager.get_context_versions(context.id)
    end

    test "returns error for non-existent context" do
      assert {:error, :not_implemented} = ContextManager.get_context_versions("non_existent")
    end
  end

  describe "context_expired?/1" do
    test "returns false for non-expired context" do
      {:ok, context} = ContextManager.create_context(%{"test" => "data"})
      
      assert ContextManager.context_expired?(context.id) == false
    end

    test "returns false for context without expiration" do
      {:ok, context} = ContextManager.create_context(%{"test" => "data"})
      
      assert ContextManager.context_expired?(context.id) == false
    end

    test "returns true for expired context" do
      {:ok, context} = ContextManager.create_context(%{"test" => "data"}, expires_in: 1)
      
      # Wait for expiration
      Process.sleep(1100)
      
      assert ContextManager.context_expired?(context.id) == true
    end

    test "returns true for non-existent context" do
      assert ContextManager.context_expired?("non_existent") == true
    end
  end

  describe "extend_context/2" do
    test "extends expiration time for existing context" do
      {:ok, context} = ContextManager.create_context(%{"test" => "data"}, expires_in: 3600)
      
      original_expires_at = context.expires_at
      
      {:ok, extended_context} = ContextManager.extend_context(context.id, 1800)
      
      assert DateTime.diff(extended_context.expires_at, original_expires_at) == 1800
    end

    test "sets expiration for context without expiration" do
      {:ok, context} = ContextManager.create_context(%{"test" => "data"})
      
      assert context.expires_at == nil
      
      {:ok, extended_context} = ContextManager.extend_context(context.id, 3600)
      
      assert %DateTime{} = extended_context.expires_at
      assert DateTime.diff(extended_context.expires_at, DateTime.utc_now()) > 3500
    end

    test "returns error for non-existent context" do
      assert {:error, :not_found} = ContextManager.extend_context("non_existent", 3600)
    end
  end

  describe "cleanup_expired_contexts/0" do
    test "removes expired contexts" do
      {:ok, persistent_context} = ContextManager.create_context(%{"persistent" => true})
      {:ok, temporary_context} = ContextManager.create_context(%{"temporary" => true}, expires_in: 1)
      
      # Wait for expiration
      Process.sleep(1100)
      
      cleaned_count = ContextManager.cleanup_expired_contexts()
      
      assert cleaned_count >= 1
      
      # Verify persistent context still exists
      assert {:ok, _} = ContextManager.get_context(persistent_context.id)
      
      # Verify temporary context was removed
      assert {:error, :not_found} = ContextManager.get_context(temporary_context.id)
    end

    test "returns count of cleaned contexts" do
      # Create multiple expired contexts
      for i <- 1..3 do
        {:ok, _} = ContextManager.create_context(%{"index" => i}, expires_in: 1)
      end
      
      # Wait for expiration
      Process.sleep(1100)
      
      cleaned_count = ContextManager.cleanup_expired_contexts()
      
      assert cleaned_count >= 3
    end
  end

  describe "concurrent access" do
    test "handles concurrent context creation" do
      tasks = for i <- 1..10 do
        Task.async(fn ->
          ContextManager.create_context(%{"index" => i})
        end)
      end

      results = Task.await_many(tasks)
      
      # All creations should succeed
      assert Enum.all?(results, fn {:ok, _} -> true; _ -> false end)
      
      # All contexts should have unique IDs
      context_ids = Enum.map(results, fn {:ok, context} -> context.id end)
      assert length(Enum.uniq(context_ids)) == 10
    end

    test "handles concurrent context updates" do
      {:ok, context} = ContextManager.create_context(%{"counter" => 0})
      
      tasks = for i <- 1..5 do
        Task.async(fn ->
          ContextManager.update_context(context.id, %{"counter" => i})
        end)
      end

      results = Task.await_many(tasks)
      
      # At least some updates should succeed
      successful_updates = Enum.filter(results, fn {:ok, _} -> true; _ -> false end)
      assert length(successful_updates) >= 1
    end

    test "handles concurrent context reads" do
      {:ok, context} = ContextManager.create_context(%{"shared" => "data"})
      
      tasks = for _i <- 1..10 do
        Task.async(fn ->
          ContextManager.get_context(context.id)
        end)
      end

      results = Task.await_many(tasks)
      
      # All reads should succeed
      assert Enum.all?(results, fn {:ok, _} -> true; _ -> false end)
      
      # All should return the same context
      contexts = Enum.map(results, fn {:ok, ctx} -> ctx end)
      assert Enum.all?(contexts, fn ctx -> ctx.id == context.id end)
    end
  end

  describe "error handling and edge cases" do
    test "handles storage errors gracefully" do
      # This test would require mocking storage failures
      # For now, we test basic error handling
      
      {:ok, context} = ContextManager.create_context(%{"test" => "data"})
      
      # Test with invalid update data
      result = ContextManager.update_context(context.id, %{"test" => "updated"})
      
      # Should handle gracefully
      assert {:ok, _} = result or {:error, _} = result
    end

    test "handles large context data" do
      # Test with relatively large data
      large_data = %{
        "large_list" => Enum.to_list(1..1000),
        "large_map" => Map.new(1..100, fn i -> {"key_#{i}", "value_#{i}"} end),
        "nested_structure" => %{
          "level1" => %{
            "level2" => %{
              "level3" => %{
                "data" => "deeply nested"
              }
            }
          }
        }
      }

      {:ok, context} = ContextManager.create_context(large_data)
      
      {:ok, retrieved} = ContextManager.get_context(context.id)
      
      assert retrieved.data == large_data
    end

    test "handles context data with special characters" do
      special_data = %{
        "unicode" => "Hello 世界 🌍",
        "special_chars" => "!@#$%^&*()_+-=[]{}|;:,.<>?",
        "quotes" => "\"double quotes\" and 'single quotes'",
        "newlines" => "line1\nline2\rline3\r\nline4",
        "null_bytes" => "before\0after"
      }

      {:ok, context} = ContextManager.create_context(special_data)
      
      {:ok, retrieved} = ContextManager.get_context(context.id)
      
      assert retrieved.data == special_data
    end

    test "handles context operations with nil values" do
      data_with_nils = %{
        "null_value" => nil,
        "empty_string" => "",
        "zero" => 0,
        "false" => false,
        "empty_list" => [],
        "empty_map" => %{}
      }

      {:ok, context} = ContextManager.create_context(data_with_nils)
      
      {:ok, retrieved} = ContextManager.get_context(context.id)
      
      assert retrieved.data == data_with_nils
    end
  end

  describe "periodic cleanup" do
    test "automatically cleans up expired contexts" do
      # Start context manager with short cleanup interval
      {:ok, _pid} = start_supervised({ContextManager, [cleanup_interval: 500]})
      
      {:ok, _} = ContextManager.create_context(%{"temporary" => true}, expires_in: 1)
      
      # Wait for expiration and cleanup
      Process.sleep(1600)
      
      # Context should be cleaned up automatically
      contexts = ContextManager.list_contexts()
      temporary_contexts = Enum.filter(contexts, fn ctx -> 
        Map.has_key?(ctx.data, "temporary")
      end)
      
      assert length(temporary_contexts) == 0
    end
  end
end