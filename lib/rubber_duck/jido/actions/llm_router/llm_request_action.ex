defmodule RubberDuck.Jido.Actions.LLMRouter.LLMRequestAction do
  @moduledoc """
  Action for handling LLM completion requests in the LLM Router Agent.
  
  This action processes LLM requests, selects the optimal provider based on
  requirements and routing strategy, tracks active requests, and processes
  them asynchronously with proper error handling and metrics.
  """
  
  use Jido.Action,
    name: "llm_request",
    description: "Routes and processes LLM completion requests with provider selection",
    schema: [
      messages: [type: {:list, :map}, required: true],
      request_id: [type: :string, required: true],
      min_context_length: [type: :integer, default: 4096],
      max_tokens: [type: :integer, default: 1000],
      required_capabilities: [type: {:list, :atom}, default: []],
      max_latency_ms: [type: :integer, default: 30_000],
      max_cost: [type: :float, default: nil],
      temperature: [type: :float, default: 0.7],
      user_id: [type: :string, default: nil],
      preferences: [type: :map, default: %{}]
    ]

  alias RubberDuck.LLM.ServiceV2
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Extract requirements from parameters
    requirements = %{
      min_context_length: params.min_context_length,
      max_response_tokens: params.max_tokens,
      required_capabilities: params.required_capabilities,
      latency_requirement: params.max_latency_ms,
      cost_limit: params.max_cost
    }
    
    # Select provider based on requirements and current state
    case select_provider(agent, requirements, params.preferences) do
      {:ok, provider, model} ->
        with {:ok, updated_agent} <- track_request(agent, params.request_id, provider, model),
             {:ok, _} <- emit_routing_decision(updated_agent, params.request_id, provider, model) do
          
          # Process request asynchronously
          Task.start(fn ->
            process_llm_request_async(
              updated_agent.id, 
              params.request_id, 
              provider, 
              model, 
              params.messages,
              build_llm_opts(params)
            )
          end)
          
          {:ok, %{
            "routed" => true,
            "provider" => Atom.to_string(provider),
            "model" => model,
            "strategy" => Atom.to_string(agent.state.load_balancing.strategy)
          }, %{agent: updated_agent}}
        end
      
      {:error, reason} ->
        # No available provider - emit error signal
        with {:ok, _} <- emit_error_signal(agent, params.request_id, "No available provider: #{reason}") do
          {:ok, %{
            "routed" => false,
            "error" => "No available provider: #{reason}"
          }, %{agent: agent}}
        end
    end
  end

  # Private functions

  defp select_provider(agent, requirements, _preferences) do
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
    
    # Update last provider index
    state_updates = %{
      load_balancing: Map.put(agent.state.load_balancing, :last_provider_index, next_index)
    }
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: _updated_agent}} ->
        {:ok, provider, hd(models)}
      {:error, reason} ->
        {:error, "Failed to update state: #{inspect(reason)}"}
    end
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

  defp select_cost_optimized(_agent, available_providers, _requirements) do
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
    
    state_updates = %{
      active_requests: Map.put(agent.state.active_requests, request_id, request_info),
      provider_states: update_in(agent.state.provider_states, [provider, :current_load], fn load ->
        (load || 0) + 1
      end)
    }
    
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end

  defp emit_routing_decision(agent, request_id, provider, model) do
    signal_params = %{
      signal_type: "llm.routing.decision",
      data: %{
        request_id: request_id,
        provider: Atom.to_string(provider),
        model: model,
        strategy: agent.state.load_balancing.strategy,
        reason: "Selected based on #{agent.state.load_balancing.strategy} strategy",
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp emit_error_signal(agent, request_id, error_message) do
    signal_params = %{
      signal_type: "llm.response.error",
      data: %{
        request_id: request_id,
        error: error_message,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp build_llm_opts(params) do
    [
      messages: params.messages,
      temperature: params.temperature,
      max_tokens: params.max_tokens,
      user_id: params.user_id
    ]
  end

  defp process_llm_request_async(agent_id, request_id, provider, model, messages, opts) do
    start_time = System.monotonic_time(:millisecond)
    
    # Build complete LLM options
    llm_opts = [
      provider: provider,
      model: model
    ] ++ opts ++ [messages: messages]
    
    # Make the actual LLM request
    result = ServiceV2.completion(llm_opts)
    
    end_time = System.monotonic_time(:millisecond)
    latency = end_time - start_time
    
    # Handle result
    case result do
      {:ok, response} ->
        # Emit successful response
        signal = Jido.Signal.new!(%{
          type: "llm.response.success",
          source: "agent:#{agent_id}",
          data: %{
            request_id: request_id,
            response: response,
            provider: Atom.to_string(provider),
            model: model,
            latency_ms: latency,
            timestamp: DateTime.utc_now()
          }
        })
        
        # Use registry or direct call to emit signal
        emit_signal(agent_id, signal)
        
        # Update metrics
        send_metric_update(agent_id, request_id, provider, model, :success, latency)
      
      {:error, error} ->
        # Try failover or emit error
        handle_request_failure(agent_id, request_id, provider, model, error)
    end
  end

  defp handle_request_failure(agent_id, request_id, failed_provider, _model, error) do
    # Send failure metric
    send_metric_update(agent_id, request_id, failed_provider, nil, :failure, 0)
    
    # Emit error response
    signal = Jido.Signal.new!(%{
      type: "llm.response.error",
      source: "agent:#{agent_id}",
      data: %{
        request_id: request_id,
        error: "Provider #{failed_provider} failed: #{inspect(error)}",
        provider: Atom.to_string(failed_provider),
        timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent_id, signal)
  end

  defp send_metric_update(agent_id, request_id, provider, model, status, latency) do
    # Send internal signal to update metrics
    GenServer.cast(agent_id, {:update_metrics, request_id, provider, model, status, latency})
  end

  defp emit_signal(agent_id, signal) do
    # Use the signal registry or direct GenServer call
    try do
      GenServer.cast(agent_id, {:emit_signal, signal})
    rescue
      _ ->
        Logger.error("Failed to emit signal to agent #{agent_id}")
    end
  end
end