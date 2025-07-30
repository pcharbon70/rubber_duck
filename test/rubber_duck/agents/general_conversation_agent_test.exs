defmodule RubberDuck.Agents.GeneralConversationAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.GeneralConversationAgent
  
  describe "agent initialization" do
    test "starts with default conversation configuration" do
      agent = GeneralConversationAgent.new("test_general")
      
      state = agent.state
      
      assert state.active_conversations == %{}
      assert state.conversation_history == []
      assert state.metrics.total_conversations == 0
      assert state.response_strategies.simple == true
      assert state.conversation_config.max_history_length == 100
    end
  end
  
  describe "conversation handling" do
    setup do
      agent = GeneralConversationAgent.new("test_general")
      %{agent: agent}
    end
    
    test "handles conversation_request signal", %{agent: agent} do
      signal = %{
        "type" => "conversation_request",
        "data" => %{
          "query" => "What is Elixir?",
          "conversation_id" => "conv_123",
          "context" => %{"style" => "technical"},
          "provider" => "openai",
          "model" => "gpt-4",
          "user_id" => "user_123"
        }
      }
      
      {:ok, updated_agent} = GeneralConversationAgent.handle_signal(agent, signal)
      
      # Check that conversation was created
      assert Map.has_key?(updated_agent.state.active_conversations, "conv_123")
      conversation = updated_agent.state.active_conversations["conv_123"]
      assert conversation.id == "conv_123"
      assert conversation.last_query == "What is Elixir?"
    end
    
    test "detects when clarification is needed", %{agent: agent} do
      # Short ambiguous query
      signal = %{
        "type" => "conversation_request",
        "data" => %{
          "query" => "Tell me about it",
          "conversation_id" => "conv_456",
          "context" => %{},
          "provider" => "openai",
          "model" => "gpt-4",
          "user_id" => "user_123"
        }
      }
      
      {:ok, updated_agent} = GeneralConversationAgent.handle_signal(agent, signal)
      
      # Should have requested clarification
      assert updated_agent.state.metrics.clarifications_requested == 1
    end
    
    test "handles clarification_response signal", %{agent: agent} do
      signal = %{
        "type" => "clarification_response",
        "data" => %{
          "conversation_id" => "conv_789",
          "clarification" => "I meant Elixir programming language",
          "original_query" => "Tell me about it",
          "provider" => "openai",
          "model" => "gpt-4",
          "user_id" => "user_123"
        }
      }
      
      {:ok, _updated_agent} = GeneralConversationAgent.handle_signal(agent, signal)
      
      # Processing would happen asynchronously
    end
  end
  
  describe "context switching" do
    setup do
      agent = GeneralConversationAgent.new("test_general")
      
      # Create an active conversation
      agent = put_in(agent.state.active_conversations["conv_123"], %{
        id: "conv_123",
        context: %{"topic" => "elixir"},
        messages: [],
        created_at: System.monotonic_time(:millisecond),
        last_activity: System.monotonic_time(:millisecond)
      })
      
      %{agent: agent}
    end
    
    test "handles context_switch signal", %{agent: agent} do
      signal = %{
        "type" => "context_switch",
        "data" => %{
          "conversation_id" => "conv_123",
          "new_context" => %{"topic" => "phoenix"},
          "preserve_history" => true
        }
      }
      
      {:ok, updated_agent} = GeneralConversationAgent.handle_signal(agent, signal)
      
      # Check context was switched
      conversation = updated_agent.state.active_conversations["conv_123"]
      assert conversation.context == %{"topic" => "phoenix"}
      
      # Check old context was saved to stack
      assert length(updated_agent.state.context_stack) == 1
      assert hd(updated_agent.state.context_stack) == %{"topic" => "elixir"}
      
      # Check metrics
      assert updated_agent.state.metrics.context_switches == 1
    end
    
    test "handles context switch without preserving history", %{agent: agent} do
      signal = %{
        "type" => "context_switch",
        "data" => %{
          "conversation_id" => "conv_123",
          "new_context" => %{"topic" => "otp"},
          "preserve_history" => false
        }
      }
      
      {:ok, updated_agent} = GeneralConversationAgent.handle_signal(agent, signal)
      
      # Context stack should remain empty
      assert updated_agent.state.context_stack == []
    end
  end
  
  describe "metrics tracking" do
    test "returns comprehensive metrics" do
      agent = GeneralConversationAgent.new("test_general")
      
      # Add some test data
      agent = agent
      |> put_in([:state, :active_conversations, "conv_1"], %{messages: [1, 2, 3]})
      |> put_in([:state, :active_conversations, "conv_2"], %{messages: [1, 2]})
      |> put_in([:state, :metrics, :total_conversations], 10)
      
      signal = %{"type" => "get_conversation_metrics"}
      {:ok, _} = GeneralConversationAgent.handle_signal(agent, signal)
      
      # Would verify the emitted signal in a real test
    end
  end
  
  describe "response strategies" do
    test "can be initialized with custom strategies" do
      agent = GeneralConversationAgent.new("test_general", %{
        response_strategies: %{
          simple: false,
          detailed: true,
          technical: true,
          casual: false
        }
      })
      
      strategies = agent.state.response_strategies
      assert strategies.simple == false
      assert strategies.detailed == true
      assert strategies.technical == true
      assert strategies.casual == false
    end
  end
  
  describe "conversation configuration" do
    test "can be initialized with custom config" do
      agent = GeneralConversationAgent.new("test_general", %{
        conversation_config: %{
          max_history_length: 50,
          context_timeout_ms: 600_000,  # 10 minutes
          enable_learning: false,
          enable_personalization: true
        }
      })
      
      config = agent.state.conversation_config
      assert config.max_history_length == 50
      assert config.context_timeout_ms == 600_000
      assert config.enable_learning == false
      assert config.enable_personalization == true
    end
  end
  
  describe "error handling" do
    test "handles unknown signals gracefully" do
      agent = GeneralConversationAgent.new("test_general")
      
      signal = %{
        "type" => "unknown_signal",
        "data" => %{}
      }
      
      {:ok, unchanged_agent} = GeneralConversationAgent.handle_signal(agent, signal)
      
      assert unchanged_agent == agent
    end
    
    test "handles missing conversation_id gracefully" do
      agent = GeneralConversationAgent.new("test_general")
      
      signal = %{
        "type" => "context_switch",
        "data" => %{
          "conversation_id" => "non_existent",
          "new_context" => %{},
          "preserve_history" => true
        }
      }
      
      {:ok, unchanged_agent} = GeneralConversationAgent.handle_signal(agent, signal)
      
      # Should handle gracefully without errors
      assert unchanged_agent == agent
    end
  end
  
  describe "topic detection" do
    test "creates new conversation when none exists", %{agent: agent} do
      signal = %{
        "type" => "conversation_request",
        "data" => %{
          "query" => "Let's talk about distributed systems",
          "conversation_id" => "conv_new",
          "context" => %{},
          "provider" => "openai",
          "model" => "gpt-4",
          "user_id" => "user_123"
        }
      }
      
      {:ok, updated_agent} = GeneralConversationAgent.handle_signal(agent, signal)
      
      conversation = updated_agent.state.active_conversations["conv_new"]
      assert conversation != nil
      assert conversation.messages == []
    end
  end
end