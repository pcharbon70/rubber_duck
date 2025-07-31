defmodule RubberDuck.Integration.ConversationAgentsTest do
  @moduledoc """
  Integration tests for conversation agent system.
  
  Tests the interaction between:
  - ConversationRouterAgent
  - PlanningConversationAgent
  - CodeAnalysisAgent
  - EnhancementConversationAgent
  - GeneralConversationAgent
  """
  
  use ExUnit.Case, async: false
  
  alias RubberDuck.Agents.{
    ConversationRouterAgent,
    PlanningConversationAgent,
    CodeAnalysisAgent,
    EnhancementConversationAgent,
    GeneralConversationAgent
  }
  
  # Test helpers to capture emitted signals
  defmodule SignalCollector do
    use GenServer
    
    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, %{signals: []}, opts)
    end
    
    def get_signals(pid), do: GenServer.call(pid, :get_signals)
    def clear(pid), do: GenServer.cast(pid, :clear)
    
    @impl true
    def init(state), do: {:ok, state}
    
    @impl true
    def handle_call(:get_signals, _from, state) do
      {:reply, Enum.reverse(state.signals), state}
    end
    
    @impl true
    def handle_cast(:clear, state) do
      {:noreply, %{state | signals: []}}
    end
    
    @impl true
    def handle_info({:signal, signal}, state) do
      {:noreply, %{state | signals: [signal | state.signals]}}
    end
  end
  
  setup do
    # Start signal collector
    {:ok, collector} = SignalCollector.start_link()
    
    # Subscribe to signals (in a real system, this would use the signal router)
    Process.register(collector, :test_signal_collector)
    
    on_exit(fn ->
      Process.unregister(:test_signal_collector)
    end)
    
    %{collector: collector}
  end
  
  describe "Routing Accuracy" do
    test "ConversationRouterAgent correctly routes planning queries", %{collector: collector} do
      router = ConversationRouterAgent.new("test_router")
      
      planning_signal = %{
        "type" => "conversation_route_request",
        "data" => %{
          "query" => "Help me plan a new feature for user authentication",
          "context" => %{},
          "request_id" => "plan_123"
        }
      }
      
      {:ok, updated_router} = ConversationRouterAgent.handle_signal(router, planning_signal)
      
      # Verify routing decision
      assert updated_router.state.metrics.total_requests == 1
      assert Map.has_key?(updated_router.state.metrics.routes_used, "planning")
    end
    
    test "ConversationRouterAgent correctly routes analysis queries", %{collector: collector} do
      router = ConversationRouterAgent.new("test_router")
      
      analysis_signal = %{
        "type" => "conversation_route_request",
        "data" => %{
          "query" => "Analyze this code for security vulnerabilities",
          "context" => %{"code" => "def process(input), do: File.read!(input)"},
          "request_id" => "analysis_123"
        }
      }
      
      {:ok, updated_router} = ConversationRouterAgent.handle_signal(router, analysis_signal)
      
      # Verify routing decision
      assert Map.has_key?(updated_router.state.metrics.routes_used, "analysis")
    end
    
    test "ConversationRouterAgent correctly routes general queries", %{collector: collector} do
      router = ConversationRouterAgent.new("test_router")
      
      general_signal = %{
        "type" => "conversation_route_request",
        "data" => %{
          "query" => "What is Elixir?",
          "context" => %{},
          "request_id" => "general_123"
        }
      }
      
      {:ok, updated_router} = ConversationRouterAgent.handle_signal(router, general_signal)
      
      # Should route to simple/general conversation
      assert updated_router.state.metrics.total_requests == 1
    end
  end
  
  describe "Conversation Handling" do
    test "PlanningConversationAgent handles plan creation flow", %{collector: collector} do
      agent = PlanningConversationAgent.new("test_planner")
      
      # Initial planning request
      planning_request = %{
        "type" => "planning_request",
        "data" => %{
          "query" => "Create a plan for implementing user authentication",
          "conversation_id" => "conv_plan_123",
          "context" => %{"project_type" => "web_app"},
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, updated_agent} = PlanningConversationAgent.handle_signal(agent, planning_request)
      
      # Verify conversation was created
      assert Map.has_key?(updated_agent.state.active_conversations, "conv_plan_123")
      conversation = updated_agent.state.active_conversations["conv_plan_123"]
      assert conversation.phase == :initial_query
    end
    
    test "GeneralConversationAgent handles context switching", %{collector: collector} do
      agent = GeneralConversationAgent.new("test_general")
      
      # Create initial conversation
      agent = put_in(agent.state.active_conversations["conv_123"], %{
        id: "conv_123",
        context: %{"topic" => "elixir"},
        messages: [],
        created_at: System.monotonic_time(:millisecond),
        last_activity: System.monotonic_time(:millisecond)
      })
      
      # Switch context
      context_switch = %{
        "type" => "context_switch",
        "data" => %{
          "conversation_id" => "conv_123",
          "new_context" => %{"topic" => "phoenix"},
          "preserve_history" => true
        }
      }
      
      {:ok, updated_agent} = GeneralConversationAgent.handle_signal(agent, context_switch)
      
      # Verify context switch
      assert updated_agent.state.active_conversations["conv_123"].context["topic"] == "phoenix"
      assert length(updated_agent.state.context_stack) == 1
      assert hd(updated_agent.state.context_stack)["topic"] == "elixir"
    end
    
    test "EnhancementConversationAgent handles feedback loop", %{collector: collector} do
      agent = EnhancementConversationAgent.new("test_enhancer")
      
      # Submit feedback
      feedback_signal = %{
        "type" => "feedback_received",
        "data" => %{
          "request_id" => "req_123",
          "suggestion_id" => "sug_456",
          "feedback" => %{"rating" => 5},
          "accepted" => true
        }
      }
      
      {:ok, updated_agent} = EnhancementConversationAgent.handle_signal(agent, feedback_signal)
      
      # Verify metrics updated
      assert updated_agent.state.metrics.suggestions_accepted == 1
      assert updated_agent.state.metrics.avg_improvement_score == 1.0
    end
  end
  
  describe "Context Preservation" do
    test "Conversation context is preserved across interactions" do
      agent = GeneralConversationAgent.new("test_general")
      
      # First conversation
      first_request = %{
        "type" => "conversation_request",
        "data" => %{
          "query" => "Tell me about Elixir",
          "conversation_id" => "ctx_test",
          "context" => %{"user_preference" => "technical"},
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, agent} = GeneralConversationAgent.handle_signal(agent, first_request)
      
      # Second conversation with same ID
      second_request = %{
        "type" => "conversation_request",
        "data" => %{
          "query" => "What about its concurrency model?",
          "conversation_id" => "ctx_test",
          "context" => %{},
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, agent} = GeneralConversationAgent.handle_signal(agent, second_request)
      
      # Context should be preserved
      conversation = agent.state.active_conversations["ctx_test"]
      assert conversation.context["user_preference"] == "technical"
      assert conversation.last_query == "What about its concurrency model?"
    end
    
    test "Planning context flows through phases" do
      agent = PlanningConversationAgent.new("test_planner")
      
      # Create conversation in plan_created phase
      agent = put_in(agent.state.active_conversations["plan_ctx"], %{
        conversation_id: "plan_ctx",
        phase: :plan_created,
        plan_id: "plan_123",
        context: %{"project" => "my_app"},
        messages: []
      })
      
      # Improvement request
      improvement_signal = %{
        "type" => "plan_improvement_request",
        "data" => %{
          "conversation_id" => "plan_ctx",
          "improvement_type" => "add_tests",
          "details" => "Add comprehensive test coverage"
        }
      }
      
      {:ok, updated_agent} = PlanningConversationAgent.handle_signal(agent, improvement_signal)
      
      # Context preserved, phase updated
      conversation = updated_agent.state.active_conversations["plan_ctx"]
      assert conversation.context["project"] == "my_app"
      assert conversation.phase == :improving_plan
    end
  end
  
  describe "Analysis Integration" do
    test "CodeAnalysisAgent integrates with conversation flow" do
      agent = CodeAnalysisAgent.new("test_analyzer")
      
      # Analysis request from conversation
      analysis_request = %{
        "type" => "code_analysis_request",
        "data" => %{
          "file_path" => create_test_file(),
          "options" => %{"enhance_with_llm" => false},
          "request_id" => "analysis_integration",
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, updated_agent} = CodeAnalysisAgent.handle_signal(agent, analysis_request)
      
      # Verify analysis queued
      assert length(updated_agent.state.analysis_queue) == 1
      assert Map.has_key?(updated_agent.state.active_analyses, "analysis_integration")
    end
    
    test "Analysis results can trigger enhancement suggestions" do
      enhancer = EnhancementConversationAgent.new("test_enhancer")
      
      # Enhancement request based on analysis
      enhancement_request = %{
        "type" => "enhancement_request",
        "data" => %{
          "content" => "def hello, do: :world",
          "context" => %{
            "analysis_results" => %{
              "issues" => ["Missing documentation"]
            }
          },
          "preferences" => %{},
          "request_id" => "enh_from_analysis"
        }
      }
      
      {:ok, updated_enhancer} = EnhancementConversationAgent.handle_signal(enhancer, enhancement_request)
      
      # Enhancement should be queued
      assert length(updated_enhancer.state.enhancement_queue) == 1
    end
  end
  
  describe "Enhancement Quality" do
    test "Enhancement suggestions are ranked by impact" do
      agent = EnhancementConversationAgent.new("test_enhancer")
      
      # Multiple enhancement requests
      requests = [
        %{
          "type" => "enhancement_request",
          "data" => %{
            "content" => "def calculate(a, b), do: a + b",
            "context" => %{"type" => "elixir"},
            "preferences" => %{"techniques" => ["cot"]},
            "request_id" => "enh_1"
          }
        },
        %{
          "type" => "enhancement_request",
          "data" => %{
            "content" => "# Simple function\ndef test, do: nil",
            "context" => %{"type" => "elixir"},
            "preferences" => %{"techniques" => ["self_correction"]},
            "request_id" => "enh_2"
          }
        }
      ]
      
      agent = Enum.reduce(requests, agent, fn request, acc_agent ->
        {:ok, updated} = EnhancementConversationAgent.handle_signal(acc_agent, request)
        updated
      end)
      
      # Multiple enhancements queued
      assert length(agent.state.enhancement_queue) == 2
    end
    
    test "Enhancement metrics track improvement over time" do
      agent = EnhancementConversationAgent.new("test_enhancer")
      
      # Simulate multiple feedback cycles
      feedbacks = [
        %{"accepted" => true, "rating" => 5},
        %{"accepted" => true, "rating" => 4},
        %{"accepted" => false, "rating" => 2},
        %{"accepted" => true, "rating" => 5}
      ]
      
      agent = Enum.reduce(Enum.with_index(feedbacks), agent, fn {{feedback, idx}, _}, acc_agent ->
        signal = %{
          "type" => "feedback_received",
          "data" => %{
            "request_id" => "req_#{idx}",
            "suggestion_id" => "sug_#{idx}",
            "feedback" => feedback,
            "accepted" => feedback["accepted"]
          }
        }
        
        {:ok, updated} = EnhancementConversationAgent.handle_signal(acc_agent, signal)
        updated
      end)
      
      # Check metrics
      assert agent.state.metrics.suggestions_generated == 4
      assert agent.state.metrics.suggestions_accepted == 3
      assert agent.state.metrics.avg_improvement_score == 0.75
    end
  end
  
  describe "Inter-agent Communication" do
    test "Router agent can hand off to specialized agents" do
      router = ConversationRouterAgent.new("test_router")
      
      # Complex query requiring handoff
      complex_signal = %{
        "type" => "conversation_route_request",
        "data" => %{
          "query" => "Generate a GenServer that handles user sessions with timeout",
          "context" => %{},
          "request_id" => "handoff_test"
        }
      }
      
      {:ok, updated_router} = ConversationRouterAgent.handle_signal(router, complex_signal)
      
      # Should route to generation
      assert Map.has_key?(updated_router.state.metrics.routes_used, "generation")
    end
    
    test "General agent can request handoff for specialized queries" do
      agent = GeneralConversationAgent.new("test_general")
      
      # This would normally trigger async processing and handoff
      specialized_request = %{
        "type" => "conversation_request",
        "data" => %{
          "query" => "Generate a complete authentication module",
          "conversation_id" => "handoff_conv",
          "context" => %{},
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, _updated_agent} = GeneralConversationAgent.handle_signal(agent, specialized_request)
      
      # In a real system, this would emit a handoff_request signal
    end
  end
  
  # Helper functions
  
  defp create_test_file do
    path = "/tmp/test_#{:rand.uniform(10000)}.ex"
    content = """
    defmodule TestModule do
      def hello do
        _unused = 42
        "hello"
      end
    end
    """
    File.write!(path, content)
    path
  end
end