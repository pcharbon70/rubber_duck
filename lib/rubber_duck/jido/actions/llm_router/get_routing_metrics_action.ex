defmodule RubberDuck.Jido.Actions.LLMRouter.GetRoutingMetricsAction do
  @moduledoc """
  Action for retrieving current routing metrics from the LLM Router Agent.
  
  This action builds a comprehensive metrics report including provider status,
  performance metrics, load balancing information, and cost tracking.
  """
  
  use Jido.Action,
    name: "get_routing_metrics",
    description: "Retrieves current routing metrics and provider status",
    schema: []

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction

  @impl true
  def run(_params, context) do
    agent = context.agent
    
    # Build comprehensive metrics report
    metrics_report = build_metrics_report(agent)
    
    # Emit metrics signal
    with {:ok, _} <- emit_metrics_signal(agent, metrics_report) do
      {:ok, Map.merge(metrics_report, %{
        "success" => true,
        "timestamp" => DateTime.utc_now()
      }), %{agent: agent}}
    end
  end

  # Private functions

  defp build_metrics_report(agent) do
    %{
      "total_requests" => agent.state.metrics.total_requests,
      "active_requests" => map_size(agent.state.active_requests),
      "providers" => build_provider_metrics(agent),
      "load_balancing_strategy" => Atom.to_string(agent.state.load_balancing.strategy),
      "total_cost" => agent.state.metrics.total_cost,
      "routing_performance" => build_routing_performance_metrics(agent),
      "system_health" => build_system_health_metrics(agent)
    }
  end

  defp build_provider_metrics(agent) do
    Enum.map(agent.state.providers, fn {name, config} ->
      state = agent.state.provider_states[name]
      
      %{
        "name" => Atom.to_string(name),
        "status" => state && Atom.to_string(state.status) || "unknown",
        "models" => config.models,
        "current_load" => state && state.current_load || 0,
        "requests_handled" => agent.state.metrics.requests_by_provider[name] || 0,
        "avg_latency_ms" => agent.state.metrics.avg_latency_by_provider[name] || 0,
        "error_rate" => agent.state.metrics.error_rates[name] || 0.0,
        "consecutive_failures" => state && state.consecutive_failures || 0,
        "last_health_check" => state && format_timestamp(state.last_health_check),
        "priority" => config.priority,
        "timeout" => config.timeout
      }
    end)
  end

  defp build_routing_performance_metrics(agent) do
    total_requests = agent.state.metrics.total_requests
    
    provider_distribution = agent.state.metrics.requests_by_provider
    |> Enum.map(fn {provider, count} ->
      percentage = if total_requests > 0, do: (count / total_requests) * 100, else: 0
      %{
        "provider" => Atom.to_string(provider),
        "requests" => count,
        "percentage" => Float.round(percentage, 2)
      }
    end)
    
    %{
      "provider_distribution" => provider_distribution,
      "average_latencies" => format_latencies(agent.state.metrics.avg_latency_by_provider),
      "error_rates" => format_error_rates(agent.state.metrics.error_rates),
      "model_usage" => format_model_usage(agent.state.metrics.requests_by_model)
    }
  end

  defp build_system_health_metrics(agent) do
    healthy_providers = count_healthy_providers(agent.state.provider_states)
    total_providers = map_size(agent.state.providers)
    
    health_percentage = if total_providers > 0 do
      (healthy_providers / total_providers) * 100
    else
      0
    end
    
    %{
      "healthy_providers" => healthy_providers,
      "total_providers" => total_providers,
      "health_percentage" => Float.round(health_percentage, 2),
      "circuit_breakers_active" => count_active_circuit_breakers(agent.state.circuit_breakers),
      "rate_limiters_active" => count_active_rate_limiters(agent.state.rate_limiters)
    }
  end

  defp emit_metrics_signal(agent, metrics_report) do
    signal_params = %{
      signal_type: "llm.provider.metrics",
      data: Map.merge(metrics_report, %{
        timestamp: DateTime.utc_now()
      })
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  # Helper functions

  defp format_timestamp(nil), do: nil
  defp format_timestamp(monotonic_time) do
    # Convert monotonic time to approximate DateTime
    # This is a simplified conversion - in production you might want more precise tracking
    now = DateTime.utc_now()
    current_monotonic = System.monotonic_time(:millisecond)
    diff_ms = current_monotonic - monotonic_time
    DateTime.add(now, -diff_ms, :millisecond) |> DateTime.to_iso8601()
  end

  defp format_latencies(latencies) do
    latencies
    |> Enum.map(fn {provider, latency} ->
      %{
        "provider" => Atom.to_string(provider),
        "avg_latency_ms" => Float.round(latency, 2)
      }
    end)
  end

  defp format_error_rates(error_rates) do
    error_rates
    |> Enum.map(fn {provider, rate} ->
      %{
        "provider" => Atom.to_string(provider),
        "error_rate" => Float.round(rate * 100, 2)  # Convert to percentage
      }
    end)
  end

  defp format_model_usage(model_usage) do
    model_usage
    |> Enum.map(fn {model, count} ->
      %{
        "model" => model,
        "requests" => count
      }
    end)
  end

  defp count_healthy_providers(provider_states) do
    provider_states
    |> Enum.count(fn {_name, state} -> state.status == :healthy end)
  end

  defp count_active_circuit_breakers(circuit_breakers) do
    circuit_breakers
    |> Enum.count(fn {_name, breaker} -> Map.get(breaker, :state) == :open end)
  end

  defp count_active_rate_limiters(rate_limiters) do
    rate_limiters
    |> Enum.count(fn {_name, limiter} -> Map.get(limiter, :active, false) end)
  end
end