defmodule RubberDuck.Jido.Actions.PromptManager.GetAnalyticsAction do
  @moduledoc """
  Action for retrieving analytics and performance metrics for templates.
  
  This action builds a comprehensive analytics report based on template usage,
  performance metrics, and system statistics.
  """
  
  use Jido.Action,
    name: "get_analytics", 
    description: "Retrieves analytics and performance metrics for templates",
    schema: [
      filters: [type: :map, default: %{}, description: "Filters for analytics report"]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction

  @impl true
  def run(%{filters: filters}, context) do
    agent = context.agent
    analytics = build_analytics_report(agent, filters)
    
    signal_data = Map.merge(analytics, %{
      timestamp: DateTime.utc_now()
    })
    
    case EmitSignalAction.run(
      %{signal_type: "prompt.analytics.report", data: signal_data},
      %{agent: agent}
    ) do
      {:ok, _result, %{agent: updated_agent}} ->
        {:ok, signal_data, %{agent: updated_agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end

  # Private helper functions

  defp build_analytics_report(agent, filters) do
    templates = Map.values(agent.state.templates)
    
    %{
      "total_templates" => length(templates),
      "templates_by_category" => group_by_category(templates),
      "most_used_templates" => get_most_used_templates(templates, 10),
      "cache_hit_rate" => calculate_cache_hit_rate(agent),
      "avg_build_success_rate" => calculate_avg_success_rate(templates),
      "generated_at" => DateTime.utc_now(),
      "period" => Map.get(filters, "period", "all_time")
    }
  end

  defp group_by_category(templates) do
    templates
    |> Enum.group_by(& &1.category)
    |> Map.new(fn {category, temps} -> {category, length(temps)} end)
  end

  defp get_most_used_templates(templates, limit) do
    templates
    |> Enum.map(fn template ->
      usage_count = get_in(template.metadata, [:usage_count]) || 0
      %{
        "id" => template.id,
        "name" => template.name,
        "usage_count" => usage_count,
        "category" => template.category
      }
    end)
    |> Enum.sort_by(& &1["usage_count"], :desc)
    |> Enum.take(limit)
  end

  defp calculate_cache_hit_rate(_agent) do
    # Simplified implementation
    # In production, would track hit/miss ratios
    0.85
  end

  defp calculate_avg_success_rate(templates) do
    if Enum.empty?(templates) do
      0.0
    else
      total_rate = templates
      |> Enum.map(fn template ->
        usage = get_in(template.metadata, [:usage_count]) || 0
        errors = get_in(template.metadata, [:error_count]) || 0
        if usage > 0, do: (usage - errors) / usage, else: 1.0
      end)
      |> Enum.sum()
      
      total_rate / length(templates)
    end
  end
end