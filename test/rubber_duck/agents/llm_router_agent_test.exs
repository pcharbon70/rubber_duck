defmodule RubberDuck.Agents.LLMRouterAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.LLMRouterAgent
  alias RubberDuck.TestSupport.{MockAgent, SignalCapture}

  setup do
    # Start a test agent instance
    {:ok, agent} = MockAgent.start_agent(LLMRouterAgent, %{
      providers: %{},
      provider_states: %{},
      load_balancing: %{
        strategy: :round_robin,
        weights: %{},
        last_provider_index: 0
      }
    })

    # Start signal capture
    SignalCapture.start_link()
    
    {:ok, agent: agent}
  end

  describe "provider registration" do
    test "registers a new provider successfully", %{agent: agent} do
      # Send provider registration signal
      signal = %{
        "id" => "test-signal-1",
        "source" => "test",
        "type" => "provider_register",
        "data" => %{
          "name" => "openai",
          "config" => %{
            "api_key" => "test-key",
            "base_url" => "https://api.openai.com",
            "models" => ["gpt-4", "gpt-3.5-turbo"],
            "priority" => 1,
            "rate_limit" => %{"limit" => 100, "unit" => "minute"}
          }
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      # Check for provider registered signal
      assert_receive {:signal, %{"type" => "provider_registered"} = response}, 1000
      assert response["data"]["provider"] == "openai"
      assert response["data"]["status"] == "registered"
      assert response["data"]["models"] == ["gpt-4", "gpt-3.5-turbo"]
    end

    test "handles invalid provider registration", %{agent: agent} do
      # Send invalid provider registration (missing models)
      signal = %{
        "id" => "test-signal-2",
        "source" => "test",
        "type" => "provider_register",
        "data" => %{
          "name" => "invalid",
          "config" => %{
            "api_key" => "test-key"
          }
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      # Check for error response
      assert_receive {:signal, %{"type" => "provider_registered"} = response}, 1000
      assert response["data"]["provider"] == "invalid"
      assert response["data"]["error"] =~ "Registration failed"
    end
  end

  describe "provider updates" do
    setup %{agent: agent} do
      # Register a provider first
      signal = %{
        "id" => "setup-signal",
        "source" => "test",
        "type" => "provider_register",
        "data" => %{
          "name" => "openai",
          "config" => %{
            "api_key" => "test-key",
            "models" => ["gpt-4"],
            "priority" => 1
          }
        }
      }

      {:ok, agent_with_provider} = LLMRouterAgent.handle_signal(agent, signal)
      
      # Clear signals from setup
      SignalCapture.clear()
      
      {:ok, agent: agent_with_provider}
    end

    test "updates provider configuration", %{agent: agent} do
      # Send provider update signal
      signal = %{
        "id" => "test-signal-3",
        "source" => "test",
        "type" => "provider_update",
        "data" => %{
          "name" => "openai",
          "updates" => %{
            "models" => ["gpt-4", "gpt-4-turbo"],
            "priority" => 2
          }
        }
      }

      {:ok, updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      # Check for update confirmation
      assert_receive {:signal, %{"type" => "provider_updated"} = response}, 1000
      assert response["data"]["provider"] == "openai"
      assert response["data"]["status"] == "updated"
      
      # Verify provider was updated
      assert :openai in Map.keys(updated_agent.state.providers)
      assert updated_agent.state.providers[:openai].models == ["gpt-4", "gpt-4-turbo"]
    end

    test "handles update for non-existent provider", %{agent: agent} do
      signal = %{
        "id" => "test-signal-4",
        "source" => "test",
        "type" => "provider_update",
        "data" => %{
          "name" => "nonexistent",
          "updates" => %{"priority" => 5}
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      # Check for error response
      assert_receive {:signal, %{"type" => "provider_updated"} = response}, 1000
      assert response["data"]["error"] == "Provider not found"
    end
  end

  describe "health monitoring" do
    setup %{agent: agent} do
      # Register a provider
      signal = %{
        "id" => "setup-signal",
        "source" => "test",
        "type" => "provider_register",
        "data" => %{
          "name" => "openai",
          "config" => %{
            "api_key" => "test-key",
            "models" => ["gpt-4"]
          }
        }
      }

      {:ok, agent_with_provider} = LLMRouterAgent.handle_signal(agent, signal)
      SignalCapture.clear()
      
      {:ok, agent: agent_with_provider}
    end

    test "updates provider health status", %{agent: agent} do
      # Send health update
      signal = %{
        "id" => "test-signal-5",
        "source" => "test",
        "type" => "provider_health",
        "data" => %{
          "provider" => "openai",
          "status" => "healthy",
          "latency_ms" => 250
        }
      }

      {:ok, updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      # Verify health was updated
      provider_state = updated_agent.state.provider_states[:openai]
      assert provider_state.status == :healthy
      assert updated_agent.state.metrics.avg_latency_by_provider[:openai] == 250
    end

    test "tracks consecutive failures", %{agent: agent} do
      # Send unhealthy status
      signal = %{
        "id" => "test-signal-6",
        "source" => "test",
        "type" => "provider_health",
        "data" => %{
          "provider" => "openai",
          "status" => "unhealthy",
          "latency_ms" => nil
        }
      }

      {:ok, updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      provider_state = updated_agent.state.provider_states[:openai]
      assert provider_state.status == :unhealthy
      assert provider_state.consecutive_failures == 1
    end
  end

  describe "LLM request routing" do
    setup %{agent: agent} do
      # Register multiple providers
      providers = [
        {"openai", ["gpt-4", "gpt-3.5-turbo"], 1},
        {"anthropic", ["claude-3-sonnet"], 2},
        {"local", ["llama-2"], 3}
      ]

      agent_with_providers = Enum.reduce(providers, agent, fn {name, models, priority}, acc ->
        signal = %{
          "id" => "setup-#{name}",
          "source" => "test",
          "type" => "provider_register",
          "data" => %{
            "name" => name,
            "config" => %{
              "api_key" => "test-key-#{name}",
              "models" => models,
              "priority" => priority
            }
          }
        }
        
        {:ok, updated} = LLMRouterAgent.handle_signal(acc, signal)
        updated
      end)

      SignalCapture.clear()
      
      {:ok, agent: agent_with_providers}
    end

    test "routes request with round-robin strategy", %{agent: agent} do
      # Send LLM request
      signal = %{
        "id" => "test-signal-7",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-123",
          "messages" => [%{"role" => "user", "content" => "Hello"}],
          "max_tokens" => 100
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      # Check for routing decision
      assert_receive {:signal, %{"type" => "routing_decision"} = decision}, 1000
      assert decision["data"]["request_id"] == "req-123"
      assert decision["data"]["provider"] in ["openai", "anthropic", "local"]
      assert decision["data"]["strategy"] == "round_robin"
    end

    test "handles no available providers", %{agent: agent} do
      # Mark all providers as unhealthy
      agent_unhealthy = agent
      |> put_in([:state, :provider_states, :openai, :status], :unhealthy)
      |> put_in([:state, :provider_states, :anthropic, :status], :unhealthy)
      |> put_in([:state, :provider_states, :local, :status], :unhealthy)

      signal = %{
        "id" => "test-signal-8",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-124",
          "messages" => [%{"role" => "user", "content" => "Hello"}]
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent_unhealthy, signal)

      # Check for error response
      assert_receive {:signal, %{"type" => "llm_response"} = response}, 1000
      assert response["data"]["request_id"] == "req-124"
      assert response["data"]["error"] =~ "No available provider"
    end

    test "respects model requirements", %{agent: agent} do
      # Request requiring specific capabilities
      signal = %{
        "id" => "test-signal-9",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-125",
          "messages" => [%{"role" => "user", "content" => "Analyze this image"}],
          "required_capabilities" => ["vision"],
          "min_context_length" => 100_000
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      # Should route to claude-3-sonnet which has vision capability
      assert_receive {:signal, %{"type" => "routing_decision"} = decision}, 1000
      assert decision["data"]["model"] == "claude-3-sonnet"
    end
  end

  describe "metrics reporting" do
    setup %{agent: agent} do
      # Register a provider and simulate some requests
      signal = %{
        "id" => "setup-signal",
        "source" => "test",
        "type" => "provider_register",
        "data" => %{
          "name" => "openai",
          "config" => %{
            "api_key" => "test-key",
            "models" => ["gpt-4"]
          }
        }
      }

      {:ok, agent_with_provider} = LLMRouterAgent.handle_signal(agent, signal)
      
      # Update some metrics manually for testing
      agent_with_metrics = agent_with_provider
      |> put_in([:state, :metrics, :total_requests], 10)
      |> put_in([:state, :metrics, :requests_by_provider, :openai], 10)
      |> put_in([:state, :metrics, :avg_latency_by_provider, :openai], 150.5)
      |> put_in([:state, :metrics, :error_rates, :openai], 0.05)
      
      SignalCapture.clear()
      
      {:ok, agent: agent_with_metrics}
    end

    test "returns comprehensive metrics", %{agent: agent} do
      signal = %{
        "id" => "test-signal-10",
        "source" => "test",
        "type" => "get_routing_metrics"
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      assert_receive {:signal, %{"type" => "provider_metrics"} = metrics}, 1000
      
      data = metrics["data"]
      assert data["total_requests"] == 10
      assert data["load_balancing_strategy"] == "round_robin"
      
      # Find OpenAI provider in the list
      openai_metrics = Enum.find(data["providers"], fn p -> p["name"] == "openai" end)
      assert openai_metrics["requests_handled"] == 10
      assert openai_metrics["avg_latency_ms"] == 150.5
      assert openai_metrics["error_rate"] == 0.05
    end
  end

  describe "load balancing strategies" do
    setup %{agent: agent} do
      # Register providers with different characteristics
      providers = [
        {"fast_provider", ["model-a"], 1, 100},  # Fast latency
        {"slow_provider", ["model-b"], 1, 500},  # Slow latency
        {"cheap_provider", ["model-c"], 1, 200}  # Medium latency
      ]

      agent_with_providers = Enum.reduce(providers, agent, fn {name, models, priority, latency}, acc ->
        # Register provider
        signal = %{
          "id" => "setup-#{name}",
          "source" => "test",
          "type" => "provider_register",
          "data" => %{
            "name" => name,
            "config" => %{
              "api_key" => "test-key-#{name}",
              "models" => models,
              "priority" => priority
            }
          }
        }
        
        {:ok, updated} = LLMRouterAgent.handle_signal(acc, signal)
        
        # Set initial latency
        updated
        |> put_in([:state, :metrics, :avg_latency_by_provider, String.to_atom(name)], latency)
      end)

      SignalCapture.clear()
      
      {:ok, agent: agent_with_providers}
    end

    test "performance_first strategy selects fastest provider", %{agent: agent} do
      # Change to performance_first strategy
      agent_perf = put_in(agent.state.load_balancing.strategy, :performance_first)

      signal = %{
        "id" => "test-signal-11",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-126",
          "messages" => [%{"role" => "user", "content" => "Hello"}]
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent_perf, signal)

      assert_receive {:signal, %{"type" => "routing_decision"} = decision}, 1000
      assert decision["data"]["provider"] == "fast_provider"
      assert decision["data"]["strategy"] == "performance_first"
    end

    test "cost_optimized strategy selects cheapest provider", %{agent: agent} do
      # Change to cost_optimized strategy
      agent_cost = put_in(agent.state.load_balancing.strategy, :cost_optimized)

      signal = %{
        "id" => "test-signal-12",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-127",
          "messages" => [%{"role" => "user", "content" => "Hello"}]
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent_cost, signal)

      assert_receive {:signal, %{"type" => "routing_decision"} = decision}, 1000
      # In our mock, local provider would be cheapest
      assert decision["data"]["strategy"] == "cost_optimized"
    end

    test "least_loaded strategy distributes based on load", %{agent: agent} do
      # Set different loads for providers
      agent_with_load = agent
      |> put_in([:state, :load_balancing, :strategy], :least_loaded)
      |> put_in([:state, :provider_states, :fast_provider, :current_load], 5)
      |> put_in([:state, :provider_states, :slow_provider, :current_load], 1)
      |> put_in([:state, :provider_states, :cheap_provider, :current_load], 3)

      signal = %{
        "id" => "test-signal-13",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-128",
          "messages" => [%{"role" => "user", "content" => "Hello"}]
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent_with_load, signal)

      assert_receive {:signal, %{"type" => "routing_decision"} = decision}, 1000
      assert decision["data"]["provider"] == "slow_provider"  # Lowest load
      assert decision["data"]["strategy"] == "least_loaded"
    end
  end
end