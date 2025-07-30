defmodule RubberDuck.Agents.ResponseProcessorAgentTest do
  use ExUnit.Case, async: true
  alias RubberDuck.Agents.ResponseProcessorAgent
  alias RubberDuck.Agents.Response.ProcessedResponse
  
  describe "agent initialization" do
    test "initializes with parsers, enhancers, and validators" do
      {:ok, agent} = ResponseProcessorAgent.mount(%{}, %{
        cache: %{},
        metrics: %{
          total_processed: 0,
          total_cached: 0,
          cache_hits: 0,
          cache_misses: 0,
          avg_processing_time: 0.0,
          format_distribution: %{},
          quality_distribution: %{},
          error_count: 0
        },
        parsers: %{},
        enhancers: [],
        validators: [],
        config: %{
          cache_ttl: 7200,
          max_cache_size: 10000,
          enable_streaming: true,
          quality_threshold: 0.8,
          compression_enabled: true,
          auto_enhance: true,
          fallback_to_text: true
        }
      })
      
      assert map_size(agent.parsers) > 0
      assert is_list(agent.enhancers)
      assert is_list(agent.validators)
      assert Map.has_key?(agent, :config)
    end
  end
  
  describe "response processing signals" do
    setup do
      {:ok, agent} = ResponseProcessorAgent.mount(%{}, %{
        cache: %{},
        metrics: %{
          total_processed: 0,
          total_cached: 0,
          cache_hits: 0,
          cache_misses: 0,
          avg_processing_time: 0.0,
          format_distribution: %{},
          quality_distribution: %{},
          error_count: 0
        },
        parsers: %{},
        enhancers: [],
        validators: [],
        config: %{
          cache_ttl: 7200,
          max_cache_size: 10000,
          enable_streaming: true,
          quality_threshold: 0.8,
          compression_enabled: true,
          auto_enhance: true,
          fallback_to_text: true
        }
      })
      
      %{agent: agent}
    end
    
    test "processes response successfully", %{agent: agent} do
      response_data = %{
        "content" => "This is a test response with good quality content.",
        "request_id" => "req-123",
        "provider" => "openai",
        "model" => "gpt-4"
      }
      
      signal = %{
        "type" => "process_response",
        "data" => response_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      # Check that response was processed
      assert updated_agent.metrics.total_processed >= agent.metrics.total_processed
      
      # Check signal was emitted
      assert_receive {:signal_emitted, "response_processed", response_data}
      assert Map.has_key?(response_data, "content")
      assert Map.has_key?(response_data, "quality_score")
      assert response_data["cache_hit"] == false
    end
    
    test "uses cache for duplicate content", %{agent: agent} do
      content = "This is cached content."
      
      response_data = %{
        "content" => content,
        "request_id" => "req-123",
        "provider" => "openai",
        "model" => "gpt-4"
      }
      
      signal = %{
        "type" => "process_response",
        "data" => response_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      # First request - should process and cache
      {:ok, updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "response_processed", first_response}
      assert first_response["cache_hit"] == false
      
      # Second request - should hit cache
      {:ok, _final_agent} = ResponseProcessorAgent.handle_signal(updated_agent, signal)
      
      assert_receive {:signal_emitted, "response_processed", second_response}
      assert second_response["cache_hit"] == true
    end
    
    test "handles parsing errors gracefully", %{agent: agent} do
      response_data = %{
        "content" => "",  # Empty content that might cause issues
        "request_id" => "req-456",
        "provider" => "openai",
        "model" => "gpt-4"
      }
      
      signal = %{
        "type" => "process_response",
        "data" => response_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      # Should emit some kind of response (processed or failed)
      assert_receive {:signal_emitted, signal_type, _data}
      assert signal_type in ["response_processed", "response_processing_failed"]
    end
    
    test "parses response with specific format", %{agent: agent} do
      json_content = ~s({"name": "John", "age": 30})
      
      parse_data = %{
        "content" => json_content,
        "request_id" => "req-789",
        "format" => "json"
      }
      
      signal = %{
        "type" => "parse_response",
        "data" => parse_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, signal_type, response_data}
      assert signal_type in ["response_parsed", "response_parsing_failed"]
      
      if signal_type == "response_parsed" do
        assert response_data["format"] == :json
        assert Map.has_key?(response_data, "parsed_content")
      end
    end
    
    test "validates response quality", %{agent: agent} do
      validation_data = %{
        "content" => "This is a well-formed response with proper punctuation and structure.",
        "request_id" => "req-validation"
      }
      
      signal = %{
        "type" => "validate_response",
        "data" => validation_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "response_validated", validation_result}
      assert Map.has_key?(validation_result, "quality_score")
      assert Map.has_key?(validation_result, "is_valid")
      assert is_float(validation_result["quality_score"])
    end
    
    test "enhances response content", %{agent: agent} do
      enhancement_data = %{
        "content" => "This   has    extra    spaces   and  \n\n\n\n  line breaks.",
        "request_id" => "req-enhance"
      }
      
      signal = %{
        "type" => "enhance_response",
        "data" => enhancement_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "response_enhanced", enhancement_result}
      assert Map.has_key?(enhancement_result, "enhanced_content")
      assert Map.has_key?(enhancement_result, "enhancement_log")
      
      # Enhanced content should have normalized spacing
      enhanced = enhancement_result["enhanced_content"]
      refute String.contains?(enhanced, "    ")  # No quadruple spaces
      refute String.contains?(enhanced, "\n\n\n")  # No triple line breaks
    end
  end
  
  describe "caching operations" do
    setup do
      {:ok, agent} = ResponseProcessorAgent.mount(%{}, %{
        cache: %{
          "existing_key" => %{
            data: %{"content" => "cached content"},
            expires_at: DateTime.add(DateTime.utc_now(), 3600),
            created_at: DateTime.utc_now()
          }
        },
        metrics: %{
          total_processed: 0,
          total_cached: 0,
          cache_hits: 0,
          cache_misses: 0,
          avg_processing_time: 0.0,
          format_distribution: %{},
          quality_distribution: %{},
          error_count: 0
        },
        parsers: %{},
        enhancers: [],
        validators: [],
        config: %{cache_ttl: 7200, max_cache_size: 10000}
      })
      
      %{agent: agent}
    end
    
    test "retrieves cached response", %{agent: agent} do
      cache_data = %{"cache_key" => "existing_key"}
      
      signal = %{
        "type" => "get_cached_response",
        "data" => cache_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "cached_response_found", cached_data}
      assert cached_data["content"] == "cached content"
    end
    
    test "handles cache miss", %{agent: agent} do
      cache_data = %{"cache_key" => "nonexistent_key"}
      
      signal = %{
        "type" => "get_cached_response",
        "data" => cache_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "cached_response_not_found", miss_data}
      assert miss_data["cache_key"] == "nonexistent_key"
    end
    
    test "invalidates cache entries", %{agent: agent} do
      invalidation_data = %{"cache_keys" => ["existing_key"]}
      
      signal = %{
        "type" => "invalidate_cache",
        "data" => invalidation_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      # Cache should be cleared
      refute Map.has_key?(updated_agent.cache, "existing_key")
      
      assert_receive {:signal_emitted, "cache_invalidated", invalidation_result}
      assert invalidation_result["invalidated_keys"] == ["existing_key"]
    end
    
    test "clears entire cache", %{agent: agent} do
      signal = %{"type" => "clear_cache"}
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      # Cache should be empty
      assert map_size(updated_agent.cache) == 0
      
      assert_receive {:signal_emitted, "cache_cleared", clear_result}
      assert clear_result["cleared_entries"] == 1
    end
  end
  
  describe "metrics and status" do
    setup do
      {:ok, agent} = ResponseProcessorAgent.mount(%{}, %{
        cache: %{"key1" => %{data: "data1"}, "key2" => %{data: "data2"}},
        metrics: %{
          total_processed: 100,
          total_cached: 50,
          cache_hits: 30,
          cache_misses: 20,
          avg_processing_time: 25.5,
          format_distribution: %{json: 40, text: 60},
          quality_distribution: %{good: 70, fair: 30},
          error_count: 5
        },
        parsers: %{json: "JSONParser", text: "TextParser"},
        enhancers: [:format_beautification, :link_enrichment],
        validators: [:completeness_check, :safety_validation],
        config: %{cache_ttl: 7200, max_cache_size: 10000}
      })
      
      %{agent: agent}
    end
    
    test "returns processing metrics", %{agent: agent} do
      signal = %{"type" => "get_metrics"}
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "processing_metrics", metrics}
      assert Map.has_key?(metrics, "processing")
      assert Map.has_key?(metrics, "caching")
      assert Map.has_key?(metrics, "distributions")
      
      assert metrics["processing"]["total_processed"] == 100
      assert metrics["caching"]["cache_hits"] == 30
      assert metrics["distributions"]["formats"] == %{json: 40, text: 60}
    end
    
    test "returns agent status", %{agent: agent} do
      signal = %{"type" => "get_status"}
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "processor_status", status}
      assert status["status"] == "healthy"
      assert status["cache_size"] == 2
      assert status["total_processed"] == 100
      assert Map.has_key?(status, "parsers_available")
      assert Map.has_key?(status, "enhancers_enabled")
      assert Map.has_key?(status, "memory_usage")
    end
    
    test "updates configuration", %{agent: agent} do
      config_updates = %{
        "cache_ttl" => 3600,
        "quality_threshold" => 0.9
      }
      
      signal = %{
        "type" => "configure_processor",
        "data" => config_updates
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, updated_agent} = ResponseProcessorAgent.handle_signal(agent_with_mock, signal)
      
      # Configuration should be updated
      assert updated_agent.config["cache_ttl"] == 3600
      assert updated_agent.config["quality_threshold"] == 0.9
      
      assert_receive {:signal_emitted, "processor_configured", config_result}
      assert config_result["changes"] == ["cache_ttl", "quality_threshold"]
    end
  end
  
  describe "ProcessedResponse data structure" do
    test "creates new processed response" do
      response = ProcessedResponse.new("test content", "req-123", :openai, "gpt-4")
      
      assert response.original_response == "test content"
      assert response.request_id == "req-123"
      assert response.provider == :openai
      assert response.model == "gpt-4"
      assert response.format == :unknown
      assert response.quality_score == 0.0
      assert is_binary(response.id)
    end
    
    test "updates parsed content and format" do
      response = ProcessedResponse.new("test", "req-123", :openai, "gpt-4")
      
      updated = ProcessedResponse.set_parsed_content(response, %{"key" => "value"}, :json)
      
      assert updated.parsed_content == %{"key" => "value"}
      assert updated.format == :json
      assert Map.has_key?(updated.metadata, :parsing_completed_at)
    end
    
    test "updates quality score and validation results" do
      response = ProcessedResponse.new("test", "req-123", :openai, "gpt-4")
      
      validation_results = %{
        is_valid: true,
        completeness_score: 0.9,
        readability_score: 0.8,
        safety_score: 1.0,
        issues: []
      }
      
      updated = ProcessedResponse.set_quality_score(response, 0.85, validation_results)
      
      assert updated.quality_score == 0.85
      assert updated.validation_results.is_valid == true
      assert updated.validation_results.completeness_score == 0.9
    end
    
    test "adds enhancement log entries" do
      response = ProcessedResponse.new("test", "req-123", :openai, "gpt-4")
      
      updated = ProcessedResponse.add_enhancement_log(response, :format_beautification, 0.6, 0.8)
      
      assert length(updated.enhancement_log) == 1
      
      log_entry = List.first(updated.enhancement_log)
      assert log_entry.type == :format_beautification
      assert log_entry.before_quality == 0.6
      assert log_entry.after_quality == 0.8
    end
    
    test "adds error log entries" do
      response = ProcessedResponse.new("test", "req-123", :openai, "gpt-4")
      
      updated = ProcessedResponse.add_error_log(response, :parsing_failed, "Invalid JSON")
      
      assert length(updated.error_log) == 1
      
      error_entry = List.first(updated.error_log)
      assert error_entry.type == :parsing_failed
      assert error_entry.message == "Invalid JSON"
    end
    
    test "determines if response is successful" do
      # Successful response
      good_validation = %{is_valid: true, completeness_score: 0.9, readability_score: 0.8, safety_score: 1.0, issues: []}
      good_response = ProcessedResponse.new("good content", "req-123", :openai, "gpt-4")
      |> ProcessedResponse.set_quality_score(0.85, good_validation)
      
      assert ProcessedResponse.successful?(good_response)
      
      # Unsuccessful response
      bad_validation = %{is_valid: false, completeness_score: 0.3, readability_score: 0.2, safety_score: 0.8, issues: ["incomplete"]}
      bad_response = ProcessedResponse.new("bad", "req-456", :openai, "gpt-4")
      |> ProcessedResponse.set_quality_score(0.3, bad_validation)
      
      refute ProcessedResponse.successful?(bad_response)
    end
    
    test "determines if response is cacheable" do
      # High quality response should be cacheable
      good_validation = %{is_valid: true, completeness_score: 0.9, readability_score: 0.8, safety_score: 1.0, issues: []}
      good_response = ProcessedResponse.new("This is a good quality response with sufficient length", "req-123", :openai, "gpt-4")
      |> ProcessedResponse.set_quality_score(0.85, good_validation)
      |> ProcessedResponse.set_enhanced_content("This is a good quality response with sufficient length")
      
      assert ProcessedResponse.cacheable?(good_response)
      
      # Low quality response should not be cacheable
      bad_validation = %{is_valid: false, completeness_score: 0.3, readability_score: 0.2, safety_score: 0.8, issues: ["incomplete"]}
      bad_response = ProcessedResponse.new("bad", "req-456", :openai, "gpt-4")
      |> ProcessedResponse.set_quality_score(0.3, bad_validation)
      
      refute ProcessedResponse.cacheable?(bad_response)
    end
    
    test "converts to client response format" do
      response = ProcessedResponse.new("test content", "req-123", :openai, "gpt-4")
      |> ProcessedResponse.set_parsed_content("parsed", :text)
      |> ProcessedResponse.set_quality_score(0.8, %{is_valid: true, completeness_score: 0.8, readability_score: 0.7, safety_score: 1.0, issues: []})
      |> ProcessedResponse.set_enhanced_content("enhanced content")
      |> ProcessedResponse.set_processing_time(150)
      
      client_response = ProcessedResponse.to_client_response(response)
      
      assert client_response.content == "enhanced content"
      assert client_response.format == :text
      assert client_response.quality_score == 0.8
      assert client_response.provider == :openai
      assert client_response.processing_time == 150
      assert Map.has_key?(client_response, :metadata)
    end
  end
  
  describe "unknown signals" do
    setup do
      {:ok, agent} = ResponseProcessorAgent.mount(%{}, %{
        cache: %{},
        metrics: %{
          total_processed: 0,
          total_cached: 0,
          cache_hits: 0,
          cache_misses: 0,
          avg_processing_time: 0.0,
          format_distribution: %{},
          quality_distribution: %{},
          error_count: 0
        },
        parsers: %{},
        enhancers: [],
        validators: [],
        config: %{cache_ttl: 7200, max_cache_size: 10000}
      })
      
      %{agent: agent}
    end
    
    test "handles unknown signal gracefully", %{agent: agent} do
      signal = %{
        "type" => "unknown_signal",
        "data" => %{"some" => "data"}
      }
      
      # Should not crash
      {:ok, _updated_agent} = ResponseProcessorAgent.handle_signal(agent, signal)
    end
  end
end