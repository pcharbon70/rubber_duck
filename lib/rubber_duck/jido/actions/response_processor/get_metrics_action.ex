defmodule RubberDuck.Jido.Actions.ResponseProcessor.GetMetricsAction do
  @moduledoc """
  Action for retrieving processing metrics and performance data.
  
  This action builds and returns a comprehensive metrics report including
  processing statistics, cache performance, and format distributions.
  """
  
  use Jido.Action,
    name: "get_metrics",
    description: "Retrieves comprehensive processing metrics and performance data",
    schema: []

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    metrics = build_metrics_report(agent)
    
    signal_data = Map.merge(metrics, %{
      timestamp: DateTime.utc_now()
    })
    
    case EmitSignalAction.run(
      %{signal_type: "response.metrics", data: signal_data},
      %{agent: agent}
    ) do
      {:ok, _result, %{agent: updated_agent}} ->
        {:ok, signal_data, %{agent: updated_agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end

  # Private functions

  defp build_metrics_report(agent) do
    metrics = agent.state.metrics
    cache_total = metrics.cache_hits + metrics.cache_misses
    cache_hit_rate = if cache_total > 0, do: metrics.cache_hits / cache_total, else: 0.0
    
    %{
      "processing" => %{
        "total_processed" => metrics.total_processed,
        "avg_processing_time_ms" => metrics.avg_processing_time,
        "error_count" => metrics.error_count,
        "error_rate" => if(metrics.total_processed > 0, do: metrics.error_count / metrics.total_processed, else: 0.0)
      },
      "caching" => %{
        "cache_hits" => metrics.cache_hits,
        "cache_misses" => metrics.cache_misses,
        "hit_rate" => cache_hit_rate,
        "cache_size" => map_size(agent.state.cache)
      },
      "distributions" => %{
        "formats" => metrics.format_distribution,
        "quality" => metrics.quality_distribution
      },
      "generated_at" => DateTime.utc_now()
    }
  end
end