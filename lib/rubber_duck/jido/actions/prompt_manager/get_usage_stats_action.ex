defmodule RubberDuck.Jido.Actions.PromptManager.GetUsageStatsAction do
  @moduledoc """
  Action for retrieving usage statistics for a specific template.
  
  This action retrieves detailed usage statistics and analytics data
  for a specific template by ID.
  """
  
  use Jido.Action,
    name: "get_usage_stats",
    description: "Retrieves usage statistics for a specific template",
    schema: [
      template_id: [type: :string, required: true, description: "Template ID to get stats for"]
    ]

  alias RubberDuck.Agents.Prompt.Template
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction

  @impl true
  def run(%{template_id: template_id}, context) do
    agent = context.agent
    
    case Map.get(agent.state.templates, template_id) do
      nil ->
        signal_data = %{
          template_id: template_id,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "prompt.template.not_found", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:error, :template_not_found, %{agent: updated_agent}}
          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
        
      template ->
        stats = Template.get_stats(template)
        analytics_data = Map.get(agent.state.analytics, template_id, %{})
        
        signal_data = %{
          template_id: template_id,
          stats: stats,
          detailed_analytics: analytics_data,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "prompt.usage.stats", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:ok, signal_data, %{agent: updated_agent}}
          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
    end
  end
end