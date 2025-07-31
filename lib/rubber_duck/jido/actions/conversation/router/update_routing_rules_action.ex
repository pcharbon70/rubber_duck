defmodule RubberDuck.Jido.Actions.Conversation.Router.UpdateRoutingRulesAction do
  @moduledoc """
  Action for updating routing rules dynamically.
  
  This action allows dynamic updates to routing rules by:
  - Validating new routing rules format
  - Updating agent state with new rules
  - Logging rule changes for audit
  """
  
  use Jido.Action,
    name: "update_routing_rules", 
    description: "Updates routing rules with validation",
    schema: [
      rules: [type: {:list, :map}, required: true, doc: "New routing rules to apply"]
    ]

  require Logger
  
  alias RubberDuck.Jido.Actions.Base.UpdateStateAction

  @impl true
  def run(params, context) do
    agent = context.agent
    
    case validate_routing_rules(params.rules) do
      {:ok, validated_rules} ->
        state_updates = %{routing_rules: validated_rules}
        
        case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
          {:ok, _, %{agent: updated_agent}} ->
            Logger.info("Updated routing rules for agent #{agent.id}")
            {:ok, %{
              rules_updated: true,
              rule_count: length(validated_rules)
            }, %{agent: updated_agent}}
            
          {:error, reason} ->
            {:error, {:state_update_failed, reason}}
        end
        
      {:error, reason} ->
        Logger.error("Invalid routing rules: #{inspect(reason)}")
        {:error, {:validation_failed, reason}}
    end
  end

  # Private functions

  defp validate_routing_rules(rules) when is_list(rules) do
    if Enum.all?(rules, &valid_rule?/1) do
      {:ok, rules}
    else
      {:error, :invalid_rule_format}
    end
  end

  defp validate_routing_rules(_), do: {:error, :rules_must_be_list}

  defp valid_rule?(rule) when is_map(rule) do
    Map.has_key?(rule, :route) and
    Map.has_key?(rule, :priority) and
    (Map.has_key?(rule, :keywords) or Map.has_key?(rule, :patterns))
  end

  defp valid_rule?(_), do: false
end