defmodule RubberDuck.Agents.TokenManager.BudgetTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.TokenManager.Budget

  describe "Budget.new/1" do
    test "creates a budget with required fields" do
      attrs = %{
        name: "Monthly OpenAI Budget",
        type: :project,
        entity_id: "proj_123",
        period: :monthly,
        limit: Decimal.new("100.00")
      }
      
      budget = Budget.new(attrs)
      
      assert budget.name == "Monthly OpenAI Budget"
      assert budget.type == :project
      assert budget.entity_id == "proj_123"
      assert budget.period == :monthly
      assert Decimal.eq?(budget.limit, Decimal.new("100.00"))
      assert Decimal.eq?(budget.remaining, Decimal.new("100.00"))
      assert budget.currency == "USD"
      assert budget.active == true
    end

    test "sets correct period bounds for daily budget" do
      attrs = %{
        name: "Daily Budget",
        type: :user,
        entity_id: "user_123",
        period: :daily,
        limit: Decimal.new("10.00")
      }
      
      budget = Budget.new(attrs)
      today = Date.utc_today()
      
      assert DateTime.to_date(budget.period_start) == today
      assert DateTime.to_date(budget.period_end) == today
      assert budget.period_start.hour == 0
      assert budget.period_end.hour == 23
    end

    test "sets correct period bounds for monthly budget" do
      attrs = %{
        name: "Monthly Budget",
        type: :global,
        period: :monthly,
        limit: Decimal.new("1000.00")
      }
      
      budget = Budget.new(attrs)
      
      assert budget.period_start.day == 1
      assert budget.period_end.day == Date.days_in_month(budget.period_end)
    end

    test "includes default alert thresholds" do
      attrs = %{
        name: "Test Budget",
        type: :user,
        entity_id: "user_123",
        period: :weekly,
        limit: Decimal.new("50.00")
      }
      
      budget = Budget.new(attrs)
      
      assert budget.alert_thresholds == [50, 80, 90]
    end
  end

  describe "Budget.spend/2" do
    setup do
      budget = Budget.new(%{
        name: "Test Budget",
        type: :user,
        entity_id: "user_123",
        period: :daily,
        limit: Decimal.new("10.00")
      })
      
      {:ok, budget: budget}
    end

    test "records spending within budget", %{budget: budget} do
      amount = Decimal.new("5.00")
      
      {:ok, updated_budget} = Budget.spend(budget, amount)
      
      assert Decimal.eq?(updated_budget.spent, Decimal.new("5.00"))
      assert Decimal.eq?(updated_budget.remaining, Decimal.new("5.00"))
    end

    test "rejects spending exceeding budget", %{budget: budget} do
      amount = Decimal.new("15.00")
      
      {:error, :budget_exceeded} = Budget.spend(budget, amount)
    end

    test "allows spending with override active", %{budget: budget} do
      budget = %{budget | override_active: true}
      amount = Decimal.new("15.00")
      
      {:ok, updated_budget} = Budget.spend(budget, amount)
      
      assert Decimal.eq?(updated_budget.spent, Decimal.new("15.00"))
      assert Decimal.eq?(updated_budget.remaining, Decimal.new("-5.00"))
    end

    test "triggers alerts at thresholds", %{budget: budget} do
      # Spend 50% of budget
      {:ok, budget} = Budget.spend(budget, Decimal.new("5.00"))
      
      assert 50 in budget.alerts_sent
      
      # Spend to 80%
      {:ok, budget} = Budget.spend(budget, Decimal.new("3.00"))
      
      assert 80 in budget.alerts_sent
      assert length(budget.alerts_sent) == 2
    end
  end

  describe "Budget.would_exceed?/2" do
    test "returns true when amount would exceed budget" do
      budget = Budget.new(%{
        name: "Test Budget",
        type: :user,
        entity_id: "user_123",
        period: :daily,
        limit: Decimal.new("10.00")
      })
      
      budget = %{budget | spent: Decimal.new("8.00"), remaining: Decimal.new("2.00")}
      
      assert Budget.would_exceed?(budget, Decimal.new("5.00")) == true
      assert Budget.would_exceed?(budget, Decimal.new("2.00")) == false
      assert Budget.would_exceed?(budget, Decimal.new("1.99")) == false
    end

    test "returns false when override is active" do
      budget = Budget.new(%{
        name: "Test Budget",
        type: :user,
        entity_id: "user_123",
        period: :daily,
        limit: Decimal.new("10.00")
      })
      
      budget = %{budget | 
        spent: Decimal.new("9.00"), 
        remaining: Decimal.new("1.00"),
        override_active: true
      }
      
      assert Budget.would_exceed?(budget, Decimal.new("5.00")) == false
    end
  end

  describe "Budget.usage_percentage/1" do
    test "calculates correct usage percentage" do
      budget = Budget.new(%{
        name: "Test Budget",
        type: :user,
        entity_id: "user_123",
        period: :daily,
        limit: Decimal.new("10.00")
      })
      
      budget = %{budget | spent: Decimal.new("2.50")}
      
      percentage = Budget.usage_percentage(budget)
      assert Decimal.eq?(percentage, Decimal.new("25.00"))
    end

    test "handles zero limit" do
      budget = Budget.new(%{
        name: "Test Budget",
        type: :user,
        entity_id: "user_123",
        period: :daily,
        limit: Decimal.new("0.00")
      })
      
      percentage = Budget.usage_percentage(budget)
      assert Decimal.eq?(percentage, Decimal.new("0"))
    end
  end

  describe "Budget.expired?/1" do
    test "returns true for expired budget" do
      budget = Budget.new(%{
        name: "Test Budget",
        type: :user,
        entity_id: "user_123",
        period: :daily,
        limit: Decimal.new("10.00")
      })
      
      # Set period_end to yesterday
      budget = %{budget | period_end: DateTime.add(DateTime.utc_now(), -1, :day)}
      
      assert Budget.expired?(budget) == true
    end

    test "returns false for active budget" do
      budget = Budget.new(%{
        name: "Test Budget",
        type: :user,
        entity_id: "user_123",
        period: :daily,
        limit: Decimal.new("10.00")
      })
      
      assert Budget.expired?(budget) == false
    end
  end

  describe "Budget.renew/1" do
    test "renews budget for next period" do
      budget = Budget.new(%{
        name: "Test Budget",
        type: :user,
        entity_id: "user_123",
        period: :daily,
        limit: Decimal.new("10.00")
      })
      
      # Add some spending
      budget = %{budget | 
        spent: Decimal.new("8.00"), 
        remaining: Decimal.new("2.00"),
        alerts_sent: [50, 80]
      }
      
      renewed_budget = Budget.renew(budget)
      
      assert Decimal.eq?(renewed_budget.spent, Decimal.new("0"))
      assert Decimal.eq?(renewed_budget.remaining, Decimal.new("10.00"))
      assert renewed_budget.alerts_sent == []
      assert DateTime.compare(renewed_budget.period_start, budget.period_start) == :gt
    end
  end

  describe "Budget.activate_override/2" do
    test "activates override with valid approval" do
      budget = Budget.new(%{
        name: "Test Budget",
        type: :user,
        entity_id: "user_123",
        period: :daily,
        limit: Decimal.new("10.00")
      })
      
      approval_data = %{
        "approved" => true,
        "approver" => "admin",
        "reason" => "Emergency request"
      }
      
      {:ok, updated_budget} = Budget.activate_override(budget, approval_data)
      
      assert updated_budget.override_active == true
      assert updated_budget.metadata["override_approval"] == approval_data
    end

    test "rejects invalid approval" do
      budget = Budget.new(%{
        name: "Test Budget",
        type: :user,
        entity_id: "user_123",
        period: :daily,
        limit: Decimal.new("10.00")
      })
      
      approval_data = %{
        "approved" => false,
        "approver" => "user"
      }
      
      {:error, :invalid_override_approval} = Budget.activate_override(budget, approval_data)
    end
  end

  describe "Budget.status_summary/1" do
    test "returns comprehensive status summary" do
      budget = Budget.new(%{
        name: "Test Budget",
        type: :project,
        entity_id: "proj_123",
        period: :monthly,
        limit: Decimal.new("500.00")
      })
      
      budget = %{budget | 
        spent: Decimal.new("150.00"), 
        remaining: Decimal.new("350.00"),
        alerts_sent: [50]
      }
      
      summary = Budget.status_summary(budget)
      
      assert summary.name == "Test Budget"
      assert summary.type == :project
      assert summary.limit == "500.00"
      assert summary.spent == "150.00"
      assert summary.remaining == "350.00"
      assert summary.usage_percentage == "30.00"
      assert summary.alerts_sent == [50]
      assert summary.active == true
      assert summary.expired == false
    end
  end
end