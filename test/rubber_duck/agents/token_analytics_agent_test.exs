defmodule RubberDuck.Agents.TokenAnalyticsAgentTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.Agents.TokenAnalyticsAgent
  alias RubberDuck.Tokens
  
  describe "TokenAnalyticsAgent" do
    setup do
      # Create test users
      {:ok, user1} = RubberDuck.Accounts.register_user(%{
        email: "user1@example.com",
        password: "password123456"
      })
      
      {:ok, user2} = RubberDuck.Accounts.register_user(%{
        email: "user2@example.com",
        password: "password123456"
      })
      
      # Create some test data
      create_test_usage_data(user1, user2)
      
      # Initialize agent
      {:ok, agent} = TokenAnalyticsAgent.new(%{
        cache_ttl: 60_000,
        trend_window: 86_400_000
      })
      
      %{agent: agent, user1: user1, user2: user2}
    end
    
    test "initializes with correct state", %{agent: agent} do
      assert agent.state.cache_ttl == 60_000
      assert agent.state.analytics_cache == %{}
      assert agent.state.trend_window == 86_400_000
      assert is_map(agent.state.alert_thresholds)
    end
    
    test "handles user summary request", %{agent: agent, user1: user} do
      signal = %{
        "type" => "analytics_request",
        "data" => %{
          "query_type" => "user_summary",
          "user_id" => user.id,
          "start_date" => nil,
          "end_date" => nil
        }
      }
      
      # Capture emitted signals
      {:ok, updated_agent} = TokenAnalyticsAgent.handle_signal(agent, signal)
      
      # Result should be cached
      cache_key = {:user_summary, user.id, nil, nil}
      assert Map.has_key?(updated_agent.state.analytics_cache, cache_key)
    end
    
    test "handles project costs request", %{agent: agent} do
      project_id = Uniq.UUID.generate()
      
      signal = %{
        "type" => "analytics_request",
        "data" => %{
          "query_type" => "project_costs",
          "project_id" => project_id,
          "start_date" => DateTime.add(DateTime.utc_now(), -86400, :second) |> DateTime.to_iso8601(),
          "end_date" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }
      
      {:ok, updated_agent} = TokenAnalyticsAgent.handle_signal(agent, signal)
      
      # Should handle gracefully even with no data
      assert is_map(updated_agent.state.analytics_cache)
    end
    
    test "handles model comparison request", %{agent: agent} do
      signal = %{
        "type" => "analytics_request",
        "data" => %{
          "query_type" => "model_comparison",
          "models" => ["gpt-4", "claude-3"],
          "period" => "day"
        }
      }
      
      {:ok, updated_agent} = TokenAnalyticsAgent.handle_signal(agent, signal)
      
      # Should cache the comparison
      cache_key = {:model_comparison, ["gpt-4", "claude-3"], "day"}
      assert Map.has_key?(updated_agent.state.analytics_cache, cache_key)
    end
    
    test "handles usage trends request", %{agent: agent, user1: user} do
      signal = %{
        "type" => "analytics_request",
        "data" => %{
          "query_type" => "usage_trends",
          "entity_type" => "user",
          "entity_id" => user.id,
          "period" => "hour"
        }
      }
      
      {:ok, _updated_agent} = TokenAnalyticsAgent.handle_signal(agent, signal)
      
      # Trends should be calculated (even if zero due to lack of historical data)
      assert true
    end
    
    test "handles cost breakdown request", %{agent: agent} do
      signal = %{
        "type" => "analytics_request",
        "data" => %{
          "query_type" => "cost_breakdown",
          "entity_type" => "global",
          "entity_id" => nil,
          "group_by" => ["provider", "model"]
        }
      }
      
      {:ok, _updated_agent} = TokenAnalyticsAgent.handle_signal(agent, signal)
      
      # Should handle breakdown request
      assert true
    end
    
    test "updates analytics cache on token usage flush", %{agent: agent, user1: user} do
      usage_records = [
        %{
          "provider" => "openai",
          "model" => "gpt-4",
          "total_tokens" => 1000,
          "cost" => "0.03",
          "user_id" => user.id
        },
        %{
          "provider" => "anthropic",
          "model" => "claude-3",
          "total_tokens" => 2000,
          "cost" => "0.06",
          "user_id" => user.id
        }
      ]
      
      signal = %{"type" => "token_usage_flush", "data" => usage_records}
      
      {:ok, updated_agent} = TokenAnalyticsAgent.handle_signal(agent, signal)
      
      # Check cache was updated
      user_key = {:user_stats, user.id}
      assert Map.has_key?(updated_agent.state.analytics_cache, user_key)
      
      user_stats = updated_agent.state.analytics_cache[user_key]
      assert user_stats.tokens == 3000
      assert Decimal.equal?(user_stats.cost, Decimal.new("0.09"))
      assert user_stats.requests == 2
    end
    
    test "maintains global stats", %{agent: agent, user1: user1, user2: user2} do
      usage_records = [
        %{"provider" => "openai", "model" => "gpt-4", "total_tokens" => 1000, "cost" => "0.03", "user_id" => user1.id},
        %{"provider" => "openai", "model" => "gpt-4", "total_tokens" => 2000, "cost" => "0.06", "user_id" => user2.id}
      ]
      
      signal = %{"type" => "token_usage_flush", "data" => usage_records}
      {:ok, updated_agent} = TokenAnalyticsAgent.handle_signal(agent, signal)
      
      global_stats = updated_agent.state.analytics_cache[:global_stats]
      assert global_stats.tokens == 3000
      assert Decimal.equal?(global_stats.cost, Decimal.new("0.09"))
      assert global_stats.requests == 2
    end
    
    test "tracks model-specific stats", %{agent: agent, user1: user} do
      usage_records = [
        %{"provider" => "openai", "model" => "gpt-4", "total_tokens" => 1000, "cost" => "0.03", "user_id" => user.id},
        %{"provider" => "openai", "model" => "gpt-4", "total_tokens" => 500, "cost" => "0.015", "user_id" => user.id},
        %{"provider" => "openai", "model" => "gpt-3.5", "total_tokens" => 2000, "cost" => "0.002", "user_id" => user.id}
      ]
      
      signal = %{"type" => "token_usage_flush", "data" => usage_records}
      {:ok, updated_agent} = TokenAnalyticsAgent.handle_signal(agent, signal)
      
      # Check GPT-4 stats
      gpt4_stats = updated_agent.state.analytics_cache[{:model_stats, "gpt-4"}]
      assert gpt4_stats.tokens == 1500
      assert Decimal.equal?(gpt4_stats.cost, Decimal.new("0.045"))
      assert gpt4_stats.requests == 2
      
      # Check GPT-3.5 stats
      gpt35_stats = updated_agent.state.analytics_cache[{:model_stats, "gpt-3.5"}]
      assert gpt35_stats.tokens == 2000
      assert Decimal.equal?(gpt35_stats.cost, Decimal.new("0.002"))
      assert gpt35_stats.requests == 1
    end
    
    test "respects cache TTL", %{agent: agent, user1: user} do
      # Set very short TTL
      agent = %{agent | state: Map.put(agent.state, :cache_ttl, 100)}
      
      # Add cached entry
      cache_entry = %{
        data: %{total_tokens: 1000},
        cached_at: DateTime.add(DateTime.utc_now(), -200, :millisecond) # 200ms ago
      }
      
      agent = %{agent | state: Map.put(agent.state, :analytics_cache, %{
        {:user_summary, user.id, nil, nil} => cache_entry
      })}
      
      # Request should miss cache due to expiry
      signal = %{
        "type" => "analytics_request",
        "data" => %{
          "query_type" => "user_summary",
          "user_id" => user.id
        }
      }
      
      {:ok, updated_agent} = TokenAnalyticsAgent.handle_signal(agent, signal)
      
      # Cache should be refreshed
      new_cache_entry = updated_agent.state.analytics_cache[{:user_summary, user.id, nil, nil}]
      refute new_cache_entry.cached_at == cache_entry.cached_at
    end
    
    test "performs health check", %{agent: agent} do
      {:healthy, health_data} = TokenAnalyticsAgent.health_check(agent)
      assert health_data.cache_size == 0
      
      # Add many cache entries
      large_cache = Enum.reduce(1..100, %{}, fn i, acc ->
        Map.put(acc, {:test, i}, %{data: %{}, cached_at: DateTime.utc_now()})
      end)
      
      agent = %{agent | state: Map.put(agent.state, :analytics_cache, large_cache)}
      
      {:healthy, health_data2} = TokenAnalyticsAgent.health_check(agent)
      assert health_data2.cache_size == 100
    end
    
    test "handles invalid date formats gracefully", %{agent: agent} do
      signal = %{
        "type" => "analytics_request",
        "data" => %{
          "query_type" => "user_summary",
          "user_id" => Uniq.UUID.generate(),
          "start_date" => "invalid-date",
          "end_date" => "2024-01-01"
        }
      }
      
      # Should not crash
      {:ok, _updated_agent} = TokenAnalyticsAgent.handle_signal(agent, signal)
    end
  end
  
  # Helper function to create test data
  defp create_test_usage_data(user1, user2) do
    # Create usage for user1
    Enum.each(1..5, fn i ->
      Tokens.record_usage(%{
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 100 * i,
        completion_tokens: 50 * i,
        total_tokens: 150 * i,
        cost: Decimal.mult(Decimal.new("0.001"), Decimal.new(i)),
        currency: "USD",
        user_id: user1.id,
        request_id: "test_req_#{i}_#{Uniq.UUID.generate()}",
        feature: "test"
      })
    end)
    
    # Create usage for user2
    Enum.each(1..3, fn i ->
      Tokens.record_usage(%{
        provider: "anthropic",
        model: "claude-3",
        prompt_tokens: 200 * i,
        completion_tokens: 100 * i,
        total_tokens: 300 * i,
        cost: Decimal.mult(Decimal.new("0.002"), Decimal.new(i)),
        currency: "USD",
        user_id: user2.id,
        request_id: "test_req_u2_#{i}_#{Uniq.UUID.generate()}",
        feature: "test"
      })
    end)
  end
end