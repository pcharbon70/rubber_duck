defmodule RubberDuck.LoadBalancing.LoadBalancerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.LoadBalancing.LoadBalancer
  
  # Mock provider module for testing
  defmodule MockProvider do
    def capabilities(_state) do
      %{
        models: ["test-model"],
        request_types: [:chat, :completion],
        features: [:streaming]
      }
    end
  end
  
  defmodule MockProviderGPT do
    def capabilities(_state) do
      %{
        models: ["gpt-4", "gpt-3.5-turbo"],
        request_types: [:chat, :completion],
        features: [:streaming, :function_calling]
      }
    end
  end
  
  setup do
    # Start the load balancer for each test
    {:ok, _pid} = LoadBalancer.start_link()
    
    # Clean up any existing providers
    stats = LoadBalancer.get_provider_stats()
    Enum.each(stats, fn {provider_id, _info} ->
      LoadBalancer.remove_provider(provider_id)
    end)
    
    :ok
  end
  
  describe "add_provider/3" do
    test "adds a provider successfully" do
      assert :ok = LoadBalancer.add_provider(:test_provider, MockProvider, %{weight: 100})
      
      stats = LoadBalancer.get_provider_stats()
      assert Map.has_key?(stats, :test_provider)
      
      provider_info = stats[:test_provider]
      assert provider_info.id == :test_provider
      assert provider_info.module == MockProvider
      assert provider_info.weight == 100
      assert provider_info.health_score == 1.0
      assert provider_info.active_connections == 0
    end
    
    test "adds provider with custom health score" do
      assert :ok = LoadBalancer.add_provider(:test_provider, MockProvider, %{health_score: 0.8})
      
      stats = LoadBalancer.get_provider_stats()
      provider_info = stats[:test_provider]
      assert provider_info.health_score == 0.8
    end
  end
  
  describe "remove_provider/1" do
    test "removes an existing provider" do
      LoadBalancer.add_provider(:test_provider, MockProvider)
      assert :ok = LoadBalancer.remove_provider(:test_provider)
      
      stats = LoadBalancer.get_provider_stats()
      refute Map.has_key?(stats, :test_provider)
    end
    
    test "removing non-existent provider succeeds" do
      assert :ok = LoadBalancer.remove_provider(:non_existent)
    end
  end
  
  describe "route_request/2 with round_robin strategy" do
    setup do
      LoadBalancer.set_routing_strategy(:round_robin)
      :ok
    end
    
    test "routes to providers in round-robin fashion" do
      LoadBalancer.add_provider(:provider1, MockProvider)
      LoadBalancer.add_provider(:provider2, MockProvider)
      LoadBalancer.add_provider(:provider3, MockProvider)
      
      # Make several requests and verify round-robin behavior
      results = for _i <- 1..9 do
        {:ok, provider_id} = LoadBalancer.route_request(%{})
        provider_id
      end
      
      # Should cycle through providers
      assert Enum.take(results, 3) |> Enum.sort() == [:provider1, :provider2, :provider3]
      assert Enum.drop(results, 3) |> Enum.take(3) |> Enum.sort() == [:provider1, :provider2, :provider3]
    end
    
    test "returns error when no providers available" do
      result = LoadBalancer.route_request(%{})
      assert result == {:error, :no_available_providers}
    end
    
    test "skips unhealthy providers" do
      LoadBalancer.add_provider(:healthy, MockProvider)
      LoadBalancer.add_provider(:unhealthy, MockProvider, %{health_score: 0.3})
      
      # Multiple requests should only go to healthy provider
      results = for _i <- 1..5 do
        {:ok, provider_id} = LoadBalancer.route_request(%{})
        provider_id
      end
      
      assert Enum.all?(results, &(&1 == :healthy))
    end
  end
  
  describe "route_request/2 with weighted strategy" do
    setup do
      LoadBalancer.set_routing_strategy(:weighted)
      :ok
    end
    
    test "distributes load according to weights" do
      LoadBalancer.add_provider(:heavy, MockProvider, %{weight: 300})
      LoadBalancer.add_provider(:light, MockProvider, %{weight: 100})
      
      # Make many requests to see weight distribution
      results = for _i <- 1..100 do
        {:ok, provider_id} = LoadBalancer.route_request(%{})
        provider_id
      end
      
      heavy_count = Enum.count(results, &(&1 == :heavy))
      light_count = Enum.count(results, &(&1 == :light))
      
      # Heavy should get roughly 3x more requests (75% vs 25%)
      assert heavy_count > light_count * 2
      assert heavy_count > 60  # Should be around 75
      assert light_count > 15  # Should be around 25
    end
    
    test "considers health score in weighting" do
      LoadBalancer.add_provider(:healthy_heavy, MockProvider, %{weight: 200, health_score: 1.0})
      LoadBalancer.add_provider(:unhealthy_heavy, MockProvider, %{weight: 200, health_score: 0.5})
      
      results = for _i <- 1..50 do
        {:ok, provider_id} = LoadBalancer.route_request(%{})
        provider_id
      end
      
      healthy_count = Enum.count(results, &(&1 == :healthy_heavy))
      unhealthy_count = Enum.count(results, &(&1 == :unhealthy_heavy))
      
      # Healthy provider should get more requests due to better health score
      assert healthy_count > unhealthy_count
    end
  end
  
  describe "route_request/2 with least_connections strategy" do
    setup do
      LoadBalancer.set_routing_strategy(:least_connections)
      :ok
    end
    
    test "routes to provider with fewest connections" do
      LoadBalancer.add_provider(:provider1, MockProvider)
      LoadBalancer.add_provider(:provider2, MockProvider)
      
      # Simulate connections on provider1
      LoadBalancer.connection_opened(:provider1)
      LoadBalancer.connection_opened(:provider1)
      
      # Next request should go to provider2 (fewer connections)
      {:ok, provider_id} = LoadBalancer.route_request(%{})
      assert provider_id == :provider2
    end
  end
  
  describe "route_request/2 with capability_based strategy" do
    setup do
      LoadBalancer.set_routing_strategy(:capability_based)
      :ok
    end
    
    test "routes based on provider capabilities" do
      LoadBalancer.add_provider(:generic_provider, MockProvider)
      LoadBalancer.add_provider(:gpt_provider, MockProviderGPT)
      
      # Request for GPT-4 should go to GPT provider
      {:ok, provider_id} = LoadBalancer.route_request(%{model: "gpt-4", type: :chat})
      assert provider_id == :gpt_provider
      
      # Generic request should work with either
      {:ok, _provider_id} = LoadBalancer.route_request(%{type: :chat})
    end
    
    test "considers provider performance in scoring" do
      LoadBalancer.add_provider(:slow_provider, MockProvider, %{weight: 50})
      LoadBalancer.add_provider(:fast_provider, MockProvider, %{weight: 150})
      
      # Fast provider should be preferred due to higher weight
      results = for _i <- 1..20 do
        {:ok, provider_id} = LoadBalancer.route_request(%{type: :chat})
        provider_id
      end
      
      fast_count = Enum.count(results, &(&1 == :fast_provider))
      slow_count = Enum.count(results, &(&1 == :slow_provider))
      
      assert fast_count > slow_count
    end
  end
  
  describe "route_request/2 with consistent_hash strategy" do
    setup do
      LoadBalancer.set_routing_strategy(:consistent_hash)
      :ok
    end
    
    test "routes consistently for same session" do
      LoadBalancer.add_provider(:provider1, MockProvider)
      LoadBalancer.add_provider(:provider2, MockProvider)
      LoadBalancer.add_provider(:provider3, MockProvider)
      
      session_params = %{user_id: "user123", session_id: "session456"}
      
      # Multiple requests with same session should go to same provider
      results = for _i <- 1..5 do
        {:ok, provider_id} = LoadBalancer.route_request(session_params)
        provider_id
      end
      
      # All requests should go to the same provider
      assert Enum.uniq(results) |> length() == 1
    end
    
    test "distributes different sessions across providers" do
      LoadBalancer.add_provider(:provider1, MockProvider)
      LoadBalancer.add_provider(:provider2, MockProvider)
      LoadBalancer.add_provider(:provider3, MockProvider)
      
      # Different sessions should potentially go to different providers
      sessions = for i <- 1..20 do
        params = %{user_id: "user#{i}", session_id: "session#{i}"}
        {:ok, provider_id} = LoadBalancer.route_request(params)
        provider_id
      end
      
      # Should use multiple providers
      unique_providers = Enum.uniq(sessions)
      assert length(unique_providers) > 1
    end
  end
  
  describe "update_health_score/2" do
    test "updates provider health score" do
      LoadBalancer.add_provider(:test_provider, MockProvider)
      
      assert :ok = LoadBalancer.update_health_score(:test_provider, 0.7)
      
      stats = LoadBalancer.get_provider_stats()
      assert stats[:test_provider].health_score == 0.7
    end
    
    test "ignores updates for non-existent provider" do
      assert :ok = LoadBalancer.update_health_score(:non_existent, 0.5)
    end
    
    test "affects routing for unhealthy providers" do
      LoadBalancer.set_routing_strategy(:round_robin)
      LoadBalancer.add_provider(:provider1, MockProvider)
      LoadBalancer.add_provider(:provider2, MockProvider)
      
      # Make provider2 unhealthy
      LoadBalancer.update_health_score(:provider2, 0.3)
      
      # Requests should only go to provider1
      results = for _i <- 1..5 do
        {:ok, provider_id} = LoadBalancer.route_request(%{})
        provider_id
      end
      
      assert Enum.all?(results, &(&1 == :provider1))
    end
  end
  
  describe "connection tracking" do
    test "tracks connection open/close" do
      LoadBalancer.add_provider(:test_provider, MockProvider)
      
      LoadBalancer.connection_opened(:test_provider)
      LoadBalancer.connection_opened(:test_provider)
      
      stats = LoadBalancer.get_provider_stats()
      assert stats[:test_provider].active_connections == 2
      
      LoadBalancer.connection_closed(:test_provider)
      
      stats = LoadBalancer.get_provider_stats()
      assert stats[:test_provider].active_connections == 1
    end
    
    test "connection count doesn't go below zero" do
      LoadBalancer.add_provider(:test_provider, MockProvider)
      
      LoadBalancer.connection_closed(:test_provider)
      LoadBalancer.connection_closed(:test_provider)
      
      stats = LoadBalancer.get_provider_stats()
      assert stats[:test_provider].active_connections == 0
    end
  end
  
  describe "get_stats/0" do
    test "returns load balancer statistics" do
      LoadBalancer.add_provider(:provider1, MockProvider)
      LoadBalancer.add_provider(:provider2, MockProvider)
      LoadBalancer.connection_opened(:provider1)
      
      stats = LoadBalancer.get_stats()
      
      assert stats.provider_count == 2
      assert stats.total_active_connections == 1
      assert stats.routing_strategy == :capability_based  # default
      assert is_boolean(stats.backpressure_enabled)
      assert is_integer(stats.max_queue_size)
      assert is_integer(stats.queue_size)
    end
  end
  
  describe "set_routing_strategy/1" do
    test "updates routing strategy" do
      assert :ok = LoadBalancer.set_routing_strategy(:round_robin)
      
      stats = LoadBalancer.get_stats()
      assert stats.routing_strategy == :round_robin
    end
    
    test "affects subsequent routing decisions" do
      LoadBalancer.add_provider(:provider1, MockProvider, %{weight: 100})
      LoadBalancer.add_provider(:provider2, MockProvider, %{weight: 100})
      
      # Set to round robin and verify behavior
      LoadBalancer.set_routing_strategy(:round_robin)
      
      results = for _i <- 1..4 do
        {:ok, provider_id} = LoadBalancer.route_request(%{})
        provider_id
      end
      
      # Should alternate between providers
      assert Enum.take(results, 2) |> Enum.sort() == [:provider1, :provider2]
    end
  end
  
  describe "strategy override" do
    test "allows per-request strategy override" do
      LoadBalancer.set_routing_strategy(:round_robin)
      LoadBalancer.add_provider(:provider1, MockProvider, %{weight: 100})
      LoadBalancer.add_provider(:provider2, MockProvider, %{weight: 300})
      
      # Override to use weighted strategy for this request
      results = for _i <- 1..20 do
        {:ok, provider_id} = LoadBalancer.route_request(%{}, strategy: :weighted)
        provider_id
      end
      
      provider2_count = Enum.count(results, &(&1 == :provider2))
      
      # With weighted strategy, provider2 should get more requests
      assert provider2_count > 10
    end
  end
end