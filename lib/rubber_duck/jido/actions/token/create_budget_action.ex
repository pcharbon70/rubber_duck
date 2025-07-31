defmodule RubberDuck.Jido.Actions.Token.CreateBudgetAction do
  @moduledoc """
  Action for creating new token usage budgets.
  
  This action creates and validates new budget configurations for
  controlling token usage costs. It handles:
  
  - Budget validation and creation
  - State updates to store the new budget
  - Signal emission for budget creation events
  """
  
  use Jido.Action,
    name: "create_budget",
    description: "Creates a new token usage budget",
    schema: [
      name: [type: :string, required: true],
      type: [type: :string, required: true, values: ["global", "user", "project", "team"]],
      entity_id: [type: :string, required: true],
      period: [type: :string, required: true, values: ["daily", "weekly", "monthly", "yearly"]],
      limit: [type: {:or, [:string, :integer, :float]}, required: true],
      currency: [type: :string, default: "USD"],
      alert_thresholds: [type: {:list, :integer}, default: [50, 80, 90]],
      override_policy: [type: :map, default: %{}],
      active: [type: :boolean, default: true]
    ]

  alias RubberDuck.Agents.TokenManager.Budget
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, budget_attrs} <- build_budget_attributes(params),
         {:ok, budget} <- create_budget(budget_attrs),
         {:ok, updated_agent} <- store_budget(agent, budget),
         {:ok, _} <- emit_creation_signal(updated_agent, budget) do
      {:ok, %{"budget_id" => budget.id, "budget" => budget}, %{agent: updated_agent}}
    end
  end

  # Private functions

  defp build_budget_attributes(params) do
    budget_attrs = %{
      name: params.name,
      type: String.to_atom(params.type),
      entity_id: params.entity_id,
      period: String.to_atom(params.period),
      limit: parse_limit(params.limit),
      currency: params.currency,
      alert_thresholds: params.alert_thresholds,
      override_policy: params.override_policy,
      active: params.active
    }
    
    {:ok, budget_attrs}
  end

  defp parse_limit(limit) when is_binary(limit) do
    case Decimal.parse(limit) do
      {decimal, ""} -> decimal
      _ -> Decimal.new(limit)
    end
  end
  defp parse_limit(limit) when is_number(limit), do: Decimal.new(limit)
  defp parse_limit(limit), do: limit

  defp create_budget(budget_attrs) do
    budget = Budget.new(budget_attrs)
    {:ok, budget}
  rescue
    error ->
      Logger.error("Failed to create budget: #{inspect(error)}")
      {:error, {:budget_creation_failed, error}}
  end

  defp store_budget(agent, budget) do
    state_updates = %{
      budgets: Map.put(agent.state.budgets, budget.id, budget)
    }
    
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end

  defp emit_creation_signal(agent, budget) do
    signal_params = %{
      signal_type: "token.budget.created",
      data: %{
        budget_id: budget.id,
        name: budget.name,
        budget_type: budget.type,
        limit: budget.limit,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end