defmodule RubberDuck.Tokens.Resources.BudgetTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.Tokens
  
  describe "budget persistence" do
    setup do
      # Create a test user
      {:ok, user} = RubberDuck.Accounts.register_user(%{
        email: "test@example.com",
        password: "password123456"
      })
      
      %{user: user}
    end
    
    test "creates a budget", %{user: user} do
      attrs = %{
        name: "Monthly AI Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "monthly",
        limit_amount: Decimal.new("100.00"),
        currency: "USD"
      }
      
      assert {:ok, budget} = Tokens.create_budget(attrs)
      assert budget.name == "Monthly AI Budget"
      assert budget.entity_type == "user"
      assert budget.entity_id == user.id
      assert budget.period_type == "monthly"
      assert Decimal.equal?(budget.limit_amount, Decimal.new("100.00"))
      assert budget.is_active == true
      assert Decimal.equal?(budget.current_spending, Decimal.new("0"))
    end
    
    test "validates entity_type values" do
      attrs = %{
        name: "Invalid Budget",
        entity_type: "invalid_type",
        period_type: "monthly",
        limit_amount: Decimal.new("100.00")
      }
      
      assert {:error, error} = Tokens.create_budget(attrs)
      assert error.errors |> Enum.any?(fn e -> 
        e.field == :entity_type && e.message =~ "is invalid"
      end)
    end
    
    test "validates period_type values" do
      attrs = %{
        name: "Invalid Budget",
        entity_type: "global",
        period_type: "invalid_period",
        limit_amount: Decimal.new("100.00")
      }
      
      assert {:error, error} = Tokens.create_budget(attrs)
      assert error.errors |> Enum.any?(fn e -> 
        e.field == :period_type && e.message =~ "is invalid"
      end)
    end
    
    test "updates budget spending", %{user: user} do
      {:ok, budget} = Tokens.create_budget(%{
        name: "Test Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "monthly",
        limit_amount: Decimal.new("100.00")
      })
      
      # Update spending
      assert {:ok, updated} = Tokens.update_spending(budget, Decimal.new("25.50"))
      assert Decimal.equal?(updated.current_spending, Decimal.new("25.50"))
      assert updated.last_updated != nil
      
      # Add more spending
      assert {:ok, updated2} = Tokens.update_spending(updated, Decimal.new("10.00"))
      assert Decimal.equal?(updated2.current_spending, Decimal.new("35.50"))
    end
    
    test "resets budget period", %{user: user} do
      {:ok, budget} = Tokens.create_budget(%{
        name: "Test Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "daily",
        limit_amount: Decimal.new("50.00"),
        current_spending: Decimal.new("45.00")
      })
      
      # Update spending first
      {:ok, budget} = Tokens.update_spending(budget, Decimal.new("45.00"))
      
      # Reset period
      assert {:ok, reset} = Tokens.reset_budget_period(budget)
      assert Decimal.equal?(reset.current_spending, Decimal.new("0"))
      assert reset.last_reset != nil
      assert reset.period_start != budget.period_start
    end
    
    test "finds applicable budgets", %{user: user} do
      # Create user budget
      {:ok, user_budget} = Tokens.create_budget(%{
        name: "User Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "monthly",
        limit_amount: Decimal.new("100.00")
      })
      
      # Create global budget
      {:ok, global_budget} = Tokens.create_budget(%{
        name: "Global Budget",
        entity_type: "global",
        period_type: "yearly",
        limit_amount: Decimal.new("10000.00")
      })
      
      # Create inactive budget
      {:ok, inactive} = Tokens.create_budget(%{
        name: "Inactive Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "daily",
        limit_amount: Decimal.new("10.00"),
        is_active: false
      })
      
      # Find applicable budgets
      assert {:ok, budgets} = Tokens.find_applicable_budgets(user.id, nil)
      budget_ids = Enum.map(budgets, & &1.id)
      
      assert user_budget.id in budget_ids
      assert global_budget.id in budget_ids
      refute inactive.id in budget_ids
    end
    
    test "activates budget override", %{user: user} do
      {:ok, budget} = Tokens.create_budget(%{
        name: "Test Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "monthly",
        limit_amount: Decimal.new("100.00")
      })
      
      approval_data = %{
        "approved_by" => "admin@example.com",
        "reason" => "Emergency request",
        "expires_at" => DateTime.add(DateTime.utc_now(), 3600, :second)
      }
      
      assert {:ok, overridden} = Tokens.activate_override(budget, approval_data)
      assert overridden.override_active == true
      assert overridden.override_data["approved_by"] == "admin@example.com"
      assert overridden.override_data["activated_at"] != nil
    end
    
    test "deactivates budget override", %{user: user} do
      {:ok, budget} = Tokens.create_budget(%{
        name: "Test Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "monthly",
        limit_amount: Decimal.new("100.00")
      })
      
      # First activate
      {:ok, budget} = Tokens.activate_override(budget, %{"approved_by" => "admin"})
      assert budget.override_active == true
      
      # Then deactivate
      assert {:ok, deactivated} = Tokens.deactivate_override(budget)
      assert deactivated.override_active == false
      assert deactivated.override_data == %{}
    end
    
    test "lists active budgets" do
      # Create active and inactive budgets
      {:ok, active1} = Tokens.create_budget(%{
        name: "Active 1",
        entity_type: "global",
        period_type: "monthly",
        limit_amount: Decimal.new("100.00")
      })
      
      {:ok, active2} = Tokens.create_budget(%{
        name: "Active 2",
        entity_type: "global",
        period_type: "yearly",
        limit_amount: Decimal.new("1000.00")
      })
      
      {:ok, _inactive} = Tokens.create_budget(%{
        name: "Inactive",
        entity_type: "global",
        period_type: "daily",
        limit_amount: Decimal.new("10.00"),
        is_active: false
      })
      
      assert {:ok, active_budgets} = Tokens.list_active_budgets()
      active_ids = Enum.map(active_budgets, & &1.id)
      
      assert active1.id in active_ids
      assert active2.id in active_ids
      assert length(active_budgets) >= 2
    end
    
    test "calculates budget metrics", %{user: user} do
      {:ok, budget} = Tokens.create_budget(%{
        name: "Test Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "monthly",
        limit_amount: Decimal.new("100.00")
      })
      
      # Update spending to 75
      {:ok, budget} = Tokens.update_spending(budget, Decimal.new("75.00"))
      
      # Load with calculations
      {:ok, loaded} = Tokens.get_budget(budget.id, load: [:remaining_budget, :utilization_percentage, :is_over_limit])
      
      assert Decimal.equal?(loaded.remaining_budget, Decimal.new("25.00"))
      assert loaded.utilization_percentage == 75.0
      assert loaded.is_over_limit == false
      
      # Exceed budget
      {:ok, exceeded} = Tokens.update_spending(budget, Decimal.new("30.00"))
      {:ok, loaded2} = Tokens.get_budget(exceeded.id, load: [:remaining_budget, :is_over_limit])
      
      assert Decimal.compare(loaded2.remaining_budget, Decimal.new("0")) == :lt
      assert loaded2.is_over_limit == true
    end
    
    test "enforces unique entity budget constraint", %{user: user} do
      attrs = %{
        name: "Duplicate Budget",
        entity_type: "user",
        entity_id: user.id,
        period_type: "monthly",
        limit_amount: Decimal.new("100.00")
      }
      
      assert {:ok, _budget1} = Tokens.create_budget(attrs)
      
      # Try to create another with same entity/name
      assert {:error, error} = Tokens.create_budget(attrs)
      assert error.errors |> Enum.any?(fn e -> 
        e.message =~ "already been taken"
      end)
    end
  end
end