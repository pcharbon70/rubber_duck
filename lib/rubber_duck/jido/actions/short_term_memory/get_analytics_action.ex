defmodule RubberDuck.Jido.Actions.ShortTermMemory.GetAnalyticsAction do
  use Jido.Action,
    name: "get_analytics",
    description: "Get memory analytics and metrics",
    schema: []
  
  alias RubberDuck.Agents.{ErrorHandling, ActionErrorPatterns}
  require Logger
  
  @impl true
  def run(_params, context) do
    ErrorHandling.safe_execute(fn ->
      # Validate context
      with :ok <- validate_context(context) do
        agent = context.agent
        
        # Safely build analytics with error handling
        case build_analytics(agent.state) do
          {:ok, analytics} ->
            {:ok, analytics, %{agent: agent}}
          error -> error
        end
      end
    end)
  end
  
  defp validate_context(%{agent: %{state: state}}) when is_map(state), do: :ok
  defp validate_context(_), do: ErrorHandling.validation_error("Invalid context: missing agent state", %{})
  
  defp build_analytics(state) do
    try do
      metrics = Map.get(state, :metrics, %{})
      access_patterns = Map.get(state, :access_patterns, %{})
      
      analytics = %{
        total_items: Map.get(metrics, :total_items, 0),
        memory_usage_bytes: Map.get(metrics, :memory_usage_bytes, 0),
        avg_item_size: Map.get(metrics, :avg_item_size, 0),
        cache_hit_ratio: safe_calculate_cache_hit_ratio(metrics),
        last_cleanup: Map.get(metrics, :last_cleanup),
        access_patterns: access_patterns
      }
      
      {:ok, analytics}
    rescue
      error ->
        ErrorHandling.system_error("Failed to build analytics: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end
  
  defp safe_calculate_cache_hit_ratio(metrics) when is_map(metrics) do
    cache_hits = Map.get(metrics, :cache_hits, 0)
    cache_misses = Map.get(metrics, :cache_misses, 0)
    total_requests = cache_hits + cache_misses
    
    if total_requests > 0 do
      cache_hits / total_requests
    else
      0.0
    end
  end
  defp safe_calculate_cache_hit_ratio(_), do: 0.0
end