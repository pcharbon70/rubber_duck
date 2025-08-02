defmodule RubberDuck.Jido.Actions.Metrics.AggregateMetricsAction do
  @moduledoc """
  Action for aggregating metrics from the current window data.
  
  This action processes the accumulated metrics data, computes statistical
  aggregations, and updates the time-series data for monitoring.
  """
  
  use Jido.Action,
    name: "aggregate_metrics",
    description: "Aggregates current window metrics data into time series",
    schema: []

  alias RubberDuck.Jido.Actions.Base.UpdateStateAction
  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    
    Logger.debug("Aggregating metrics window data")
    
    # Aggregate window data
    with {:ok, aggregated_data} <- aggregate_window_data(agent.state.current_window),
         {:ok, updated_time_series} <- update_time_series(agent.state, aggregated_data),
         {:ok, computed_metrics} <- compute_metrics(updated_time_series),
         {:ok, cleared_window} <- clear_current_window() do
      
      # Update agent state with new data
      state_updates = Map.merge(updated_time_series, %{
        metrics: computed_metrics,
        current_window: cleared_window
      })
      
      case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
        {:ok, _, %{agent: updated_agent}} ->
          {:ok, %{aggregated: true, window_cleared: true}, %{agent: updated_agent}}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Private functions
  
  defp aggregate_window_data(current_window) do
    # Aggregate action data
    action_summaries = current_window.actions
    |> Enum.map(fn {agent_id, actions} ->
      latencies = actions
      |> Enum.filter(fn {_, _, status} -> status == :success end)
      |> Enum.map(fn {_, duration, _} -> duration end)
      
      error_count = Enum.count(actions, fn {_, _, status} -> status == :error end)
      
      {agent_id, %{
        count: length(actions),
        latencies: latencies,
        error_count: error_count
      }}
    end)
    |> Map.new()
    
    # Also aggregate error data
    error_summaries = current_window.errors
    |> Enum.map(fn {agent_id, errors} ->
      {agent_id, length(errors)}
    end)
    |> Map.new()
    
    aggregated = Map.merge(action_summaries, %{errors: error_summaries})
    {:ok, aggregated}
  end
  
  defp update_time_series(current_state, aggregated_data) do
    try do
      # Extract error data
      _error_data = Map.get(aggregated_data, :errors, %{})
      action_data = Map.delete(aggregated_data, :errors)
      
      # Update latency time series
      new_latencies = Enum.reduce(action_data, current_state.action_latencies || %{}, 
        fn {agent_id, summary}, acc ->
          buffer = Map.get(acc, agent_id, create_circular_buffer())
          updated = push_to_buffer(buffer, summary.latencies)
          Map.put(acc, agent_id, updated)
        end)
      
      # Update throughput time series
      new_throughput = Enum.reduce(action_data, current_state.throughput || %{},
        fn {agent_id, summary}, acc ->
          buffer = Map.get(acc, agent_id, create_circular_buffer())
          updated = push_to_buffer(buffer, summary.count)
          Map.put(acc, agent_id, updated)
        end)
      
      # Update error rates time series
      new_error_rates = Enum.reduce(action_data, current_state.error_rates || %{},
        fn {agent_id, summary}, acc ->
          buffer = Map.get(acc, agent_id, create_circular_buffer())
          error_rate = if summary.count > 0, do: summary.error_count / summary.count, else: 0
          updated = push_to_buffer(buffer, error_rate)
          Map.put(acc, agent_id, updated)
        end)
      
      updated_state = %{
        action_latencies: new_latencies,
        throughput: new_throughput,
        error_rates: new_error_rates
      }
      
      {:ok, updated_state}
      
    rescue
      error ->
        Logger.error("Failed to update time series: #{inspect(error)}")
        {:error, "Time series update failed: #{Exception.message(error)}"}
    end
  end
  
  defp compute_metrics(state_data) do
    try do
      # Compute per-agent metrics
      agent_metrics = (state_data.action_latencies || %{})
      |> Enum.map(fn {agent_id, latency_buffer} ->
        all_latencies = buffer_to_list(latency_buffer) |> List.flatten()
        
        metrics = if length(all_latencies) > 0 do
          sorted = Enum.sort(all_latencies)
          %{
            latency_p50: percentile(sorted, 0.5),
            latency_p95: percentile(sorted, 0.95),
            latency_p99: percentile(sorted, 0.99),
            latency_mean: Enum.sum(sorted) / length(sorted),
            throughput: calculate_throughput(Map.get(state_data.throughput || %{}, agent_id)),
            error_rate: calculate_error_rate(Map.get(state_data.error_rates || %{}, agent_id))
          }
        else
          %{
            latency_p50: 0,
            latency_p95: 0,
            latency_p99: 0,
            latency_mean: 0,
            throughput: 0,
            error_rate: 0
          }
        end
        
        {agent_id, metrics}
      end)
      |> Map.new()
      
      # Compute system-wide metrics
      system_metrics = %{
        total_agents: map_size(agent_metrics),
        total_throughput: agent_metrics |> Map.values() |> Enum.map(& &1.throughput) |> Enum.sum(),
        avg_latency: calculate_system_avg_latency(agent_metrics),
        total_errors: calculate_total_errors(state_data.error_rates || %{})
      }
      
      computed = %{agents: agent_metrics, system: system_metrics}
      {:ok, computed}
      
    rescue
      error ->
        Logger.error("Failed to compute metrics: #{inspect(error)}")
        {:error, "Metrics computation failed: #{Exception.message(error)}"}
    end
  end
  
  defp clear_current_window do
    {:ok, %{
      actions: %{},
      errors: %{},
      resources: %{}
    }}
  end
  
  # Helper functions for circular buffer operations (simplified)
  
  defp create_circular_buffer do
    %{data: [], size: 0, max_size: 300}  # 5 minutes of second-resolution data
  end
  
  defp push_to_buffer(buffer, item) do
    new_data = [item | buffer.data] |> Enum.take(buffer.max_size)
    %{buffer | data: new_data, size: length(new_data)}
  end
  
  defp buffer_to_list(buffer) do
    buffer.data
  end
  
  # Statistical calculation helpers
  
  defp percentile(sorted_list, p) do
    k = (length(sorted_list) - 1) * p
    f = :erlang.floor(k)
    c = :erlang.ceil(k)
    
    if f == c do
      Enum.at(sorted_list, trunc(k))
    else
      v0 = Enum.at(sorted_list, trunc(f))
      v1 = Enum.at(sorted_list, trunc(c))
      v0 + (k - f) * (v1 - v0)
    end
  end
  
  defp calculate_throughput(nil), do: 0
  defp calculate_throughput(throughput_buffer) do
    counts = buffer_to_list(throughput_buffer)
    if length(counts) > 0 do
      Enum.sum(counts) / length(counts)
    else
      0
    end
  end
  
  defp calculate_error_rate(nil), do: 0
  defp calculate_error_rate(error_rate_buffer) do
    rates = buffer_to_list(error_rate_buffer)
    if length(rates) > 0 do
      Enum.sum(rates) / length(rates)
    else
      0
    end
  end
  
  defp calculate_system_avg_latency(agent_metrics) do
    latencies = agent_metrics |> Map.values() |> Enum.map(& &1.latency_mean)
    if length(latencies) > 0 do
      Enum.sum(latencies) / length(latencies)
    else
      0
    end
  end
  
  defp calculate_total_errors(error_rates) do
    error_rates
    |> Map.values()
    |> Enum.map(&buffer_to_list/1)
    |> List.flatten()
    |> Enum.sum()
    |> round()
  end
end