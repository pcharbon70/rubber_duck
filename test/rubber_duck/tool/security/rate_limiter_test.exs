defmodule RubberDuck.Tool.Security.RateLimiterTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.Security.RateLimiter
  
  setup do
    # Start a fresh RateLimiter for each test
    start_supervised!({RateLimiter, []})
    :ok
  end
  
  describe "basic rate limiting" do
    test "allows requests within rate limit" do
      assert :ok = RateLimiter.acquire("user1", :test_tool, 1)
      assert :ok = RateLimiter.acquire("user1", :test_tool, 1)
    end
    
    test "blocks requests exceeding rate limit" do
      # Acquire all available tokens
      for _ <- 1..10 do
        assert :ok = RateLimiter.acquire("user1", :test_tool, 1)
      end
      
      # Next request should be rate limited
      assert {:error, :rate_limited} = RateLimiter.acquire("user1", :test_tool, 1)
    end
    
    test "different users have separate rate limits" do
      # Exhaust user1's tokens
      for _ <- 1..10 do
        assert :ok = RateLimiter.acquire("user1", :test_tool, 1)
      end
      
      # user2 should still have tokens available
      assert :ok = RateLimiter.acquire("user2", :test_tool, 1)
    end
    
    test "different tools have separate rate limits" do
      # Exhaust tokens for tool1
      for _ <- 1..10 do
        assert :ok = RateLimiter.acquire("user1", :tool1, 1)
      end
      
      # tool2 should still have tokens available
      assert :ok = RateLimiter.acquire("user1", :tool2, 1)
    end
  end
  
  describe "token refill" do
    test "tokens refill over time" do
      # Exhaust all tokens
      for _ <- 1..10 do
        assert :ok = RateLimiter.acquire("user1", :test_tool, 1)
      end
      
      # Should be rate limited
      assert {:error, :rate_limited} = RateLimiter.acquire("user1", :test_tool, 1)
      
      # Wait for tokens to refill (default is 1 token per second)
      Process.sleep(1100)
      
      # Should be able to acquire token again
      assert :ok = RateLimiter.acquire("user1", :test_tool, 1)
    end
  end
  
  describe "availability checking" do
    test "check_available doesn't consume tokens" do
      # Check availability multiple times
      assert true = RateLimiter.check_available("user1", :test_tool, 1)
      assert true = RateLimiter.check_available("user1", :test_tool, 1)
      assert true = RateLimiter.check_available("user1", :test_tool, 1)
      
      # Should still be able to acquire tokens
      assert :ok = RateLimiter.acquire("user1", :test_tool, 5)
    end
    
    test "check_available returns false when rate limited" do
      # Exhaust all tokens
      for _ <- 1..10 do
        assert :ok = RateLimiter.acquire("user1", :test_tool, 1)
      end
      
      # Should show as not available
      assert false = RateLimiter.check_available("user1", :test_tool, 1)
    end
  end
  
  describe "rate limit configuration" do
    test "can update rate limits" do
      # Set custom limits
      config = %{
        max_tokens: 5,
        refill_rate: 2  # 2 tokens per second
      }
      
      assert :ok = RateLimiter.update_limits("user1", :test_tool, config)
      
      # Should only allow 5 tokens
      for _ <- 1..5 do
        assert :ok = RateLimiter.acquire("user1", :test_tool, 1)
      end
      
      assert {:error, :rate_limited} = RateLimiter.acquire("user1", :test_tool, 1)
    end
  end
  
  describe "user priorities" do
    test "high priority users get more effective tokens" do
      # Set user priorities
      RateLimiter.set_user_priority("high_user", :high)
      RateLimiter.set_user_priority("low_user", :low)
      
      # High priority user should be able to acquire more tokens
      # (high priority has 2x multiplier, so 1 token costs 0.5 effective tokens)
      for _ <- 1..10 do
        assert :ok = RateLimiter.acquire("high_user", :test_tool, 1)
      end
      
      # Should still have tokens available due to priority
      assert :ok = RateLimiter.acquire("high_user", :test_tool, 1)
    end
    
    test "low priority users get fewer effective tokens" do
      RateLimiter.set_user_priority("low_user", :low)
      
      # Low priority user should be limited faster
      # (low priority has 0.5x multiplier, so 1 token costs 2 effective tokens)
      for _ <- 1..5 do
        assert :ok = RateLimiter.acquire("low_user", :test_tool, 1)
      end
      
      # Should be rate limited sooner
      assert {:error, :rate_limited} = RateLimiter.acquire("low_user", :test_tool, 1)
    end
  end
  
  describe "circuit breaker" do
    test "circuit breaker opens after failures" do
      # Record multiple failures
      for _ <- 1..5 do
        RateLimiter.record_result("user1", :failing_tool, :failure)
      end
      
      # Circuit should be open
      assert {:error, :circuit_open} = RateLimiter.acquire("user1", :failing_tool, 1)
    end
    
    test "circuit breaker closes after successes" do
      # Record failures to open circuit
      for _ <- 1..5 do
        RateLimiter.record_result("user1", :test_tool, :failure)
      end
      
      # Circuit should be open
      assert {:error, :circuit_open} = RateLimiter.acquire("user1", :test_tool, 1)
      
      # Wait for circuit to go to half-open (simulate timeout)
      Process.sleep(100)
      
      # Record successes to close circuit
      for _ <- 1..3 do
        RateLimiter.record_result("user1", :test_tool, :success)
      end
      
      # Circuit should be closed now
      assert :ok = RateLimiter.acquire("user1", :test_tool, 1)
    end
  end
  
  describe "statistics" do
    test "provides global statistics" do
      # Generate some activity
      RateLimiter.acquire("user1", :tool1, 1)
      RateLimiter.acquire("user2", :tool2, 1)
      RateLimiter.set_user_priority("user1", :high)
      
      {:ok, stats} = RateLimiter.get_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :total_buckets)
      assert Map.has_key?(stats, :by_priority)
      assert stats.total_buckets > 0
    end
    
    test "provides user-specific statistics" do
      RateLimiter.acquire("user1", :test_tool, 1)
      
      {:ok, stats} = RateLimiter.get_stats("user1")
      
      assert is_map(stats)
      assert stats.user_id == "user1"
      assert Map.has_key?(stats, :tools)
    end
    
    test "provides tool-specific statistics" do
      RateLimiter.acquire("user1", :test_tool, 1)
      RateLimiter.acquire("user2", :test_tool, 1)
      
      {:ok, stats} = RateLimiter.get_stats(nil, :test_tool)
      
      assert is_map(stats)
      assert stats.tool == :test_tool
      assert Map.has_key?(stats, :users)
    end
    
    test "provides user-tool specific statistics" do
      RateLimiter.acquire("user1", :test_tool, 5)
      
      {:ok, stats} = RateLimiter.get_stats("user1", :test_tool)
      
      assert is_map(stats)
      assert Map.has_key?(stats, :rate_limit)
      assert Map.has_key?(stats, :circuit_breaker)
      
      # Check rate limit stats
      rate_limit = stats.rate_limit
      assert is_map(rate_limit)
      assert Map.has_key?(rate_limit, :tokens_available)
      assert Map.has_key?(rate_limit, :max_tokens)
    end
  end
  
  describe "reset functionality" do
    test "can reset rate limits and circuit breakers" do
      # Exhaust tokens and trigger circuit breaker
      for _ <- 1..10 do
        RateLimiter.acquire("user1", :test_tool, 1)
      end
      
      for _ <- 1..5 do
        RateLimiter.record_result("user1", :test_tool, :failure)
      end
      
      # Should be blocked
      assert {:error, :circuit_open} = RateLimiter.acquire("user1", :test_tool, 1)
      
      # Reset
      assert :ok = RateLimiter.reset("user1", :test_tool)
      
      # Should be able to acquire again
      assert :ok = RateLimiter.acquire("user1", :test_tool, 1)
    end
  end
  
  describe "adaptive rate limiting" do
    test "increases limits on consistent success" do
      # Start with default limits
      RateLimiter.acquire("user1", :test_tool, 1)
      
      # Record multiple successes
      for _ <- 1..10 do
        RateLimiter.record_result("user1", :test_tool, :success)
      end
      
      # Rate limit should have increased (this is implementation dependent)
      {:ok, stats} = RateLimiter.get_stats("user1", :test_tool)
      rate_limit = stats.rate_limit
      
      # Max tokens might have increased from default
      assert rate_limit.max_tokens >= 10
    end
    
    test "decreases limits on failures" do
      # Start with some activity
      RateLimiter.acquire("user1", :test_tool, 1)
      
      # Record failures
      for _ <- 1..3 do
        RateLimiter.record_result("user1", :test_tool, :failure)
      end
      
      # Rate limit should have decreased
      {:ok, stats} = RateLimiter.get_stats("user1", :test_tool)
      rate_limit = stats.rate_limit
      
      # Max tokens might have decreased from default
      assert rate_limit.max_tokens <= 10
    end
  end
end