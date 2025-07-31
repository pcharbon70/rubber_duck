defmodule RubberDuck.Tokens.Resources.TokenUsageTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.Tokens
  alias RubberDuck.Tokens.Resources.TokenUsage
  
  describe "token usage persistence" do
    setup do
      # Create a test user
      {:ok, user} = RubberDuck.Accounts.register_user(%{
        email: "test@example.com",
        password: "password123456"
      })
      
      %{user: user}
    end
    
    test "creates a token usage record", %{user: user} do
      attrs = %{
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150,
        cost: Decimal.new("0.0045"),
        currency: "USD",
        user_id: user.id,
        request_id: "req_#{Uniq.UUID.generate()}",
        feature: "code_analysis"
      }
      
      assert {:ok, usage} = Tokens.record_usage(attrs)
      assert usage.provider == "openai"
      assert usage.model == "gpt-4"
      assert usage.prompt_tokens == 100
      assert usage.completion_tokens == 50
      assert usage.total_tokens == 150
      assert Decimal.equal?(usage.cost, Decimal.new("0.0045"))
      assert usage.user_id == user.id
    end
    
    test "enforces unique request_id constraint", %{user: user} do
      request_id = "req_#{Uniq.UUID.generate()}"
      
      attrs = %{
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150,
        cost: Decimal.new("0.0045"),
        currency: "USD",
        user_id: user.id,
        request_id: request_id
      }
      
      assert {:ok, _usage1} = Tokens.record_usage(attrs)
      
      # Try to create another with same request_id
      assert {:error, error} = Tokens.record_usage(attrs)
      assert error.errors |> Enum.any?(fn e -> 
        e.field == :request_id && e.message =~ "has already been taken"
      end)
    end
    
    test "bulk creates multiple usage records", %{user: user} do
      records = Enum.map(1..5, fn i ->
        %{
          provider: "openai",
          model: "gpt-4",
          prompt_tokens: 100 * i,
          completion_tokens: 50 * i,
          total_tokens: 150 * i,
          cost: Decimal.mult(Decimal.new("0.001"), Decimal.new(i)),
          currency: "USD",
          user_id: user.id,
          request_id: "req_#{i}_#{Uniq.UUID.generate()}"
        }
      end)
      
      assert {:ok, results} = Tokens.bulk_record_usage(records)
      assert length(results) == 5
      assert Enum.all?(results, fn r -> r.provider == "openai" end)
    end
    
    test "queries usage by user", %{user: user} do
      # Create some usage records
      Enum.each(1..3, fn i ->
        Tokens.record_usage(%{
          provider: "openai",
          model: "gpt-4",
          prompt_tokens: 100,
          completion_tokens: 50,
          total_tokens: 150,
          cost: Decimal.new("0.0045"),
          currency: "USD",
          user_id: user.id,
          request_id: "req_#{i}_#{Uniq.UUID.generate()}"
        })
      end)
      
      # Create another user's record
      {:ok, other_user} = RubberDuck.Accounts.register_user(%{
        email: "other@example.com",
        password: "password123456"
      })
      
      Tokens.record_usage(%{
        provider: "anthropic",
        model: "claude-3",
        prompt_tokens: 200,
        completion_tokens: 100,
        total_tokens: 300,
        cost: Decimal.new("0.009"),
        currency: "USD",
        user_id: other_user.id,
        request_id: "req_other_#{Uniq.UUID.generate()}"
      })
      
      # Query user's usage
      assert {:ok, usage_list} = Tokens.list_user_usage(user.id)
      assert length(usage_list) == 3
      assert Enum.all?(usage_list, fn u -> u.user_id == user.id end)
    end
    
    test "aggregates token usage by user", %{user: user} do
      # Create usage records with known values
      Enum.each([100, 200, 300], fn tokens ->
        Tokens.record_usage(%{
          provider: "openai",
          model: "gpt-4",
          prompt_tokens: tokens,
          completion_tokens: div(tokens, 2),
          total_tokens: tokens + div(tokens, 2),
          cost: Decimal.mult(Decimal.new("0.00001"), Decimal.new(tokens)),
          currency: "USD",
          user_id: user.id,
          request_id: "req_#{tokens}_#{Uniq.UUID.generate()}"
        })
      end)
      
      # Sum tokens for user
      assert {:ok, result} = Tokens.sum_user_tokens(user.id)
      
      # Total should be (100+50) + (200+100) + (300+150) = 900
      assert result.total_tokens == 900
      assert result.request_count == 3
      assert Decimal.equal?(result.total_cost, Decimal.new("0.006"))
    end
    
    test "filters usage by date range", %{user: user} do
      # Create records at different times
      now = DateTime.utc_now()
      yesterday = DateTime.add(now, -86400, :second)
      last_week = DateTime.add(now, -604800, :second)
      
      # Record from yesterday
      {:ok, recent} = Tokens.record_usage(%{
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150,
        cost: Decimal.new("0.0045"),
        currency: "USD",
        user_id: user.id,
        request_id: "req_recent_#{Uniq.UUID.generate()}"
      })
      
      # Manually update timestamp (in real app, would use time travel in tests)
      # For now, we'll test with current timestamps
      
      # Query with date range
      assert {:ok, results} = Tokens.list_usage_in_range(
        DateTime.add(now, -172800, :second), # 2 days ago
        DateTime.add(now, 3600, :second)      # 1 hour from now
      )
      
      # Should include our recent record
      assert Enum.any?(results, fn r -> r.id == recent.id end)
    end
    
    test "loads user relationship", %{user: user} do
      {:ok, usage} = Tokens.record_usage(%{
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150,
        cost: Decimal.new("0.0045"),
        currency: "USD",
        user_id: user.id,
        request_id: "req_#{Uniq.UUID.generate()}"
      })
      
      # Load with user relationship
      {:ok, loaded} = Tokens.get_usage(usage.id, load: [:user])
      assert loaded.user.id == user.id
      assert loaded.user.email == "test@example.com"
    end
    
    test "validates required fields" do
      # Missing user_id
      assert {:error, error} = Tokens.record_usage(%{
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150,
        cost: Decimal.new("0.0045"),
        currency: "USD",
        request_id: "req_#{Uniq.UUID.generate()}"
      })
      
      assert error.errors |> Enum.any?(fn e -> 
        e.field == :user_id && e.message =~ "is required"
      end)
    end
    
    test "calculates total tokens correctly", %{user: user} do
      {:ok, usage} = Tokens.record_usage(%{
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 100,
        completion_tokens: 50,
        # Don't provide total_tokens, let it be calculated
        cost: Decimal.new("0.0045"),
        currency: "USD",
        user_id: user.id,
        request_id: "req_#{Uniq.UUID.generate()}"
      })
      
      assert usage.total_tokens == 150
    end
  end
end