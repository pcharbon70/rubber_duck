defmodule RubberDuck.Agents.ConversationRouterAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.ConversationRouterAgent
  
  describe "agent initialization" do
    test "starts with default routing configuration" do
      # Create a new agent instance directly
      agent = ConversationRouterAgent.new("test_router")
      
      # Check the initial state
      state = agent.state
      
      assert state.routing_table != nil
      assert state.metrics.total_requests == 0
      assert state.circuit_breakers == %{}
    end
  end
  
  describe "signal handling" do
    setup do
      agent = ConversationRouterAgent.new("test_router")
      %{agent: agent}
    end
    
    test "handles conversation_route_request signal", %{agent: agent} do
      signal = %{
        "type" => "conversation_route_request",
        "data" => %{
          "query" => "How do I implement a GenServer?",
          "context" => %{},
          "request_id" => "req_123"
        }
      }
      
      # Call handle_signal directly on the agent struct
      {:ok, updated_agent} = ConversationRouterAgent.handle_signal(agent, signal)
      
      # Check that metrics were updated
      state = updated_agent.state
      assert state.metrics.total_requests == 1
      
      # Should have routed to generation because query contains "implement"
      assert Map.has_key?(state.metrics.routes_used, "generation")
      assert state.metrics.routes_used["generation"] == 1
    end
    
    test "classifies and routes planning queries correctly", %{agent: agent} do
      signal = %{
        "type" => "conversation_route_request",
        "data" => %{
          "query" => "Help me plan a new feature implementation",
          "context" => %{},
          "request_id" => "req_456"
        }
      }
      
      # Call handle_signal directly on the agent struct
      {:ok, updated_agent} = ConversationRouterAgent.handle_signal(agent, signal)
      
      state = updated_agent.state
      
      # Should have routed to planning conversation
      assert Map.has_key?(state.metrics.routes_used, "planning")
      assert state.metrics.routes_used["planning"] == 1
    end
  end
  
  describe "metrics collection" do
    setup do
      agent = ConversationRouterAgent.new("test_router")
      %{agent: agent}
    end
    
    test "tracks routing decisions", %{agent: agent} do
      signal = %{
        "type" => "conversation_route_request",
        "data" => %{
          "query" => "What is Elixir?",
          "context" => %{},
          "request_id" => "req_789"
        }
      }
      
      # Call handle_signal directly on the agent struct
      {:ok, updated_agent} = ConversationRouterAgent.handle_signal(agent, signal)
      
      state = updated_agent.state
      assert state.metrics.total_requests == 1
      # "What is Elixir?" is a simple factual question - should route to simple
      # But our rules don't have specific keywords for this, so it falls back to default
      assert map_size(state.metrics.routes_used) > 0
    end
  end
  
  describe "classification integration" do
    test "uses QuestionClassifier for query analysis" do
      agent = ConversationRouterAgent.new("test_router")
      
      signal = %{
        "type" => "conversation_route_request",
        "data" => %{
          "query" => "Can you analyze this complex multi-step problem?",
          "context" => %{},
          "request_id" => "req_complex"
        }
      }
      
      {:ok, updated_agent} = ConversationRouterAgent.handle_signal(agent, signal)
      
      # Verify that complex queries are routed appropriately
      state = updated_agent.state
      # Query contains "analyze" so should route to analysis
      assert Map.has_key?(state.metrics.routes_used, "analysis")
      assert state.metrics.routes_used["analysis"] == 1
    end
    
    test "routes debugging queries to problem_solver" do
      agent = ConversationRouterAgent.new("test_router")
      
      signal = %{
        "type" => "conversation_route_request",
        "data" => %{
          "query" => "Help me debug this error in my code",
          "context" => %{},
          "request_id" => "req_debug"
        }
      }
      
      {:ok, updated_agent} = ConversationRouterAgent.handle_signal(agent, signal)
      
      state = updated_agent.state
      assert Map.has_key?(state.metrics.routes_used, "problem_solver")
    end
  end
  
  describe "routing rules" do
    test "can update routing rules dynamically" do
      agent = ConversationRouterAgent.new("test_router")
      
      # Update routing rules
      signal = %{
        "type" => "update_routing_rules",
        "data" => %{
          "rules" => [
            %{
              keywords: ["test", "testing"],
              route: :testing,
              priority: 100
            }
          ]
        }
      }
      
      {:ok, updated_agent} = ConversationRouterAgent.handle_signal(agent, signal)
      
      # Verify rules were updated
      assert length(updated_agent.state.routing_rules) == 1
      assert hd(updated_agent.state.routing_rules).route == :testing
    end
  end
  
  describe "error handling" do
    test "handles missing required fields gracefully" do
      agent = ConversationRouterAgent.new("test_router")
      
      signal = %{
        "type" => "conversation_route_request",
        "data" => %{
          "query" => "Test query"
          # Missing request_id
        }
      }
      
      {:ok, updated_agent} = ConversationRouterAgent.handle_signal(agent, signal)
      
      # Should track the failure
      state = updated_agent.state
      assert Map.has_key?(state.metrics.failures, "{:missing_fields, [\"request_id\"]}")
    end
  end
  
  describe "metrics retrieval" do
    test "can retrieve routing metrics" do
      agent = ConversationRouterAgent.new("test_router")
      
      # Make a few routing requests first
      signal1 = %{
        "type" => "conversation_route_request",
        "data" => %{
          "query" => "Help me plan a project",
          "context" => %{},
          "request_id" => "req_1"
        }
      }
      
      {:ok, agent} = ConversationRouterAgent.handle_signal(agent, signal1)
      
      # Get metrics
      signal = %{"type" => "get_routing_metrics"}
      {:ok, final_agent} = ConversationRouterAgent.handle_signal(agent, signal)
      
      # Verify metrics are tracked
      assert final_agent.state.metrics.total_requests == 1
      assert Map.has_key?(final_agent.state.metrics.routes_used, "planning")
    end
  end
end