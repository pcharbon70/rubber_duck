defmodule RubberDuck.Jido.Actions.Provider.ProviderActionsTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido.Actions.Provider.{
    ProviderHealthCheckAction,
    ProviderConfigUpdateAction,
    ProviderRateLimitAction,
    ProviderFailoverAction
  }
  
  # Mock agent state for testing
  defp mock_agent_state do
    %{
      name: "test_provider",
      state: %{
        provider_module: RubberDuck.LLM.Providers.Anthropic,
        provider_config: %{
          api_key: "test-key",
          api_version: "2023-06-01"
        },
        active_requests: %{},
        metrics: %{
          total_requests: 100,
          successful_requests: 95,
          failed_requests: 5,
          total_tokens: 50000,
          avg_latency: 250.5,
          last_request_time: System.monotonic_time(:millisecond)
        },
        rate_limiter: %{
          limit: 100,
          window: 60000,
          current_count: 25,
          window_start: System.monotonic_time(:millisecond)
        },
        circuit_breaker: %{
          state: :closed,
          failure_count: 2,
          consecutive_failures: 0,
          last_failure_time: nil,
          last_success_time: System.monotonic_time(:millisecond),
          failure_threshold: 5,
          success_threshold: 2,
          timeout: 60000,
          half_open_requests: 0
        },
        capabilities: [:chat, :code, :analysis, :streaming],
        max_concurrent_requests: 10
      }
    }
  end
  
  describe "ProviderHealthCheckAction" do
    test "performs basic health check successfully" do
      agent = mock_agent_state()
      params = %{check_connectivity: false}
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderHealthCheckAction.run(params, context)
      
      assert result.provider == "test_provider"
      assert result.health_score >= 0
      assert result.status in [:excellent, :good, :fair, :poor, :critical]
      assert Map.has_key?(result, :basic_health)
      assert Map.has_key?(result, :provider_metrics)
      assert Map.has_key?(result, :recommendations)
      assert %DateTime{} = result.timestamp
    end
    
    test "includes provider-specific metrics for Anthropic" do
      agent = mock_agent_state()
      params = %{include_detailed_metrics: true}
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderHealthCheckAction.run(params, context)
      
      assert result.provider_metrics.provider_type == :anthropic
      assert Map.has_key?(result.provider_metrics, :anthropic_specific)
      anthropic_metrics = result.provider_metrics.anthropic_specific
      assert Map.has_key?(anthropic_metrics, :api_version)
      assert Map.has_key?(anthropic_metrics, :context_window)
      assert Map.has_key?(anthropic_metrics, :supported_models)
    end
    
    test "calculates health score correctly" do
      agent = mock_agent_state()
      params = %{}
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderHealthCheckAction.run(params, context)
      
      # With good metrics, should have high health score
      assert result.health_score > 80
      assert result.status in [:excellent, :good]
    end
    
    test "provides recommendations for improvement" do
      agent = mock_agent_state()
      params = %{}
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderHealthCheckAction.run(params, context)
      
      assert is_list(result.recommendations)
      assert length(result.recommendations) > 0
    end
  end
  
  describe "ProviderConfigUpdateAction" do
    test "validates configuration updates successfully" do
      agent = mock_agent_state()
      params = %{
        config_updates: %{api_version: "2023-06-01"},
        validate_only: true
      }
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderConfigUpdateAction.run(params, context)
      
      assert result.validation_result == :valid
      assert Map.has_key?(result, :proposed_config)
      assert Map.has_key?(result, :current_config)
    end
    
    test "rejects invalid configuration updates" do
      agent = mock_agent_state()
      params = %{
        config_updates: %{api_version: "invalid-version"},
        validate_only: true
      }
      context = %{agent: agent}
      
      assert {:error, {:config_validation_failed, errors}} = 
        ProviderConfigUpdateAction.run(params, context)
      
      assert is_list(errors)
      assert length(errors) > 0
    end
    
    test "validates Anthropic-specific configuration" do
      agent = mock_agent_state()
      params = %{
        config_updates: %{
          safety_level: :strict,
          max_tokens: 150000
        },
        validate_only: true
      }
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderConfigUpdateAction.run(params, context)
      assert result.validation_result == :valid
    end
    
    test "rejects invalid Anthropic configuration" do
      agent = mock_agent_state()
      params = %{
        config_updates: %{
          safety_level: :invalid,
          max_tokens: 300000  # Too high
        },
        validate_only: true
      }
      context = %{agent: agent}
      
      assert {:error, {:config_validation_failed, errors}} = 
        ProviderConfigUpdateAction.run(params, context)
      
      assert length(errors) >= 2  # Both safety_level and max_tokens invalid
    end
  end
  
  describe "ProviderRateLimitAction" do
    test "checks rate limit status successfully" do
      agent = mock_agent_state()
      params = %{operation: :check}
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderRateLimitAction.run(params, context)
      
      assert result.status in [:unlimited, :exceeded, :critical, :warning, :healthy]
      assert is_integer(result.current_count)
      assert is_integer(result.limit)
      assert is_number(result.utilization_percent)
      assert is_boolean(result.can_make_request)
      assert %DateTime{} = result.checked_at
    end
    
    test "adjusts rate limits with valid parameters" do
      agent = mock_agent_state()
      params = %{
        operation: :adjust,
        new_limit: 150,
        new_window_ms: 120000
      }
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderRateLimitAction.run(params, context)
      
      assert result.status == :adjusted
      assert Map.has_key?(result, :previous_config)
      assert Map.has_key?(result, :new_config)
      assert result.new_config.limit == 150
      assert %DateTime{} = result.adjusted_at
    end
    
    test "rejects invalid rate limit adjustments" do
      agent = mock_agent_state()
      params = %{
        operation: :adjust,
        new_limit: -10,  # Invalid
        new_window_ms: 0  # Invalid
      }
      context = %{agent: agent}
      
      assert {:error, {:invalid_adjustment_params, errors}} = 
        ProviderRateLimitAction.run(params, context)
      
      assert is_list(errors)
      assert length(errors) >= 2
    end
    
    test "resets rate limiter successfully" do
      agent = mock_agent_state()
      params = %{operation: :reset}
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderRateLimitAction.run(params, context)
      
      assert result.status == :reset
      assert is_integer(result.previous_count)
      assert %DateTime{} = result.reset_at
    end
    
    test "monitors rate limit performance" do
      agent = mock_agent_state()
      params = %{operation: :monitor}
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderRateLimitAction.run(params, context)
      
      assert Map.has_key?(result, :performance)
      assert Map.has_key?(result, :current_config)
      assert Map.has_key?(result, :recommendations)
      assert Map.has_key?(result, :auto_adjustment)
      assert %DateTime{} = result.monitored_at
    end
    
    test "applies backoff strategy" do
      agent = mock_agent_state()
      params = %{
        operation: :backoff,
        backoff_factor: 2.0
      }
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderRateLimitAction.run(params, context)
      
      assert result.status == :backoff_applied
      assert result.backoff_factor == 2.0
      assert Map.has_key?(result, :previous_config)
      assert Map.has_key?(result, :new_config)
      assert %DateTime{} = result.applied_at
    end
  end
  
  describe "ProviderFailoverAction" do
    test "detects failover conditions successfully" do
      agent = mock_agent_state()
      params = %{operation: :detect}
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderFailoverAction.run(params, context)
      
      assert Map.has_key?(result, :current_health)
      assert is_list(result.failover_triggers)
      assert is_list(result.available_providers)
      assert Map.has_key?(result, :recommendation)
      assert is_boolean(result.should_failover)
      assert %DateTime{} = result.detected_at
    end
    
    test "monitors failover status when not in failover" do
      agent = mock_agent_state()
      params = %{operation: :monitor}
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderFailoverAction.run(params, context)
      
      assert result.status == :normal_operation
      assert result.in_failover == false
      assert %DateTime{} = result.monitored_at
    end
    
    test "analyzes failure patterns" do
      agent = mock_agent_state()
      params = %{operation: :analyze}
      context = %{agent: agent}
      
      assert {:ok, result} = ProviderFailoverAction.run(params, context)
      
      assert Map.has_key?(result, :failure_count)
      assert Map.has_key?(result, :patterns)
      assert Map.has_key?(result, :insights)
      assert Map.has_key?(result, :recommendations)
      assert %DateTime{} = result.analyzed_at
    end
    
    test "handles invalid operations gracefully" do
      agent = mock_agent_state()
      params = %{operation: :invalid_operation}
      context = %{agent: agent}
      
      assert {:error, {:invalid_operation, :invalid_operation}} = 
        ProviderFailoverAction.run(params, context)
    end
  end
  
  describe "Integration tests" do
    test "all actions can be executed on mock agent" do
      agent = mock_agent_state()
      context = %{agent: agent}
      
      # Test health check
      assert {:ok, _} = ProviderHealthCheckAction.run(%{}, context)
      
      # Test config validation
      assert {:ok, _} = ProviderConfigUpdateAction.run(
        %{config_updates: %{api_version: "2023-06-01"}, validate_only: true}, 
        context
      )
      
      # Test rate limit check
      assert {:ok, _} = ProviderRateLimitAction.run(%{operation: :check}, context)
      
      # Test failover detection
      assert {:ok, _} = ProviderFailoverAction.run(%{operation: :detect}, context)
    end
    
    test "actions handle missing agent state gracefully" do
      invalid_agent = %{name: "test", state: %{}}
      context = %{agent: invalid_agent}
      
      # Most actions should handle missing state gracefully
      assert {:error, _} = ProviderConfigUpdateAction.run(
        %{config_updates: %{}, validate_only: true}, 
        context
      )
    end
  end
end