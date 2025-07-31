defmodule RubberDuck.Agents.BudgetEnforcementAgent do
  @moduledoc """
  Agent responsible for enforcing token usage budgets.
  
  Monitors token usage against defined budgets and:
  - Enforces spending limits
  - Manages budget periods and resets
  - Handles override approvals
  - Sends alerts and notifications
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "budget_enforcement_agent",
    description: "Enforces token usage budgets and limits",
    schema: [
      active_budgets: [type: :map, default: %{}],
      budget_cache_ttl: [type: :integer, default: 60_000], # 1 minute
      check_interval: [type: :integer, default: 30_000], # 30 seconds
      alert_thresholds: [type: :list, default: [0.8, 0.9, 1.0]], # 80%, 90%, 100%
      enforcement_stats: [type: :map, default: %{
        checks_performed: 0,
        budgets_exceeded: 0,
        requests_blocked: 0,
        overrides_granted: 0
      }]
    ]
  
  require Logger
  alias RubberDuck.Tokens
  
  @doc """
  Initializes the budget enforcement agent.
  """
  @impl true
  def pre_init(config) do
    # Subscribe to budget-related signals
    config = Map.put(config, :signal_subscriptions, [
      %{type: "token_usage_request"},
      %{type: "budget_check"},
      %{type: "budget_override_request"},
      %{type: "budget_reset"},
      %{type: "budget_update"}
    ])
    
    {:ok, config}
  end
  
  @doc """
  Loads active budgets after initialization.
  """
  @impl true
  def post_init(agent) do
    # Load all active budgets
    case load_active_budgets() do
      {:ok, budgets} ->
        new_state = Map.put(agent.state, :active_budgets, budgets)
        schedule_periodic_check(agent.state.check_interval)
        {:ok, %{agent | state: new_state}}
        
      {:error, reason} ->
        Logger.error("Failed to load active budgets: #{inspect(reason)}")
        {:ok, agent}
    end
  end
  
  @doc """
  Handles budget enforcement signals.
  """
  def handle_signal(agent, %{"type" => "token_usage_request", "data" => request}) do
    # Check if the request would exceed any budgets
    user_id = request["user_id"]
    project_id = request["project_id"]
    estimated_cost = Decimal.new(to_string(request["estimated_cost"] || "0"))
    
    case check_budget_limits(agent, user_id, project_id, estimated_cost) do
      {:ok, :within_budget} ->
        emit_signal(agent, %{
          "type" => "budget_check_passed",
          "data" => %{
            "request_id" => request["request_id"],
            "user_id" => user_id,
            "project_id" => project_id
          }
        })
        {:ok, agent}
        
      {:error, {:budget_exceeded, budget_info}} ->
        agent = increment_stat(agent, :requests_blocked)
        
        emit_signal(agent, %{
          "type" => "budget_check_failed",
          "data" => %{
            "request_id" => request["request_id"],
            "user_id" => user_id,
            "project_id" => project_id,
            "budget_id" => budget_info.id,
            "budget_name" => budget_info.name,
            "current_spending" => budget_info.current_spending,
            "limit" => budget_info.limit_amount,
            "reason" => "Budget limit exceeded"
          }
        })
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "budget_override_request", "data" => request}) do
    budget_id = request["budget_id"]
    approval_data = request["approval_data"]
    
    case process_override_request(budget_id, approval_data) do
      {:ok, _budget} ->
        agent = increment_stat(agent, :overrides_granted)
        
        emit_signal(agent, %{
          "type" => "budget_override_granted",
          "data" => %{
            "budget_id" => budget_id,
            "approved_by" => approval_data["approved_by"],
            "timestamp" => DateTime.utc_now()
          }
        })
        
        # Reload budget cache
        agent = reload_budget(agent, budget_id)
        {:ok, agent}
        
      {:error, reason} ->
        Logger.error("Failed to process override request: #{inspect(reason)}")
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "budget_update", "data" => update}) do
    budget_id = update["budget_id"]
    
    # Reload the updated budget
    agent = reload_budget(agent, budget_id)
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "periodic_check"}) do
    # Check all budgets for period resets
    agent = check_and_reset_budgets(agent)
    
    # Schedule next check
    schedule_periodic_check(agent.state.check_interval)
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "token_usage_flush", "data" => usage_records}) do
    # Update budget spending based on actual usage
    agent = update_budget_spending(agent, usage_records)
    {:ok, agent}
  end
  
  def handle_signal(agent, _signal) do
    {:ok, agent}
  end
  
  # Budget checking functions
  
  defp check_budget_limits(agent, user_id, project_id, estimated_cost) do
    agent = increment_stat(agent, :checks_performed)
    
    # Find applicable budgets
    budgets = find_applicable_budgets(agent, user_id, project_id)
    
    # Check each budget
    exceeded_budgets = Enum.filter(budgets, fn budget ->
      would_exceed_budget?(budget, estimated_cost)
    end)
    
    case exceeded_budgets do
      [] -> 
        {:ok, :within_budget}
        
      [budget | _] ->
        # Return the first exceeded budget
        {:error, {:budget_exceeded, budget}}
    end
  end
  
  defp find_applicable_budgets(agent, user_id, project_id) do
    agent.state.active_budgets
    |> Map.values()
    |> Enum.filter(fn budget ->
      case budget.entity_type do
        "user" -> budget.entity_id == user_id
        "project" -> budget.entity_id == project_id
        "global" -> true
        _ -> false
      end
    end)
  end
  
  defp would_exceed_budget?(budget, additional_cost) do
    # Check if override is active
    if budget.override_active do
      false
    else
      new_spending = Decimal.add(budget.current_spending, additional_cost)
      Decimal.compare(new_spending, budget.limit_amount) == :gt
    end
  end
  
  # Budget update functions
  
  defp update_budget_spending(agent, usage_records) do
    # Group records by user and project
    grouped = group_usage_records(usage_records)
    
    # Update each affected budget
    Enum.reduce(grouped, agent, fn {{entity_type, entity_id}, records}, acc_agent ->
      total_cost = calculate_total_cost(records)
      update_entity_budgets(acc_agent, entity_type, entity_id, total_cost)
    end)
  end
  
  defp group_usage_records(records) do
    Enum.reduce(records, %{}, fn record, acc ->
      user_id = record["user_id"] || record[:user_id]
      project_id = record["project_id"] || record[:project_id]
      cost = Decimal.new(to_string(record["cost"] || record[:cost] || "0"))
      
      acc
      |> Map.update({:user, user_id}, [cost], &[cost | &1])
      |> Map.update({:project, project_id}, [cost], &[cost | &1])
      |> Map.update({:global, nil}, [cost], &[cost | &1])
    end)
  end
  
  defp calculate_total_cost(costs) do
    Enum.reduce(costs, Decimal.new("0"), &Decimal.add/2)
  end
  
  defp update_entity_budgets(agent, entity_type, entity_id, amount) do
    budgets = find_entity_budgets(agent, entity_type, entity_id)
    
    Enum.reduce(budgets, agent, fn budget, acc_agent ->
      case Tokens.update_spending(budget.id, amount) do
        {:ok, updated_budget} ->
          # Update cache
          new_budgets = Map.put(acc_agent.state.active_budgets, budget.id, updated_budget)
          new_state = Map.put(acc_agent.state, :active_budgets, new_budgets)
          
          # Check for threshold alerts
          check_budget_thresholds(%{acc_agent | state: new_state}, updated_budget)
          
        {:error, reason} ->
          Logger.error("Failed to update budget spending: #{inspect(reason)}")
          acc_agent
      end
    end)
  end
  
  defp find_entity_budgets(agent, entity_type, entity_id) do
    agent.state.active_budgets
    |> Map.values()
    |> Enum.filter(fn budget ->
      budget.entity_type == to_string(entity_type) && 
      (is_nil(entity_id) || budget.entity_id == entity_id)
    end)
  end
  
  # Budget period management
  
  defp check_and_reset_budgets(agent) do
    now = DateTime.utc_now()
    
    agent.state.active_budgets
    |> Map.values()
    |> Enum.filter(&needs_reset?(&1, now))
    |> Enum.reduce(agent, fn budget, acc_agent ->
      reset_budget_period(acc_agent, budget)
    end)
  end
  
  defp needs_reset?(%{period_type: "fixed"}, _now), do: false
  defp needs_reset?(%{period_end: nil}, _now), do: false
  defp needs_reset?(%{period_end: period_end}, now) do
    DateTime.compare(now, period_end) == :gt
  end
  
  defp reset_budget_period(agent, budget) do
    case Tokens.reset_budget_period(budget.id) do
      {:ok, reset_budget} ->
        # Update cache
        new_budgets = Map.put(agent.state.active_budgets, budget.id, reset_budget)
        new_state = Map.put(agent.state, :active_budgets, new_budgets)
        
        emit_signal(agent, %{
          "type" => "budget_reset",
          "data" => %{
            "budget_id" => budget.id,
            "budget_name" => budget.name,
            "new_period_start" => reset_budget.period_start,
            "new_period_end" => reset_budget.period_end
          }
        })
        
        %{agent | state: new_state}
        
      {:error, reason} ->
        Logger.error("Failed to reset budget period: #{inspect(reason)}")
        agent
    end
  end
  
  # Threshold checking
  
  defp check_budget_thresholds(agent, budget) do
    utilization = calculate_utilization(budget)
    
    Enum.each(agent.state.alert_thresholds, fn threshold ->
      if utilization >= threshold && !already_alerted?(agent, budget.id, threshold) do
        emit_budget_alert(agent, budget, threshold, utilization)
        mark_as_alerted(agent, budget.id, threshold)
      end
    end)
    
    agent
  end
  
  defp calculate_utilization(%{current_spending: current, limit_amount: limit}) do
    if Decimal.compare(limit, Decimal.new("0")) == :gt do
      current
      |> Decimal.div(limit)
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.to_float()
    else
      0.0
    end
  end
  
  defp already_alerted?(_agent, _budget_id, _threshold) do
    # Would track alerts in state
    false
  end
  
  defp mark_as_alerted(agent, _budget_id, _threshold) do
    # Would update alert tracking
    agent
  end
  
  defp emit_budget_alert(agent, budget, threshold, utilization) do
    emit_signal(agent, %{
      "type" => "budget_alert",
      "data" => %{
        "budget_id" => budget.id,
        "budget_name" => budget.name,
        "threshold" => threshold,
        "utilization" => utilization,
        "current_spending" => budget.current_spending,
        "limit" => budget.limit_amount,
        "timestamp" => DateTime.utc_now()
      }
    })
  end
  
  # Helper functions
  
  defp load_active_budgets do
    case Tokens.list_active_budgets() do
      {:ok, budgets} ->
        budget_map = Enum.reduce(budgets, %{}, fn budget, acc ->
          Map.put(acc, budget.id, budget)
        end)
        {:ok, budget_map}
        
      error -> error
    end
  end
  
  defp reload_budget(agent, budget_id) do
    case Tokens.get_budget(budget_id) do
      {:ok, budget} ->
        new_budgets = Map.put(agent.state.active_budgets, budget.id, budget)
        new_state = Map.put(agent.state, :active_budgets, new_budgets)
        %{agent | state: new_state}
        
      {:error, _reason} ->
        # Remove from cache if not found
        new_budgets = Map.delete(agent.state.active_budgets, budget_id)
        new_state = Map.put(agent.state, :active_budgets, new_budgets)
        %{agent | state: new_state}
    end
  end
  
  defp process_override_request(budget_id, approval_data) do
    Tokens.activate_override(budget_id, approval_data)
  end
  
  defp schedule_periodic_check(_interval) do
    # In a real implementation, this would schedule a timer
    :ok
  end
  
  defp increment_stat(agent, stat_name) do
    new_stats = Map.update!(agent.state.enforcement_stats, stat_name, &(&1 + 1))
    new_state = Map.put(agent.state, :enforcement_stats, new_stats)
    %{agent | state: new_state}
  end
  
  @doc """
  Health check for the budget enforcement agent.
  """
  @impl true
  def health_check(agent) do
    stats = agent.state.enforcement_stats
    active_budget_count = map_size(agent.state.active_budgets)
    
    block_rate = if stats.checks_performed > 0 do
      stats.requests_blocked / stats.checks_performed
    else
      0.0
    end
    
    if active_budget_count > 0 && block_rate < 0.5 do
      {:healthy, %{
        active_budgets: active_budget_count,
        checks_performed: stats.checks_performed,
        block_rate: block_rate
      }}
    else
      {:unhealthy, %{
        active_budgets: active_budget_count,
        block_rate: block_rate,
        message: if(active_budget_count == 0, do: "No active budgets", else: "High block rate")
      }}
    end
  end
end