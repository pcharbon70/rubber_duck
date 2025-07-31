defmodule RubberDuck.Jido.Actions.PromptManager.UpdateTemplateAction do
  @moduledoc """
  Action for updating an existing prompt template.
  
  This action updates a template with new data, invalidates related cache entries,
  and emits appropriate signals for success, failure, or not found scenarios.
  """
  
  use Jido.Action,
    name: "update_template",
    description: "Updates an existing prompt template",
    schema: [
      id: [type: :string, required: true, description: "Template ID to update"],
      update_data: [type: :map, required: true, description: "Data to update the template with"]
    ]

  alias RubberDuck.Agents.Prompt.Template
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(%{id: template_id, update_data: update_data}, context) do
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
        case Template.update(template, update_data) do
          {:ok, updated_template} ->
            agent_with_template = put_in(agent.state.templates[template_id], updated_template)
            
            # Invalidate cache entries for this template
            agent_with_cache = invalidate_template_cache(agent_with_template, template_id)
            
            signal_data = %{
              template_id: template_id,
              name: updated_template.name,
              version: updated_template.version,
              timestamp: DateTime.utc_now()
            }
            
            case EmitSignalAction.run(
              %{signal_type: "prompt.template.updated", data: signal_data},
              %{agent: agent_with_cache}
            ) do
              {:ok, _result, %{agent: final_agent}} ->
                Logger.info("Updated template: #{updated_template.name} (#{template_id})")
                {:ok, %{template: updated_template}, %{agent: final_agent}}
              {:error, reason} ->
                {:error, {:signal_emission_failed, reason}}
            end
            
          {:error, reason} ->
            signal_data = %{
              template_id: template_id,
              error: reason,
              timestamp: DateTime.utc_now()
            }
            
            case EmitSignalAction.run(
              %{signal_type: "prompt.template.update_failed", data: signal_data},
              %{agent: agent}
            ) do
              {:ok, _result, %{agent: updated_agent}} ->
                {:error, reason, %{agent: updated_agent}}
              {:error, emit_reason} ->
                {:error, {:signal_emission_failed, emit_reason}}
            end
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
end