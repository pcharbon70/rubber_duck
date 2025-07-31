defmodule RubberDuck.Jido.Actions.ShortTermMemory.GetAnalyticsAction do
  use Jido.Action,
    name: "get_analytics",
    description: "Get memory analytics and metrics",
    schema: []
  
  @impl true
  def run(_params, context) do
    agent = context.agent
    
    analytics = %{
      total_items: agent.state.metrics.total_items,
      memory_usage_bytes: agent.state.metrics.memory_usage_bytes,
      avg_item_size: agent.state.metrics.avg_item_size,
      cache_hit_ratio: calculate_cache_hit_ratio(agent.state.metrics),
      last_cleanup: agent.state.metrics.last_cleanup,
      access_patterns: agent.state.access_patterns
    }
    
    {:ok, analytics, %{agent: agent}}
  end
  
  defp calculate_cache_hit_ratio(metrics) do
    total_requests = metrics.cache_hits + metrics.cache_misses
    if total_requests > 0 do
      metrics.cache_hits / total_requests
    else
      0.0
    end
  end
end