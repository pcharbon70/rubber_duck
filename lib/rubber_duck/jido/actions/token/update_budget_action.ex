defmodule RubberDuck.Jido.Actions.Token.UpdateBudgetAction do
  @moduledoc """
  Action for updating existing token usage budgets.
  
  This action handles modifications to existing budget configurations,
  including limit adjustments, status changes, and policy updates.
  """
  
  use Jido.Action,
    name: "update_budget",
    description: "Updates an existing token usage budget",
    schema: [
      budget_id: [type: :string, required: true],
      updates: [type: :map, required: true]
    ]

  alias RubberDuck.Agents.TokenManager.Budget
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, budget} <- find_budget(agent.state.budgets, params.budget_id),
         {:ok, updated_budget} <- apply_budget_updates(budget, params.updates),
         {:ok, updated_agent} <- store_updated_budget(agent, params.budget_id, updated_budget),
         {:ok, _} <- emit_update_signal(updated_agent, params.budget_id, params.updates) do
      {:ok, %{"budget" => updated_budget}, %{agent: updated_agent}}
    end
  end

  # Private functions

  defp find_budget(budgets, budget_id) do
    case Map.get(budgets, budget_id) do
      nil ->
        {:error, "Budget not found"}
      budget ->
        {:ok, budget}
    end
  end

  defp apply_budget_updates(budget, updates) do
    try do
      updated_budget = Budget.update(budget, updates)
      {:ok, updated_budget}
    rescue
      error ->
        Logger.error("Failed to update budget: #{inspect(error)}")
        {:error, {:budget_update_failed, error}}
    end
  end

  defp store_updated_budget(agent, budget_id, updated_budget) do
    state_updates = %{
      budgets: Map.put(agent.state.budgets, budget_id, updated_budget)
    }
    
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end

  defp emit_update_signal(agent, budget_id, updates) do
    signal_params = %{
      signal_type: "token.budget.updated",
      data: %{
        budget_id: budget_id,
        updates: updates,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end