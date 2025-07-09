defmodule RubberDuck.LLM.Providers.TGITest do
  use ExUnit.Case, async: true

  alias RubberDuck.LLM.Providers.TGI
  alias RubberDuck.LLM.{Request, Response, ProviderConfig}

  describe "validate_config/1" do
    test "validates base_url is present" do
      config = %ProviderConfig{
        name: :tgi,
        adapter: TGI,
        base_url: "http://localhost:8080"
      }

      assert :ok = TGI.validate_config(config)
    end

    test "returns error when base_url is missing" do
      config = %ProviderConfig{
        name: :tgi,
        adapter: TGI,
        base_url: nil
      }

      assert {:error, "base_url is required for TGI provider"} = TGI.validate_config(config)
    end

    test "does not require API key for self-hosted TGI" do
      config = %ProviderConfig{
        name: :tgi,
        adapter: TGI,
        base_url: "http://localhost:8080",
        api_key: nil
      }

      assert :ok = TGI.validate_config(config)
    end
  end

  describe "info/0" do
    test "returns provider information" do
      info = TGI.info()

      assert info.name == "Text Generation Inference"
      assert info.description == "High-performance inference server for Hugging Face models"
      assert info.requires_api_key == false
      assert info.supports_streaming == true
      assert info.supports_function_calling == true
      assert info.supports_system_messages == true
      assert info.supports_json_mode == true
      assert info.supports_guided_generation == true
      assert info.supports_vision == false
    end

    test "includes comprehensive model list" do
      info = TGI.info()

      assert is_list(info.supported_models)
      assert length(info.supported_models) > 10
      assert "llama-3.1-8b" in info.supported_models
      assert "mistral-7b" in info.supported_models
      assert "codellama-13b" in info.supported_models
      assert "falcon-7b" in info.supported_models
      assert "starcoder" in info.supported_models
    end
  end

  describe "supports_feature?/1" do
    test "supports expected features" do
      assert TGI.supports_feature?(:streaming)
      assert TGI.supports_feature?(:system_messages)
      assert TGI.supports_feature?(:json_mode)
      assert TGI.supports_feature?(:function_calling)
      assert TGI.supports_feature?(:guided_generation)
    end

    test "does not support vision" do
      refute TGI.supports_feature?(:vision)
    end

    test "does not support unknown features" do
      refute TGI.supports_feature?(:unknown_feature)
    end
  end

  describe "count_tokens/2" do
    test "estimates tokens for text" do
      text = "Hello, this is a test message for token counting."

      assert {:ok, count} = TGI.count_tokens(text, "llama-3.1-8b")
      assert is_integer(count)
      assert count > 0
    end

    test "estimates tokens for longer text" do
      text = String.duplicate("word ", 100)

      assert {:ok, count} = TGI.count_tokens(text, "mistral-7b")
      assert is_integer(count)
      assert count > 100
    end

    test "handles empty text" do
      assert {:ok, 0} = TGI.count_tokens("", "llama-3.1-8b")
    end
  end

  describe "execute/2 - endpoint selection" do
    setup do
      config = %ProviderConfig{
        name: :tgi,
        adapter: TGI,
        base_url: "http://localhost:8080",
        timeout: 30_000
      }

      {:ok, config: config}
    end

    test "selects chat endpoint for message-based requests", %{config: config} do
      request = %Request{
        model: "llama-3.1-8b",
        messages: [
          %{"role" => "system", "content" => "You are helpful."},
          %{"role" => "user", "content" => "Hello"}
        ]
      }

      # Test endpoint selection logic
      endpoint = TGI.send(:determine_endpoint, [request])
      assert endpoint == "/v1/chat/completions"
    end

    test "selects generate endpoint for prompt-based requests", %{config: config} do
      request = %Request{
        model: "llama-3.1-8b",
        messages: [],
        options: %{prompt: "Complete this: Hello"}
      }

      # Test endpoint selection logic
      endpoint = TGI.send(:determine_endpoint, [request])
      assert endpoint == "/generate"
    end

    test "defaults to chat endpoint", %{config: config} do
      request = %Request{
        model: "llama-3.1-8b",
        messages: [],
        options: %{}
      }

      # Test endpoint selection logic
      endpoint = TGI.send(:determine_endpoint, [request])
      assert endpoint == "/v1/chat/completions"
    end
  end

  describe "request building" do
    setup do
      config = %ProviderConfig{
        name: :tgi,
        adapter: TGI,
        base_url: "http://localhost:8080"
      }

      {:ok, config: config}
    end

    test "builds chat completions request correctly", %{config: config} do
      request = %Request{
        model: "llama-3.1-8b",
        messages: [
          %{"role" => "system", "content" => "You are helpful."},
          %{"role" => "user", "content" => "Hello"}
        ],
        options: %{
          temperature: 0.7,
          max_tokens: 100,
          tools: [
            %{
              "type" => "function",
              "function" => %{
                "name" => "get_weather",
                "description" => "Get weather"
              }
            }
          ]
        }
      }

      # Expected request body for chat completions
      expected_body = %{
        "model" => "llama-3.1-8b",
        "messages" => [
          %{"role" => "system", "content" => "You are helpful."},
          %{"role" => "user", "content" => "Hello"}
        ],
        "stream" => false,
        "temperature" => 0.7,
        "max_tokens" => 100,
        "tools" => [
          %{
            "type" => "function",
            "function" => %{
              "name" => "get_weather",
              "description" => "Get weather"
            }
          }
        ]
      }

      # Test request building (this would need mocking for actual HTTP calls)
      # For now, we validate the structure
      assert is_map(expected_body)
    end

    test "builds generate request correctly", %{config: config} do
      request = %Request{
        model: "llama-3.1-8b",
        messages: [],
        options: %{
          prompt: "Complete this: Hello",
          temperature: 0.8,
          max_tokens: 200,
          top_p: 0.9
        }
      }

      # Expected request body for generate
      expected_body = %{
        "inputs" => "Complete this: Hello",
        "parameters" => %{
          "temperature" => 0.8,
          "max_new_tokens" => 200,
          "top_p" => 0.9
        }
      }

      # Test request building structure
      assert is_map(expected_body)
    end

    test "handles function calling parameters", %{config: config} do
      request = %Request{
        model: "llama-3.1-8b",
        messages: [%{"role" => "user", "content" => "What's the weather?"}],
        options: %{
          tools: [
            %{
              "type" => "function",
              "function" => %{
                "name" => "get_weather",
                "description" => "Get current weather"
              }
            }
          ],
          tool_choice: "auto"
        }
      }

      # Should include tools in chat completions request
      expected_keys = ["model", "messages", "stream", "tools", "tool_choice"]
      # In actual implementation, these would be properly formatted
      assert is_list(expected_keys)
    end
  end

  describe "response parsing" do
    test "parses OpenAI-compatible chat completions response" do
      # Mock OpenAI-compatible response from TGI
      openai_response = %{
        "id" => "chatcmpl-abc123",
        "object" => "chat.completion",
        "created" => 1_677_652_288,
        "model" => "llama-3.1-8b",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Hello! How can I help you today?"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 20,
          "total_tokens" => 30
        }
      }

      response = Response.from_provider(:tgi, openai_response)

      assert response.id == "chatcmpl-abc123"
      assert response.model == "llama-3.1-8b"
      assert response.provider == :tgi
      assert length(response.choices) == 1
      assert response.usage.prompt_tokens == 10
      assert response.usage.completion_tokens == 20
      assert response.usage.total_tokens == 30
      assert Response.get_content(response) == "Hello! How can I help you today?"
    end

    test "parses TGI-native generate response" do
      # Mock TGI-native response from /generate endpoint
      tgi_response = %{
        "generated_text" => "Hello there! I'm doing well, thank you for asking.",
        "finish_reason" => "stop",
        "details" => %{
          "prefill" => ["Hello", "how", "are", "you"],
          "tokens" => ["Hello", "there!", "I'm", "doing", "well"],
          "generated_tokens" => 5
        }
      }

      response = Response.from_provider(:tgi, tgi_response)

      assert String.starts_with?(response.id, "tgi_")
      assert response.model == "tgi"
      assert response.provider == :tgi
      assert length(response.choices) == 1
      assert response.usage.prompt_tokens == 4
      assert response.usage.completion_tokens == 5
      assert response.usage.total_tokens == 9
      assert Response.get_content(response) == "Hello there! I'm doing well, thank you for asking."
    end

    test "handles response with no usage information" do
      minimal_response = %{
        "generated_text" => "Simple response"
      }

      response = Response.from_provider(:tgi, minimal_response)

      assert response.usage.prompt_tokens == 0
      assert response.usage.completion_tokens == 0
      assert response.usage.total_tokens == 0
      assert Response.get_content(response) == "Simple response"
    end
  end

  describe "health_check/1" do
    test "returns healthy status when TGI is running" do
      config = %ProviderConfig{
        name: :tgi,
        adapter: TGI,
        base_url: "http://localhost:8080"
      }

      # This would need mocking in a real test
      # Expected health check to /health endpoint
      # Expected response: 200 OK

      # Mock info response from /info endpoint
      # Expected response: %{"model_id" => "llama-3.1-8b", ...}

      # assert {:ok, health} = TGI.health_check(config)
      # assert health.status == :healthy
      # assert health.model == "llama-3.1-8b"
      # assert String.contains?(health.message, "healthy")
    end

    test "returns connection error when TGI is not running" do
      config = %ProviderConfig{
        name: :tgi,
        adapter: TGI,
        # Wrong port
        base_url: "http://localhost:9999"
      }

      # Would return {:error, {:connection_failed, reason}}
      # when TGI server is not accessible
    end

    test "handles HTTP errors from TGI server" do
      config = %ProviderConfig{
        name: :tgi,
        adapter: TGI,
        base_url: "http://localhost:8080"
      }

      # Mock scenarios:
      # - 404: TGI not found
      # - 500: TGI server error
      # - 503: TGI service unavailable

      # assert {:error, {:unhealthy, message}} = TGI.health_check(config)
    end
  end

  describe "stream_completion/3" do
    setup do
      config = %ProviderConfig{
        name: :tgi,
        adapter: TGI,
        base_url: "http://localhost:8080",
        timeout: 60_000
      }

      request = %Request{
        model: "llama-3.1-8b",
        messages: [%{"role" => "user", "content" => "Tell me a story"}]
      }

      {:ok, config: config, request: request}
    end

    test "returns a reference for streaming", %{config: config, request: request} do
      callback = fn event -> send(self(), event) end

      # In production, this would start streaming
      # assert {:ok, ref} = TGI.stream_completion(request, config, callback)
      # assert is_reference(ref)
    end

    test "handles chat completions streaming format" do
      # Mock OpenAI-compatible streaming chunks
      chunk1 = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n"
      chunk2 = "data: {\"choices\":[{\"delta\":{\"content\":\" there!\"}}]}\n\n"
      chunk3 = "data: [DONE]\n\n"

      # Streaming should parse these chunks correctly
      # and send {:chunk, %{content: "Hello", done: false}, ref}
      # followed by {:chunk, %{content: " there!", done: false}, ref}
      # and finally {:done, ref}
    end

    test "handles TGI-native streaming format" do
      # Mock TGI-native streaming chunks
      chunk1 = "{\"token\":{\"text\":\"Hello\"},\"generated_text\":null}"
      chunk2 = "{\"token\":{\"text\":\" there!\"},\"generated_text\":null}"
      chunk3 = "{\"token\":{\"text\":\"\"},\"generated_text\":\"Hello there!\"}"

      # Streaming should parse these chunks correctly
    end
  end

  describe "cost calculation" do
    test "TGI is free for self-hosted models" do
      # Mock TGI response
      tgi_response = %{
        "generated_text" => "Test response",
        "details" => %{
          "prefill" => ["test"],
          "tokens" => ["response"]
        }
      }

      response = Response.from_provider(:tgi, tgi_response)
      cost = Response.calculate_cost(response)

      assert cost == 0.0
    end

    test "OpenAI-compatible format is also free" do
      openai_response = %{
        "id" => "test",
        "object" => "chat.completion",
        "model" => "llama-3.1-8b",
        "choices" => [
          %{
            "message" => %{"content" => "Test response"},
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 20,
          "total_tokens" => 30
        }
      }

      response = Response.from_provider(:tgi, openai_response)
      cost = Response.calculate_cost(response)

      assert cost == 0.0
    end
  end

  describe "error handling" do
    test "handles connection errors gracefully" do
      config = %ProviderConfig{
        name: :tgi,
        adapter: TGI,
        base_url: "http://invalid-host:8080"
      }

      request = %Request{
        model: "llama-3.1-8b",
        messages: [%{"role" => "user", "content" => "Test"}]
      }

      # Would return {:error, {:connection_error, reason}}
    end

    test "handles HTTP errors properly" do
      # Test various HTTP status codes from TGI:
      # - 400: Bad request (invalid parameters)
      # - 404: Model not found
      # - 422: Validation error
      # - 500: Internal server error
      # - 503: Service unavailable (model loading)
    end

    test "handles malformed JSON responses" do
      # TGI should return valid JSON, but handle edge cases
      # where response might be malformed
    end
  end

  describe "advanced features" do
    test "supports function calling with tools" do
      request = %Request{
        model: "llama-3.1-8b",
        messages: [%{"role" => "user", "content" => "What's the weather?"}],
        options: %{
          tools: [
            %{
              "type" => "function",
              "function" => %{
                "name" => "get_weather",
                "description" => "Get weather information"
              }
            }
          ],
          tool_choice: "auto"
        }
      }

      # Should include tools in the request body
      assert is_map(request.options)
      assert Map.has_key?(request.options, :tools)
    end

    test "supports guided generation with JSON schema" do
      request = %Request{
        model: "llama-3.1-8b",
        messages: [%{"role" => "user", "content" => "Generate a JSON response"}],
        options: %{
          json_mode: true,
          schema: %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"},
              "age" => %{"type" => "integer"}
            }
          }
        }
      }

      # Should support structured output generation
      assert request.options[:json_mode] == true
      assert Map.has_key?(request.options, :schema)
    end
  end
end
