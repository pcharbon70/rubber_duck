defmodule RubberDuck.Jido.Actions.PromptManager.ListTemplatesAction do
  @moduledoc """
  Action for listing prompt templates with optional filtering.
  
  This action retrieves templates from the agent's state, applies any specified
  filters, and emits a signal with the filtered template list.
  """
  
  use Jido.Action,
    name: "list_templates",
    description: "Lists prompt templates with optional filtering",
    schema: [
      filters: [type: :map, default: %{}, description: "Filters to apply to template list"]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction

  @impl true
  def run(%{filters: filters}, context) do
    agent = context.agent
    
    templates = agent.state.templates
    |> Map.values()
    |> apply_template_filters(filters)
    |> Enum.map(fn template ->
      Map.take(template, [:id, :name, :description, :category, :tags, :version, :created_at, :access_level])
    end)
    
    signal_data = %{
      templates: templates,
      count: length(templates),
      filters_applied: filters,
      timestamp: DateTime.utc_now()
    }
    
    case EmitSignalAction.run(
      %{signal_type: "prompt.templates.list", data: signal_data},
      %{agent: agent}
    ) do
      {:ok, _result, %{agent: updated_agent}} ->
        {:ok, signal_data, %{agent: updated_agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end

  # Private helper functions

  defp apply_template_filters(templates, filters) when is_map(filters) do
    templates
    |> filter_by_category(Map.get(filters, "category"))
    |> filter_by_tags(Map.get(filters, "tags"))
    |> filter_by_access_level(Map.get(filters, "access_level"))
    |> sort_templates(Map.get(filters, "sort_by"))
    |> limit_results(Map.get(filters, "limit"))
  end

  defp apply_template_filters(templates, _), do: templates

  defp filter_by_category(templates, nil), do: templates
  defp filter_by_category(templates, category) do
    Enum.filter(templates, &(&1.category == category))
  end

  defp filter_by_tags(templates, nil), do: templates
  defp filter_by_tags(templates, tags) when is_list(tags) do
    Enum.filter(templates, fn template ->
      Enum.any?(tags, &(&1 in template.tags))
    end)
  end

  defp filter_by_access_level(templates, nil), do: templates
  defp filter_by_access_level(templates, access_level) do
    Enum.filter(templates, &(&1.access_level == String.to_atom(access_level)))
  end

  defp sort_templates(templates, "name"), do: Enum.sort_by(templates, & &1.name)
  defp sort_templates(templates, "created_at"), do: Enum.sort_by(templates, & &1.created_at, DateTime)
  defp sort_templates(templates, "updated_at"), do: Enum.sort_by(templates, & &1.updated_at, DateTime)
  defp sort_templates(templates, _), do: templates

  defp limit_results(templates, nil), do: templates
  defp limit_results(templates, limit) when is_integer(limit) do
    Enum.take(templates, limit)
  end
end