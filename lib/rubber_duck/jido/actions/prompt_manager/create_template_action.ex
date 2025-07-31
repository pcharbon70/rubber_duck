defmodule RubberDuck.Jido.Actions.PromptManager.CreateTemplateAction do
  @moduledoc """
  Action for creating a new prompt template.
  
  This action creates a new template with validation, adds it to the agent's
  state, and emits appropriate signals for success or failure.
  """
  
  use Jido.Action,
    name: "create_template",
    description: "Creates a new prompt template with validation",
    schema: [
      template_data: [type: :map, required: true, description: "Template data structure"]
    ]

  alias RubberDuck.Agents.Prompt.Template
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(%{template_data: template_data}, context) do
    agent = context.agent
    
    case Template.new(template_data) do
      {:ok, template} ->
        updated_agent = put_in(agent.state.templates[template.id], template)
        
        signal_data = %{
          template_id: template.id,
          name: template.name,
          category: template.category,
          version: template.version,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "prompt.template.created", data: signal_data},
          %{agent: updated_agent}
        ) do
          {:ok, _result, %{agent: final_agent}} ->
            Logger.info("Created template: #{template.name} (#{template.id})")
            {:ok, %{template: template}, %{agent: final_agent}}
          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
        
      {:error, reason} ->
        signal_data = %{
          error: reason,
          template_data: template_data,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "prompt.template.creation_failed", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            Logger.warning("Failed to create template: #{reason}")
            {:error, reason, %{agent: updated_agent}}
          {:error, emit_reason} ->
            {:error, {:signal_emission_failed, emit_reason}}
        end
    end
  end
end