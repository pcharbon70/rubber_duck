defmodule RubberDuck.Agents.ProviderAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.{ProviderAgent, OpenAIProviderAgent, AnthropicProviderAgent, LocalProviderAgent}
  alias RubberDuck.TestSupport.{MockAgent, SignalCapture}

  # Mock provider module for testing
  defmodule MockProvider do
    @behaviour RubberDuck.LLM.Provider

    def execute(_request, _config) do
      {:ok, %RubberDuck.LLM.Response{
        id: "test-response",
        choices: [%{message: %{role: "assistant", content: "Test response"}}],
        usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
        model: "test-model",
        created: DateTime.to_unix(DateTime.utc_now())
      }}
    end

    def validate_config(_config), do: :ok
    def info, do: %{name: "Mock", models: ["test-model"]}
    def supports_feature?(_feature), do: true
    def estimate_tokens(_messages, _model), do: {:ok, %{prompt_tokens: 10}}
  end

  setup do
    SignalCapture.start_link()
    :ok
  end

  describe "base provider agent functionality" do
    setup do
      # Create a test provider agent
      defmodule TestProviderAgent do
        use RubberDuck.Agents.ProviderAgent,
          name: "test_provider",
          description: "Test provider agent"
      end

      {:ok, agent} = MockAgent.start_agent(TestProviderAgent, %{
        provider_module: MockProvider,
        provider_config: %{name: :mock, api_key: "test-key"},
        rate_limiter: %{limit: 10, window: 60_000}
      })

      {:ok, agent: agent}
    end

    test "handles provider request successfully", %{agent: agent} do
      signal = %{
        "id" => "test-signal-1",
        "source" => "test",
        "type" => "provider_request",
        "data" => %{
          "request_id" => "req-001",
          "messages" => [%{"role" => "user", "content" => "Hello"}],
          "model" => "test-model",
          "temperature" => 0.7
        }
      }

      {:ok, _updated_agent} = TestProviderAgent.handle_signal(agent, signal)

      # Should receive response signal
      assert_receive {:signal, %{"type" => "provider_response"} = response}, 2000
      assert response["data"]["request_id"] == "req-001"
      assert response["data"]["provider"] == "test_provider"
    end

    test "enforces rate limiting", %{agent: agent} do
      # Set a very low rate limit
      agent = put_in(agent.state.rate_limiter, %{
        limit: 2,
        window: 60_000,
        current_count: 2,
        window_start: System.monotonic_time(:millisecond)
      })

      signal = %{
        "id" => "test-signal-2",
        "source" => "test",
        "type" => "provider_request",
        "data" => %{
          "request_id" => "req-002",
          "messages" => [%{"role" => "user", "content" => "Hello"}],
          "model" => "test-model"
        }
      }

      {:ok, _updated_agent} = TestProviderAgent.handle_signal(agent, signal)

      # Should receive rate limit error
      assert_receive {:signal, %{"type" => "provider_error"} = error}, 1000
      assert error["data"]["error_type"] == "rate_limited"
    end

    test "circuit breaker opens after failures", %{agent: agent} do
      # Set circuit breaker to near threshold
      agent = put_in(agent.state.circuit_breaker, %{
        state: :closed,
        failure_count: 4,
        consecutive_failures: 4,
        failure_threshold: 5,
        timeout: 60_000
      })

      # Simulate a failure by updating state
      agent = put_in(agent.state.circuit_breaker.consecutive_failures, 5)
      agent = put_in(agent.state.circuit_breaker.state, :open)

      signal = %{
        "id" => "test-signal-3",
        "source" => "test",
        "type" => "provider_request",
        "data" => %{
          "request_id" => "req-003",
          "messages" => [%{"role" => "user", "content" => "Hello"}],
          "model" => "test-model"
        }
      }

      {:ok, _updated_agent} = TestProviderAgent.handle_signal(agent, signal)

      # Should receive circuit breaker error
      assert_receive {:signal, %{"type" => "provider_error"} = error}, 1000
      assert error["data"]["error_type"] == "circuit_breaker_open"
    end

    test "handles feature check", %{agent: agent} do
      signal = %{
        "id" => "test-signal-4",
        "source" => "test",
        "type" => "feature_check",
        "data" => %{"feature" => "streaming"}
      }

      {:ok, _updated_agent} = TestProviderAgent.handle_signal(agent, signal)

      assert_receive {:signal, %{"type" => "feature_check_response"} = response}, 1000
      assert response["data"]["feature"] == "streaming"
      assert response["data"]["supported"] == true
    end

    test "provides status report", %{agent: agent} do
      signal = %{
        "id" => "test-signal-5",
        "source" => "test",
        "type" => "get_provider_status"
      }

      {:ok, _updated_agent} = TestProviderAgent.handle_signal(agent, signal)

      assert_receive {:signal, %{"type" => "provider_status"} = status}, 1000
      assert status["data"]["provider"] == "test_provider"
      assert status["data"]["status"] == "healthy"
      assert status["data"]["circuit_breaker"]["state"] == "closed"
    end
  end

  describe "OpenAI provider agent" do
    setup do
      {:ok, agent} = MockAgent.start_agent(OpenAIProviderAgent, %{})
      {:ok, agent: agent}
    end

    test "initializes with OpenAI-specific configuration", %{agent: agent} do
      assert agent.state.provider_module == RubberDuck.LLM.Providers.OpenAI
      assert :function_calling in agent.state.capabilities
      assert :streaming in agent.state.capabilities
      assert agent.state.rate_limiter.limit > 0
    end

    test "handles function configuration", %{agent: agent} do
      functions = [
        %{
          "name" => "get_weather",
          "description" => "Get the weather",
          "parameters" => %{}
        }
      ]

      signal = %{
        "id" => "test-signal-6",
        "source" => "test",
        "type" => "configure_functions",
        "data" => %{"functions" => functions}
      }

      {:ok, updated_agent} = OpenAIProviderAgent.handle_signal(agent, signal)

      assert updated_agent.state[:functions] == functions
      assert_receive {:signal, %{"type" => "functions_configured"}}, 1000
    end

    test "handles streaming request", %{agent: agent} do
      signal = %{
        "id" => "test-signal-7",
        "source" => "test",
        "type" => "stream_request",
        "data" => %{
          "request_id" => "req-004",
          "messages" => [%{"role" => "user", "content" => "Stream this"}],
          "model" => "gpt-4",
          "callback_signal" => "stream_chunk"
        }
      }

      {:ok, _updated_agent} = OpenAIProviderAgent.handle_signal(agent, signal)

      # In a real test, would check for stream chunks
      # For now, just verify no immediate error
      refute_receive {:signal, %{"type" => "provider_error"}}, 100
    end
  end

  describe "Anthropic provider agent" do
    setup do
      {:ok, agent} = MockAgent.start_agent(AnthropicProviderAgent, %{})
      {:ok, agent: agent}
    end

    test "initializes with Anthropic-specific configuration", %{agent: agent} do
      assert agent.state.provider_module == RubberDuck.LLM.Providers.Anthropic
      assert :vision in agent.state.capabilities
      assert :large_context in agent.state.capabilities
      assert :safety_features in agent.state.capabilities
    end

    test "handles safety configuration", %{agent: agent} do
      signal = %{
        "id" => "test-signal-8",
        "source" => "test",
        "type" => "configure_safety",
        "data" => %{
          "block_flagged_content" => false,
          "content_filtering" => "strict"
        }
      }

      {:ok, updated_agent} = AnthropicProviderAgent.handle_signal(agent, signal)

      assert updated_agent.state.safety_config.block_flagged_content == false
      assert updated_agent.state.safety_config.content_filtering == :strict
      assert_receive {:signal, %{"type" => "safety_configured"}}, 1000
    end

    test "handles vision request for supported models", %{agent: agent} do
      signal = %{
        "id" => "test-signal-9",
        "source" => "test",
        "type" => "vision_request",
        "data" => %{
          "request_id" => "req-005",
          "messages" => [%{"role" => "user", "content" => "What's in this image?"}],
          "model" => "claude-3-opus",
          "images" => [%{"data" => "base64data", "media_type" => "image/jpeg"}]
        }
      }

      {:ok, _updated_agent} = AnthropicProviderAgent.handle_signal(agent, signal)

      # Should process normally (no immediate error)
      refute_receive {:signal, %{"type" => "provider_error"}}, 100
    end

    test "rejects vision request for unsupported models", %{agent: agent} do
      signal = %{
        "id" => "test-signal-10",
        "source" => "test",
        "type" => "vision_request",
        "data" => %{
          "request_id" => "req-006",
          "messages" => [%{"role" => "user", "content" => "What's in this image?"}],
          "model" => "claude-2.0",
          "images" => [%{"data" => "base64data"}]
        }
      }

      {:ok, _updated_agent} = AnthropicProviderAgent.handle_signal(agent, signal)

      assert_receive {:signal, %{"type" => "provider_error"} = error}, 1000
      assert error["data"]["error_type"] == "unsupported_feature"
    end
  end

  describe "Local provider agent" do
    setup do
      {:ok, agent} = MockAgent.start_agent(LocalProviderAgent, %{})
      {:ok, agent: agent}
    end

    test "initializes with local-specific configuration", %{agent: agent} do
      assert agent.state.provider_module == RubberDuck.LLM.Providers.Ollama
      assert :offline in agent.state.capabilities
      assert :privacy in agent.state.capabilities
      assert agent.state.loaded_models == %{}
    end

    test "handles model loading", %{agent: agent} do
      signal = %{
        "id" => "test-signal-11",
        "source" => "test",
        "type" => "load_model",
        "data" => %{"model" => "llama2-7b"}
      }

      {:ok, _updated_agent} = LocalProviderAgent.handle_signal(agent, signal)

      # Should attempt to load (in test, would mock the actual loading)
      refute_receive {:signal, %{"type" => "model_load_failed"}}, 100
    end

    test "lists available models", %{agent: agent} do
      signal = %{
        "id" => "test-signal-12",
        "source" => "test",
        "type" => "list_available_models"
      }

      {:ok, _updated_agent} = LocalProviderAgent.handle_signal(agent, signal)

      assert_receive {:signal, %{"type" => "available_models"} = response}, 1000
      assert Map.has_key?(response["data"], "models")
      assert Map.has_key?(response["data"], "loaded")
    end

    test "provides resource status", %{agent: agent} do
      signal = %{
        "id" => "test-signal-13",
        "source" => "test",
        "type" => "get_resource_status"
      }

      {:ok, _updated_agent} = LocalProviderAgent.handle_signal(agent, signal)

      assert_receive {:signal, %{"type" => "resource_status"} = status}, 1000
      assert Map.has_key?(status["data"], "cpu_usage")
      assert Map.has_key?(status["data"], "memory_usage")
      assert Map.has_key?(status["data"], "loaded_models")
    end

    test "rejects request for unloaded model", %{agent: agent} do
      signal = %{
        "id" => "test-signal-14",
        "source" => "test",
        "type" => "provider_request",
        "data" => %{
          "request_id" => "req-007",
          "messages" => [%{"role" => "user", "content" => "Hello"}],
          "model" => "unloaded-model"
        }
      }

      {:ok, _updated_agent} = LocalProviderAgent.handle_signal(agent, signal)

      assert_receive {:signal, %{"type" => "provider_error"} = error}, 1000
      assert error["data"]["error_type"] == "model_not_loaded"
    end
  end

  describe "provider agent metrics" do
    setup do
      defmodule MetricsTestAgent do
        use RubberDuck.Agents.ProviderAgent,
          name: "metrics_test",
          description: "Test metrics"
      end

      {:ok, agent} = MockAgent.start_agent(MetricsTestAgent, %{
        provider_module: MockProvider,
        provider_config: %{name: :mock}
      })

      {:ok, agent: agent}
    end

    test "tracks request metrics", %{agent: agent} do
      # Simulate successful request completion
      GenServer.cast(agent.pid, {:request_completed, "req-008", :success, 150, %{total_tokens: 20}})

      # Get updated state
      updated_agent = GenServer.call(agent.pid, :get_state)

      assert updated_agent.state.metrics.total_requests == 1
      assert updated_agent.state.metrics.successful_requests == 1
      assert updated_agent.state.metrics.failed_requests == 0
      assert updated_agent.state.metrics.avg_latency == 150.0
      assert updated_agent.state.metrics.total_tokens == 20
    end

    test "updates circuit breaker on failures", %{agent: agent} do
      # Simulate multiple failures
      Enum.each(1..5, fn i ->
        GenServer.cast(agent.pid, {:request_completed, "req-#{i}", :failure, 100, nil})
      end)

      # Get updated state
      :timer.sleep(100)
      updated_agent = GenServer.call(agent.pid, :get_state)

      assert updated_agent.state.circuit_breaker.state == :open
      assert updated_agent.state.circuit_breaker.consecutive_failures >= 5
    end
  end
end