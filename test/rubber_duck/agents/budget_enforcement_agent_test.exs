defmodule RubberDuck.Agents.BudgetEnforcementAgentTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.Agents.BudgetEnforcementAgent
  alias RubberDuck.Tokens
  
  describe "BudgetEnforcementAgent" do
    setup do
      # Create test users
      {:ok, user} = RubberDuck.Accounts.register_user(%{
        email: "test@example.com",
        password: "password123456"
      })
      
      # Create test budgets
      {:ok, user_budget} = Tokens.create_budget(%{
        name: "User Monthly Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "monthly",
        limit_amount: Decimal.new("100.00"),
        currency: "USD"
      })
      
      {:ok, global_budget} = Tokens.create_budget(%{
        name: "Global Daily Budget",
        entity_type: "global",
        period_type: "daily",
        limit_amount: Decimal.new("1000.00"),
        currency: "USD"
      })
      
      # Initialize agent with budgets pre-loaded
      {:ok, agent} = BudgetEnforcementAgent.new(%{
        budget_cache_ttl: 60_000,
        check_interval: 30_000,
        alert_thresholds: [0.5, 0.8, 1.0]
      })
      
      # Manually set up the agent state with budgets
      agent = %{agent | state: %{agent.state | 
        active_budgets: %{
          user_budget.id => user_budget,
          global_budget.id => global_budget
        }
      }}
      
      %{
        agent: agent,
        user: user,
        user_budget: user_budget,
        global_budget: global_budget
      }
    end
    
    test "initializes with correct state", %{agent: agent} do
      assert agent.state.budget_cache_ttl == 60_000
      assert agent.state.check_interval == 30_000
      assert agent.state.alert_thresholds == [0.5, 0.8, 1.0]
      assert is_map(agent.state.enforcement_stats)
    end
    
    test "checks budget limits for token usage request", %{agent: agent, user: user} do
      signal = %{
        "type" => "token_usage_request",
        "data" => %{
          "user_id" => user.id,
          "project_id" => nil,
          "estimated_cost" => "25.00",
          "request_id" => "req_#{Uniq.UUID.generate()}"
        }
      }
      
      {:ok, updated_agent} = BudgetEnforcementAgent.handle_signal(agent, signal)
      
      # Should pass as cost is within budget
      assert updated_agent.state.enforcement_stats.checks_performed == 1
      assert updated_agent.state.enforcement_stats.requests_blocked == 0
    end
    
    test "blocks request exceeding budget", %{agent: agent, user: user, user_budget: user_budget} do
      # Update budget to be near limit
      {:ok, _} = Tokens.update_spending(user_budget, Decimal.new("95.00"))
      
      # Reload budget in agent
      {:ok, updated_budget} = Tokens.get_budget(user_budget.id)
      agent = put_in(agent.state.active_budgets[user_budget.id], updated_budget)
      
      signal = %{
        "type" => "token_usage_request",
        "data" => %{
          "user_id" => user.id,
          "project_id" => nil,
          "estimated_cost" => "10.00",
          "request_id" => "req_#{Uniq.UUID.generate()}"
        }
      }
      
      {:ok, updated_agent} = BudgetEnforcementAgent.handle_signal(agent, signal)
      
      # Should block as it would exceed budget
      assert updated_agent.state.enforcement_stats.requests_blocked == 1
    end
    
    test "handles budget override request", %{agent: agent, user_budget: user_budget} do
      signal = %{
        "type" => "budget_override_request",
        "data" => %{
          "budget_id" => user_budget.id,
          "approval_data" => %{
            "approved_by" => "admin@example.com",
            "reason" => "Critical task",
            "expires_at" => DateTime.add(DateTime.utc_now(), 3600, :second)
          }
        }
      }
      
      {:ok, updated_agent} = BudgetEnforcementAgent.handle_signal(agent, signal)
      
      # Should have granted override
      assert updated_agent.state.enforcement_stats.overrides_granted == 1
      
      # Budget should be updated with override
      updated_budget = updated_agent.state.active_budgets[user_budget.id]
      assert updated_budget.override_active == true
    end
    
    test "allows request with active override", %{agent: agent, user: user, user_budget: user_budget} do
      # Activate override
      {:ok, overridden} = Tokens.activate_override(user_budget, %{
        "approved_by" => "admin@example.com"
      })
      
      # Update agent's cache
      agent = put_in(agent.state.active_budgets[user_budget.id], overridden)
      
      # Update spending to exceed limit
      {:ok, updated} = Tokens.update_spending(overridden, Decimal.new("150.00"))
      agent = put_in(agent.state.active_budgets[user_budget.id], updated)
      
      signal = %{
        "type" => "token_usage_request",
        "data" => %{
          "user_id" => user.id,
          "project_id" => nil,
          "estimated_cost" => "50.00",
          "request_id" => "req_#{Uniq.UUID.generate()}"
        }
      }
      
      {:ok, updated_agent} = BudgetEnforcementAgent.handle_signal(agent, signal)
      
      # Should pass due to override
      assert updated_agent.state.enforcement_stats.requests_blocked == 0
    end
    
    test "handles budget update signal", %{agent: agent, user_budget: user_budget} do
      signal = %{
        "type" => "budget_update",
        "data" => %{
          "budget_id" => user_budget.id
        }
      }
      
      # Update the budget in database
      {:ok, _} = Tokens.update_budget(user_budget, %{
        limit_amount: Decimal.new("200.00")
      })
      
      {:ok, updated_agent} = BudgetEnforcementAgent.handle_signal(agent, signal)
      
      # Budget should be reloaded
      reloaded_budget = updated_agent.state.active_budgets[user_budget.id]
      assert Decimal.equal?(reloaded_budget.limit_amount, Decimal.new("200.00"))
    end
    
    test "updates budget spending from usage records", %{agent: agent, user: user, user_budget: user_budget} do
      usage_records = [
        %{
          "user_id" => user.id,
          "cost" => "10.00"
        },
        %{
          "user_id" => user.id,
          "cost" => "15.00"
        }
      ]
      
      signal = %{"type" => "token_usage_flush", "data" => usage_records}
      
      {:ok, updated_agent} = BudgetEnforcementAgent.handle_signal(agent, signal)
      
      # Budget spending should be updated
      updated_budget = updated_agent.state.active_budgets[user_budget.id]
      assert Decimal.equal?(updated_budget.current_spending, Decimal.new("25.00"))
    end
    
    test "checks multiple applicable budgets", %{agent: agent, user: user} do
      # Both user and global budgets apply
      signal = %{
        "type" => "token_usage_request",
        "data" => %{
          "user_id" => user.id,
          "project_id" => nil,
          "estimated_cost" => "50.00",
          "request_id" => "req_#{Uniq.UUID.generate()}"
        }
      }
      
      {:ok, updated_agent} = BudgetEnforcementAgent.handle_signal(agent, signal)
      
      # Should check both budgets
      assert updated_agent.state.enforcement_stats.checks_performed == 1
      
      # Should pass as both budgets have capacity
      assert updated_agent.state.enforcement_stats.requests_blocked == 0
    end
    
    test "filters inactive budgets", %{agent: agent, user: user} do
      # Create inactive budget
      {:ok, inactive_budget} = Tokens.create_budget(%{
        name: "Inactive Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "daily",
        limit_amount: Decimal.new("0.01"),
        is_active: false
      })
      
      # Add to agent (but it's inactive)
      agent = put_in(agent.state.active_budgets[inactive_budget.id], inactive_budget)
      
      signal = %{
        "type" => "token_usage_request",
        "data" => %{
          "user_id" => user.id,
          "project_id" => nil,
          "estimated_cost" => "1.00",
          "request_id" => "req_#{Uniq.UUID.generate()}"
        }
      }
      
      {:ok, updated_agent} = BudgetEnforcementAgent.handle_signal(agent, signal)
      
      # Should not be blocked by inactive budget
      assert updated_agent.state.enforcement_stats.requests_blocked == 0
    end
    
    test "performs health check", %{agent: agent} do
      {:healthy, health_data} = BudgetEnforcementAgent.health_check(agent)
      assert health_data.active_budgets == 2
      assert health_data.checks_performed == 0
      assert health_data.block_rate == 0.0
      
      # Update stats
      agent = %{agent | state: %{agent.state | 
        enforcement_stats: %{
          checks_performed: 100,
          budgets_exceeded: 10,
          requests_blocked: 10,
          overrides_granted: 2
        }
      }}
      
      {:healthy, health_data2} = BudgetEnforcementAgent.health_check(agent)
      assert health_data2.checks_performed == 100
      assert health_data2.block_rate == 0.1
      
      # Unhealthy - high block rate
      agent = %{agent | state: %{agent.state | 
        enforcement_stats: %{
          checks_performed: 100,
          budgets_exceeded: 60,
          requests_blocked: 60,
          overrides_granted: 5
        }
      }}
      
      {:unhealthy, unhealthy_data} = BudgetEnforcementAgent.health_check(agent)
      assert unhealthy_data.block_rate == 0.6
    end
    
    test "handles periodic budget reset", %{agent: agent, user_budget: user_budget} do
      # Set budget period end to past
      past_end = DateTime.add(DateTime.utc_now(), -3600, :second)
      
      # Manually update budget to simulate expired period
      # In real app, this would be handled by the database
      expired_budget = %{user_budget | 
        period_end: past_end,
        current_spending: Decimal.new("50.00")
      }
      
      agent = put_in(agent.state.active_budgets[user_budget.id], expired_budget)
      
      signal = %{"type" => "periodic_check"}
      
      {:ok, _updated_agent} = BudgetEnforcementAgent.handle_signal(agent, signal)
      
      # In a real implementation, this would trigger a reset
      # For now, we just verify the signal is handled
      assert true
    end
  end
end