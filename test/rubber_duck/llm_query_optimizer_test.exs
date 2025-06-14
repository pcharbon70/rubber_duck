defmodule RubberDuck.LLMQueryOptimizerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.LLMQueryOptimizer
  alias RubberDuck.LLMDataManager
  alias RubberDuck.MnesiaManager
  
  setup_all do
    # Ensure Mnesia is running and tables are created
    {:ok, _pid} = MnesiaManager.start_link()
    :ok = MnesiaManager.initialize_schema()
    
    on_exit(fn ->
      # Clean up test data
      :mnesia.clear_table(:llm_responses)
      :mnesia.clear_table(:llm_provider_status)
    end)
    
    :ok
  end
  
  setup do
    # Clean tables before each test
    :mnesia.clear_table(:llm_responses)
    :mnesia.clear_table(:llm_provider_status)
    :ok
  end
  
  describe "optimized prompt lookup" do
    test "performs efficient prompt hash lookup" do
      # Store test response
      response_data = %{
        provider: "openai",
        model: "gpt-4",
        prompt: "What is machine learning?",
        response: "Machine learning is a subset of AI...",
        tokens_used: 45,
        cost: 0.001,
        latency: 800
      }
      
      {:ok, _response_id} = LLMDataManager.store_response(response_data)
      
      # Generate prompt hash
      prompt_hash = :crypto.hash(:sha256, response_data.prompt) |> Base.encode64(padding: false)
      
      # Test optimized lookup
      {:ok, result} = LLMQueryOptimizer.optimized_prompt_lookup(prompt_hash)
      
      assert result.provider == "openai"
      assert result.model == "gpt-4"
      assert result.response == "Machine learning is a subset of AI..."
    end
    
    test "handles cache integration for repeated lookups" do
      # Store test response
      response_data = %{
        provider: "anthropic",
        model: "claude",
        prompt: "Explain quantum computing",
        response: "Quantum computing uses quantum mechanics...",
        tokens_used: 60,
        cost: 0.002
      }
      
      {:ok, _response_id} = LLMDataManager.store_response(response_data)
      
      prompt_hash = :crypto.hash(:sha256, response_data.prompt) |> Base.encode64(padding: false)
      
      # First lookup (should hit database)
      {:ok, result1} = LLMQueryOptimizer.optimized_prompt_lookup(prompt_hash, use_cache: true)
      
      # Second lookup (should hit cache)
      {:ok, result2} = LLMQueryOptimizer.optimized_prompt_lookup(prompt_hash, use_cache: true)
      
      assert result1.response == result2.response
      assert result1.provider == result2.provider
    end
    
    test "filters by provider and model" do
      # Store responses for different providers
      responses = [
        %{provider: "openai", model: "gpt-4", prompt: "Test prompt", response: "OpenAI response"},
        %{provider: "anthropic", model: "claude", prompt: "Test prompt", response: "Anthropic response"}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      prompt_hash = :crypto.hash(:sha256, "Test prompt") |> Base.encode64(padding: false)
      
      # Test provider-specific lookup
      {:ok, openai_result} = LLMQueryOptimizer.optimized_prompt_lookup(prompt_hash, provider: "openai")
      assert openai_result.provider == "openai"
      
      {:ok, anthropic_result} = LLMQueryOptimizer.optimized_prompt_lookup(prompt_hash, provider: "anthropic")
      assert anthropic_result.provider == "anthropic"
    end
  end
  
  describe "provider statistics optimization" do
    test "calculates provider averages efficiently" do
      provider = "openai"
      
      # Store multiple responses for the provider
      responses = [
        %{provider: provider, model: "gpt-4", prompt: "Test 1", response: "Response 1", tokens_used: 100, cost: 0.002, latency: 800},
        %{provider: provider, model: "gpt-4", prompt: "Test 2", response: "Response 2", tokens_used: 150, cost: 0.003, latency: 1200},
        %{provider: provider, model: "gpt-3.5", prompt: "Test 3", response: "Response 3", tokens_used: 80, cost: 0.001, latency: 600}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Test optimized provider stats
      {:ok, stats} = LLMQueryOptimizer.optimized_provider_stats(provider, :timer.hours(1), aggregation: :avg)
      
      assert is_map(stats)
      assert Map.has_key?(stats, :latency)
      assert Map.has_key?(stats, :cost)
      assert Map.has_key?(stats, :tokens_used)
    end
    
    test "calculates provider sums and percentiles" do
      provider = "anthropic"
      
      # Store test data
      responses = [
        %{provider: provider, model: "claude", prompt: "Test 1", response: "Response 1", tokens_used: 100, cost: 0.002, latency: 800},
        %{provider: provider, model: "claude", prompt: "Test 2", response: "Response 2", tokens_used: 200, cost: 0.004, latency: 1000}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Test sums
      {:ok, sums} = LLMQueryOptimizer.optimized_provider_stats(provider, :timer.hours(1), aggregation: :sum)
      assert is_map(sums)
      
      # Test percentiles
      {:ok, percentiles} = LLMQueryOptimizer.optimized_provider_stats(provider, :timer.hours(1), aggregation: :percentiles)
      assert is_map(percentiles)
    end
    
    test "generates time series data" do
      provider = "cohere"
      
      # Store test data
      response_data = %{
        provider: provider,
        model: "command",
        prompt: "Time series test",
        response: "Response",
        tokens_used: 100,
        cost: 0.002,
        latency: 800
      }
      
      LLMDataManager.store_response(response_data)
      
      # Test time series aggregation
      {:ok, time_series} = LLMQueryOptimizer.optimized_provider_stats(provider, :timer.hours(1), aggregation: :time_series)
      
      assert is_list(time_series)
    end
  end
  
  describe "cost analysis optimization" do
    test "performs efficient cost aggregation" do
      # Store responses with cost data
      responses = [
        %{provider: "openai", model: "gpt-4", prompt: "Cost test 1", response: "Response 1", cost: 0.005},
        %{provider: "openai", model: "gpt-3.5", prompt: "Cost test 2", response: "Response 2", cost: 0.002},
        %{provider: "anthropic", model: "claude", prompt: "Cost test 3", response: "Response 3", cost: 0.003}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Test cost analysis
      {:ok, analysis} = LLMQueryOptimizer.optimized_cost_analysis()
      
      assert is_map(analysis)
      assert Map.has_key?(analysis, :total_cost)
      assert Map.has_key?(analysis, :breakdown)
      assert analysis.total_cost >= 0.010  # Sum of all costs
    end
    
    test "includes cost trends when requested" do
      # Store some cost data
      response_data = %{
        provider: "openai",
        model: "gpt-4",
        prompt: "Trend test",
        response: "Response",
        cost: 0.005
      }
      
      LLMDataManager.store_response(response_data)
      
      # Test with trends
      {:ok, analysis} = LLMQueryOptimizer.optimized_cost_analysis(include_trends: true)
      
      assert Map.has_key?(analysis, :trends)
      assert is_list(analysis.trends)
    end
    
    test "supports cost breakdown by different dimensions" do
      # Store responses for breakdown testing
      responses = [
        %{provider: "openai", model: "gpt-4", prompt: "Breakdown test 1", response: "Response 1", cost: 0.005},
        %{provider: "anthropic", model: "claude", prompt: "Breakdown test 2", response: "Response 2", cost: 0.003}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Test breakdown by provider
      {:ok, provider_breakdown} = LLMQueryOptimizer.optimized_cost_analysis(breakdown_by: [:provider])
      assert Map.has_key?(provider_breakdown, :breakdown)
      
      # Test breakdown by model
      {:ok, model_breakdown} = LLMQueryOptimizer.optimized_cost_analysis(breakdown_by: [:model])
      assert Map.has_key?(model_breakdown, :breakdown)
    end
  end
  
  describe "session lookup optimization" do
    test "efficiently retrieves session responses" do
      session_id = "test_session_123"
      
      # Store responses for the session
      responses = [
        %{provider: "openai", model: "gpt-4", prompt: "Session prompt 1", response: "Response 1", session_id: session_id},
        %{provider: "openai", model: "gpt-4", prompt: "Session prompt 2", response: "Response 2", session_id: session_id},
        %{provider: "anthropic", model: "claude", prompt: "Other session", response: "Response 3", session_id: "other_session"}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Test session lookup
      {:ok, session_responses} = LLMQueryOptimizer.optimized_session_lookup(session_id)
      
      assert is_list(session_responses)
      assert length(session_responses) == 2  # Only responses for the target session
      
      # Verify all responses belong to the correct session
      Enum.each(session_responses, fn response ->
        if is_map(response) do
          assert Map.get(response, :session_id) == session_id
        end
      end)
    end
    
    test "supports temporal filtering for session lookup" do
      session_id = "temporal_session"
      current_time = :os.system_time(:millisecond)
      old_time = current_time - :timer.hours(2)
      
      # Store response
      response_data = %{
        provider: "openai",
        model: "gpt-4",
        prompt: "Temporal test",
        response: "Response",
        session_id: session_id
      }
      
      LLMDataManager.store_response(response_data)
      
      # Test with since parameter
      {:ok, recent_responses} = LLMQueryOptimizer.optimized_session_lookup(session_id, since: old_time)
      assert is_list(recent_responses)
      
      # Test with very recent since (should return fewer results)
      {:ok, very_recent_responses} = LLMQueryOptimizer.optimized_session_lookup(session_id, since: current_time)
      assert length(very_recent_responses) <= length(recent_responses)
    end
    
    test "respects limit parameter" do
      session_id = "limit_test_session"
      
      # Store multiple responses
      responses = Enum.map(1..5, fn i ->
        %{
          provider: "openai",
          model: "gpt-4",
          prompt: "Limit test #{i}",
          response: "Response #{i}",
          session_id: session_id
        }
      end)
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Test with limit
      {:ok, limited_responses} = LLMQueryOptimizer.optimized_session_lookup(session_id, limit: 3)
      
      assert is_list(limited_responses)
      assert length(limited_responses) <= 3
    end
  end
  
  describe "token usage analysis" do
    test "analyzes token usage patterns" do
      # Store responses with token data
      responses = [
        %{provider: "openai", model: "gpt-4", prompt: "Token test 1", response: "Response 1", tokens_used: 100},
        %{provider: "openai", model: "gpt-3.5", prompt: "Token test 2", response: "Response 2", tokens_used: 80},
        %{provider: "anthropic", model: "claude", prompt: "Token test 3", response: "Response 3", tokens_used: 120}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Test token analysis
      {:ok, analysis} = LLMQueryOptimizer.optimized_token_analysis()
      
      assert is_map(analysis)
      assert Map.has_key?(analysis, :total_tokens)
      assert Map.has_key?(analysis, :by_provider)
      assert Map.has_key?(analysis, :by_model)
      assert Map.has_key?(analysis, :usage_rate)
      
      assert analysis.total_tokens == 300  # Sum of all tokens
    end
    
    test "filters token analysis by providers" do
      # Store responses for multiple providers
      responses = [
        %{provider: "openai", model: "gpt-4", prompt: "Provider test 1", response: "Response 1", tokens_used: 100},
        %{provider: "anthropic", model: "claude", prompt: "Provider test 2", response: "Response 2", tokens_used: 80}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Test filtering by specific provider
      {:ok, openai_analysis} = LLMQueryOptimizer.optimized_token_analysis(providers: ["openai"])
      
      assert is_map(openai_analysis)
      assert Map.has_key?(openai_analysis.by_provider, "openai")
      refute Map.has_key?(openai_analysis.by_provider, "anthropic")
    end
    
    test "includes predictions when requested" do
      # Store some token data
      response_data = %{
        provider: "openai",
        model: "gpt-4",
        prompt: "Prediction test",
        response: "Response",
        tokens_used: 100
      }
      
      LLMDataManager.store_response(response_data)
      
      # Test with predictions
      {:ok, analysis} = LLMQueryOptimizer.optimized_token_analysis(include_predictions: true)
      
      assert Map.has_key?(analysis, :predictions)
      assert is_map(analysis.predictions)
    end
  end
  
  describe "batch query optimization" do
    test "processes multiple queries efficiently" do
      # Store test data
      responses = [
        %{provider: "openai", model: "gpt-4", prompt: "Batch test 1", response: "Response 1", session_id: "session1"},
        %{provider: "anthropic", model: "claude", prompt: "Batch test 2", response: "Response 2", session_id: "session2"}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Define batch queries
      queries = [
        {:prompt_lookup, %{prompt_hash: generate_prompt_hash("Batch test 1")}},
        {:session_lookup, %{session_id: "session1"}},
        {:provider_stats, %{provider: "openai", time_range: :timer.hours(1)}}
      ]
      
      # Test batch optimization
      results = LLMQueryOptimizer.batch_optimize_queries(queries)
      
      assert is_list(results)
      assert length(results) == length(queries)
    end
    
    test "supports parallel batch processing" do
      # Store test data
      response_data = %{
        provider: "openai",
        model: "gpt-4",
        prompt: "Parallel test",
        response: "Response",
        session_id: "parallel_session"
      }
      
      LLMDataManager.store_response(response_data)
      
      # Define queries for parallel processing
      queries = [
        {:session_lookup, %{session_id: "parallel_session"}},
        {:token_analysis, %{opts: []}},
        {:cost_analysis, %{opts: []}}
      ]
      
      # Test parallel processing
      results = LLMQueryOptimizer.batch_optimize_queries(queries, parallel: true)
      
      assert is_list(results)
      assert length(results) == length(queries)
    end
  end
  
  describe "query performance analysis" do
    test "analyzes query performance and provides suggestions" do
      # Test performance analysis for different scenarios
      fast_analysis = LLMQueryOptimizer.analyze_query_performance(:prompt_lookup, 100, 10)
      assert fast_analysis.performance_score > 50
      
      slow_analysis = LLMQueryOptimizer.analyze_query_performance(:cost_analysis, 2000, 50000)
      assert slow_analysis.performance_score < fast_analysis.performance_score
      assert length(slow_analysis.suggestions) > 0
    end
    
    test "provides optimization suggestions based on query patterns" do
      # Test different query types
      prompt_analysis = LLMQueryOptimizer.analyze_query_performance(:prompt_lookup, 500, 100)
      session_analysis = LLMQueryOptimizer.analyze_query_performance(:session_lookup, 800, 200)
      
      assert is_list(prompt_analysis.suggestions)
      assert is_list(session_analysis.suggestions)
    end
  end
  
  # Helper Functions
  
  defp generate_prompt_hash(prompt) do
    :crypto.hash(:sha256, prompt) |> Base.encode64(padding: false)
  end
end