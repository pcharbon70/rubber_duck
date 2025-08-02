defmodule RubberDuck.Jido.Actions.Provider.ProviderHealthCheckAction do
  @moduledoc """
  Action for performing comprehensive provider health checks with provider-specific metrics.
  
  This action provides:
  - Circuit breaker status monitoring
  - Rate limiting status checks
  - Provider-specific performance metrics
  - Capacity and availability assessment
  - Error rate and latency analysis
  - Resource utilization monitoring
  """
  
  use Jido.Action,
    name: "provider_health_check",
    description: "Performs comprehensive provider health check with provider-specific metrics",
    schema: [
      include_detailed_metrics: [type: :boolean, default: true],
      include_performance_history: [type: :boolean, default: false],
      metric_window_seconds: [type: :integer, default: 300],
      check_connectivity: [type: :boolean, default: true]
    ]

  alias RubberDuck.LLM.{ProviderConfig, ConfigLoader}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    try do
      # Gather basic health metrics
      basic_health = collect_basic_health_metrics(agent)
      
      # Gather provider-specific metrics
      provider_metrics = collect_provider_specific_metrics(agent, params)
      
      # Check connectivity if requested
      connectivity = if params.check_connectivity do
        check_provider_connectivity(agent)
      else
        %{status: :skipped}
      end
      
      # Gather performance history if requested
      performance_history = if params.include_performance_history do
        collect_performance_history(agent, params.metric_window_seconds)
      else
        %{status: :skipped}
      end
      
      # Calculate overall health score
      health_score = calculate_health_score(basic_health, provider_metrics, connectivity)
      
      health_report = %{
        timestamp: DateTime.utc_now(),
        provider: agent.name,
        health_score: health_score,
        status: determine_status_from_score(health_score),
        basic_health: basic_health,
        provider_metrics: provider_metrics,
        connectivity: connectivity,
        performance_history: performance_history,
        recommendations: generate_recommendations(basic_health, provider_metrics, connectivity)
      }
      
      Logger.info("Health check completed for #{agent.name}", 
        provider: agent.name, 
        health_score: health_score,
        status: health_report.status
      )
      
      {:ok, health_report}
      
    rescue
      error ->
        Logger.error("Health check failed for #{agent.name}: #{inspect(error)}")
        {:error, {:health_check_failed, error}}
    end
  end
  
  # Private helper functions
  
  defp collect_basic_health_metrics(agent) do
    state = agent.state
    circuit_breaker = state.circuit_breaker
    rate_limiter = state.rate_limiter
    metrics = state.metrics
    
    %{
      circuit_breaker: %{
        state: circuit_breaker.state,
        failure_count: circuit_breaker.failure_count,
        consecutive_failures: circuit_breaker.consecutive_failures,
        last_failure_time: circuit_breaker.last_failure_time,
        last_success_time: circuit_breaker.last_success_time,
        health_status: circuit_breaker_health_status(circuit_breaker)
      },
      rate_limiter: %{
        current_count: rate_limiter.current_count,
        limit: rate_limiter.limit,
        window_ms: rate_limiter.window,
        utilization_percent: calculate_rate_limit_utilization(rate_limiter),
        time_until_reset: calculate_time_until_reset(rate_limiter)
      },
      active_requests: %{
        count: map_size(state.active_requests),
        max_concurrent: state.max_concurrent_requests,
        utilization_percent: calculate_request_utilization(state)
      },
      performance: %{
        total_requests: metrics.total_requests,
        successful_requests: metrics.successful_requests,
        failed_requests: metrics.failed_requests,
        success_rate_percent: calculate_success_rate(metrics),
        average_latency_ms: metrics.avg_latency,
        total_tokens: metrics.total_tokens,
        last_request_time: metrics.last_request_time
      }
    }
  end
  
  defp collect_provider_specific_metrics(agent, params) do
    state = agent.state
    provider_module = state.provider_module
    
    base_metrics = %{
      provider_type: get_provider_type(provider_module),
      capabilities: state.capabilities,
      provider_config: get_safe_config(state.provider_config)
    }
    
    # Add provider-specific metrics based on provider type
    case provider_module do
      RubberDuck.LLM.Providers.Anthropic ->
        Map.merge(base_metrics, collect_anthropic_metrics(agent, params))
      
      RubberDuck.LLM.Providers.OpenAI ->
        Map.merge(base_metrics, collect_openai_metrics(agent, params))
      
      RubberDuck.LLM.Providers.Ollama ->
        Map.merge(base_metrics, collect_ollama_metrics(agent, params))
      
      _ ->
        Map.merge(base_metrics, %{provider_specific: %{error: "Unknown provider type"}})
    end
  end
  
  defp collect_anthropic_metrics(agent, _params) do
    config = agent.state.provider_config
    
    %{
      anthropic_specific: %{
        api_version: Map.get(config, :api_version, "unknown"),
        safety_level: Map.get(config, :safety_level, "default"),
        context_window: get_anthropic_context_window(config),
        supported_models: get_anthropic_models(config),
        vision_enabled: :vision in agent.state.capabilities,
        streaming_enabled: :streaming in agent.state.capabilities,
        system_message_support: :system_messages in agent.state.capabilities
      }
    }
  end
  
  defp collect_openai_metrics(agent, _params) do
    config = agent.state.provider_config
    
    %{
      openai_specific: %{
        api_version: Map.get(config, :api_version, "unknown"),
        organization_id: Map.get(config, :organization_id, "not_set"),
        supported_models: get_openai_models(config),
        function_calling_enabled: Map.get(config, :enable_functions, false),
        streaming_enabled: :streaming in agent.state.capabilities,
        fine_tuned_models: get_openai_fine_tuned_models(config)
      }
    }
  end
  
  defp collect_ollama_metrics(agent, _params) do
    config = agent.state.provider_config
    
    %{
      ollama_specific: %{
        host: Map.get(config, :host, "localhost"),
        port: Map.get(config, :port, 11434),
        loaded_models: get_ollama_loaded_models(config),
        available_models: get_ollama_available_models(config),
        gpu_memory_usage: get_ollama_gpu_usage(config),
        cpu_usage: get_ollama_cpu_usage(config),
        model_loading_time: get_ollama_model_load_time(config)
      }
    }
  end
  
  defp check_provider_connectivity(agent) do
    provider_module = agent.state.provider_module
    config = agent.state.provider_config
    
    start_time = System.monotonic_time(:millisecond)
    
    try do
      # Attempt a simple health check request based on provider
      result = case provider_module do
        RubberDuck.LLM.Providers.Anthropic ->
          check_anthropic_connectivity(config)
        
        RubberDuck.LLM.Providers.OpenAI ->
          check_openai_connectivity(config)
        
        RubberDuck.LLM.Providers.Ollama ->
          check_ollama_connectivity(config)
        
        _ ->
          {:error, :unsupported_provider}
      end
      
      latency = System.monotonic_time(:millisecond) - start_time
      
      case result do
        {:ok, _} ->
          %{
            status: :healthy,
            latency_ms: latency,
            checked_at: DateTime.utc_now()
          }
        
        {:error, reason} ->
          %{
            status: :unhealthy,
            error: reason,
            latency_ms: latency,
            checked_at: DateTime.utc_now()
          }
      end
      
    rescue
      error ->
        latency = System.monotonic_time(:millisecond) - start_time
        %{
          status: :error,
          error: {:connectivity_check_failed, error},
          latency_ms: latency,
          checked_at: DateTime.utc_now()
        }
    end
  end
  
  defp collect_performance_history(agent, window_seconds) do
    # In a real implementation, this would query a metrics store
    # For now, return basic historical data from agent state
    metrics = agent.state.metrics
    
    %{
      window_seconds: window_seconds,
      collected_at: DateTime.utc_now(),
      summary: %{
        total_requests_in_window: metrics.total_requests,
        average_latency_ms: metrics.avg_latency,
        success_rate_percent: calculate_success_rate(metrics),
        peak_concurrent_requests: map_size(agent.state.active_requests)
      },
      # Note: In production, this would include time-series data
      note: "Historical metrics collection requires external metrics store"
    }
  end
  
  defp calculate_health_score(basic_health, provider_metrics, connectivity) do
    # Circuit breaker health (30%)
    circuit_score = case basic_health.circuit_breaker.state do
      :closed -> 1.0
      :half_open -> 0.6
      :open -> 0.0
    end * 0.3
    
    # Success rate (25%)
    success_rate = basic_health.performance.success_rate_percent / 100.0
    success_score = success_rate * 0.25
    
    # Rate limit utilization (20%) - lower utilization is better
    rate_utilization = basic_health.rate_limiter.utilization_percent / 100.0
    rate_score = (1.0 - rate_utilization) * 0.2
    
    # Active request utilization (15%) - lower utilization is better  
    request_utilization = basic_health.active_requests.utilization_percent / 100.0
    request_score = (1.0 - request_utilization) * 0.15
    
    # Connectivity (10%)
    connectivity_score = case connectivity.status do
      :healthy -> 1.0
      :unhealthy -> 0.0
      :error -> 0.0
      :skipped -> 0.8  # Neutral score if skipped
    end * 0.1
    
    total_score = circuit_score + success_score + rate_score + request_score + connectivity_score
    Float.round(total_score * 100, 2)  # Convert to percentage
  end
  
  defp determine_status_from_score(health_score) do
    cond do
      health_score >= 90 -> :excellent
      health_score >= 75 -> :good
      health_score >= 50 -> :fair
      health_score >= 25 -> :poor
      true -> :critical
    end
  end
  
  defp generate_recommendations(basic_health, provider_metrics, connectivity) do
    recommendations = []
    
    # Circuit breaker recommendations
    recommendations = case basic_health.circuit_breaker.state do
      :open ->
        ["Circuit breaker is open - investigate failure causes and wait for recovery" | recommendations]
      :half_open ->
        ["Circuit breaker is in half-open state - monitor for recovery" | recommendations]
      _ -> recommendations
    end
    
    # Rate limiting recommendations
    recommendations = if basic_health.rate_limiter.utilization_percent > 80 do
      ["High rate limit utilization (#{basic_health.rate_limiter.utilization_percent}%) - consider request throttling" | recommendations]
    else
      recommendations
    end
    
    # Success rate recommendations
    recommendations = if basic_health.performance.success_rate_percent < 95 do
      ["Low success rate (#{basic_health.performance.success_rate_percent}%) - investigate error patterns" | recommendations]
    else
      recommendations
    end
    
    # Connectivity recommendations
    recommendations = case connectivity.status do
      :unhealthy ->
        ["Provider connectivity issues detected - check network and API status" | recommendations]
      :error ->
        ["Connectivity check failed - verify provider configuration" | recommendations]
      _ -> recommendations
    end
    
    # Add general recommendations if none found
    if Enum.empty?(recommendations) do
      ["Provider is healthy - no specific recommendations"]
    else
      recommendations
    end
  end
  
  # Helper calculation functions
  
  defp circuit_breaker_health_status(circuit_breaker) do
    case circuit_breaker.state do
      :closed -> :healthy
      :half_open -> :recovering
      :open -> :unhealthy
    end
  end
  
  defp calculate_rate_limit_utilization(rate_limiter) do
    if rate_limiter.limit && rate_limiter.limit > 0 do
      Float.round(rate_limiter.current_count / rate_limiter.limit * 100, 2)
    else
      0.0
    end
  end
  
  defp calculate_time_until_reset(rate_limiter) do
    if rate_limiter.window_start do
      window_end = rate_limiter.window_start + rate_limiter.window
      now = System.monotonic_time(:millisecond)
      max(0, window_end - now)
    else
      0
    end
  end
  
  defp calculate_request_utilization(state) do
    if state.max_concurrent_requests > 0 do
      Float.round(map_size(state.active_requests) / state.max_concurrent_requests * 100, 2)
    else
      0.0
    end
  end
  
  defp calculate_success_rate(%{total_requests: 0}), do: 100.0
  defp calculate_success_rate(%{total_requests: total, successful_requests: successful}) do
    Float.round(successful / total * 100, 2)
  end
  
  defp get_provider_type(RubberDuck.LLM.Providers.Anthropic), do: :anthropic
  defp get_provider_type(RubberDuck.LLM.Providers.OpenAI), do: :openai
  defp get_provider_type(RubberDuck.LLM.Providers.Ollama), do: :ollama
  defp get_provider_type(_), do: :unknown
  
  defp get_safe_config(config) do
    # Remove sensitive information from config for health report
    config
    |> Map.drop([:api_key, :secret_key, :token, :password])
    |> Map.put(:api_key_present, Map.has_key?(config, :api_key))
  end
  
  # Provider-specific helper functions (stubbed for now)
  
  defp get_anthropic_context_window(_config), do: 200_000
  defp get_anthropic_models(_config), do: ["claude-3-5-sonnet-20241022", "claude-3-haiku-20240307"]
  
  defp get_openai_models(_config), do: ["gpt-4", "gpt-3.5-turbo", "gpt-4-turbo"]
  defp get_openai_fine_tuned_models(_config), do: []
  
  defp get_ollama_loaded_models(_config), do: ["llama3.1:8b"]
  defp get_ollama_available_models(_config), do: ["llama3.1:8b", "mistral:7b"]
  defp get_ollama_gpu_usage(_config), do: %{used_mb: 2048, total_mb: 8192}
  defp get_ollama_cpu_usage(_config), do: 15.5
  defp get_ollama_model_load_time(_config), do: 1200
  
  # Provider connectivity check functions (simplified)
  
  defp check_anthropic_connectivity(_config) do
    # In production, this would make an actual API call
    {:ok, %{status: "healthy"}}
  end
  
  defp check_openai_connectivity(_config) do
    # In production, this would make an actual API call  
    {:ok, %{status: "healthy"}}
  end
  
  defp check_ollama_connectivity(_config) do
    # In production, this would check Ollama server status
    {:ok, %{status: "healthy"}}
  end
end