defmodule RubberDuck.Agents.LLMRouterAgentTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Agents.LLMRouterAgent

  setup do
    # Create a test agent with initial state
    initial_state = %{
      providers: %{},
      provider_states: %{},
      model_capabilities: %{},
      routing_rules: [],
      active_requests: %{},
      metrics: %{
        total_requests: 0,
        requests_by_provider: %{},
        avg_latency_by_provider: %{},
        error_rates: %{},
        total_cost: 0.0,
        requests_by_model: %{}
      },
      load_balancing: %{
        strategy: :round_robin,
        weights: %{},
        last_provider_index: 0
      },
      circuit_breakers: %{},
      rate_limiters: %{}
    }
    
    agent = %{
      id: "test-agent-#{:rand.uniform(1000)}",
      state: initial_state
    }
    
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

      # Mock emit_signal to capture signals
      test_pid = self()
      agent_with_emit = Map.put(agent, :emit_signal, fn type, data ->
        send(test_pid, {:signal, %{"type" => type, "data" => data}})
      end)

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent_with_emit, signal)

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
      # Clear message queue
      receive do
        _ -> :ok
      after
        0 -> :ok
      end
      
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
      # Clear message queue
      receive do
        _ -> :ok
      after
        0 -> :ok
      end
      
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

      # Clear message queue
      receive do
        _ -> :ok
      after
        0 -> :ok
      end
      
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
      
      # Clear message queue
      receive do
        _ -> :ok
      after
        0 -> :ok
      end
      
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

      # Clear message queue
      receive do
        _ -> :ok
      after
        0 -> :ok
      end
      
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

    test "tracks active requests correctly", %{agent: agent} do
      signal = %{
        "id" => "test-signal-14",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-129",
          "messages" => [%{"role" => "user", "content" => "Hello"}]
        }
      }

      {:ok, updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      # Check active request is tracked
      assert updated_agent.state.active_requests["req-129"]
      assert updated_agent.state.active_requests["req-129"].status == :active
      assert updated_agent.state.active_requests["req-129"].provider in [:openai, :anthropic, :local]
    end

    test "handles requests with cost limits", %{agent: agent} do
      signal = %{
        "id" => "test-signal-15",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-130",
          "messages" => [%{"role" => "user", "content" => "Hello"}],
          "max_cost" => 0.002  # Very low cost limit
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      # Should route to local provider (cheapest)
      assert_receive {:signal, %{"type" => "routing_decision"} = decision}, 1000
      assert decision["data"]["provider"] == "local"
    end

    test "handles requests with latency requirements", %{agent: agent} do
      # Set up latency metrics
      agent_with_latency = agent
      |> put_in([:state, :metrics, :avg_latency_by_provider, :openai], 50)
      |> put_in([:state, :metrics, :avg_latency_by_provider, :anthropic], 100)
      |> put_in([:state, :metrics, :avg_latency_by_provider, :local], 20)

      signal = %{
        "id" => "test-signal-16",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-131",
          "messages" => [%{"role" => "user", "content" => "Hello"}],
          "max_latency_ms" => 30
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent_with_latency, signal)

      # Should route to local provider (fastest)
      assert_receive {:signal, %{"type" => "routing_decision"} = decision}, 1000
      assert decision["data"]["provider"] == "local"
    end
  end

  describe "failover and circuit breaker" do
    setup %{agent: agent} do
      # Register providers
      providers = [{"primary", ["model-a"]}, {"secondary", ["model-b"]}]
      
      agent_with_providers = Enum.reduce(providers, agent, fn {name, models}, acc ->
        signal = %{
          "id" => "setup-#{name}",
          "source" => "test",
          "type" => "provider_register",
          "data" => %{
            "name" => name,
            "config" => %{
              "api_key" => "test-key-#{name}",
              "models" => models
            }
          }
        }
        
        {:ok, updated} = LLMRouterAgent.handle_signal(acc, signal)
        updated
      end)

      # Clear message queue
      receive do
        _ -> :ok
      after
        0 -> :ok
      end
      {:ok, agent: agent_with_providers}
    end

    test "handles circuit breaker activation", %{agent: agent} do
      # Simulate multiple failures for primary provider
      agent_with_failures = agent
      |> put_in([:state, :provider_states, :primary, :consecutive_failures], 5)
      |> put_in([:state, :circuit_breakers, :primary], %{
        state: :open,
        opened_at: System.monotonic_time(:millisecond),
        failure_count: 5,
        half_open_at: System.monotonic_time(:millisecond) + 60_000
      })

      signal = %{
        "id" => "test-cb-1",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-cb-1",
          "messages" => [%{"role" => "user", "content" => "Hello"}]
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent_with_failures, signal)

      # Should route to secondary provider
      assert_receive {:signal, %{"type" => "routing_decision"} = decision}, 1000
      assert decision["data"]["provider"] == "secondary"
    end

    test "resets circuit breaker after cool-down", %{agent: agent} do
      # Set circuit breaker in half-open state
      agent_half_open = agent
      |> put_in([:state, :circuit_breakers, :primary], %{
        state: :half_open,
        opened_at: System.monotonic_time(:millisecond) - 65_000,
        failure_count: 0,
        half_open_at: System.monotonic_time(:millisecond) - 5_000
      })

      # Send successful health check
      health_signal = %{
        "id" => "test-cb-2",
        "source" => "test",
        "type" => "provider_health",
        "data" => %{
          "provider" => "primary",
          "status" => "healthy",
          "latency_ms" => 100
        }
      }

      {:ok, updated_agent} = LLMRouterAgent.handle_signal(agent_half_open, health_signal)

      # Check provider is healthy again
      assert updated_agent.state.provider_states[:primary].status == :healthy
      assert updated_agent.state.provider_states[:primary].consecutive_failures == 0
    end
  end

  describe "rate limiting" do
    setup %{agent: agent} do
      # Register provider with rate limit
      signal = %{
        "id" => "setup-rl",
        "source" => "test",
        "type" => "provider_register",
        "data" => %{
          "name" => "limited_provider",
          "config" => %{
            "api_key" => "test-key",
            "models" => ["model-rl"],
            "rate_limit" => %{"limit" => 10, "unit" => "minute"}
          }
        }
      }

      {:ok, agent_with_provider} = LLMRouterAgent.handle_signal(agent, signal)
      # Clear message queue
      receive do
        _ -> :ok
      after
        0 -> :ok
      end
      
      {:ok, agent: agent_with_provider}
    end

    test "tracks rate limit usage", %{agent: agent} do
      # Initialize rate limiter state
      agent_with_rl = put_in(agent.state.rate_limiters[:limited_provider], %{
        requests: [],
        limit: {10, :minute}
      })

      # Make multiple requests
      requests = for i <- 1..3 do
        signal = %{
          "id" => "test-rl-#{i}",
          "source" => "test",
          "type" => "llm_request",
          "data" => %{
            "request_id" => "req-rl-#{i}",
            "messages" => [%{"role" => "user", "content" => "Request #{i}"}]
          }
        }
        
        {:ok, _} = LLMRouterAgent.handle_signal(agent_with_rl, signal)
        signal
      end

      assert length(requests) == 3
      
      # Verify routing decisions were made
      assert_receive {:signal, %{"type" => "routing_decision"}}, 1000
      assert_receive {:signal, %{"type" => "routing_decision"}}, 1000
      assert_receive {:signal, %{"type" => "routing_decision"}}, 1000
    end
  end

  describe "provider capability matching" do
    setup %{agent: agent} do
      # Register providers with different capabilities
      providers = [
        {"vision_provider", ["vision-model"], ["vision", "chat"]},
        {"code_provider", ["code-model"], ["code", "chat", "analysis"]},
        {"basic_provider", ["basic-model"], ["chat"]}
      ]

      agent_with_providers = Enum.reduce(providers, agent, fn {name, models, capabilities}, acc ->
        signal = %{
          "id" => "setup-#{name}",
          "source" => "test",
          "type" => "provider_register",
          "data" => %{
            "name" => name,
            "config" => %{
              "api_key" => "test-key-#{name}",
              "models" => models
            }
          }
        }
        
        {:ok, updated} = LLMRouterAgent.handle_signal(acc, signal)
        
        # Manually set model capabilities for testing
        model = hd(models)
        updated
        |> put_in([:state, :model_capabilities, model], %{
          max_context: 8192,
          capabilities: capabilities,
          cost_per_1k_tokens: 0.01
        })
      end)

      # Clear message queue
      receive do
        _ -> :ok
      after
        0 -> :ok
      end
      {:ok, agent: agent_with_providers}
    end

    test "routes to provider with required capabilities", %{agent: agent} do
      # Request requiring code capability
      signal = %{
        "id" => "test-cap-1",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-cap-1",
          "messages" => [%{"role" => "user", "content" => "Write a function"}],
          "required_capabilities" => ["code"]
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      assert_receive {:signal, %{"type" => "routing_decision"} = decision}, 1000
      assert decision["data"]["provider"] == "code_provider"
      assert decision["data"]["model"] == "code-model"
    end

    test "routes to any provider when no specific capabilities required", %{agent: agent} do
      signal = %{
        "id" => "test-cap-2",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-cap-2",
          "messages" => [%{"role" => "user", "content" => "Hello"}],
          "required_capabilities" => []
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      assert_receive {:signal, %{"type" => "routing_decision"} = decision}, 1000
      assert decision["data"]["provider"] in ["vision_provider", "code_provider", "basic_provider"]
    end

    test "returns error when no provider has required capabilities", %{agent: agent} do
      signal = %{
        "id" => "test-cap-3",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-cap-3",
          "messages" => [%{"role" => "user", "content" => "Translate audio"}],
          "required_capabilities" => ["audio", "translation"]
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent, signal)

      assert_receive {:signal, %{"type" => "llm_response"} = response}, 1000
      assert response["data"]["error"] =~ "No available provider"
    end
  end

  describe "cost tracking and optimization" do
    setup %{agent: agent} do
      # Register providers with cost data
      providers = [
        {"expensive", ["gpt-4"], 0.03},
        {"moderate", ["claude-3"], 0.01},
        {"cheap", ["llama-2"], 0.001}
      ]

      agent_with_providers = Enum.reduce(providers, agent, fn {name, models, cost}, acc ->
        signal = %{
          "id" => "setup-#{name}",
          "source" => "test",
          "type" => "provider_register",
          "data" => %{
            "name" => name,
            "config" => %{
              "api_key" => "test-key-#{name}",
              "models" => models
            }
          }
        }
        
        {:ok, updated} = LLMRouterAgent.handle_signal(acc, signal)
        
        # Set cost per token
        model = hd(models)
        updated
        |> put_in([:state, :model_capabilities, model], %{
          max_context: 8192,
          capabilities: [:chat],
          cost_per_1k_tokens: cost
        })
      end)

      # Clear message queue
      receive do
        _ -> :ok
      after
        0 -> :ok
      end
      {:ok, agent: agent_with_providers}
    end

    test "tracks cumulative cost", %{agent: agent} do
      # Simulate completed request with token usage
      request_id = "req-cost-1"
      provider = :expensive
      model = "gpt-4"
      
      # Track request
      agent_tracking = track_request(agent, request_id, provider, model)
      
      # Simulate metric update with token count
      {:noreply, agent_with_cost} = LLMRouterAgent.handle_cast(
        {:update_metrics, request_id, provider, model, :success, 150},
        agent_tracking
      )

      # Verify metrics were updated
      assert agent_with_cost.state.metrics.total_requests == 1
      assert agent_with_cost.state.metrics.requests_by_provider[provider] == 1
    end

    test "selects provider based on cost optimization", %{agent: agent} do
      agent_cost_opt = put_in(agent.state.load_balancing.strategy, :cost_optimized)

      signal = %{
        "id" => "test-cost-2",
        "source" => "test",
        "type" => "llm_request",
        "data" => %{
          "request_id" => "req-cost-2",
          "messages" => [%{"role" => "user", "content" => "Hello"}]
        }
      }

      {:ok, _updated_agent} = LLMRouterAgent.handle_signal(agent_cost_opt, signal)

      assert_receive {:signal, %{"type" => "routing_decision"} = decision}, 1000
      assert decision["data"]["provider"] == "cheap"
      assert decision["data"]["model"] == "llama-2"
    end
  end

  # Helper function
  defp track_request(agent, request_id, provider, model) do
    request_info = %{
      provider: provider,
      model: model,
      started_at: System.monotonic_time(:millisecond),
      status: :active
    }
    
    agent
    |> put_in([:state, :active_requests, request_id], request_info)
    |> update_in([:state, :provider_states, provider, :current_load], &((&1 || 0) + 1))
  end
end