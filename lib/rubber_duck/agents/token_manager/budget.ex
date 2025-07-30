defmodule RubberDuck.Agents.TokenManager.Budget do
  @moduledoc """
  Budget management for token usage control.
  
  Supports hierarchical budgets (global, team, user, project) with
  time-based periods and flexible alert/override policies.
  """

  @type budget_type :: :global | :team | :user | :project
  @type budget_period :: :daily | :weekly | :monthly | :yearly | :custom
  
  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    type: budget_type(),
    entity_id: String.t() | nil,
    period: budget_period(),
    period_start: DateTime.t(),
    period_end: DateTime.t(),
    limit: Decimal.t(),
    currency: String.t(),
    spent: Decimal.t(),
    remaining: Decimal.t(),
    alert_thresholds: [integer()],
    alerts_sent: [integer()],
    override_policy: map(),
    override_active: boolean(),
    active: boolean(),
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    metadata: map()
  }

  defstruct [
    :id,
    :name,
    :type,
    :entity_id,
    :period,
    :period_start,
    :period_end,
    :limit,
    :currency,
    :spent,
    :remaining,
    :alert_thresholds,
    :alerts_sent,
    :override_policy,
    :override_active,
    :active,
    :created_at,
    :updated_at,
    :metadata
  ]

  @doc """
  Creates a new Budget.
  
  ## Parameters
  
  - `attrs` - Map containing budget attributes
  
  ## Examples
  
      iex> Budget.new(%{
      ...>   name: "Monthly OpenAI Budget",
      ...>   type: :project,
      ...>   entity_id: "proj123",
      ...>   period: :monthly,
      ...>   limit: Decimal.new(100)
      ...> })
      %Budget{...}
  """
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()
    {period_start, period_end} = calculate_period_bounds(attrs.period, now)
    limit = attrs.limit
    
    %__MODULE__{
      id: Map.get(attrs, :id, generate_id()),
      name: Map.fetch!(attrs, :name),
      type: Map.fetch!(attrs, :type),
      entity_id: Map.get(attrs, :entity_id),
      period: Map.fetch!(attrs, :period),
      period_start: period_start,
      period_end: period_end,
      limit: limit,
      currency: Map.get(attrs, :currency, "USD"),
      spent: Map.get(attrs, :spent, Decimal.new(0)),
      remaining: Map.get(attrs, :remaining, limit),
      alert_thresholds: Map.get(attrs, :alert_thresholds, [50, 80, 90]),
      alerts_sent: Map.get(attrs, :alerts_sent, []),
      override_policy: Map.get(attrs, :override_policy, default_override_policy()),
      override_active: Map.get(attrs, :override_active, false),
      active: Map.get(attrs, :active, true),
      created_at: Map.get(attrs, :created_at, now),
      updated_at: Map.get(attrs, :updated_at, now),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @doc """
  Updates a budget with new attributes.
  """
  def update(%__MODULE__{} = budget, updates) when is_map(updates) do
    # Update simple fields
    budget = Enum.reduce(updates, budget, fn {key, value}, acc ->
      case key do
        "limit" -> 
          new_limit = Decimal.new(value)
          %{acc | 
            limit: new_limit,
            remaining: Decimal.sub(new_limit, acc.spent)
          }
        "active" -> %{acc | active: value}
        "alert_thresholds" -> %{acc | alert_thresholds: value}
        "override_policy" -> %{acc | override_policy: value}
        _ -> acc
      end
    end)
    
    %{budget | updated_at: DateTime.utc_now()}
  end

  @doc """
  Records spending against the budget.
  
  Returns `{:ok, updated_budget}` or `{:error, reason}`.
  """
  def spend(%__MODULE__{} = budget, amount) when is_struct(amount, Decimal) do
    new_spent = Decimal.add(budget.spent, amount)
    new_remaining = Decimal.sub(budget.limit, new_spent)
    
    if Decimal.gt?(new_remaining, 0) or budget.override_active do
      updated_budget = %{budget | 
        spent: new_spent,
        remaining: new_remaining,
        updated_at: DateTime.utc_now()
      }
      
      # Check for alerts
      updated_budget = check_and_send_alerts(updated_budget)
      
      {:ok, updated_budget}
    else
      {:error, :budget_exceeded}
    end
  end

  @doc """
  Checks if spending an amount would exceed the budget.
  """
  def would_exceed?(%__MODULE__{} = budget, amount) when is_struct(amount, Decimal) do
    not budget.override_active and Decimal.lt?(budget.remaining, amount)
  end

  @doc """
  Calculates the percentage of budget used.
  """
  def usage_percentage(%__MODULE__{} = budget) do
    if Decimal.gt?(budget.limit, 0) do
      Decimal.mult(
        Decimal.div(budget.spent, budget.limit),
        Decimal.new(100)
      ) |> Decimal.round(2)
    else
      Decimal.new(0)
    end
  end

  @doc """
  Checks if the budget period has expired and needs renewal.
  """
  def expired?(%__MODULE__{} = budget) do
    DateTime.compare(DateTime.utc_now(), budget.period_end) == :gt
  end

  @doc """
  Renews the budget for the next period.
  """
  def renew(%__MODULE__{} = budget) do
    now = DateTime.utc_now()
    {period_start, period_end} = calculate_period_bounds(budget.period, now)
    
    %{budget |
      period_start: period_start,
      period_end: period_end,
      spent: Decimal.new(0),
      remaining: budget.limit,
      alerts_sent: [],
      updated_at: now
    }
  end

  @doc """
  Activates a budget override.
  """
  def activate_override(%__MODULE__{} = budget, approval_data) do
    if valid_override_approval?(budget.override_policy, approval_data) do
      {:ok, %{budget | 
        override_active: true,
        updated_at: DateTime.utc_now(),
        metadata: Map.put(budget.metadata, "override_approval", approval_data)
      }}
    else
      {:error, :invalid_override_approval}
    end
  end

  @doc """
  Deactivates a budget override.
  """
  def deactivate_override(%__MODULE__{} = budget) do
    %{budget | 
      override_active: false,
      updated_at: DateTime.utc_now(),
      metadata: Map.delete(budget.metadata, "override_approval")
    }
  end

  @doc """
  Returns a summary of the budget status.
  """
  def status_summary(%__MODULE__{} = budget) do
    %{
      id: budget.id,
      name: budget.name,
      type: budget.type,
      entity_id: budget.entity_id,
      period: budget.period,
      limit: Decimal.to_string(budget.limit),
      spent: Decimal.to_string(budget.spent),
      remaining: Decimal.to_string(budget.remaining),
      usage_percentage: Decimal.to_string(usage_percentage(budget)),
      currency: budget.currency,
      active: budget.active,
      override_active: budget.override_active,
      expired: expired?(budget),
      alerts_sent: budget.alerts_sent,
      period_end: budget.period_end
    }
  end

  ## Private Functions

  defp calculate_period_bounds(:daily, reference_date) do
    start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")
    end_date = DateTime.new!(Date.utc_today(), ~T[23:59:59], "Etc/UTC")
    {start, end_date}
  end

  defp calculate_period_bounds(:weekly, reference_date) do
    today = DateTime.to_date(reference_date)
    days_since_monday = Date.day_of_week(today) - 1
    monday = Date.add(today, -days_since_monday)
    sunday = Date.add(monday, 6)
    
    start = DateTime.new!(monday, ~T[00:00:00], "Etc/UTC")
    end_date = DateTime.new!(sunday, ~T[23:59:59], "Etc/UTC")
    {start, end_date}
  end

  defp calculate_period_bounds(:monthly, reference_date) do
    date = DateTime.to_date(reference_date)
    start_date = Date.beginning_of_month(date)
    end_date = Date.end_of_month(date)
    
    start = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")
    {start, end_dt}
  end

  defp calculate_period_bounds(:yearly, reference_date) do
    year = reference_date.year
    start = DateTime.new!(Date.new!(year, 1, 1), ~T[00:00:00], "Etc/UTC")
    end_date = DateTime.new!(Date.new!(year, 12, 31), ~T[23:59:59], "Etc/UTC")
    {start, end_date}
  end

  defp default_override_policy do
    %{
      "requires_approval" => true,
      "approvers" => ["admin"],
      "max_override_percentage" => 50,
      "notification_required" => true
    }
  end

  defp check_and_send_alerts(%__MODULE__{} = budget) do
    usage_pct = usage_percentage(budget) |> Decimal.to_integer()
    
    new_alerts = Enum.filter(budget.alert_thresholds, fn threshold ->
      usage_pct >= threshold and threshold not in budget.alerts_sent
    end)
    
    if new_alerts != [] do
      # In production, would actually send alerts
      %{budget | alerts_sent: budget.alerts_sent ++ new_alerts}
    else
      budget
    end
  end

  defp valid_override_approval?(policy, approval_data) do
    # Simplified validation - in production would check actual approvers
    Map.get(approval_data, "approved", false) and
    Map.get(approval_data, "approver") in Map.get(policy, "approvers", [])
  end

  defp generate_id do
    "budget_#{System.unique_integer([:positive, :monotonic])}"
  end
end