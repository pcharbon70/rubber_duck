defmodule RubberDuck.Jido.Actions.PromptManager.OptimizeTemplateAction do
  @moduledoc """
  Action for generating optimization recommendations for a template.
  
  This action analyzes a template and provides optimization suggestions
  based on content length, variable usage, and other factors.
  """
  
  use Jido.Action,
    name: "optimize_template",
    description: "Generates optimization recommendations for a template",
    schema: [
      template_id: [type: :string, required: true, description: "Template ID to optimize"]
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
        suggestions = generate_optimization_suggestions(template, agent)
        
        signal_data = %{
          template_id: template_id,
          suggestions: suggestions,
          confidence_score: calculate_confidence_score(suggestions, template),
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "prompt.optimization.suggestions", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:ok, signal_data, %{agent: updated_agent}}
          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
    end
  end

  # Private helper functions

  defp generate_optimization_suggestions(template, _agent) do
    suggestions = []
    
    # Check for long content
    suggestions = if String.length(template.content) > 1000 do
      [%{
        type: "content_length",
        message: "Template content is quite long. Consider breaking it into smaller, more focused templates.",
        priority: "medium"
      } | suggestions]
    else
      suggestions
    end
    
    # Check for unused variables
    content_vars = Template.extract_variables(template.content)
    defined_vars = Enum.map(template.variables, & &1.name)
    unused_vars = defined_vars -- content_vars
    
    suggestions = if length(unused_vars) > 0 do
      [%{
        type: "unused_variables",
        message: "Variables defined but not used: #{Enum.join(unused_vars, ", ")}",
        priority: "low"
      } | suggestions]
    else
      suggestions
    end
    
    # Check for missing descriptions
    suggestions = if template.description == "" do
      [%{
        type: "missing_description",
        message: "Template lacks a description. Add one to improve discoverability.",
        priority: "low"
      } | suggestions]
    else
      suggestions
    end
    
    suggestions
  end

  defp calculate_confidence_score(suggestions, _template) do
    # Simple confidence calculation based on suggestion count and types
    base_score = 0.8
    penalty_per_suggestion = 0.1
    
    max(0.1, base_score - (length(suggestions) * penalty_per_suggestion))
  end
end