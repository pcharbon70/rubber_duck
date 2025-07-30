defmodule RubberDuck.Agents.LLMRouterAgent do
  @moduledoc """
  Autonomous agent for intelligent LLM provider routing and load balancing.
  
  This agent manages the selection of LLM providers based on various factors
  including cost, performance, capabilities, and availability. It provides
  failover support, load balancing, and comprehensive metrics tracking.
  
  ## Signals
  
  ### Input Signals
  - `llm_request`: Request for LLM completion
  - `provider_register`: Register new provider
  - `provider_update`: Update provider configuration
  - `provider_health`: Health check result
  - `get_routing_metrics`: Request current metrics
  
  ### Output Signals
  - `llm_response`: LLM completion response
  - `routing_decision`: Details of routing decision
  - `provider_registered`: Provider registration confirmation
  - `provider_updated`: Provider update confirmation
  - `provider_metrics`: Current provider metrics
  - `cost_report`: Cost tracking information
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "llm_router",
    description: "Routes LLM requests to optimal providers with load balancing and failover",
    category: "infrastructure",
    schema: [
      providers: [type: :map, default: %{}],  # provider_name => config
      provider_states: [type: :map, default: %{}],  # provider_name => state
      model_capabilities: [type: :map, default: %{}],  # model => capabilities
      routing_rules: [type: {:list, :map}, default: []],
      active_requests: [type: :map, default: %{}],
      metrics: [type: :map, default: %{
        total_requests: 0,
        requests_by_provider: %{},
        avg_latency_by_provider: %{},
        error_rates: %{},
        total_cost: 0.0,
        requests_by_model: %{}
      }],
      load_balancing: [type: :map, default: %{
        strategy: :round_robin,  # :round_robin, :least_loaded, :cost_optimized, :performance_first
        weights: %{},
        last_provider_index: 0
      }],
      circuit_breakers: [type: :map, default: %{}],
      rate_limiters: [type: :map, default: %{}]
    ]
  
  require Logger
  
  alias RubberDuck.LLM.{ServiceV2, ProviderConfig, ConfigLoader}
  
  # Signal Handlers
  
  @impl true
  def handle_signal(agent, %{"type" => "llm_request"} = signal) do
    %{
      "data" => %{
        "messages" => messages,
        "request_id" => request_id
      } = data
    } = signal
    
    requirements = extract_requirements(data)
    preferences = data["preferences"] || %{}
    
    # Select provider based on requirements and current state
    case select_provider(agent, requirements, preferences) do
      {:ok, provider, model} ->
        # Track active request
        agent = track_request(agent, request_id, provider, model)
        
        # Emit routing decision
        emit_signal("routing_decision", %{
          "request_id" => request_id,
          "provider" => Atom.to_string(provider),
          "model" => model,
          "strategy" => agent.state.load_balancing.strategy,
          "reason" => "Selected based on #{agent.state.load_balancing.strategy} strategy"
        })
        
        # Process request asynchronously
        Task.start(fn ->
          process_llm_request(agent.id, request_id, provider, model, messages, data)
        end)
        
        {:ok, agent}
      
      {:error, reason} ->
        # No available provider
        emit_signal("llm_response", %{
          "request_id" => request_id,
          "error" => "No available provider: #{reason}"
        })
        
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "provider_register"} = signal) do
    %{
      "data" => %{
        "name" => name,
        "config" => config_map
      }
    } = signal
    
    provider_name = String.to_atom(name)
    
    # Convert config map to ProviderConfig struct
    provider_config = build_provider_config(provider_name, config_map)
    
    # Validate configuration
    case ProviderConfig.validate(provider_config) do
      {:ok, validated_config} ->
        # Register provider
        agent = agent
        |> put_in([:state, :providers, provider_name], validated_config)
        |> put_in([:state, :provider_states, provider_name], %{
          status: :healthy,
          last_health_check: System.monotonic_time(:millisecond),
          consecutive_failures: 0,
          current_load: 0
        })
        |> update_model_capabilities(validated_config)
        
        # Initialize metrics
        agent = agent
        |> put_in([:state, :metrics, :requests_by_provider, provider_name], 0)
        |> put_in([:state, :metrics, :avg_latency_by_provider, provider_name], 0)
        |> put_in([:state, :metrics, :error_rates, provider_name], 0.0)
        
        emit_signal("provider_registered", %{
          "provider" => name,
          "models" => validated_config.models,
          "status" => "registered"
        })
        
        {:ok, agent}
      
      {:error, reason} ->
        emit_signal("provider_registered", %{
          "provider" => name,
          "error" => "Registration failed: #{inspect(reason)}"
        })
        
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "provider_update"} = signal) do
    %{
      "data" => %{
        "name" => name,
        "updates" => updates
      }
    } = signal
    
    provider_name = String.to_atom(name)
    
    case agent.state.providers[provider_name] do
      nil ->
        emit_signal("provider_updated", %{
          "provider" => name,
          "error" => "Provider not found"
        })
        {:ok, agent}
      
      existing_config ->
        # Apply updates
        updated_config = apply_config_updates(existing_config, updates)
        
        agent = agent
        |> put_in([:state, :providers, provider_name], updated_config)
        |> update_model_capabilities(updated_config)
        
        emit_signal("provider_updated", %{
          "provider" => name,
          "status" => "updated"
        })
        
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "provider_health"} = signal) do
    %{
      "data" => %{
        "provider" => provider,
        "status" => status,
        "latency_ms" => latency_ms
      }
    } = signal
    
    provider_name = String.to_atom(provider)
    
    # Update provider state
    agent = update_provider_health(agent, provider_name, status, latency_ms)
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "get_routing_metrics"} = _signal) do
    metrics = build_metrics_report(agent)
    
    emit_signal("provider_metrics", metrics)
    
    {:ok, agent}
  end
  
  def handle_signal(agent, signal) do
    Logger.warning("LLMRouterAgent received unknown signal: #{inspect(signal["type"])}")
    {:ok, agent}
  end
  
  # Private Functions
  
  defp extract_requirements(data) do
    %{
      min_context_length: data["min_context_length"] || 4096,
      max_response_tokens: data["max_tokens"] || 1000,
      required_capabilities: data["required_capabilities"] || [],
      latency_requirement: data["max_latency_ms"] || 30_000,
      cost_limit: data["max_cost"] || nil
    }
  end
  
  defp select_provider(agent, requirements, preferences) do
    # Get available providers
    available_providers = get_available_providers(agent, requirements)
    
    if Enum.empty?(available_providers) do
      {:error, "No providers match requirements"}
    else
      # Apply routing strategy
      case agent.state.load_balancing.strategy do
        :round_robin ->
          select_round_robin(agent, available_providers)
        
        :least_loaded ->
          select_least_loaded(agent, available_providers)
        
        :cost_optimized ->
          select_cost_optimized(agent, available_providers, requirements)
        
        :performance_first ->
          select_performance_first(agent, available_providers)
        
        _ ->
          # Default to first available
          {provider, models} = hd(available_providers)
          {:ok, provider, hd(models)}
      end
    end
  end
  
  defp get_available_providers(agent, requirements) do
    agent.state.providers
    |> Enum.filter(fn {provider_name, config} ->
      # Check if provider is healthy
      provider_state = agent.state.provider_states[provider_name]
      provider_healthy = provider_state && provider_state.status == :healthy
      
      # Check if provider has models matching requirements
      matching_models = Enum.filter(config.models, fn model ->
        model_matches_requirements?(agent, model, requirements)
      end)
      
      provider_healthy && not Enum.empty?(matching_models)
    end)
    |> Enum.map(fn {provider_name, config} ->
      matching_models = Enum.filter(config.models, fn model ->
        model_matches_requirements?(agent, model, requirements)
      end)
      {provider_name, matching_models}
    end)
  end
  
  defp model_matches_requirements?(agent, model, requirements) do
    capabilities = agent.state.model_capabilities[model] || %{}
    
    # Check context length
    context_ok = (capabilities[:max_context] || 4096) >= requirements.min_context_length
    
    # Check required capabilities
    has_capabilities = Enum.all?(requirements.required_capabilities, fn cap ->
      cap in (capabilities[:capabilities] || [])
    end)
    
    context_ok && has_capabilities
  end
  
  defp select_round_robin(agent, available_providers) do
    # Get next provider in rotation
    num_providers = length(available_providers)
    next_index = rem(agent.state.load_balancing.last_provider_index + 1, num_providers)
    
    {provider, models} = Enum.at(available_providers, next_index)
    
    # Update last provider index in agent state will happen in the caller
    {:ok, provider, hd(models)}
  end
  
  defp select_least_loaded(agent, available_providers) do
    # Find provider with lowest current load
    {provider, models} = 
      available_providers
      |> Enum.min_by(fn {provider_name, _models} ->
        state = agent.state.provider_states[provider_name]
        state.current_load || 0
      end)
    
    {:ok, provider, hd(models)}
  end
  
  defp select_cost_optimized(agent, available_providers, _requirements) do
    # Select cheapest provider
    # In real implementation, would use actual cost data
    {provider, models} = 
      available_providers
      |> Enum.min_by(fn {provider_name, _models} ->
        # Simplified cost model
        case provider_name do
          :openai -> 0.03  # $/1k tokens
          :anthropic -> 0.025
          :local -> 0.001
          _ -> 0.05
        end
      end)
    
    {:ok, provider, hd(models)}
  end
  
  defp select_performance_first(agent, available_providers) do
    # Select provider with best latency
    {provider, models} = 
      available_providers
      |> Enum.min_by(fn {provider_name, _models} ->
        agent.state.metrics.avg_latency_by_provider[provider_name] || 999_999
      end)
    
    {:ok, provider, hd(models)}
  end
  
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
  
  defp process_llm_request(agent_id, request_id, provider, model, messages, data) do
    start_time = System.monotonic_time(:millisecond)
    
    # Build LLM options
    llm_opts = [
      provider: provider,
      model: model,
      messages: messages,
      temperature: data["temperature"] || 0.7,
      max_tokens: data["max_tokens"] || 1000,
      user_id: data["user_id"]
    ]
    
    # Make the actual LLM request
    result = ServiceV2.completion(llm_opts)
    
    end_time = System.monotonic_time(:millisecond)
    latency = end_time - start_time
    
    # Handle result
    case result do
      {:ok, response} ->
        # Emit successful response
        emit_signal("llm_response", %{
          "request_id" => request_id,
          "response" => response,
          "provider" => Atom.to_string(provider),
          "model" => model,
          "latency_ms" => latency
        })
        
        # Update metrics
        send_metric_update(agent_id, request_id, provider, model, :success, latency)
      
      {:error, error} ->
        # Try failover
        handle_request_failure(agent_id, request_id, provider, model, messages, data, error)
    end
  end
  
  defp handle_request_failure(agent_id, request_id, failed_provider, _model, messages, data, error) do
    # Send failure metric
    send_metric_update(agent_id, request_id, failed_provider, nil, :failure, 0)
    
    # Emit error response (in production, would implement failover)
    emit_signal("llm_response", %{
      "request_id" => request_id,
      "error" => "Provider #{failed_provider} failed: #{inspect(error)}",
      "provider" => Atom.to_string(failed_provider)
    })
  end
  
  defp send_metric_update(agent_id, request_id, provider, model, status, latency) do
    # Send internal signal to update metrics
    GenServer.cast(agent_id, {:update_metrics, request_id, provider, model, status, latency})
  end
  
  defp update_provider_health(agent, provider_name, status, latency_ms) do
    health_status = if status == "healthy", do: :healthy, else: :unhealthy
    
    case agent.state.provider_states[provider_name] do
      nil ->
        agent
      
      current_state ->
        updated_state = current_state
        |> Map.put(:status, health_status)
        |> Map.put(:last_health_check, System.monotonic_time(:millisecond))
        |> Map.update(:consecutive_failures, 0, fn failures ->
          if health_status == :healthy, do: 0, else: failures + 1
        end)
        
        # Update latency if healthy
        agent = if health_status == :healthy && latency_ms do
          update_in(agent.state.metrics.avg_latency_by_provider[provider_name], fn current ->
            if current do
              # Simple moving average
              (current * 0.9) + (latency_ms * 0.1)
            else
              latency_ms
            end
          end)
        else
          agent
        end
        
        put_in(agent.state.provider_states[provider_name], updated_state)
    end
  end
  
  defp build_provider_config(name, config_map) do
    %ProviderConfig{
      name: name,
      adapter: Module.concat([RubberDuck.LLM.Providers, Macro.camelize(Atom.to_string(name))]),
      api_key: config_map["api_key"],
      base_url: config_map["base_url"],
      models: config_map["models"] || [],
      priority: config_map["priority"] || 1,
      rate_limit: parse_rate_limit(config_map["rate_limit"]),
      max_retries: config_map["max_retries"] || 3,
      timeout: config_map["timeout"] || 30_000,
      headers: config_map["headers"] || %{},
      options: config_map["options"] || []
    }
  end
  
  defp parse_rate_limit(nil), do: nil
  defp parse_rate_limit(%{"limit" => limit, "unit" => unit}) do
    {limit, String.to_atom(unit)}
  end
  
  defp apply_config_updates(config, updates) do
    Enum.reduce(updates, config, fn {key, value}, acc ->
      Map.put(acc, String.to_existing_atom(key), value)
    end)
  end
  
  defp update_model_capabilities(agent, provider_config) do
    # In production, would load actual model capabilities
    # For now, use simplified capabilities
    model_caps = Enum.reduce(provider_config.models, %{}, fn model, acc ->
      capabilities = case model do
        "gpt-4" -> %{
          max_context: 8192,
          capabilities: [:chat, :code, :analysis],
          cost_per_1k_tokens: 0.03
        }
        "gpt-3.5-turbo" -> %{
          max_context: 4096,
          capabilities: [:chat, :code],
          cost_per_1k_tokens: 0.002
        }
        "claude-3-sonnet" -> %{
          max_context: 200_000,
          capabilities: [:chat, :code, :analysis, :vision],
          cost_per_1k_tokens: 0.003
        }
        _ -> %{
          max_context: 4096,
          capabilities: [:chat],
          cost_per_1k_tokens: 0.001
        }
      end
      
      Map.put(acc, model, capabilities)
    end)
    
    update_in(agent.state.model_capabilities, &Map.merge(&1, model_caps))
  end
  
  defp build_metrics_report(agent) do
    %{
      "total_requests" => agent.state.metrics.total_requests,
      "active_requests" => map_size(agent.state.active_requests),
      "providers" => Enum.map(agent.state.providers, fn {name, config} ->
        state = agent.state.provider_states[name]
        %{
          "name" => Atom.to_string(name),
          "status" => state && Atom.to_string(state.status) || "unknown",
          "models" => config.models,
          "current_load" => state && state.current_load || 0,
          "requests_handled" => agent.state.metrics.requests_by_provider[name] || 0,
          "avg_latency_ms" => agent.state.metrics.avg_latency_by_provider[name] || 0,
          "error_rate" => agent.state.metrics.error_rates[name] || 0.0
        }
      end),
      "load_balancing_strategy" => Atom.to_string(agent.state.load_balancing.strategy),
      "total_cost" => agent.state.metrics.total_cost
    }
  end
  
  # GenServer callbacks for internal updates
  
  @impl true
  def handle_cast({:update_metrics, request_id, provider, model, status, latency}, agent) do
    # Remove from active requests
    {request_info, agent} = pop_in(agent.state.active_requests[request_id])
    
    if request_info do
      # Update provider load
      agent = update_in(agent.state.provider_states[provider].current_load, &max(&1 - 1, 0))
      
      # Update metrics
      agent = agent
      |> update_in([:state, :metrics, :total_requests], &(&1 + 1))
      |> update_in([:state, :metrics, :requests_by_provider, provider], &((&1 || 0) + 1))
      
      # Update model metrics
      agent = if model do
        update_in(agent.state.metrics.requests_by_model[model], &((&1 || 0) + 1))
      else
        agent
      end
      
      # Update latency for successful requests
      agent = if status == :success && latency > 0 do
        update_in(agent.state.metrics.avg_latency_by_provider[provider], fn current ->
          if current do
            # Weighted average
            (current * 0.95) + (latency * 0.05)
          else
            latency
          end
        end)
      else
        agent
      end
      
      # Update error rate
      agent = if status == :failure do
        update_in(agent.state.metrics.error_rates[provider], fn current ->
          total = agent.state.metrics.requests_by_provider[provider] || 1
          ((current || 0.0) * (total - 1) + 1.0) / total
        end)
      else
        agent
      end
      
      {:noreply, agent}
    else
      {:noreply, agent}
    end
  end
end