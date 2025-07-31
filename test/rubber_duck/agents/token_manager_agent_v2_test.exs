defmodule RubberDuck.Agents.TokenManagerAgentV2Test do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.TokenManagerAgentV2
  alias RubberDuck.Jido.Actions.Token.{
    TrackUsageAction,
    CheckBudgetAction,
    CreateBudgetAction,
    GetStatusAction
  }

  describe "TokenManagerAgentV2 initialization" do
    test "initializes with default configuration" do
      {:ok, state} = TokenManagerAgentV2.on_init(%{})
      
      assert state.budgets == %{}
      assert state.active_requests == %{}
      assert state.usage_buffer == []
      assert state.provenance_buffer == []
      assert state.provenance_graph == []
      assert state.metrics.total_tokens == 0
      assert Decimal.eq?(state.metrics.total_cost, Decimal.new(0))
      assert state.config.buffer_size == 100
      assert state.config.flush_interval == 5_000
    end

    test "includes default pricing models" do
      {:ok, state} = TokenManagerAgentV2.on_init(%{})
      
      assert Map.has_key?(state.pricing_models, "openai")
      assert Map.has_key?(state.pricing_models, "anthropic")
      assert Map.has_key?(state.pricing_models, "local")
      
      # Check OpenAI pricing
      assert state.pricing_models["openai"]["gpt-4"].prompt == 0.03
      assert state.pricing_models["openai"]["gpt-4"].completion == 0.06
    end

    test "merges custom configuration" do
      custom_config = %{buffer_size: 200, flush_interval: 10_000}
      {:ok, state} = TokenManagerAgentV2.on_init(%{config: custom_config})
      
      assert state.config.buffer_size == 200
      assert state.config.flush_interval == 10_000
      # Should keep defaults for other values
      assert state.config.retention_days == 90
    end
  end

  describe "action integration through handle_signal" do
    setup do
      {:ok, state} = TokenManagerAgentV2.on_init(%{})
      agent = %{id: "test_agent", state: state}
      {:ok, agent: agent}
    end

    test "routes track_usage signal to TrackUsageAction", %{agent: agent} do
      data = %{
        request_id: "req_123",
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 100,
        completion_tokens: 50,
        user_id: "user_123",
        project_id: "proj_123",
        metadata: %{},
        provenance: %{parent_request_id: nil}
      }
      
      {:ok, result, updated_agent} = TokenManagerAgentV2.handle_signal("track_usage", data, agent)
      
      assert result["tracked"] == true
      assert Map.has_key?(result, "usage")
      assert Map.has_key?(result, "provenance")
      
      # Verify state was updated
      assert length(updated_agent.state.usage_buffer) == 1
      assert length(updated_agent.state.provenance_buffer) == 1
      assert updated_agent.state.metrics.requests_tracked == 1
      assert updated_agent.state.metrics.total_tokens == 150
    end

    test "routes check_budget signal to CheckBudgetAction", %{agent: agent} do
      data = %{
        user_id: "user_123",
        project_id: "proj_123",
        estimated_tokens: 100,
        request_id: "req_456"
      }
      
      {:ok, result, _updated_agent} = TokenManagerAgentV2.handle_signal("check_budget", data, agent)
      
      # Should be allowed since no budgets are configured
      assert result["allowed"] == true
    end

    test "routes create_budget signal to CreateBudgetAction", %{agent: agent} do
      data = %{
        name: "Test Budget",
        type: "user",
        entity_id: "user_123",
        period: "monthly",
        limit: "100.00"
      }
      
      {:ok, result, updated_agent} = TokenManagerAgentV2.handle_signal("create_budget", data, agent)
      
      assert Map.has_key?(result, "budget_id")
      assert Map.has_key?(result, "budget")
      
      # Verify budget was stored
      budget_id = result["budget_id"]
      assert Map.has_key?(updated_agent.state.budgets, budget_id)
    end

    test "routes get_status signal to GetStatusAction", %{agent: agent} do
      {:ok, result, _updated_agent} = TokenManagerAgentV2.handle_signal("get_status", %{}, agent)
      
      assert result["healthy"] == true
      assert result["budgets_active"] == 0
      assert result["buffer_size"] == 0
      assert result["total_tracked"] == 0
      assert Map.has_key?(result, "timestamp")
    end

    test "handles unknown signal types gracefully", %{agent: agent} do
      {:error, reason, _agent} = TokenManagerAgentV2.handle_signal("unknown_signal", %{}, agent)
      
      assert reason == "Unknown signal type: unknown_signal"
    end
  end

  describe "direct action usage" do
    setup do
      {:ok, state} = TokenManagerAgentV2.on_init(%{})
      agent = %{id: "test_agent", state: state}
      {:ok, agent: agent}
    end

    test "can use TrackUsageAction directly", %{agent: agent} do
      params = %{
        request_id: "req_789",
        provider: "anthropic",
        model: "claude-3-sonnet",
        prompt_tokens: 200,
        completion_tokens: 100,
        user_id: "user_456",
        project_id: "proj_456",
        metadata: %{team_id: "team_123"},
        provenance: %{
          parent_request_id: nil,
          workflow_id: "workflow_123",
          task_type: "text_generation"
        }
      }
      
      context = %{agent: agent}
      
      {:ok, result, %{agent: updated_agent}} = TrackUsageAction.run(params, context)
      
      assert result["tracked"] == true
      usage = result["usage"]
      assert usage.request_id == "req_789"
      assert usage.total_tokens == 300
      assert usage.team_id == "team_123"
      
      # Verify cost calculation
      assert Decimal.positive?(usage.cost)
      
      # Verify provenance
      provenance = result["provenance"]
      assert provenance.request_id == "req_789"
      assert provenance.workflow_id == "workflow_123"
      assert provenance.task_type == "text_generation"
      assert provenance.depth == 0  # root request
    end

    test "can use CreateBudgetAction and CheckBudgetAction together", %{agent: agent} do
      # First create a budget
      create_params = %{
        name: "User Budget",
        type: "user",
        entity_id: "user_123",
        period: "monthly",
        limit: "50.00"
      }
      
      {:ok, create_result, %{agent: agent_with_budget}} = 
        CreateBudgetAction.run(create_params, %{agent: agent})
      
      budget_id = create_result["budget_id"]
      assert Map.has_key?(agent_with_budget.state.budgets, budget_id)
      
      # Now check budget for a small request (should be allowed)
      check_params = %{
        user_id: "user_123",
        project_id: "proj_123",
        estimated_tokens: 100,  # Small request
        request_id: "req_check_1"
      }
      
      {:ok, check_result, _} = 
        CheckBudgetAction.run(check_params, %{agent: agent_with_budget})
      
      assert check_result["allowed"] == true
      
      # Check budget for a large request (might be denied depending on pricing)
      large_check_params = %{
        user_id: "user_123",
        project_id: "proj_123",
        estimated_tokens: 100_000,  # Very large request
        request_id: "req_check_2"
      }
      
      {:ok, large_check_result, _} = 
        CheckBudgetAction.run(large_check_params, %{agent: agent_with_budget})
      
      # Result depends on pricing calculation, but should return boolean
      assert is_boolean(large_check_result["allowed"])
    end
  end

  describe "state validation" do
    test "validates budgets correctly" do
      {:ok, state} = TokenManagerAgentV2.on_init(%{})
      
      # Valid state should pass
      assert {:ok, ^state} = TokenManagerAgentV2.on_before_validate_state(state)
      
      # Invalid budgets should fail
      invalid_state = %{state | budgets: "not_a_map"}
      assert {:error, "budgets must be a map"} = 
        TokenManagerAgentV2.on_before_validate_state(invalid_state)
    end

    test "validates metrics correctly" do
      {:ok, state} = TokenManagerAgentV2.on_init(%{})
      
      # Invalid metrics should fail
      invalid_state = %{state | metrics: %{total_tokens: -1}}
      assert {:error, "invalid metrics structure"} = 
        TokenManagerAgentV2.on_before_validate_state(invalid_state)
    end
  end

  describe "utility functions" do
    test "calculate_token_cost works correctly" do
      usage = %{
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 100,
        completion_tokens: 50
      }
      
      pricing_models = TokenManagerAgentV2.default_pricing_models()
      cost = TokenManagerAgentV2.calculate_token_cost(usage, pricing_models)
      
      assert cost.currency == "USD"
      assert Decimal.positive?(cost.amount)
      
      # Should be: (100 * 0.03 / 1000) + (50 * 0.06 / 1000) = 0.003 + 0.003 = 0.006
      expected = Decimal.new("0.006")
      assert Decimal.eq?(cost.amount, expected)
    end

    test "calculate_token_cost handles unknown models" do
      usage = %{
        provider: "unknown",
        model: "unknown-model",
        prompt_tokens: 100,
        completion_tokens: 50
      }
      
      pricing_models = TokenManagerAgentV2.default_pricing_models()
      cost = TokenManagerAgentV2.calculate_token_cost(usage, pricing_models)
      
      assert cost.currency == "USD"
      assert Decimal.eq?(cost.amount, Decimal.new(0))
    end
  end

  describe "task configurations" do
    test "provides correct task configurations" do
      flush_config = TokenManagerAgentV2.flush_buffer_task_config()
      assert flush_config.name == "flush_buffer"
      assert flush_config.schedule == "*/5 * * * *"
      
      metrics_config = TokenManagerAgentV2.metrics_update_task_config()
      assert metrics_config.name == "update_metrics"
      assert metrics_config.schedule == "0 * * * *"
      
      cleanup_config = TokenManagerAgentV2.cleanup_task_config()
      assert cleanup_config.name == "cleanup_old_data"
      assert cleanup_config.schedule == "0 0 * * *"
    end
  end
end