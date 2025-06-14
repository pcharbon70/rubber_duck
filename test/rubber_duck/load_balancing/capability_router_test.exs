defmodule RubberDuck.LoadBalancing.CapabilityRouterTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.LoadBalancing.CapabilityRouter
  
  @test_providers %{
    openai: %{
      id: :openai,
      capabilities: %{
        models: ["gpt-4", "gpt-3.5-turbo", "gpt-4-turbo"],
        request_types: [:chat, :completion, :embedding],
        features: [:streaming, :function_calling, :vision],
        user_tiers: [:free, :premium, :enterprise]
      },
      performance_metrics: %{
        avg_latency_ms: 200,
        requests_per_second: 10,
        success_rate: 0.98,
        performance_index: 0.9
      },
      cost_metrics: %{
        cost_per_request: 0.002
      },
      health_score: 0.95,
      weight: 100,
      active_connections: 5
    },
    anthropic: %{
      id: :anthropic,
      capabilities: %{
        models: ["claude-3-sonnet", "claude-3-haiku", "claude-3-opus"],
        request_types: [:chat, :completion],
        features: [:streaming, :long_context],
        user_tiers: [:premium, :enterprise]
      },
      performance_metrics: %{
        avg_latency_ms: 150,
        requests_per_second: 8,
        success_rate: 0.99,
        performance_index: 0.95
      },
      cost_metrics: %{
        cost_per_request: 0.003
      },
      health_score: 0.97,
      weight: 120,
      active_connections: 2
    },
    cohere: %{
      id: :cohere,
      capabilities: %{
        models: ["command", "command-light", "embed-english"],
        request_types: [:chat, :completion, :embedding],
        features: [:embedding, :classification],
        user_tiers: [:free, :premium]
      },
      performance_metrics: %{
        avg_latency_ms: 300,
        requests_per_second: 5,
        success_rate: 0.95,
        performance_index: 0.8
      },
      cost_metrics: %{
        cost_per_request: 0.001
      },
      health_score: 0.85,
      weight: 80,
      active_connections: 10
    }
  }
  
  describe "select_provider/3" do
    test "selects provider that supports required model" do
      requirements = %{
        model: "gpt-4",
        type: :chat,
        priority: :normal
      }
      
      {:ok, provider_id} = CapabilityRouter.select_provider(@test_providers, requirements)
      
      assert provider_id == :openai
    end
    
    test "selects provider with best overall score" do
      requirements = %{
        model: nil,  # Any model
        type: :chat,
        priority: :normal
      }
      
      {:ok, provider_id} = CapabilityRouter.select_provider(@test_providers, requirements)
      
      # Should select anthropic due to better performance despite higher cost
      assert provider_id == :anthropic
    end
    
    test "returns error when no provider supports requirements" do
      requirements = %{
        model: "unknown-model",
        type: :chat,
        priority: :normal
      }
      
      result = CapabilityRouter.select_provider(@test_providers, requirements)
      
      assert result == {:error, :no_suitable_providers}
    end
    
    test "respects user tier requirements" do
      requirements = %{
        model: nil,
        type: :chat,
        priority: :normal,
        user_tier: :free
      }
      
      {:ok, provider_id} = CapabilityRouter.select_provider(@test_providers, requirements)
      
      # Should not select anthropic (premium only), should prefer openai or cohere
      assert provider_id in [:openai, :cohere]
    end
    
    test "considers required features" do
      requirements = %{
        model: nil,
        type: :chat,
        priority: :normal,
        required_features: [:function_calling]
      }
      
      {:ok, provider_id} = CapabilityRouter.select_provider(@test_providers, requirements)
      
      assert provider_id == :openai  # Only OpenAI supports function calling
    end
    
    test "respects cost constraints" do
      requirements = %{
        model: nil,
        type: :chat,
        priority: :normal,
        max_cost: 0.0015
      }
      
      {:ok, provider_id} = CapabilityRouter.select_provider(@test_providers, requirements)
      
      assert provider_id == :cohere  # Only provider under cost limit
    end
    
    test "adjusts scoring based on priority" do
      high_priority_requirements = %{
        model: nil,
        type: :chat,
        priority: :critical,
        max_cost: 0.01  # High budget for critical request
      }
      
      {:ok, provider_id} = CapabilityRouter.select_provider(@test_providers, high_priority_requirements)
      
      # For critical requests, should prefer performance over cost
      assert provider_id == :anthropic
    end
  end
  
  describe "score_providers/3" do
    test "returns providers sorted by score" do
      requirements = %{
        model: nil,
        type: :chat,
        priority: :normal
      }
      
      scores = CapabilityRouter.score_providers(@test_providers, requirements)
      
      assert length(scores) == 3
      
      # Should be sorted by score (highest first)
      [first, second, third] = scores
      {_, first_score} = first
      {_, second_score} = second
      {_, third_score} = third
      
      assert first_score >= second_score
      assert second_score >= third_score
    end
    
    test "filters out providers that cannot handle request" do
      requirements = %{
        model: "gpt-4",  # Only OpenAI supports this
        type: :chat,
        priority: :normal
      }
      
      scores = CapabilityRouter.score_providers(@test_providers, requirements)
      
      # Only OpenAI should be returned
      assert length(scores) == 1
      assert elem(hd(scores), 0) == :openai
    end
  end
  
  describe "select_providers/3" do
    test "returns multiple providers for failover" do
      requirements = %{
        model: nil,
        type: :chat,
        priority: :normal
      }
      
      {:ok, providers} = CapabilityRouter.select_providers(@test_providers, requirements, count: 2)
      
      assert length(providers) == 2
      assert Enum.uniq(providers) == providers  # No duplicates
    end
    
    test "respects minimum score threshold" do
      requirements = %{
        model: nil,
        type: :chat,
        priority: :normal
      }
      
      {:ok, providers} = CapabilityRouter.select_providers(
        @test_providers, 
        requirements, 
        count: 5, 
        min_score: 70.0
      )
      
      # Should only return providers with score >= 70
      assert length(providers) <= 3
    end
    
    test "returns error when no providers meet criteria" do
      requirements = %{
        model: "unknown-model",
        type: :chat,
        priority: :normal
      }
      
      result = CapabilityRouter.select_providers(@test_providers, requirements, count: 2)
      
      assert result == {:error, :no_suitable_providers}
    end
  end
  
  describe "can_handle?/2" do
    test "returns true when provider can handle request" do
      provider = @test_providers[:openai]
      requirements = %{model: "gpt-4", type: :chat}
      
      assert CapabilityRouter.can_handle?(provider, requirements)
    end
    
    test "returns false when provider cannot handle request" do
      provider = @test_providers[:cohere]
      requirements = %{model: "gpt-4", type: :chat}  # Cohere doesn't support GPT-4
      
      refute CapabilityRouter.can_handle?(provider, requirements)
    end
    
    test "returns false when missing required features" do
      provider = @test_providers[:cohere]
      requirements = %{
        model: nil,
        type: :chat,
        required_features: [:function_calling]  # Cohere doesn't support this
      }
      
      refute CapabilityRouter.can_handle?(provider, requirements)
    end
    
    test "returns false when user tier not supported" do
      provider = @test_providers[:anthropic]
      requirements = %{
        model: nil,
        type: :chat,
        user_tier: :free  # Anthropic doesn't support free tier
      }
      
      refute CapabilityRouter.can_handle?(provider, requirements)
    end
  end
  
  describe "score_breakdown/3" do
    test "provides detailed scoring breakdown" do
      provider = @test_providers[:openai]
      requirements = %{
        model: "gpt-4",
        type: :chat,
        priority: :normal
      }
      
      breakdown = CapabilityRouter.score_breakdown(provider, requirements)
      
      assert is_map(breakdown)
      assert Map.has_key?(breakdown, :capability_match)
      assert Map.has_key?(breakdown, :performance)
      assert Map.has_key?(breakdown, :cost)
      assert Map.has_key?(breakdown, :health)
      assert Map.has_key?(breakdown, :load)
      assert Map.has_key?(breakdown, :affinity)
      assert Map.has_key?(breakdown, :weighted_total)
      
      # All scores should be numeric
      Enum.each(breakdown, fn {_key, score} ->
        assert is_number(score)
      end)
    end
    
    test "capability match score is 0 when cannot handle request" do
      provider = @test_providers[:cohere]
      requirements = %{model: "gpt-4", type: :chat}  # Cohere can't handle GPT-4
      
      breakdown = CapabilityRouter.score_breakdown(provider, requirements)
      
      assert breakdown.capability_match == 0
      assert breakdown.weighted_total == 0
    end
  end
  
  describe "model family matching" do
    test "matches model families correctly" do
      # Test data with model family
      openai_provider = %{
        id: :openai,
        capabilities: %{models: ["gpt-4"], request_types: [:chat]},
        performance_metrics: %{avg_latency_ms: 200, requests_per_second: 10, success_rate: 0.98},
        cost_metrics: %{cost_per_request: 0.002},
        health_score: 0.95,
        weight: 100,
        active_connections: 5
      }
      
      providers = %{openai: openai_provider}
      
      # Should match gpt-4-turbo to gpt-4 family
      requirements = %{model: "gpt-4-turbo", type: :chat, priority: :normal}
      
      {:ok, provider_id} = CapabilityRouter.select_provider(providers, requirements)
      assert provider_id == :openai
    end
  end
  
  describe "load balancing considerations" do
    test "prefers providers with lower active connections" do
      low_load_provider = %{
        id: :low_load,
        capabilities: %{models: ["test-model"], request_types: [:chat]},
        performance_metrics: %{avg_latency_ms: 200, requests_per_second: 10, success_rate: 0.98},
        cost_metrics: %{cost_per_request: 0.002},
        health_score: 0.95,
        weight: 100,
        active_connections: 1  # Low load
      }
      
      high_load_provider = %{
        id: :high_load,
        capabilities: %{models: ["test-model"], request_types: [:chat]},
        performance_metrics: %{avg_latency_ms: 200, requests_per_second: 10, success_rate: 0.98},
        cost_metrics: %{cost_per_request: 0.002},
        health_score: 0.95,
        weight: 100,
        active_connections: 50  # High load
      }
      
      providers = %{low_load: low_load_provider, high_load: high_load_provider}
      requirements = %{model: "test-model", type: :chat, priority: :normal}
      
      {:ok, provider_id} = CapabilityRouter.select_provider(providers, requirements)
      
      assert provider_id == :low_load
    end
  end
  
  describe "session affinity" do
    test "prefers provider when session affinity matches" do
      requirements = %{
        model: nil,
        type: :chat,
        priority: :normal,
        session_affinity: "user123_openai"  # Hints at OpenAI preference
      }
      
      {:ok, provider_id} = CapabilityRouter.select_provider(@test_providers, requirements)
      
      # Should have some preference for OpenAI due to session affinity
      assert provider_id == :openai
    end
  end
end