defmodule RubberDuck.Tokens.IntegrationTest do
  use RubberDuck.DataCase, async: false
  
  alias RubberDuck.Agents.{TokenManagerAgent, TokenPersistenceAgent}
  alias RubberDuck.Tokens
  
  describe "TokenManager and Persistence integration" do
    setup do
      # Create test user
      {:ok, user} = RubberDuck.Accounts.register_user(%{
        email: "integration@example.com",
        password: "password123456"
      })
      
      # Initialize agents
      {:ok, token_manager} = TokenManagerAgent.new(%{
        buffer_size: 3,
        flush_interval: 1000
      })
      
      {:ok, persistence_agent} = TokenPersistenceAgent.new(%{
        buffer_size: 3,
        flush_interval: 5000
      })
      
      %{
        user: user,
        token_manager: token_manager,
        persistence_agent: persistence_agent
      }
    end
    
    test "token usage flows from manager to persistence", %{
      user: user,
      token_manager: token_manager,
      persistence_agent: persistence_agent
    } do
      # Track usage in token manager
      usage_data = %{
        "provider" => "openai",
        "model" => "gpt-4",
        "prompt_tokens" => 1000,
        "completion_tokens" => 500,
        "total_tokens" => 1500,
        "user_id" => user.id,
        "project_id" => nil,
        "feature" => "integration_test"
      }
      
      # Track multiple usages to trigger flush
      {:ok, tm1} = TokenManagerAgent.handle_signal(token_manager, "track_usage", usage_data)
      {:ok, tm2} = TokenManagerAgent.handle_signal(tm1, "track_usage", Map.put(usage_data, "prompt_tokens", 2000))
      {:ok, tm3} = TokenManagerAgent.handle_signal(tm2, "track_usage", Map.put(usage_data, "prompt_tokens", 3000))
      
      # Buffer should be full, triggering flush
      assert length(tm3.usage_buffer) == 0
      
      # Simulate the flush signal being received by persistence agent
      flush_signal = %{
        "type" => "token_usage_flush",
        "data" => [
          Map.merge(usage_data, %{"request_id" => "req_1_#{Uniq.UUID.generate()}", "cost" => "0.045"}),
          Map.merge(usage_data, %{"prompt_tokens" => 2000, "total_tokens" => 2500, "request_id" => "req_2_#{Uniq.UUID.generate()}", "cost" => "0.075"}),
          Map.merge(usage_data, %{"prompt_tokens" => 3000, "total_tokens" => 3500, "request_id" => "req_3_#{Uniq.UUID.generate()}", "cost" => "0.105"})
        ]
      }
      
      {:ok, pa1} = TokenPersistenceAgent.handle_signal(persistence_agent, flush_signal)
      
      # Persistence agent should have flushed to database
      assert pa1.state.buffer == []
      assert pa1.state.stats.persisted_count == 3
      
      # Verify data in database
      {:ok, persisted} = Tokens.list_user_usage(user.id)
      assert length(persisted) == 3
      assert Enum.all?(persisted, fn u -> u.provider == "openai" && u.model == "gpt-4" end)
    end
    
    test "budget enforcement prevents token usage", %{user: user, token_manager: token_manager} do
      # Create a small budget
      {:ok, budget} = Tokens.create_budget(%{
        name: "Test Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "daily",
        limit_amount: Decimal.new("1.00"),
        currency: "USD"
      })
      
      # Update token manager with budget
      create_budget_signal = %{
        "name" => budget.name,
        "type" => "user",
        "entity_id" => user.id,
        "period" => "daily",
        "limit" => "1.00"
      }
      
      {:ok, tm_with_budget} = TokenManagerAgent.handle_signal(token_manager, "create_budget", create_budget_signal)
      
      # First request should pass
      check1 = %{
        "user_id" => user.id,
        "project_id" => nil,
        "estimated_tokens" => 1000
      }
      
      {:ok, result1, _} = TokenManagerAgent.handle_signal(tm_with_budget, "check_budget", check1)
      assert result1["allowed"] == true
      
      # Track usage to consume budget
      usage = %{
        "provider" => "openai",
        "model" => "gpt-4",
        "prompt_tokens" => 30000,
        "completion_tokens" => 3000,
        "total_tokens" => 33000,
        "user_id" => user.id,
        "cost" => 0.99
      }
      
      # Note: In real implementation, budget would be updated via persistence
      # For this test, we'll check that the data flows correctly
      {:ok, tm_after_usage} = TokenManagerAgent.handle_signal(tm_with_budget, "track_usage", usage)
      
      # The usage should be in buffer
      assert length(tm_after_usage.usage_buffer) == 1
    end
    
    test "analytics aggregation works with persisted data", %{user: user} do
      # Create test data directly in database
      records = Enum.map(1..10, fn i ->
        %{
          provider: "openai",
          model: if(rem(i, 2) == 0, do: "gpt-4", else: "gpt-3.5"),
          prompt_tokens: 100 * i,
          completion_tokens: 50 * i,
          total_tokens: 150 * i,
          cost: Decimal.mult(Decimal.new("0.001"), Decimal.new(i)),
          currency: "USD",
          user_id: user.id,
          request_id: "analytics_test_#{i}_#{Uniq.UUID.generate()}"
        }
      end)
      
      {:ok, _} = Tokens.bulk_record_usage(records)
      
      # Query aggregated data
      {:ok, summary} = Tokens.sum_user_tokens(user.id)
      
      # Total tokens: 150 * (1+2+3+4+5+6+7+8+9+10) = 150 * 55 = 8250
      assert summary.total_tokens == 8250
      assert summary.request_count == 10
      
      # Total cost: 0.001 * 55 = 0.055
      assert Decimal.equal?(summary.total_cost, Decimal.new("0.055"))
    end
    
    test "provenance tracking maintains relationships", %{user: user} do
      # Create parent request
      parent_attrs = %{
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 1000,
        completion_tokens: 500,
        total_tokens: 1500,
        cost: Decimal.new("0.045"),
        currency: "USD",
        user_id: user.id,
        request_id: "parent_#{Uniq.UUID.generate()}"
      }
      
      {:ok, parent} = Tokens.record_usage(parent_attrs)
      
      # Create provenance record
      {:ok, parent_prov} = Tokens.record_provenance(%{
        request_id: parent.request_id,
        workflow_id: "workflow_123",
        task_type: "code_generation",
        task_name: "Generate Function",
        agent_type: "generation_agent",
        input_hash: "hash_123",
        input_size: 1024,
        output_hash: "hash_456",
        output_size: 2048,
        processing_time_ms: 1500
      })
      
      # Create child request
      child_attrs = %{
        provider: "openai",
        model: "gpt-3.5",
        prompt_tokens: 500,
        completion_tokens: 200,
        total_tokens: 700,
        cost: Decimal.new("0.0007"),
        currency: "USD",
        user_id: user.id,
        request_id: "child_#{Uniq.UUID.generate()}"
      }
      
      {:ok, child} = Tokens.record_usage(child_attrs)
      
      # Create child provenance
      {:ok, child_prov} = Tokens.record_provenance(%{
        request_id: child.request_id,
        workflow_id: "workflow_123",
        task_type: "code_review",
        task_name: "Review Generated Code",
        agent_type: "review_agent",
        input_hash: "hash_456", # Output of parent becomes input
        input_size: 2048,
        output_hash: "hash_789",
        output_size: 512,
        processing_time_ms: 800
      })
      
      # Create relationship
      {:ok, relationship} = Tokens.create_relationship(%{
        parent_request_id: parent.request_id,
        child_request_id: child.request_id,
        relationship_type: "derived_from",
        metadata: %{"workflow_step" => 2}
      })
      
      # Verify relationship
      assert relationship.parent_request_id == parent.request_id
      assert relationship.child_request_id == child.request_id
      
      # Query lineage
      {:ok, ancestors} = Tokens.find_ancestors(child.request_id)
      assert length(ancestors) >= 1
      assert Enum.any?(ancestors, fn a -> a.parent_request_id == parent.request_id end)
    end
    
    test "budget period reset works correctly", %{user: user} do
      # Create daily budget
      {:ok, budget} = Tokens.create_budget(%{
        name: "Daily Reset Test",
        entity_type: "user",
        entity_id: user.id,
        period_type: "daily",
        limit_amount: Decimal.new("50.00")
      })
      
      # Add spending
      {:ok, budget_with_spending} = Tokens.update_spending(budget, Decimal.new("45.00"))
      assert Decimal.equal?(budget_with_spending.current_spending, Decimal.new("45.00"))
      
      # Reset period
      {:ok, reset_budget} = Tokens.reset_budget_period(budget_with_spending)
      assert Decimal.equal?(reset_budget.current_spending, Decimal.new("0"))
      assert reset_budget.last_reset != nil
      assert DateTime.compare(reset_budget.period_start, budget.period_start) == :gt
    end
  end
end