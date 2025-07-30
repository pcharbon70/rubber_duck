defmodule RubberDuck.Agents.EnhancementConversationAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.EnhancementConversationAgent
  
  describe "agent initialization" do
    test "starts with default enhancement configuration" do
      agent = EnhancementConversationAgent.new("test_enhancer")
      
      state = agent.state
      
      assert state.enhancement_queue == []
      assert state.active_enhancements == %{}
      assert state.metrics.total_enhancements == 0
      assert state.enhancement_config.default_techniques == [:cot, :self_correction]
    end
  end
  
  describe "enhancement requests" do
    setup do
      agent = EnhancementConversationAgent.new("test_enhancer")
      %{agent: agent}
    end
    
    test "handles enhancement_request signal", %{agent: agent} do
      signal = %{
        "type" => "enhancement_request",
        "data" => %{
          "content" => "def hello do\n  \"world\"\nend",
          "context" => %{"language" => "elixir"},
          "preferences" => %{"max_iterations" => 2},
          "request_id" => "req_123"
        }
      }
      
      {:ok, updated_agent} = EnhancementConversationAgent.handle_signal(agent, signal)
      
      # Check that request was queued
      assert length(updated_agent.state.enhancement_queue) == 1
      assert Map.has_key?(updated_agent.state.active_enhancements, "req_123")
      
      # Verify enhancement record
      enhancement = updated_agent.state.active_enhancements["req_123"]
      assert enhancement.request_id == "req_123"
      assert enhancement.iteration == 1
      assert enhancement.task.type == :elixir_code
    end
    
    test "handles iterative enhancement request", %{agent: agent} do
      signal = %{
        "type" => "enhancement_request",
        "data" => %{
          "content" => "Enhanced content",
          "context" => %{},
          "preferences" => %{},
          "request_id" => "req_456",
          "previous_result" => %{"iteration" => 1}
        }
      }
      
      {:ok, updated_agent} = EnhancementConversationAgent.handle_signal(agent, signal)
      
      enhancement = updated_agent.state.active_enhancements["req_456"]
      assert enhancement.iteration == 2
    end
    
    test "detects content type correctly", %{agent: agent} do
      test_cases = [
        {"defmodule Test do\nend", :elixir_code},
        {"function test() {}", :javascript_code},
        {"class Test:\n  pass", :python_code},
        {"# Heading\nContent", :markdown},
        {"Plain text", :text}
      ]
      
      for {content, expected_type} <- test_cases do
        signal = %{
          "type" => "enhancement_request",
          "data" => %{
            "content" => content,
            "context" => %{},
            "preferences" => %{},
            "request_id" => "req_#{expected_type}"
          }
        }
        
        {:ok, updated_agent} = EnhancementConversationAgent.handle_signal(agent, signal)
        
        enhancement = updated_agent.state.active_enhancements["req_#{expected_type}"]
        assert enhancement.task.type == expected_type
      end
    end
  end
  
  describe "feedback handling" do
    setup do
      agent = EnhancementConversationAgent.new("test_enhancer")
      %{agent: agent}
    end
    
    test "handles positive feedback", %{agent: agent} do
      signal = %{
        "type" => "feedback_received",
        "data" => %{
          "request_id" => "req_123",
          "suggestion_id" => "sug_456",
          "feedback" => %{"rating" => 5, "comment" => "Great suggestion!"},
          "accepted" => true
        }
      }
      
      {:ok, updated_agent} = EnhancementConversationAgent.handle_signal(agent, signal)
      
      # Check metrics were updated
      assert updated_agent.state.metrics.suggestions_generated == 1
      assert updated_agent.state.metrics.suggestions_accepted == 1
      assert updated_agent.state.metrics.avg_improvement_score == 1.0
      
      # Check history was updated
      assert length(updated_agent.state.enhancement_history) == 1
      history_entry = hd(updated_agent.state.enhancement_history)
      assert history_entry.accepted == true
      assert history_entry.request_id == "req_123"
    end
    
    test "handles negative feedback", %{agent: agent} do
      signal = %{
        "type" => "feedback_received",
        "data" => %{
          "request_id" => "req_789",
          "suggestion_id" => "sug_012",
          "feedback" => %{"rating" => 1, "comment" => "Not helpful"},
          "accepted" => false
        }
      }
      
      {:ok, updated_agent} = EnhancementConversationAgent.handle_signal(agent, signal)
      
      assert updated_agent.state.metrics.suggestions_generated == 1
      assert updated_agent.state.metrics.suggestions_accepted == 0
      assert updated_agent.state.metrics.avg_improvement_score == 0.0
    end
  end
  
  describe "validation handling" do
    setup do
      agent = EnhancementConversationAgent.new("test_enhancer")
      %{agent: agent}
    end
    
    test "handles validation_response signal", %{agent: agent} do
      signal = %{
        "type" => "validation_response",
        "data" => %{
          "request_id" => "req_123",
          "validation_id" => "val_456",
          "results" => %{
            "syntax_valid" => true,
            "tests_pass" => true,
            "warnings" => []
          }
        }
      }
      
      {:ok, updated_agent} = EnhancementConversationAgent.handle_signal(agent, signal)
      
      # Check validation results were stored
      assert updated_agent.state.validation_results["val_456"] != nil
      assert updated_agent.state.validation_results["val_456"]["syntax_valid"] == true
    end
  end
  
  describe "metrics retrieval" do
    test "returns comprehensive metrics" do
      agent = EnhancementConversationAgent.new("test_enhancer")
      
      # Add some test data
      agent = agent
      |> put_in([:state, :metrics, :total_enhancements], 10)
      |> put_in([:state, :metrics, :suggestions_generated], 50)
      |> put_in([:state, :metrics, :suggestions_accepted], 35)
      
      signal = %{"type" => "get_enhancement_metrics"}
      {:ok, _} = EnhancementConversationAgent.handle_signal(agent, signal)
      
      # Would verify the emitted signal in a real test with signal capture
    end
  end
  
  describe "enhancement options" do
    setup do
      agent = EnhancementConversationAgent.new("test_enhancer")
      %{agent: agent}
    end
    
    test "builds appropriate options for code content", %{agent: agent} do
      signal = %{
        "type" => "enhancement_request",
        "data" => %{
          "content" => "def test, do: :ok",
          "context" => %{},
          "preferences" => %{"include_tests" => false},
          "request_id" => "req_code"
        }
      }
      
      {:ok, updated_agent} = EnhancementConversationAgent.handle_signal(agent, signal)
      
      enhancement = updated_agent.state.active_enhancements["req_code"]
      options = enhancement.task.options
      
      assert Keyword.get(options, :validate_syntax) == true
      assert Keyword.get(options, :include_tests) == false
    end
    
    test "builds appropriate options for markdown content", %{agent: agent} do
      signal = %{
        "type" => "enhancement_request",
        "data" => %{
          "content" => "# Title\nContent here",
          "context" => %{},
          "preferences" => %{"check_links" => true},
          "request_id" => "req_md"
        }
      }
      
      {:ok, updated_agent} = EnhancementConversationAgent.handle_signal(agent, signal)
      
      enhancement = updated_agent.state.active_enhancements["req_md"]
      options = enhancement.task.options
      
      assert Keyword.get(options, :improve_structure) == true
      assert Keyword.get(options, :check_links) == true
    end
  end
  
  describe "technique selection" do
    test "respects explicitly requested techniques" do
      agent = EnhancementConversationAgent.new("test_enhancer")
      
      signal = %{
        "type" => "enhancement_request",
        "data" => %{
          "content" => "Test content",
          "context" => %{},
          "preferences" => %{
            "techniques" => ["rag", "cot"]
          },
          "request_id" => "req_tech"
        }
      }
      
      {:ok, _} = EnhancementConversationAgent.handle_signal(agent, signal)
      
      # In a real test, we'd capture the technique_selection signal
    end
  end
  
  describe "error handling" do
    test "handles unknown signals gracefully" do
      agent = EnhancementConversationAgent.new("test_enhancer")
      
      signal = %{
        "type" => "unknown_signal",
        "data" => %{}
      }
      
      {:ok, unchanged_agent} = EnhancementConversationAgent.handle_signal(agent, signal)
      
      assert unchanged_agent == agent
    end
  end
  
  describe "enhancement configuration" do
    test "can be initialized with custom config" do
      agent = EnhancementConversationAgent.new("test_enhancer", %{
        enhancement_config: %{
          default_techniques: [:rag],
          max_suggestions: 10,
          validation_enabled: false,
          ab_testing_enabled: true
        }
      })
      
      config = agent.state.enhancement_config
      assert config.default_techniques == [:rag]
      assert config.max_suggestions == 10
      assert config.validation_enabled == false
      assert config.ab_testing_enabled == true
    end
  end
end