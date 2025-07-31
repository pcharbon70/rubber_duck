defmodule RubberDuck.Agents.ShortTermMemoryAgentTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Agents.ShortTermMemoryAgent
  
  describe "ShortTermMemoryAgent" do
    test "agent starts successfully with proper state" do
      {:ok, agent_pid} = start_supervised({ShortTermMemoryAgent, id: "test_stm_agent"})
      
      # Verify agent state structure
      state = ShortTermMemoryAgent.get_state(agent_pid)
      assert state.memory_store == %{}
      assert state.indexes == %{}
      assert state.metrics.total_items == 0
      assert state.metrics.cache_hits == 0
      assert state.metrics.cache_misses == 0
    end
    
    test "stores and retrieves memory items with fast access" do
      {:ok, agent_pid} = start_supervised({ShortTermMemoryAgent, id: "stm_test"})
      
      memory_item = %{
        user_id: "user123",
        session_id: "session456", 
        content: "test memory content",
        type: :chat,
        metadata: %{important: true}
      }
      
      # Store memory item
      {:ok, result} = ShortTermMemoryAgent.store_memory(agent_pid, memory_item)
      assert result.stored == true
      assert is_binary(result.item_id)
      
      # Retrieve memory item
      {:ok, retrieved} = ShortTermMemoryAgent.get_memory(agent_pid, %{item_id: result.item_id})
      assert retrieved.content == "test memory content"
      assert retrieved.type == :chat
      assert retrieved.metadata.important == true
    end
    
    test "implements TTL expiration and cleanup" do
      {:ok, agent} = ShortTermMemoryAgent.start_link(
        id: "ttl_test",
        ttl_seconds: 1  # 1 second TTL for testing
      )
      
      memory_item = %{
        user_id: "user123",
        session_id: "session456",
        content: "expiring content"
      }
      
      # Store item
      {:ok, result} = ShortTermMemoryAgent.cmd(agent, :store_memory, memory_item)
      item_id = result.item_id
      
      # Item should exist immediately
      {:ok, retrieved} = ShortTermMemoryAgent.cmd(agent, :get_memory, %{item_id: item_id})
      assert retrieved.content == "expiring content"
      
      # Wait for expiration
      :timer.sleep(1100)
      
      # Trigger cleanup
      {:ok, _} = ShortTermMemoryAgent.cmd(agent, :cleanup_expired, %{})
      
      # Item should be expired
      {:error, :not_found} = ShortTermMemoryAgent.cmd(agent, :get_memory, %{item_id: item_id})
    end
    
    test "provides efficient search by user and session" do
      {:ok, agent} = ShortTermMemoryAgent.start_link(id: "search_test")
      
      # Store multiple items for different users/sessions
      items = [
        %{user_id: "user1", session_id: "session1", content: "user1 content1"},
        %{user_id: "user1", session_id: "session1", content: "user1 content2"},
        %{user_id: "user1", session_id: "session2", content: "user1 session2"},
        %{user_id: "user2", session_id: "session1", content: "user2 content"}
      ]
      
      # Store all items
      for item <- items do
        {:ok, _} = ShortTermMemoryAgent.cmd(agent, :store_memory, item)
      end
      
      # Search by user
      {:ok, user1_items} = ShortTermMemoryAgent.cmd(agent, :search_by_user, %{user_id: "user1"})
      assert length(user1_items) == 3
      
      # Search by session
      {:ok, session1_items} = ShortTermMemoryAgent.cmd(agent, :search_by_session, %{
        user_id: "user1", 
        session_id: "session1"
      })
      assert length(session1_items) == 2
    end
    
    test "tracks analytics and metrics" do
      {:ok, agent} = ShortTermMemoryAgent.start_link(id: "analytics_test")
      
      # Store some items to generate metrics
      for i <- 1..5 do
        memory_item = %{
          user_id: "user#{i}",
          session_id: "session1",
          content: "content #{i}"
        }
        {:ok, _} = ShortTermMemoryAgent.cmd(agent, :store_memory, memory_item)
      end
      
      # Get analytics
      {:ok, analytics} = ShortTermMemoryAgent.cmd(agent, :get_analytics, %{})
      
      assert analytics.total_items == 5
      assert analytics.memory_usage_bytes > 0
      assert is_number(analytics.avg_item_size)
      assert is_list(analytics.access_patterns)
    end
    
    test "integrates with Memory.Interaction resource" do
      {:ok, agent} = ShortTermMemoryAgent.start_link(id: "integration_test")
      
      memory_item = %{
        user_id: "integration_user",
        session_id: "integration_session",
        type: :chat,
        content: "integration test content",
        metadata: %{source: "test"}
      }
      
      # Store with persistence to Ash resource
      {:ok, result} = ShortTermMemoryAgent.cmd(agent, :store_with_persistence, memory_item)
      
      assert result.stored_in_memory == true
      assert result.persisted_to_ash == true
      assert is_binary(result.ash_record_id)
    end
  end
end