defmodule RubberDuck.MCP.RateLimiterTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.RateLimiter

  setup do
    # Start a fresh rate limiter for each test
    {:ok, pid} = RateLimiter.start_link(name: nil)

    %{rate_limiter: pid}
  end

  describe "check_limit/3" do
    test "allows requests within limits", %{rate_limiter: pid} do
      # First request should succeed
      assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})

      # Multiple requests within limit should succeed
      for _ <- 1..5 do
        assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})
      end
    end

    test "enforces rate limits per client", %{rate_limiter: pid} do
      # Set a low limit for testing
      config = %{
        client_limits: %{
          normal: %{
            max_tokens: 5,
            # Very slow refill
            refill_rate: 0.1,
            burst_allowance: 0
          }
        }
      }

      GenServer.call(pid, {:update_config, config})

      # Consume all tokens
      for _ <- 1..5 do
        assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})
      end

      # Next request should be rate limited
      assert {:error, :rate_limited, retry_after: retry} =
               GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})

      assert retry > 0
    end

    test "applies different limits based on priority", %{rate_limiter: pid} do
      # High priority should have higher limits
      for _ <- 1..100 do
        assert :ok = GenServer.call(pid, {:check_limit, "vip_client", "tools/list", :high})
      end

      # Still within high priority limits
      assert :ok = GenServer.call(pid, {:check_limit, "vip_client", "tools/list", :high})
    end

    test "tracks different operations separately", %{rate_limiter: pid} do
      # Different operations should have separate buckets
      assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})
      assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/call", :normal})
      assert :ok = GenServer.call(pid, {:check_limit, "client1", "resources/list", :normal})
    end

    test "enforces global rate limits", %{rate_limiter: pid} do
      # Update config with very low global limit
      config = %{
        global_limits: %{
          max_tokens: 10,
          refill_rate: 0.1,
          burst_allowance: 0
        }
      }

      GenServer.call(pid, {:update_config, config})

      # Multiple clients consuming global tokens
      for i <- 1..10 do
        client = "client#{i}"
        assert :ok = GenServer.call(pid, {:check_limit, client, "tools/list", :normal})
      end

      # Global limit should be hit
      assert {:error, :rate_limited, retry_after: _} =
               GenServer.call(pid, {:check_limit, "client11", "tools/list", :normal})
    end
  end

  describe "set_client_limits/2" do
    test "sets custom limits for specific clients", %{rate_limiter: pid} do
      # Set very restrictive custom limits
      custom_limits = %{
        max_tokens: 2,
        refill_rate: 0.1,
        burst_allowance: 0
      }

      assert :ok = GenServer.call(pid, {:set_client_limits, "restricted_client", custom_limits})

      # Should only allow 2 requests
      assert :ok = GenServer.call(pid, {:check_limit, "restricted_client", "tools/list", :normal})
      assert :ok = GenServer.call(pid, {:check_limit, "restricted_client", "tools/list", :normal})

      # Third request should fail
      assert {:error, :rate_limited, retry_after: _} =
               GenServer.call(pid, {:check_limit, "restricted_client", "tools/list", :normal})
    end
  end

  describe "reset_client/1" do
    test "resets rate limit state for a client", %{rate_limiter: pid} do
      # Set low limits and exhaust them
      config = %{
        client_limits: %{
          normal: %{
            max_tokens: 2,
            refill_rate: 0.01,
            burst_allowance: 0
          }
        }
      }

      GenServer.call(pid, {:update_config, config})

      # Exhaust tokens
      assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})
      assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})

      assert {:error, :rate_limited, retry_after: _} =
               GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})

      # Reset the client
      assert :ok = GenServer.call(pid, {:reset_client, "client1"})

      # Should be able to make requests again
      assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})
    end
  end

  describe "get_stats/0" do
    test "returns rate limiter statistics", %{rate_limiter: pid} do
      # Make some requests
      for i <- 1..5 do
        GenServer.call(pid, {:check_limit, "client#{i}", "tools/list", :normal})
      end

      stats = GenServer.call(pid, :get_stats)

      assert is_map(stats)
      assert stats.requests_allowed > 0
      assert stats.active_buckets > 0
      assert is_list(stats.top_consumers)
    end
  end

  describe "token bucket algorithm" do
    test "refills tokens over time", %{rate_limiter: pid} do
      # Set config with fast refill for testing
      config = %{
        client_limits: %{
          normal: %{
            max_tokens: 2,
            # 10 tokens per second
            refill_rate: 10.0,
            burst_allowance: 0
          }
        }
      }

      GenServer.call(pid, {:update_config, config})

      # Exhaust tokens
      assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})
      assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})

      assert {:error, :rate_limited, retry_after: _} =
               GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})

      # Wait for refill
      # 0.2 seconds = 2 tokens refilled
      Process.sleep(200)

      # Should be able to make requests again
      assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})
    end

    test "respects burst allowance", %{rate_limiter: pid} do
      # Set config with burst allowance
      config = %{
        client_limits: %{
          normal: %{
            max_tokens: 5,
            refill_rate: 1.0,
            # Allow 3 extra tokens
            burst_allowance: 3
          }
        }
      }

      GenServer.call(pid, {:update_config, config})

      # Should be able to make max_tokens + burst_allowance requests
      # 5 + 3
      for _ <- 1..8 do
        assert :ok = GenServer.call(pid, {:check_limit, "burst_client", "tools/list", :normal})
      end

      # Next should fail
      assert {:error, :rate_limited, retry_after: _} =
               GenServer.call(pid, {:check_limit, "burst_client", "tools/list", :normal})
    end
  end

  describe "operation costs" do
    test "different operations consume different token amounts", %{rate_limiter: pid} do
      # Set low limit to test costs
      config = %{
        client_limits: %{
          normal: %{
            max_tokens: 20,
            refill_rate: 0.1,
            burst_allowance: 0
          }
        }
      }

      GenServer.call(pid, {:update_config, config})

      # tools/list costs 1 token (default)
      for _ <- 1..10 do
        assert :ok = GenServer.call(pid, {:check_limit, "client1", "tools/list", :normal})
      end

      # workflows/execute costs 20 tokens
      assert :ok = GenServer.call(pid, {:check_limit, "client2", "workflows/execute", :normal})

      # Next workflows/execute should fail (would need 20 tokens)
      assert {:error, :rate_limited, retry_after: _} =
               GenServer.call(pid, {:check_limit, "client2", "workflows/execute", :normal})
    end
  end
end
