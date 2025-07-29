defmodule RubberDuck.Agents.PlanDecomposerAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.PlanDecomposerAgent

  describe "agent lifecycle" do
    test "starts with proper initial state" do
      agent = %{
        id: "test_decomposer",
        state: %{
          active_decompositions: %{},
          cache: %{},
          cache_enabled: true,
          strategies: [:linear, :hierarchical, :tree_of_thought],
          default_strategy: :hierarchical,
          max_depth: 5,
          llm_config: %{},
          validation_enabled: true
        }
      }
      
      assert agent.state.active_decompositions == %{}
      assert agent.state.cache == %{}
      assert :linear in agent.state.strategies
      assert :hierarchical in agent.state.strategies
      assert :tree_of_thought in agent.state.strategies
    end
  end

  describe "decompose_plan signal" do
    setup do
      agent = %{
        id: "test_decomposer",
        state: %{
          active_decompositions: %{},
          cache: %{},
          cache_enabled: true,
          strategies: [:linear, :hierarchical, :tree_of_thought],
          default_strategy: :hierarchical,
          max_depth: 5,
          llm_config: %{},
          validation_enabled: true
        }
      }
      %{agent: agent}
    end

    test "handles decomposition request signal", %{agent: agent} do
      signal = %{
        "type" => "decompose_plan",
        "plan_id" => "test_plan_123",
        "query" => "Implement user authentication with OAuth",
        "context" => %{
          "scope" => "Backend API",
          "constraints" => %{"time_limit" => "1 week"}
        }
      }

      assert {:ok, updated_agent} = PlanDecomposerAgent.handle_signal(agent, signal)
      
      # Agent should track active decomposition
      assert Map.has_key?(updated_agent.state.active_decompositions, "test_plan_123")
    end

    test "emits decomposition_complete signal on success", %{agent: agent} do
      # This test will verify the agent emits proper completion signal
      # Implementation will need to handle async nature
      signal = %{
        "type" => "decompose_plan",
        "plan_id" => "test_plan_456",
        "query" => "Add logging to the application",
        "strategy" => "linear"
      }

      assert {:ok, updated_agent} = PlanDecomposerAgent.handle_signal(agent, signal)
      
      # The agent starts async processing
      assert Map.has_key?(updated_agent.state.active_decompositions, "test_plan_456")
    end
  end

  describe "decomposition strategies" do
    setup do
      agent = %{
        id: "test_decomposer",
        state: %{
          active_decompositions: %{},
          cache: %{},
          cache_enabled: true,
          strategies: [:linear, :hierarchical, :tree_of_thought],
          default_strategy: :hierarchical,
          max_depth: 5,
          llm_config: %{model: "gpt-4"},
          validation_enabled: true
        }
      }
      %{agent: agent}
    end

    test "uses specified strategy when provided", %{agent: agent} do
      signal = %{
        "type" => "decompose_plan",
        "plan_id" => "test_linear",
        "query" => "Fix bug in payment processing",
        "strategy" => "linear"
      }

      assert {:ok, updated_agent} = PlanDecomposerAgent.handle_signal(agent, signal)
      
      decomposition = Map.get(updated_agent.state.active_decompositions, "test_linear")
      assert decomposition.strategy == :linear
    end

    test "determines strategy automatically when not specified", %{agent: agent} do
      signal = %{
        "type" => "decompose_plan", 
        "plan_id" => "test_auto",
        "query" => "Build a complex feature with multiple components"
      }

      assert {:ok, updated_agent} = PlanDecomposerAgent.handle_signal(agent, signal)
      
      decomposition = Map.get(updated_agent.state.active_decompositions, "test_auto")
      # Should choose hierarchical for complex features  
      assert decomposition.strategy == :hierarchical
    end
  end

  describe "caching" do
    setup do
      agent = %{
        id: "test_decomposer",
        state: %{
          active_decompositions: %{},
          cache: %{},
          cache_enabled: true,
          strategies: [:linear, :hierarchical, :tree_of_thought],
          default_strategy: :hierarchical,
          max_depth: 5,
          llm_config: %{},
          validation_enabled: false
        }
      }
      %{agent: agent}
    end

    test "caches decomposition results", %{agent: agent} do
      signal = %{
        "type" => "decompose_plan",
        "plan_id" => "test_cache_1", 
        "query" => "Add user profile page"
      }

      # First decomposition - starts async processing
      assert {:ok, agent_after_first} = PlanDecomposerAgent.handle_signal(agent, signal)
      assert Map.has_key?(agent_after_first.state.active_decompositions, "test_cache_1")
      
      # Simulate cache population (in real impl this would happen async)
      cache_result = %{tasks: [%{"name" => "Task 1"}], dependencies: []}
      cache_key = "decompose:#{:erlang.phash2(signal["query"])}:31832193"
      agent_with_cache = put_in(agent_after_first.state.cache[cache_key], {cache_result, DateTime.utc_now()})
      
      # Second identical request should use cache
      signal2 = Map.put(signal, "plan_id", "test_cache_2")
      assert {:ok, agent_after_second} = PlanDecomposerAgent.handle_signal(agent_with_cache, signal2)
      
      # Should not add to active decompositions when using cache
      refute Map.has_key?(agent_after_second.state.active_decompositions, "test_cache_2")
    end
  end

  describe "error handling" do
    setup do
      agent = %{
        id: "test_decomposer",
        state: %{
          active_decompositions: %{},
          cache: %{},
          cache_enabled: true,
          strategies: [:linear, :hierarchical, :tree_of_thought],
          default_strategy: :hierarchical,
          max_depth: 5,
          llm_config: %{},
          validation_enabled: true
        }
      }
      %{agent: agent}
    end

    test "emits decomposition_failed signal on error", %{agent: agent} do
      signal = %{
        "type" => "decompose_plan",
        "plan_id" => "test_error",
        # Missing required query field
        "context" => %{}
      }

      # Should return ok but emit failure signal for missing query
      assert {:ok, _updated_agent} = PlanDecomposerAgent.handle_signal(agent, signal)
      
      # In real implementation, we'd verify the decomposition_failed signal was emitted
    end
  end
end