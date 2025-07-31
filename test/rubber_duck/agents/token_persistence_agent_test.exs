defmodule RubberDuck.Agents.TokenPersistenceAgentTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.Agents.TokenPersistenceAgent
  alias RubberDuck.Tokens
  
  describe "TokenPersistenceAgent" do
    setup do
      # Create test user
      {:ok, user} = RubberDuck.Accounts.register_user(%{
        email: "test@example.com",
        password: "password123456"
      })
      
      # Initialize agent
      {:ok, agent} = TokenPersistenceAgent.new(%{
        buffer_size: 5,
        flush_interval: 1000,
        retry_attempts: 2
      })
      
      %{agent: agent, user: user}
    end
    
    test "initializes with correct state", %{agent: agent} do
      assert agent.state.buffer == []
      assert agent.state.buffer_size == 5
      assert agent.state.flush_interval == 1000
      assert agent.state.retry_attempts == 2
      assert agent.state.stats.persisted_count == 0
    end
    
    test "handles token_usage_flush signal", %{agent: agent, user: user} do
      usage_records = [
        %{
          "provider" => "openai",
          "model" => "gpt-4",
          "prompt_tokens" => 100,
          "completion_tokens" => 50,
          "total_tokens" => 150,
          "cost" => "0.0045",
          "currency" => "USD",
          "user_id" => user.id,
          "request_id" => "req_1_#{Uniq.UUID.generate()}"
        },
        %{
          "provider" => "anthropic",
          "model" => "claude-3",
          "prompt_tokens" => 200,
          "completion_tokens" => 100,
          "total_tokens" => 300,
          "cost" => "0.009",
          "currency" => "USD",
          "user_id" => user.id,
          "request_id" => "req_2_#{Uniq.UUID.generate()}"
        }
      ]
      
      signal = %{"type" => "token_usage_flush", "data" => usage_records}
      
      {:ok, updated_agent} = TokenPersistenceAgent.handle_signal(agent, signal)
      
      # Should add to buffer
      assert length(updated_agent.state.buffer) == 2
    end
    
    test "flushes buffer when full", %{agent: agent, user: user} do
      # Set smaller buffer size
      agent = %{agent | state: Map.put(agent.state, :buffer_size, 2)}
      
      # Add records to fill buffer
      usage_records = Enum.map(1..2, fn i ->
        %{
          "provider" => "openai",
          "model" => "gpt-4",
          "prompt_tokens" => 100 * i,
          "completion_tokens" => 50 * i,
          "total_tokens" => 150 * i,
          "cost" => to_string(0.001 * i),
          "currency" => "USD",
          "user_id" => user.id,
          "request_id" => "req_#{i}_#{Uniq.UUID.generate()}"
        }
      end)
      
      signal = %{"type" => "token_usage_flush", "data" => usage_records}
      
      {:ok, updated_agent} = TokenPersistenceAgent.handle_signal(agent, signal)
      
      # Buffer should be empty after flush
      assert updated_agent.state.buffer == []
      assert updated_agent.state.stats.persisted_count == 2
      
      # Verify records were persisted
      {:ok, persisted} = Tokens.list_user_usage(user.id)
      assert length(persisted) == 2
    end
    
    test "handles single usage record signal", %{agent: agent, user: user} do
      usage_record = %{
        "provider" => "openai",
        "model" => "gpt-4",
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150,
        "cost" => "0.0045",
        "currency" => "USD",
        "user_id" => user.id,
        "request_id" => "req_single_#{Uniq.UUID.generate()}"
      }
      
      signal = %{"type" => "token_usage_single", "data" => usage_record}
      
      {:ok, updated_agent} = TokenPersistenceAgent.handle_signal(agent, signal)
      
      # Should add to buffer
      assert length(updated_agent.state.buffer) == 1
      assert hd(updated_agent.state.buffer) == usage_record
    end
    
    test "handles shutdown signal with buffer flush", %{agent: agent, user: user} do
      # Add some records to buffer
      agent = %{agent | state: Map.put(agent.state, :buffer, [
        %{
          "provider" => "openai",
          "model" => "gpt-4",
          "prompt_tokens" => 100,
          "completion_tokens" => 50,
          "total_tokens" => 150,
          "cost" => "0.0045",
          "currency" => "USD",
          "user_id" => user.id,
          "request_id" => "req_shutdown_#{Uniq.UUID.generate()}"
        }
      ])}
      
      signal = %{"type" => "shutdown"}
      
      {:ok, updated_agent} = TokenPersistenceAgent.handle_signal(agent, signal)
      
      # Buffer should be flushed
      assert updated_agent.state.buffer == []
      assert updated_agent.state.stats.persisted_count == 1
    end
    
    test "handles periodic flush signal", %{agent: agent, user: user} do
      # Add record and set last_flush to trigger flush
      agent = %{agent | state: agent.state
        |> Map.put(:buffer, [%{
          "provider" => "openai",
          "model" => "gpt-4",
          "prompt_tokens" => 100,
          "completion_tokens" => 50,
          "total_tokens" => 150,
          "cost" => "0.0045",
          "currency" => "USD",
          "user_id" => user.id,
          "request_id" => "req_timer_#{Uniq.UUID.generate()}"
        }])
        |> Map.put(:last_flush, DateTime.add(DateTime.utc_now(), -10, :second))
      }
      
      signal = %{"type" => "flush_timer"}
      
      {:ok, updated_agent} = TokenPersistenceAgent.handle_signal(agent, signal)
      
      # Should have flushed
      assert updated_agent.state.buffer == []
    end
    
    test "transforms records correctly", %{agent: agent, user: user} do
      # Test with both string and atom keys
      mixed_records = [
        %{
          "provider" => "openai",
          "model" => "gpt-4",
          "prompt_tokens" => 100,
          "completion_tokens" => 50,
          "total_tokens" => 150,
          "cost" => "0.0045",
          "currency" => "USD",
          "user_id" => user.id,
          "request_id" => "req_string_#{Uniq.UUID.generate()}"
        },
        %{
          provider: "anthropic",
          model: "claude-3",
          prompt_tokens: 200,
          completion_tokens: 100,
          total_tokens: 300,
          cost: 0.009,
          currency: "USD",
          user_id: user.id,
          request_id: "req_atom_#{Uniq.UUID.generate()}"
        }
      ]
      
      # Fill buffer to trigger flush
      agent = %{agent | state: Map.put(agent.state, :buffer_size, 2)}
      signal = %{"type" => "token_usage_flush", "data" => mixed_records}
      
      {:ok, updated_agent} = TokenPersistenceAgent.handle_signal(agent, signal)
      
      # Should have persisted both
      assert updated_agent.state.stats.persisted_count == 2
      
      # Verify in database
      {:ok, persisted} = Tokens.list_user_usage(user.id)
      assert length(persisted) == 2
    end
    
    test "handles persistence errors gracefully", %{agent: agent} do
      # Add invalid record (missing user_id)
      invalid_records = [
        %{
          "provider" => "openai",
          "model" => "gpt-4",
          "prompt_tokens" => 100,
          "completion_tokens" => 50,
          "total_tokens" => 150,
          "cost" => "0.0045",
          "currency" => "USD",
          "request_id" => "req_invalid_#{Uniq.UUID.generate()}"
          # Missing user_id
        }
      ]
      
      agent = %{agent | state: Map.put(agent.state, :buffer_size, 1)}
      signal = %{"type" => "token_usage_flush", "data" => invalid_records}
      
      {:ok, updated_agent} = TokenPersistenceAgent.handle_signal(agent, signal)
      
      # Should have cleared buffer but incremented failed count
      assert updated_agent.state.buffer == []
      assert updated_agent.state.stats.failed_count == 1
      assert updated_agent.state.stats.persisted_count == 0
    end
    
    test "performs health check", %{agent: agent} do
      # Healthy state
      {:healthy, health_data} = TokenPersistenceAgent.health_check(agent)
      assert health_data.buffer_size == 0
      assert health_data.failure_rate == 0.0
      
      # Add some stats
      agent = %{agent | state: %{agent.state | 
        stats: %{
          persisted_count: 100,
          failed_count: 5,
          retry_count: 2
        }
      }}
      
      {:healthy, health_data2} = TokenPersistenceAgent.health_check(agent)
      assert health_data2.failure_rate == 5 / 105
      
      # Unhealthy - high failure rate
      agent = %{agent | state: %{agent.state | 
        stats: %{
          persisted_count: 10,
          failed_count: 5,
          retry_count: 10
        }
      }}
      
      {:unhealthy, unhealthy_data} = TokenPersistenceAgent.health_check(agent)
      assert unhealthy_data.failure_rate > 0.1
    end
    
    test "respects buffer size limits", %{agent: agent, user: user} do
      # Don't flush until buffer is full
      agent = %{agent | state: Map.put(agent.state, :buffer_size, 10)}
      
      # Add 5 records (less than buffer size)
      records = Enum.map(1..5, fn i ->
        %{
          "provider" => "openai",
          "model" => "gpt-4",
          "prompt_tokens" => 100,
          "completion_tokens" => 50,
          "total_tokens" => 150,
          "cost" => "0.0045",
          "currency" => "USD",
          "user_id" => user.id,
          "request_id" => "req_#{i}_#{Uniq.UUID.generate()}"
        }
      end)
      
      signal = %{"type" => "token_usage_flush", "data" => records}
      {:ok, updated_agent} = TokenPersistenceAgent.handle_signal(agent, signal)
      
      # Should still be in buffer
      assert length(updated_agent.state.buffer) == 5
      assert updated_agent.state.stats.persisted_count == 0
      
      # Verify nothing persisted yet
      {:ok, persisted} = Tokens.list_user_usage(user.id)
      assert length(persisted) == 0
    end
  end
end