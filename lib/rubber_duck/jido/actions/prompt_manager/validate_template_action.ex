defmodule RubberDuck.Jido.Actions.PromptManager.ValidateTemplateAction do
  @moduledoc """
  Action for validating a prompt template structure and variables.
  
  This action validates template data without storing it, useful for
  checking template validity before creation or during testing.
  """
  
  use Jido.Action,
    name: "validate_template",
    description: "Validates prompt template structure and variables",
    schema: [
      template: [type: :map, required: true, description: "Template data to validate"]
    ]

  alias RubberDuck.Agents.Prompt.Template
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction

  @impl true
  def run(%{template: template_data}, context) do
    agent = context.agent
    
    case Template.new(template_data) do
      {:ok, template} ->
        case Template.validate(template) do
          {:ok, _validated_template} ->
            signal_data = %{
              valid: true,
              template_id: template.id,
              variables_count: length(template.variables),
              timestamp: DateTime.utc_now()
            }
            
            case EmitSignalAction.run(
              %{signal_type: "prompt.template.valid", data: signal_data},
              %{agent: agent}
            ) do
              {:ok, _result, %{agent: updated_agent}} ->
                {:ok, signal_data, %{agent: updated_agent}}
              {:error, reason} ->
                {:error, {:signal_emission_failed, reason}}
            end
            
          {:error, reason} ->
            signal_data = %{
              valid: false,
              error: reason,
              template_data: template_data,
              timestamp: DateTime.utc_now()
            }
            
            case EmitSignalAction.run(
              %{signal_type: "prompt.template.invalid", data: signal_data},
              %{agent: agent}
            ) do
              {:ok, _result, %{agent: updated_agent}} ->
                {:error, reason, %{agent: updated_agent}}
              {:error, emit_reason} ->
                {:error, {:signal_emission_failed, emit_reason}}
            end
        end
        
      {:error, reason} ->
        signal_data = %{
          valid: false,
          error: reason,
          template_data: template_data,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "prompt.template.invalid", data: signal_data},
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