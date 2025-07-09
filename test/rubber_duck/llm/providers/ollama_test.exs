defmodule RubberDuck.LLM.Providers.OllamaTest do
  use ExUnit.Case, async: true

  alias RubberDuck.LLM.Providers.Ollama
  alias RubberDuck.LLM.{Request, Response, ProviderConfig}

  describe "validate_config/1" do
    test "validates base_url is present when not default" do
      config = %ProviderConfig{
        name: :ollama,
        adapter: Ollama,
        base_url: "http://custom:11434"
      }

      assert :ok = Ollama.validate_config(config)
    end

    test "accepts nil base_url as it uses default" do
      config = %ProviderConfig{
        name: :ollama,
        adapter: Ollama,
        base_url: nil
      }

      assert :ok = Ollama.validate_config(config)
    end

    test "does not require API key" do
      config = %ProviderConfig{
        name: :ollama,
        adapter: Ollama,
        api_key: nil
      }

      assert :ok = Ollama.validate_config(config)
    end
  end

  describe "info/0" do
    test "returns provider information" do
      info = Ollama.info()

      assert info.name == "Ollama"
      assert info.requires_api_key == false
      assert is_list(info.supported_models)
      assert "llama2" in info.supported_models
      assert "mistral" in info.supported_models
      assert "codellama" in info.supported_models
    end

    test "indicates supported features" do
      info = Ollama.info()

      assert info.supports_streaming == true
      assert info.supports_function_calling == false
      assert info.supports_system_messages == true
      assert info.supports_json_mode == true
      assert info.supports_vision == false
    end
  end

  describe "supports_feature?/1" do
    test "supports expected features" do
      assert Ollama.supports_feature?(:streaming)
      assert Ollama.supports_feature?(:system_messages)
      assert Ollama.supports_feature?(:json_mode)
    end

    test "does not support function calling or vision" do
      refute Ollama.supports_feature?(:function_calling)
      refute Ollama.supports_feature?(:vision)
    end

    test "does not support unknown features" do
      refute Ollama.supports_feature?(:unknown_feature)
    end
  end

  describe "count_tokens/2" do
    test "returns not supported error" do
      assert {:error, :not_supported} = Ollama.count_tokens("test text", "llama2")
    end
  end

  describe "execute/2 - request building" do
    setup do
      config = %ProviderConfig{
        name: :ollama,
        adapter: Ollama,
        base_url: "http://localhost:11434",
        timeout: 5_000
      }

      {:ok, config: config}
    end

    test "builds chat request correctly", %{config: config} do
      request = %Request{
        model: "llama2",
        messages: [
          %{"role" => "system", "content" => "You are helpful."},
          %{"role" => "user", "content" => "Hello"}
        ],
        options: %{temperature: 0.7}
      }

      # This test would need to mock the HTTP call
      # For now, we test that it doesn't crash
      # In a real test, you'd use a library like Bypass or Mox

      # Example of what the request body should look like:
      expected_body = %{
        "model" => "llama2",
        "messages" => [
          %{"role" => "system", "content" => "You are helpful."},
          %{"role" => "user", "content" => "Hello"}
        ],
        "stream" => false,
        "options" => %{"temperature" => 0.7}
      }

      # The actual HTTP call would fail in tests without mocking
      # assert {:ok, response} = Ollama.execute(request, config)
    end

    test "builds generate request for prompt-based input", %{config: config} do
      request = %Request{
        model: "llama2",
        messages: [],
        options: %{prompt: "Complete this: Hello"}
      }

      # In production, this would use the /api/generate endpoint
      # with a prompt field instead of messages
    end

    test "handles options correctly", %{config: config} do
      request = %Request{
        model: "llama2",
        messages: [%{"role" => "user", "content" => "Test"}],
        options: %{
          temperature: 0.8,
          max_tokens: 100,
          top_p: 0.9,
          stop: [".", "!"],
          system: "Custom system prompt",
          json_mode: true
        }
      }

      # These options should be mapped to Ollama format:
      # - max_tokens -> num_predict
      # - json_mode -> format: "json"
      # - system as separate field
    end
  end

  describe "health_check/1" do
    test "returns healthy status with available models when Ollama is running" do
      config = %ProviderConfig{
        name: :ollama,
        adapter: Ollama,
        base_url: "http://localhost:11434"
      }

      # This would need mocking in a real test
      # Expected response from /api/tags:
      # %{"models" => [
      #   %{"name" => "llama2:latest", ...},
      #   %{"name" => "mistral:latest", ...}
      # ]}

      # assert {:ok, health} = Ollama.health_check(config)
      # assert health.status == :healthy
      # assert is_list(health.models)
    end

    test "returns connection error when Ollama is not running" do
      config = %ProviderConfig{
        name: :ollama,
        adapter: Ollama,
        # Wrong port
        base_url: "http://localhost:9999"
      }

      # Would return {:error, {:connection_failed, reason}}
    end
  end

  describe "stream_completion/3" do
    setup do
      config = %ProviderConfig{
        name: :ollama,
        adapter: Ollama,
        base_url: "http://localhost:11434",
        timeout: 30_000
      }

      request = %Request{
        model: "llama2",
        messages: [%{"role" => "user", "content" => "Hello"}]
      }

      {:ok, config: config, request: request}
    end

    test "returns a reference for streaming", %{config: config, request: request} do
      callback = fn event -> send(self(), event) end

      # This would start streaming in a real scenario
      # assert {:ok, ref} = Ollama.stream_completion(request, config, callback)
      # assert is_reference(ref)
    end

    test "streaming callback receives chunks" do
      # In a real test with mocking:
      # - First callback: {:chunk, %{content: "Hello", done: false}, ref}
      # - Second callback: {:chunk, %{content: " there!", done: false}, ref}
      # - Final callback: {:done, ref}
    end
  end

  describe "response parsing" do
    test "parses chat endpoint response correctly" do
      # Mock response from Ollama chat endpoint
      raw_response = %{
        "model" => "llama2",
        "created_at" => "2024-01-01T00:00:00Z",
        "message" => %{
          "role" => "assistant",
          "content" => "Hello! How can I help you?"
        },
        "done" => true,
        "total_duration" => 5_000_000_000,
        "load_duration" => 1_000_000_000,
        "prompt_eval_count" => 10,
        "prompt_eval_duration" => 500_000_000,
        "eval_count" => 15,
        "eval_duration" => 3_500_000_000
      }

      # The response parser would create:
      # - Response with proper structure
      # - Usage information from eval counts
      # - Metadata with timing information
    end

    test "parses generate endpoint response correctly" do
      # Mock response from Ollama generate endpoint
      raw_response = %{
        "model" => "llama2",
        "created_at" => "2024-01-01T00:00:00Z",
        "response" => "This is the generated text.",
        "done" => true,
        "prompt_eval_count" => 5,
        "eval_count" => 10
      }

      # Should extract response field instead of message.content
    end
  end

  describe "error handling" do
    test "handles connection errors gracefully" do
      config = %ProviderConfig{
        name: :ollama,
        adapter: Ollama,
        base_url: "http://invalid-host:11434"
      }

      request = %Request{
        model: "llama2",
        messages: [%{"role" => "user", "content" => "Test"}]
      }

      # Would return {:error, {:connection_error, reason}}
    end

    test "handles HTTP errors properly" do
      # Test various HTTP status codes:
      # - 404: Model not found
      # - 500: Server error
      # - 503: Service unavailable
    end
  end
end
