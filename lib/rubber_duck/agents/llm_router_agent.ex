defmodule RubberDuck.Agents.LLMRouterAgent do
  @moduledoc """
  Autonomous agent for intelligent LLM provider routing and load balancing.
  
  This agent manages the selection of LLM providers based on various factors
  including cost, performance, capabilities, and availability. It provides
  failover support, load balancing, and comprehensive metrics tracking.
  
  ## Actions
  
  The agent supports the following actions:
  - `LLMRequestAction`: Handles LLM completion requests with provider selection
  - `ProviderRegisterAction`: Registers new LLM providers with validation
  - `ProviderUpdateAction`: Updates existing provider configurations
  - `ProviderHealthAction`: Updates provider health status and metrics
  - `GetRoutingMetricsAction`: Retrieves current routing metrics
  
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
    ],
    actions: [
      RubberDuck.Jido.Actions.LLMRouter.LLMRequestAction,
      RubberDuck.Jido.Actions.LLMRouter.ProviderRegisterAction,
      RubberDuck.Jido.Actions.LLMRouter.ProviderUpdateAction,
      RubberDuck.Jido.Actions.LLMRouter.ProviderHealthAction,
      RubberDuck.Jido.Actions.LLMRouter.GetRoutingMetricsAction,
      RubberDuck.Jido.Actions.LLMRouter.UpdateMetricsAction
    ]

  require Logger

  alias RubberDuck.Jido.Actions.LLMRouter.{
    LLMRequestAction,
    ProviderRegisterAction,
    ProviderUpdateAction,
    ProviderHealthAction,
    GetRoutingMetricsAction,
    UpdateMetricsAction
  }

  # Signal Handlers (using actions)

  def handle_signal("llm_request", data, agent) do
    params = %{
      messages: data["messages"] || [],
      request_id: data["request_id"] || Ecto.UUID.generate(),
      min_context_length: data["min_context_length"] || 4096,
      max_tokens: data["max_tokens"] || 1000,
      required_capabilities: data["required_capabilities"] || [],
      max_latency_ms: data["max_latency_ms"] || 30_000,
      max_cost: data["max_cost"],
      temperature: data["temperature"] || 0.7,
      user_id: data["user_id"],
      preferences: data["preferences"] || %{}
    }
    
    case execute_action(agent, LLMRequestAction, params) do
      {:ok, result, updated_agent} ->
        {:ok, result, updated_agent}
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  def handle_signal("provider_register", data, agent) do
    params = %{
      name: data["name"] || "",
      config: data["config"] || %{}
    }
    
    case execute_action(agent, ProviderRegisterAction, params) do
      {:ok, result, updated_agent} ->
        {:ok, result, updated_agent}
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  def handle_signal("provider_update", data, agent) do
    params = %{
      name: data["name"] || "",
      updates: data["updates"] || %{}
    }
    
    case execute_action(agent, ProviderUpdateAction, params) do
      {:ok, result, updated_agent} ->
        {:ok, result, updated_agent}
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  def handle_signal("provider_health", data, agent) do
    params = %{
      provider: data["provider"] || "",
      status: data["status"] || "unknown",
      latency_ms: data["latency_ms"]
    }
    
    case execute_action(agent, ProviderHealthAction, params) do
      {:ok, result, updated_agent} ->
        {:ok, result, updated_agent}
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  def handle_signal("get_routing_metrics", _data, agent) do
    case execute_action(agent, GetRoutingMetricsAction, %{}) do
      {:ok, result, updated_agent} ->
        {:ok, result, updated_agent}
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  def handle_signal(signal_type, _data, agent) do
    Logger.warning("LLMRouterAgent received unknown signal: #{inspect(signal_type)}")
    {:ok, %{"handled" => false, "signal" => signal_type}, agent}
  end

  # GenServer callbacks for internal updates (preserved from original)
  
  @impl true
  def handle_cast({:update_metrics, request_id, provider, model, status, latency}, agent) do
    # Remove from active requests
    {request_info, agent} = pop_in(agent.state.active_requests[request_id])
    
    if request_info do
      # Update metrics through action-based approach
      case execute_action(agent, UpdateMetricsAction, %{
        request_id: request_id,
        provider: provider,
        model: model,
        status: status,
        latency: latency
      }) do
        {:ok, _result, updated_agent} ->
          {:noreply, updated_agent}
        {:error, reason} ->
          Logger.error("Failed to update metrics: #{inspect(reason)}")
          {:noreply, agent}
      end
    else
      {:noreply, agent}
    end
  end

  @impl true
  def handle_cast({:emit_signal, signal}, agent) do
    emit_signal(agent, signal)
    {:noreply, agent}
  end

  # Health check implementation
  @impl RubberDuck.Agents.BaseAgent
  def health_check(agent) do
    healthy_providers = count_healthy_providers(agent.state.provider_states)
    total_providers = map_size(agent.state.providers)
    
    health_status = if total_providers > 0 && healthy_providers > 0 do
      :healthy
    else
      :degraded
    end
    
    {health_status, %{
      healthy_providers: healthy_providers,
      total_providers: total_providers,
      active_requests: map_size(agent.state.active_requests),
      total_requests_processed: agent.state.metrics.total_requests
    }}
  end

  # Private helper functions

  defp count_healthy_providers(provider_states) do
    provider_states
    |> Enum.count(fn {_name, state} -> state.status == :healthy end)
  end
end
