defmodule RubberDuck.Jido.Actions.PromptManager.GetTemplateAction do
  @moduledoc """
  Action for retrieving a specific prompt template by ID.
  
  This action finds a template by ID and emits appropriate signals with
  the template data and statistics or a not found signal.
  """
  
  use Jido.Action,
    name: "get_template",
    description: "Retrieves a prompt template by ID",
    schema: [
      id: [type: :string, required: true, description: "Template ID to retrieve"]
    ]

  alias RubberDuck.Agents.Prompt.Template
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction

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
        signal_data = %{
          template: template,
          stats: Template.get_stats(template),
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "prompt.template.response", data: signal_data},
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