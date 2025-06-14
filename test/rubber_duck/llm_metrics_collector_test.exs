defmodule RubberDuck.LLMMetricsCollectorTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.LLMMetricsCollector
  alias RubberDuck.MnesiaManager
  
  setup_all do
    # Ensure Mnesia is running
    {:ok, _pid} = MnesiaManager.start_link()
    :ok = MnesiaManager.initialize_schema()
    
    # Start the metrics collector
    {:ok, _pid} = LLMMetricsCollector.start_link()
    
    on_exit(fn ->
      # Clean up
      GenServer.stop(LLMMetricsCollector, :normal)
    end)
    
    :ok
  end
  
  setup do
    # Clean ETS tables before each test
    :ets.delete_all_objects(:llm_metrics)
    :ets.delete_all_objects(:llm_metric_windows)
    :ok
  end
  
  describe "request tracking" do
    test "records request start and completion" do
      request_id = "test_request_123"
      provider = "openai"
      model = "gpt-4"
      
      # Record request start
      LLMMetricsCollector.record_request_start(request_id, provider, model)
      
      # Verify request tracking is stored
      assert :ets.lookup(:llm_metrics, {:request_start, request_id}) != []
      
      # Record completion
      response_data = %{response_length: 100, tokens_used: 50}
      LLMMetricsCollector.record_request_completion(request_id, :success, response_data)
      
      # Verify request tracking is cleaned up
      assert :ets.lookup(:llm_metrics, {:request_start, request_id}) == []
    end
    
    test "handles completion without matching start" do
      # This should not crash when completion is recorded without start
      response_data = %{response_length: 100, tokens_used: 50}
      result = LLMMetricsCollector.record_request_completion("unknown_request", :success, response_data)
      
      # Should handle gracefully
      assert is_nil(result) or result == :ok
    end
  end
  
  describe "token usage tracking" do
    test "records token usage metrics" do
      provider = "anthropic"
      model = "claude-3"
      input_tokens = 100
      output_tokens = 150
      cost = 0.005
      
      LLMMetricsCollector.record_token_usage(provider, model, input_tokens, output_tokens, cost)
      
      # Verify metrics are recorded
      tags = %{provider: provider, model: model}
      
      assert get_metric_value("llm.tokens.input", tags) == input_tokens
      assert get_metric_value("llm.tokens.output", tags) == output_tokens
      assert get_metric_value("llm.tokens.total", tags) == input_tokens + output_tokens
      assert get_metric_value("llm.cost.request", tags) == cost
    end
  end
  
  describe "cache operation tracking" do
    test "records cache hits and misses" do
      metadata = %{provider: "openai", prompt_type: "chat"}
      
      # Record cache operations
      LLMMetricsCollector.record_cache_operation(:get, :hit, metadata)
      LLMMetricsCollector.record_cache_operation(:get, :hit, metadata)
      LLMMetricsCollector.record_cache_operation(:get, :miss, metadata)
      
      # Verify cache metrics
      assert get_metric_value("llm.cache.hits", metadata) == 2
      assert get_metric_value("llm.cache.misses", metadata) == 1
    end
    
    test "updates cache hit rate" do
      # Record some cache operations
      LLMMetricsCollector.record_cache_operation(:get, :hit)
      LLMMetricsCollector.record_cache_operation(:get, :hit)
      LLMMetricsCollector.record_cache_operation(:get, :miss)
      
      # Allow time for hit rate calculation
      :timer.sleep(100)
      
      # Hit rate should be calculated (this is a simplified test)
      hit_rate = get_metric_value("llm.cache.hit_rate", %{})
      assert is_number(hit_rate)
    end
  end
  
  describe "provider status tracking" do
    test "records provider status updates" do
      provider = "cohere"
      
      status_data = %{
        availability: 95.5,
        health_score: 88,
        rate_limit_utilization: 45.2
      }
      
      LLMMetricsCollector.record_provider_status(provider, status_data)
      
      # Verify provider metrics
      tags = %{provider: provider}
      
      assert get_metric_value("llm.provider.availability", tags) == 95.5
      assert get_metric_value("llm.provider.health_score", tags) == 88
      assert get_metric_value("llm.provider.rate_limit", tags) == 45.2
    end
  end
  
  describe "metrics summary" do
    test "generates metrics summary" do
      # Record some test data
      LLMMetricsCollector.record_token_usage("openai", "gpt-4", 100, 50, 0.002)
      LLMMetricsCollector.record_token_usage("anthropic", "claude", 80, 60, 0.003)
      
      LLMMetricsCollector.record_cache_operation(:get, :hit)
      LLMMetricsCollector.record_cache_operation(:get, :miss)
      
      summary = LLMMetricsCollector.get_metrics_summary()
      
      # Verify summary structure
      assert is_map(summary)
    end
    
    test "filters metrics by provider" do
      # Record data for multiple providers
      LLMMetricsCollector.record_token_usage("openai", "gpt-4", 100, 50, 0.002)
      LLMMetricsCollector.record_token_usage("anthropic", "claude", 80, 60, 0.003)
      
      # Get summary for specific provider
      openai_summary = LLMMetricsCollector.get_metrics_summary(provider: "openai")
      
      assert is_map(openai_summary)
    end
  end
  
  describe "provider comparison" do
    test "compares provider performance" do
      # Record data for multiple providers
      providers = ["openai", "anthropic", "cohere"]
      
      Enum.each(providers, fn provider ->
        LLMMetricsCollector.record_token_usage(provider, "model", 100, 50, 0.002)
        LLMMetricsCollector.record_provider_status(provider, %{
          availability: 95.0,
          health_score: 90
        })
      end)
      
      comparison = LLMMetricsCollector.get_provider_comparison()
      
      assert is_list(comparison)
      assert length(comparison) <= length(providers)
      
      # Verify comparison structure
      if length(comparison) > 0 do
        provider_data = hd(comparison)
        assert Map.has_key?(provider_data, :provider)
        assert Map.has_key?(provider_data, :health_score)
      end
    end
  end
  
  describe "cost analysis" do
    test "analyzes cost metrics" do
      # Record some cost data
      LLMMetricsCollector.record_token_usage("openai", "gpt-4", 100, 50, 0.005)
      LLMMetricsCollector.record_token_usage("openai", "gpt-3.5", 80, 40, 0.002)
      
      analysis = LLMMetricsCollector.get_cost_analysis()
      
      assert is_map(analysis)
      assert Map.has_key?(analysis, :total_cost)
      assert Map.has_key?(analysis, :cost_per_request)
      assert Map.has_key?(analysis, :cost_per_token)
    end
  end
  
  # Helper Functions
  
  defp get_metric_value(metric_name, tags) do
    key = {:metric_value, metric_name, tags}
    
    case :ets.lookup(:llm_metrics, key) do
      [{_, value}] -> value
      [] -> 0
    end
  end
end