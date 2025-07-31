defmodule RubberDuck.Jido.Actions.Token.CheckBudgetAction do
  @moduledoc """
  Action for checking budget constraints before token usage.
  
  This action evaluates whether a requested token usage would violate
  any applicable budgets for the user/project. It performs:
  
  - Budget discovery based on user_id and project_id
  - Cost estimation for the requested tokens
  - Budget constraint validation
  - Violation tracking and reporting
  - Signal emission for approval/denial events
  """
  
  use Jido.Action,
    name: "check_budget",
    description: "Checks budget constraints for token usage requests",
    schema: [
      user_id: [type: :string, required: true],
      project_id: [type: :string, required: true],
      estimated_tokens: [type: :integer, required: true],
      request_id: [type: :string, required: true]
    ]

  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, applicable_budgets} <- find_applicable_budgets(agent.state.budgets, params),
         {:ok, check_result} <- check_budgets(applicable_budgets, params.estimated_tokens, agent),
         {:ok, updated_agent} <- handle_budget_result(agent, check_result, params),
         {:ok, _} <- emit_budget_signal(updated_agent, check_result, params) do
      
      case check_result do
        {:allowed, _} ->
          {:ok, %{"allowed" => true}, %{agent: updated_agent}}
        {:denied, violations} ->
          {:ok, %{"allowed" => false, "violations" => violations}, %{agent: updated_agent}}
      end
    end
  end

  # Private functions

  defp find_applicable_budgets(budgets, params) do
    applicable = budgets
    |> Map.values()
    |> Enum.filter(fn budget ->
      budget.active and budget_applies?(budget, params.user_id, params.project_id)
    end)
    
    {:ok, applicable}
  end

  defp budget_applies?(budget, user_id, project_id) do
    case budget.type do
      :global -> true
      :user -> budget.entity_id == user_id
      :project -> budget.entity_id == project_id
      _ -> false
    end
  end

  defp check_budgets(budgets, estimated_tokens, agent) do
    violations = Enum.reduce(budgets, [], fn budget, acc ->
      estimated_cost = estimate_cost_for_tokens(estimated_tokens, agent.state.pricing_models)
      
      if RubberDuck.Agents.TokenManager.Budget.would_exceed?(budget, estimated_cost) do
        [{budget.id, budget.name, budget.remaining} | acc]
      else
        acc
      end
    end)
    
    result = if violations == [] do
      {:allowed, budgets}
    else
      {:denied, violations}
    end
    
    {:ok, result}
  end

  defp estimate_cost_for_tokens(tokens, pricing_models) do
    # Use average pricing across models for estimation
    avg_price = calculate_average_price(pricing_models)
    Decimal.mult(Decimal.new(tokens), avg_price)
  end

  defp calculate_average_price(pricing_models) do
    all_prices = for {_provider, models} <- pricing_models,
                    {_model, pricing} <- models do
      Decimal.add(
        Decimal.new(pricing.prompt),
        Decimal.new(pricing.completion)
      ) |> Decimal.div(Decimal.new(2))
    end
    
    if all_prices == [] do
      Decimal.new(0)
    else
      sum = Enum.reduce(all_prices, Decimal.new(0), &Decimal.add/2)
      Decimal.div(sum, Decimal.new(length(all_prices)))
    end
  end

  defp handle_budget_result(agent, check_result, params) do
    case check_result do
      {:allowed, budgets} ->
        # Track active request
        active_request = %{
          timestamp: DateTime.utc_now(),
          budget_ids: Enum.map(budgets, & &1.id)
        }
        
        state_updates = %{
          active_requests: Map.put(agent.state.active_requests, params.request_id, active_request)
        }
        
        UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})

      {:denied, _violations} ->
        # Record violation
        state_updates = %{
          metrics: Map.update!(agent.state.metrics, :budget_violations, &(&1 + 1))
        }
        
        UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
    end
  end

  defp emit_budget_signal(agent, check_result, params) do
    case check_result do
      {:allowed, budgets} ->
        signal_params = %{
          signal_type: "token.budget.approved",
          data: %{
            request_id: params.request_id,
            budgets_checked: length(budgets),
            timestamp: DateTime.utc_now()
          }
        }
        
        EmitSignalAction.run(signal_params, %{agent: agent})

      {:denied, violations} ->
        signal_params = %{
          signal_type: "token.budget.denied",
          data: %{
            request_id: params.request_id,
            violations: violations,
            timestamp: DateTime.utc_now()
          }
        }
        
        EmitSignalAction.run(signal_params, %{agent: agent})
    end
  end
end