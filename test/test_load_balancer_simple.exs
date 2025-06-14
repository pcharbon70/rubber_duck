defmodule TestLoadBalancerSimple do
  @moduledoc """
  Simple test to verify load balancer components work.
  """

  alias RubberDuck.LLMAbstraction.{
    LoadBalancer,
    RateLimiter,
    CircuitBreaker
  }

  alias RubberDuck.LLMAbstraction.LoadBalancer.{
    ConsistentHash,
    RoutingStrategy,
    ProviderScorer
  }

  def test_consistent_hash do
    # Test basic consistent hash functionality
    hash_ring = ConsistentHash.new()
    |> ConsistentHash.add_key("provider1")
    |> ConsistentHash.add_key("provider2")
    |> ConsistentHash.add_key("provider3")

    # Test that same input maps to same provider
    provider1 = ConsistentHash.get_key(hash_ring, "test_session_1")
    provider2 = ConsistentHash.get_key(hash_ring, "test_session_1")

    IO.puts("Consistent hash test: #{provider1 == provider2}")
    
    # Test stats
    stats = ConsistentHash.stats(hash_ring)
    IO.puts("Hash ring stats: #{inspect(stats)}")

    :ok
  end

  def test_routing_strategy do
    # Test weighted selection
    providers = [
      {"provider1", 0.5},
      {"provider2", 0.3},
      {"provider3", 0.2}
    ]

    selected = RoutingStrategy.weighted_selection(providers)
    IO.puts("Weighted selection result: #{selected}")

    # Test round robin
    provider_list = ["provider1", "provider2", "provider3"]
    {selected_rr, next_index} = RoutingStrategy.round_robin_selection(provider_list, 0)
    IO.puts("Round robin selection: #{selected_rr}, next index: #{next_index}")

    :ok
  end

  def test_rate_limiter do
    # Test rate limiter configuration
    limits = %{
      chat: %{
        requests_per_minute: 10,
        api_key_requests_per_minute: 5,
        tokens_per_minute: 1000
      }
    }

    RateLimiter.configure_provider_limits(:test_provider, limits)
    
    # Get configured limits
    configured = RateLimiter.get_provider_limits(:test_provider)
    IO.puts("Rate limiter test: #{inspect(configured.chat)}")

    :ok
  end

  def run_all_tests do
    IO.puts("=== Testing Load Balancer Components ===")
    
    test_consistent_hash()
    test_routing_strategy()
    test_rate_limiter()
    
    IO.puts("=== All tests completed ===")
  end
end

# Run the tests
TestLoadBalancerSimple.run_all_tests()