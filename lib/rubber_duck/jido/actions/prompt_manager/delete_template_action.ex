defmodule RubberDuck.Jido.Actions.PromptManager.DeleteTemplateAction do
  @moduledoc """
  Action for deleting a prompt template.
  
  This action removes a template from the agent's state, cleans up related
  cache and analytics data, and emits appropriate signals.
  """
  
  use Jido.Action,
    name: "delete_template",
    description: "Deletes a prompt template and cleans up related data",
    schema: [
      id: [type: :string, required: true, description: "Template ID to delete"]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(%{id: template_id}, context) do
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
        {_deleted_template, agent_without_template} = pop_in(agent.state.templates[template_id])
        
        # Clean up related data
        cleaned_agent = agent_without_template
        |> invalidate_template_cache(template_id)
        |> cleanup_template_analytics(template_id)
        
        signal_data = %{
          template_id: template_id,
          name: template.name,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "prompt.template.deleted", data: signal_data},
          %{agent: cleaned_agent}
        ) do
          {:ok, _result, %{agent: final_agent}} ->
            Logger.info("Deleted template: #{template.name} (#{template_id})")
            {:ok, %{deleted_template: template}, %{agent: final_agent}}
          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
    end
  end

  # Private helper functions

  defp invalidate_template_cache(agent, template_id) do
    cache = agent.state.cache
    |> Enum.reject(fn {_key, entry} ->
      case entry.data do
        %{"template_id" => ^template_id} -> true
        _ -> false
      end
    end)
    |> Map.new()
    
    put_in(agent.state.cache, cache)
  end

  defp cleanup_template_analytics(agent, template_id) do
    {_analytics, updated_agent} = pop_in(agent.state.analytics[template_id])
    updated_agent
  end
end