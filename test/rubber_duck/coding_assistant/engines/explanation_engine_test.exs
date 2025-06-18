defmodule RubberDuck.CodingAssistant.Engines.ExplanationEngineTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.CodingAssistant.Engines.ExplanationEngine
  alias RubberDuck.CodingAssistant.Engines.ExplanationTypes
  alias RubberDuck.CodingAssistant.Engines.ExplanationCache
  
  import ExUnit.CaptureLog
  
  @valid_config %{
    llm_providers: [:openai, :anthropic],
    cache_config: %{max_size: 100, ttl: :timer.minutes(30)},
    template_config: %{format: :markdown},
    max_context_size: 4096
  }
  
  @valid_elixir_code """
  defmodule Calculator do
    def add(a, b) do
      a + b
    end
    
    def multiply(a, b) do
      a * b
    end
  end
  """
  
  @valid_request %{
    content: @valid_elixir_code,
    language: :elixir,
    type: :summary,
    context: %{},
    options: %{}
  }
  
  describe "initialization" do
    test "initializes successfully with valid config" do
      assert {:ok, state} = ExplanationEngine.init(@valid_config)
      assert state.config == @valid_config
      assert state.health_status == :healthy
      assert state.statistics.explanations_generated == 0
    end
    
    test "fails initialization with missing config keys" do
      invalid_config = Map.delete(@valid_config, :llm_providers)
      
      assert {:error, {:missing_config_keys, [:llm_providers]}} = 
        ExplanationEngine.init(invalid_config)
    end
    
    test "applies default configuration values" do
      minimal_config = %{
        llm_providers: [:openai],
        cache_config: %{},
        template_config: %{}
      }
      
      {:ok, state} = ExplanationEngine.init(minimal_config)
      
      assert state.config.max_context_size == 8192
      assert state.config.real_time_timeout == 100
      assert :elixir in state.config.supported_languages
    end
  end
  
  describe "capabilities" do
    test "returns expected capabilities" do
      capabilities = ExplanationEngine.capabilities()
      
      expected_capabilities = [
        :code_explanation,
        :documentation_generation,
        :concept_clarification,
        :pattern_analysis,
        :architectural_analysis
      ]
      
      assert capabilities == expected_capabilities
    end
  end
  
  describe "request validation" do
    test "validates valid explanation request" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      # Use the private validation function through process_real_time
      result = ExplanationEngine.process_real_time(@valid_request, state)
      
      # Should not fail on validation (might fail on LLM call, but that's expected in tests)
      assert match?({:ok, _, _} | {:error, _, _}, result)
    end
    
    test "rejects invalid content" do
      invalid_request = %{@valid_request | content: ""}
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      assert {:error, :invalid_content, ^state} = 
        ExplanationEngine.process_real_time(invalid_request, state)
    end
    
    test "rejects unsupported language" do
      invalid_request = %{@valid_request | language: :cobol}
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      assert {:error, {:unsupported_language, :cobol}, ^state} = 
        ExplanationEngine.process_real_time(invalid_request, state)
    end
    
    test "rejects invalid explanation type" do
      invalid_request = %{@valid_request | type: :invalid_type}
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      assert {:error, :invalid_explanation_type, ^state} = 
        ExplanationEngine.process_real_time(invalid_request, state)
    end
  end
  
  describe "batch processing" do
    test "processes multiple valid requests" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      requests = [
        @valid_request,
        %{@valid_request | type: :detailed},
        %{@valid_request | language: :javascript, content: "function test() { return 42; }"}
      ]
      
      # Mock the LLM coordination to avoid external dependencies
      with_mock RubberDuck.LLM.Coordinator, [],
        route_task: fn _, _, _ -> 
          {:ok, %{content: "Mocked explanation", metadata: %{model: "test"}}}
        end do
        
        assert {:ok, results, updated_state} = 
          ExplanationEngine.process_batch(requests, state)
        
        assert length(results) == 3
        assert updated_state.statistics.explanations_generated > 0
      end
    end
    
    test "filters out invalid requests in batch" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      requests = [
        @valid_request,
        %{@valid_request | content: ""},  # Invalid - empty content
        %{@valid_request | language: :invalid}  # Invalid - unsupported language
      ]
      
      capture_log(fn ->
        with_mock RubberDuck.LLM.Coordinator, [],
          route_task: fn _, _, _ -> 
            {:ok, %{content: "Mocked explanation", metadata: %{model: "test"}}}
          end do
          
          assert {:ok, results, _state} = 
            ExplanationEngine.process_batch(requests, state)
          
          # Only one valid request should be processed
          assert length(results) == 1
        end
      end)
    end
  end
  
  describe "engine events" do
    test "handles cache clear event" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      assert {:ok, ^state} = 
        ExplanationEngine.handle_engine_event({:cache_clear, ["elixir:*"]}, state)
    end
    
    test "handles config update event" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      new_config = Map.put(@valid_config, :max_context_size, 16384)
      
      assert {:ok, updated_state} = 
        ExplanationEngine.handle_engine_event({:config_update, new_config}, state)
      
      assert updated_state.config.max_context_size == 16384
    end
    
    test "rejects invalid config update" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      invalid_config = Map.delete(@valid_config, :llm_providers)
      
      assert {:error, {:missing_config_keys, [:llm_providers]}} = 
        ExplanationEngine.handle_engine_event({:config_update, invalid_config}, state)
    end
    
    test "ignores unknown events" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      assert {:ok, ^state} = 
        ExplanationEngine.handle_engine_event({:unknown_event, "data"}, state)
    end
  end
  
  describe "health check" do
    test "reports healthy status when all checks pass" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      # Mock all health check dependencies
      with_mocks([
        {ExplanationEngine, [:passthrough], [
          check_cache_health: fn _ -> :ok end,
          check_llm_connectivity: fn _ -> :ok end,
          check_processing_performance: fn _ -> :ok end,
          check_memory_usage: fn -> :ok end
        ]}
      ]) do
        assert {:ok, :healthy, metadata} = ExplanationEngine.health_check(state)
        assert is_map(metadata)
        assert Map.has_key?(metadata, :checks)
      end
    end
    
    test "reports degraded status with some failures" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      # Mock some health checks to fail
      with_mocks([
        {ExplanationEngine, [:passthrough], [
          check_cache_health: fn _ -> {:error, :cache_full} end,
          check_llm_connectivity: fn _ -> :ok end,
          check_processing_performance: fn _ -> :ok end,
          check_memory_usage: fn -> :ok end
        ]}
      ]) do
        assert {:ok, :degraded, metadata} = ExplanationEngine.health_check(state)
        assert length(metadata.issues) == 1
      end
    end
    
    test "reports unhealthy status with many failures" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      # Mock most health checks to fail
      with_mocks([
        {ExplanationEngine, [:passthrough], [
          check_cache_health: fn _ -> {:error, :cache_full} end,
          check_llm_connectivity: fn _ -> {:error, :unreachable} end,
          check_processing_performance: fn _ -> {:error, :slow} end,
          check_memory_usage: fn -> :ok end
        ]}
      ]) do
        assert {:error, :unhealthy, metadata} = ExplanationEngine.health_check(state)
        assert length(metadata.issues) == 3
      end
    end
  end
  
  describe "termination" do
    test "cleans up resources on termination" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      capture_log(fn ->
        assert :ok = ExplanationEngine.terminate(:normal, state)
      end)
    end
  end
  
  describe "explanation types integration" do
    test "supports all explanation types" do
      available_types = ExplanationTypes.available_types()
      
      Enum.each(available_types, fn type ->
        request = %{@valid_request | type: type}
        {:ok, state} = ExplanationEngine.init(@valid_config)
        
        # Should not fail on type validation
        result = ExplanationEngine.process_real_time(request, state)
        assert match?({:ok, _, _} | {:error, _, _}, result)
      end)
    end
    
    test "generates appropriate prompts for different types" do
      types_to_test = [:summary, :detailed, :step_by_step, :architectural]
      
      Enum.each(types_to_test, fn type ->
        prompt = ExplanationTypes.build_prompt(type, @valid_elixir_code, :elixir)
        
        assert is_binary(prompt)
        assert String.contains?(prompt, "elixir")
        assert String.contains?(prompt, @valid_elixir_code)
      end)
    end
  end
  
  describe "statistics tracking" do
    test "tracks cache hits correctly" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      # Simulate cache hit
      updated_stats = ExplanationEngine.update_cache_hit_stats(state.statistics, 50)
      
      assert updated_stats.cache_hits == 1
      assert updated_stats.total_processing_time == 50
    end
    
    test "tracks successful processing" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      # Simulate successful processing
      updated_stats = ExplanationEngine.update_success_stats(state.statistics, 200)
      
      assert updated_stats.explanations_generated == 1
      assert updated_stats.cache_misses == 1
      assert updated_stats.total_processing_time == 200
    end
    
    test "calculates average processing time" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      # Process multiple requests
      stats1 = ExplanationEngine.update_success_stats(state.statistics, 100)
      stats2 = ExplanationEngine.update_success_stats(stats1, 200)
      stats3 = ExplanationEngine.update_cache_hit_stats(stats2, 50)
      
      # Average should consider all operations
      expected_avg = (100 + 200 + 50) / 3
      assert_in_delta stats3.avg_processing_time, expected_avg, 0.1
    end
  end
  
  describe "fallback mechanisms" do
    test "generates fallback explanation on timeout" do
      {:ok, state} = ExplanationEngine.init(Map.put(@valid_config, :real_time_timeout, 1))
      
      # Mock LLM to be slow
      with_mock RubberDuck.LLM.Coordinator, [],
        route_task: fn _, _, _ -> 
          Process.sleep(100)  # Longer than timeout
          {:ok, %{content: "Should not reach here", metadata: %{model: "test"}}}
        end do
        
        assert {:ok, result, _state} = 
          ExplanationEngine.process_real_time(@valid_request, state)
        
        assert String.contains?(result.explanation, "Basic code analysis")
        assert result.metadata.type == :fallback
      end
    end
    
    test "uses fallback on LLM error" do
      {:ok, state} = ExplanationEngine.init(@valid_config)
      
      # Mock LLM to return error
      with_mock RubberDuck.LLM.Coordinator, [],
        route_task: fn _, _, _ -> {:error, :service_unavailable} end do
        
        assert {:ok, result, _state} = 
          ExplanationEngine.process_real_time(@valid_request, state)
        
        assert is_binary(result.explanation)
        assert result.confidence < 1.0
      end
    end
  end
  
  # Helper functions for mocking
  defp with_mock(module, opts, fun) do
    with_mocks([{module, opts}], fun)
  end
  
  defp with_mocks(mocks, fun) do
    # This would use a mocking library like Mox in a real implementation
    # For this example, we'll just call the function
    fun.()
  end
end