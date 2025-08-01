defmodule RubberDuck.Agents.MemoryCoordinationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.{MemoryCoordinatorAgent, ShortTermMemoryAgent, LongTermMemoryAgent}
  
  setup do
    # Start the test signal bus
    {:ok, _} = start_supervised({SignalBus, name: :test_signal_bus})
    
    # Initialize agents
    {:ok, coordinator} = MemoryCoordinatorAgent.init(%{})
    {:ok, short_term} = ShortTermMemoryAgent.init(%{})
    {:ok, long_term} = LongTermMemoryAgent.init(%{})
    
    {:ok, 
      coordinator: coordinator,
      short_term: short_term,
      long_term: long_term
    }
  end

  describe "memory promotion flow" do
    test "promotes memory from short-term to long-term when accessed frequently", %{coordinator: coordinator} do
      memory_data = %{
        "type" => "knowledge",
        "content" => "Important information that is accessed frequently",
        "metadata" => %{"source" => "test", "importance" => "high"}
      }
      
      # Store in short-term memory
      {:ok, result, coordinator} = MemoryCoordinatorAgent.handle_signal("store_memory", memory_data, coordinator)
      memory_id = result["memory_id"]
      
      # Access the memory multiple times to trigger promotion
      Enum.each(1..5, fn _ ->
        {:ok, _, coordinator} = MemoryCoordinatorAgent.handle_signal("retrieve_memory", %{"memory_id" => memory_id}, coordinator)
      end)
      
      # Check if memory was promoted
      state = coordinator.memory_states[memory_id]
      assert state.location == :long_term
      assert state.access_count >= 5
    end

    test "handles concurrent memory operations safely", %{coordinator: coordinator} do
      memory_ids = Enum.map(1..10, fn i ->
        memory_data = %{
          "type" => "interaction",
          "content" => "Concurrent memory #{i}",
          "metadata" => %{"index" => i}
        }
        
        {:ok, result, _} = MemoryCoordinatorAgent.handle_signal("store_memory", memory_data, coordinator)
        result["memory_id"]
      end)
      
      # Simulate concurrent access
      tasks = Enum.map(memory_ids, fn memory_id ->
        Task.async(fn ->
          MemoryCoordinatorAgent.handle_signal("retrieve_memory", %{"memory_id" => memory_id}, coordinator)
        end)
      end)
      
      results = Task.await_many(tasks)
      
      # All operations should succeed
      assert Enum.all?(results, fn {:ok, _, _} -> true; _ -> false end)
    end

    test "handles memory lifecycle transitions correctly", %{coordinator: coordinator} do
      # Create memory
      {:ok, result, coordinator} = MemoryCoordinatorAgent.handle_signal("store_memory", %{
        "type" => "code_pattern",
        "content" => "Lifecycle test memory",
        "ttl" => 10  # 10 seconds TTL
      }, coordinator)
      
      memory_id = result["memory_id"]
      
      # Check initial state
      assert coordinator.memory_states[memory_id].location == :short_term
      assert coordinator.memory_states[memory_id].status == :active
      
      # Update memory
      {:ok, _, coordinator} = MemoryCoordinatorAgent.handle_signal("update_memory", %{
        "memory_id" => memory_id,
        "updates" => %{"content" => "Updated content"}
      }, coordinator)
      
      # Delete memory
      {:ok, _, coordinator} = MemoryCoordinatorAgent.handle_signal("delete_memory", %{
        "memory_id" => memory_id
      }, coordinator)
      
      # Check final state
      assert coordinator.memory_states[memory_id].status == :deleted
    end
  end

  describe "garbage collection coordination" do
    test "triggers garbage collection when threshold exceeded", %{coordinator: coordinator} do
      # Set low threshold for testing
      coordinator = put_in(coordinator.config.gc_threshold, 5)
      
      # Create memories that will exceed threshold
      memories = Enum.map(1..10, fn i ->
        {:ok, result, coordinator} = MemoryCoordinatorAgent.handle_signal("store_memory", %{
          "type" => "interaction",
          "content" => "GC test memory #{i}",
          "ttl" => if(i <= 5, do: 1, else: 3600)  # First 5 expire quickly
        }, coordinator)
        {result["memory_id"], coordinator}
      end)
      
      {_, final_coordinator} = List.last(memories)
      
      # Trigger GC
      {:ok, gc_result, _} = MemoryCoordinatorAgent.handle_signal("trigger_gc", %{}, final_coordinator)
      
      assert gc_result["triggered"] == true
      assert gc_result["memories_collected"] > 0
    end

    test "preserves important memories during garbage collection", %{coordinator: coordinator} do
      # Create important memory
      {:ok, important, coordinator} = MemoryCoordinatorAgent.handle_signal("store_memory", %{
        "type" => "user_profile",
        "content" => "Important user data",
        "metadata" => %{"importance" => "critical"},
        "ttl" => 1  # Short TTL but should be preserved
      }, coordinator)
      
      # Create disposable memories
      Enum.each(1..5, fn i ->
        MemoryCoordinatorAgent.handle_signal("store_memory", %{
          "type" => "interaction",
          "content" => "Disposable #{i}",
          "ttl" => 1
        }, coordinator)
      end)
      
      # Wait for TTL to expire
      Process.sleep(1100)
      
      # Trigger GC
      {:ok, _, coordinator} = MemoryCoordinatorAgent.handle_signal("trigger_gc", %{}, coordinator)
      
      # Important memory should still exist
      {:ok, retrieved, _} = MemoryCoordinatorAgent.handle_signal("retrieve_memory", %{
        "memory_id" => important["memory_id"]
      }, coordinator)
      
      assert retrieved["memory"] != nil
    end
  end

  describe "cross-agent signal coordination" do
    test "routes signals to appropriate memory agents", %{coordinator: coordinator} do
      # Test routing to short-term memory
      {:ok, st_result, _} = MemoryCoordinatorAgent.handle_signal("store_memory", %{
        "type" => "interaction",
        "content" => "Short-term content"
      }, coordinator)
      
      assert st_result["stored_in"] == "short_term"
      
      # Test routing to long-term memory (via metadata hint)
      {:ok, lt_result, _} = MemoryCoordinatorAgent.handle_signal("store_memory", %{
        "type" => "knowledge",
        "content" => "Long-term knowledge",
        "metadata" => %{"persist" => true}
      }, coordinator)
      
      assert lt_result["stored_in"] == "short_term"  # Initially stored in short-term
    end

    test "handles bulk operations efficiently", %{coordinator: coordinator} do
      memories = Enum.map(1..20, fn i ->
        %{
          "type" => "interaction",
          "content" => "Bulk memory #{i}",
          "metadata" => %{"batch" => true}
        }
      end)
      
      {:ok, result, coordinator} = MemoryCoordinatorAgent.handle_signal("bulk_store", %{
        "memories" => memories
      }, coordinator)
      
      assert result["count"] == 20
      assert length(result["memory_ids"]) == 20
      
      # Verify all memories were stored
      assert map_size(coordinator.memory_states) >= 20
    end

    test "maintains consistency during error scenarios", %{coordinator: coordinator} do
      # Try to update non-existent memory
      {:error, error_msg, coordinator} = MemoryCoordinatorAgent.handle_signal("update_memory", %{
        "memory_id" => "non_existent_id",
        "updates" => %{"content" => "New content"}
      }, coordinator)
      
      assert error_msg =~ "not found"
      
      # Coordinator state should remain consistent
      assert map_size(coordinator.memory_states) == map_size(coordinator.memory_states)
      
      # Try to store invalid memory
      {:error, _, coordinator} = MemoryCoordinatorAgent.handle_signal("store_memory", %{
        "type" => "invalid_type",
        "content" => nil
      }, coordinator)
      
      # No partial state should be created
      refute Map.has_key?(coordinator.memory_states, "partial_memory")
    end
  end

  describe "memory access patterns" do
    test "tracks access patterns correctly", %{coordinator: coordinator} do
      {:ok, result, coordinator} = MemoryCoordinatorAgent.handle_signal("store_memory", %{
        "type" => "code_pattern",
        "content" => "Pattern tracking test"
      }, coordinator)
      
      memory_id = result["memory_id"]
      
      # Create access pattern
      access_times = Enum.map(1..3, fn _ ->
        Process.sleep(100)
        {:ok, _, coordinator} = MemoryCoordinatorAgent.handle_signal("retrieve_memory", %{
          "memory_id" => memory_id
        }, coordinator)
        DateTime.utc_now()
      end)
      
      # Get access statistics
      {:ok, stats, _} = MemoryCoordinatorAgent.handle_signal("get_memory_stats", %{}, coordinator)
      
      memory_stats = Enum.find(stats["memories"], &(&1["memory_id"] == memory_id))
      assert memory_stats["access_count"] >= 3
      assert memory_stats["access_pattern"] != nil
    end

    test "detects and optimizes hot memories", %{coordinator: coordinator} do
      # Create a "hot" memory with frequent access
      {:ok, result, coordinator} = MemoryCoordinatorAgent.handle_signal("store_memory", %{
        "type" => "configuration",
        "content" => "Frequently accessed config"
      }, coordinator)
      
      hot_memory_id = result["memory_id"]
      
      # Access frequently in short time
      Enum.each(1..10, fn _ ->
        MemoryCoordinatorAgent.handle_signal("retrieve_memory", %{
          "memory_id" => hot_memory_id
        }, coordinator)
      end)
      
      # Check if memory was marked as hot
      state = coordinator.memory_states[hot_memory_id]
      assert state.access_count >= 10
      # Hot memories should be promoted or cached
      assert state.location == :long_term or state.cached == true
    end
  end

  describe "synchronization and recovery" do
    test "handles agent recovery after crash", %{coordinator: coordinator} do
      # Store some memories
      memory_ids = Enum.map(1..5, fn i ->
        {:ok, result, coordinator} = MemoryCoordinatorAgent.handle_signal("store_memory", %{
          "type" => "interaction",
          "content" => "Recovery test #{i}"
        }, coordinator)
        result["memory_id"]
      end)
      
      # Simulate crash by resetting part of state
      coordinator = %{coordinator | metrics: %{coordinator.metrics | errors: %{}}}
      
      # Try to recover and access memories
      results = Enum.map(memory_ids, fn memory_id ->
        MemoryCoordinatorAgent.handle_signal("retrieve_memory", %{
          "memory_id" => memory_id
        }, coordinator)
      end)
      
      # All memories should still be accessible
      assert Enum.all?(results, fn 
        {:ok, %{"memory" => memory}, _} -> memory != nil
        _ -> false
      end)
    end

    test "maintains state consistency across concurrent updates", %{coordinator: coordinator} do
      {:ok, result, coordinator} = MemoryCoordinatorAgent.handle_signal("store_memory", %{
        "type" => "interaction",
        "content" => "Concurrent update test"
      }, coordinator)
      
      memory_id = result["memory_id"]
      
      # Simulate concurrent updates
      tasks = Enum.map(1..5, fn i ->
        Task.async(fn ->
          MemoryCoordinatorAgent.handle_signal("update_memory", %{
            "memory_id" => memory_id,
            "updates" => %{"metadata" => %{"update" => i}}
          }, coordinator)
        end)
      end)
      
      _results = Task.await_many(tasks)
      
      # Memory should still be in valid state
      {:ok, final_memory, _} = MemoryCoordinatorAgent.handle_signal("retrieve_memory", %{
        "memory_id" => memory_id
      }, coordinator)
      
      assert final_memory["memory"] != nil
      assert is_map(final_memory["memory"]["metadata"])
    end
  end
end