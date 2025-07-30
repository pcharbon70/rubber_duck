defmodule RubberDuck.Agents.PlanningConversationAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.PlanningConversationAgent
  
  describe "agent initialization" do
    test "starts with default planning configuration" do
      agent = PlanningConversationAgent.new("test_planner")
      
      state = agent.state
      
      assert state.conversation_state == :idle
      assert state.active_conversations == %{}
      assert state.metrics.total_plans_created == 0
    end
  end
  
  describe "plan creation signals" do
    setup do
      agent = PlanningConversationAgent.new("test_planner")
      %{agent: agent}
    end
    
    test "handles plan_creation_request signal", %{agent: agent} do
      signal = %{
        "type" => "plan_creation_request",
        "data" => %{
          "query" => "Create a plan to implement user authentication",
          "context" => %{"language" => "elixir"},
          "conversation_id" => "conv_123",
          "user_id" => "user_456"
        }
      }
      
      {:ok, updated_agent} = PlanningConversationAgent.handle_signal(agent, signal)
      
      # Check that conversation was started
      state = updated_agent.state
      assert Map.has_key?(state.active_conversations, "conv_123")
      assert state.active_conversations["conv_123"].status == :extracting_plan
    end
    
    test "handles plan validation signals", %{agent: agent} do
      # First create a plan
      plan_signal = %{
        "type" => "plan_creation_request",
        "data" => %{
          "query" => "Create a plan to refactor the database module",
          "context" => %{},
          "conversation_id" => "conv_456",
          "user_id" => "user_789"
        }
      }
      
      {:ok, agent_with_plan} = PlanningConversationAgent.handle_signal(agent, plan_signal)
      
      # Simulate validation request
      validation_signal = %{
        "type" => "validate_plan_request",
        "data" => %{
          "conversation_id" => "conv_456",
          "plan_id" => "plan_123"  # Would be set by actual plan creation
        }
      }
      
      {:ok, updated_agent} = PlanningConversationAgent.handle_signal(agent_with_plan, validation_signal)
      
      state = updated_agent.state
      conv = state.active_conversations["conv_456"]
      assert conv.status == :validating
    end
  end
  
  describe "conversation state management" do
    setup do
      agent = PlanningConversationAgent.new("test_planner")
      %{agent: agent}
    end
    
    test "tracks conversation lifecycle", %{agent: agent} do
      # Start conversation
      start_signal = %{
        "type" => "plan_creation_request",
        "data" => %{
          "query" => "Plan a migration from REST to GraphQL",
          "context" => %{},
          "conversation_id" => "conv_lifecycle",
          "user_id" => "user_test"
        }
      }
      
      {:ok, agent} = PlanningConversationAgent.handle_signal(agent, start_signal)
      
      # Complete conversation
      complete_signal = %{
        "type" => "complete_conversation",
        "data" => %{
          "conversation_id" => "conv_lifecycle",
          "plan_id" => "plan_final",
          "status" => "completed"
        }
      }
      
      {:ok, final_agent} = PlanningConversationAgent.handle_signal(agent, complete_signal)
      
      state = final_agent.state
      assert state.metrics.total_plans_created == 1
      assert state.metrics.completed_conversations == 1
    end
  end
  
  describe "plan improvement flow" do
    test "handles plan improvement requests" do
      agent = PlanningConversationAgent.new("test_planner")
      
      signal = %{
        "type" => "improve_plan_request",
        "data" => %{
          "plan_id" => "plan_to_improve",
          "conversation_id" => "conv_improve",
          "validation_results" => %{
            "summary" => "warning",
            "suggestions" => ["Add more specific success criteria"]
          }
        }
      }
      
      {:ok, updated_agent} = PlanningConversationAgent.handle_signal(agent, signal)
      
      state = updated_agent.state
      assert state.active_conversations["conv_improve"].status == :improving
    end
  end
  
  describe "metrics collection" do
    test "tracks planning metrics" do
      agent = PlanningConversationAgent.new("test_planner")
      
      # Create multiple plans
      final_agent = Enum.reduce(1..3, agent, fn i, acc_agent ->
        signal = %{
          "type" => "plan_creation_request",
          "data" => %{
            "query" => "Plan task #{i}",
            "context" => %{},
            "conversation_id" => "conv_#{i}",
            "user_id" => "user_test"
          }
        }
        
        {:ok, updated_agent} = PlanningConversationAgent.handle_signal(acc_agent, signal)
        updated_agent
      end)
      
      # Get metrics
      metrics_signal = %{"type" => "get_planning_metrics"}
      {:ok, agent_with_metrics} = PlanningConversationAgent.handle_signal(final_agent, metrics_signal)
      
      assert agent_with_metrics.state.metrics.active_conversations == 3
    end
  end
end