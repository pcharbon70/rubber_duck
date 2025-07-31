defmodule RubberDuck.Tokens.Resources.Budget do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Tokens,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  @moduledoc """
  Persistent storage for token budget definitions and tracking.
  
  Manages spending limits, period resets, and override approvals
  for controlling token consumption across users, projects, and teams.
  """

  postgres do
    table "token_budgets"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [
        :name,
        :entity_type,
        :entity_id,
        :period_type,
        :period_start,
        :period_end,
        :limit_amount,
        :currency,
        :is_active,
        :metadata
      ]

      change fn changeset, _context ->
        # Initialize spending and calculate period end
        changeset
        |> Ash.Changeset.change_attribute(:current_spending, Decimal.new(0))
        |> calculate_period_end()
      end
    end

    update :update do
      primary? true
      accept [
        :name,
        :limit_amount,
        :is_active,
        :metadata
      ]
    end

    read :active do
      filter expr(is_active == true)
    end

    read :applicable do
      argument :user_id, :uuid, allow_nil?: true
      argument :project_id, :uuid, allow_nil?: true
      
      prepare fn query, _context ->
        query
        |> Ash.Query.filter(is_active == true)
        |> Ash.Query.filter(
          (entity_type == "user" and entity_id == ^query.arguments.user_id) or
          (entity_type == "project" and entity_id == ^query.arguments.project_id)
        )
      end
    end

    update :update_spending do
      argument :amount, :decimal do
        allow_nil? false
        constraints min: 0
      end
      
      change fn changeset, _context ->
        current = Ash.Changeset.get_attribute(changeset, :current_spending) || Decimal.new(0)
        amount = changeset.arguments.amount
        
        new_spending = Decimal.add(current, amount)
        
        changeset
        |> Ash.Changeset.change_attribute(:current_spending, new_spending)
        |> Ash.Changeset.change_attribute(:last_updated, DateTime.utc_now())
      end
    end

    update :reset_period do
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:current_spending, Decimal.new(0))
        |> Ash.Changeset.change_attribute(:period_start, DateTime.utc_now())
        |> calculate_period_end()
        |> Ash.Changeset.change_attribute(:last_reset, DateTime.utc_now())
      end
    end

    read :check_limit do
      argument :amount, :decimal do
        allow_nil? false
        constraints min: 0
      end
      
      prepare fn query, _context ->
        # This would typically be used with a single budget
        # The actual limit checking happens in the agent logic
        query
      end
    end

    update :activate_override do
      argument :approval_data, :map do
        allow_nil? false
      end
      
      change fn changeset, _context ->
        approval_data = Map.merge(changeset.arguments.approval_data, %{
          "activated_at" => DateTime.utc_now()
        })
        
        changeset
        |> Ash.Changeset.change_attribute(:override_active, true)
        |> Ash.Changeset.change_attribute(:override_data, approval_data)
      end
    end

    update :deactivate_override do
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:override_active, false)
        |> Ash.Changeset.change_attribute(:override_data, %{})
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      description "Human-readable name for the budget"
    end

    attribute :entity_type, :string do
      allow_nil? false
      description "Type of entity this budget applies to"
    end

    attribute :entity_id, :uuid do
      allow_nil? true
      description "ID of the entity (null for global budgets)"
    end

    attribute :period_type, :string do
      allow_nil? false
      description "How often the budget resets"
    end

    attribute :period_start, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      description "Start of the current budget period"
    end

    attribute :period_end, :utc_datetime_usec do
      allow_nil? true
      description "End of the current budget period (calculated)"
    end

    attribute :limit_amount, :decimal do
      allow_nil? false
      constraints min: 0
      description "Maximum spending allowed in the period"
    end

    attribute :current_spending, :decimal do
      allow_nil? false
      default Decimal.new(0)
      constraints min: 0
      description "Current spending in this period"
    end

    attribute :currency, :string do
      allow_nil? false
      default "USD"
      constraints max_length: 3
      description "Currency code (ISO 4217)"
    end

    attribute :is_active, :boolean do
      allow_nil? false
      default true
      description "Whether this budget is currently enforced"
    end

    attribute :override_active, :boolean do
      allow_nil? false
      default false
      description "Whether an override is currently active"
    end

    attribute :override_data, :map do
      allow_nil? false
      default %{}
      description "Override approval details and metadata"
    end

    attribute :last_reset, :utc_datetime_usec do
      allow_nil? true
      description "When the budget was last reset"
    end

    attribute :last_updated, :utc_datetime_usec do
      allow_nil? true
      description "When spending was last updated"
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      description "Additional budget configuration"
    end

    timestamps()
  end

  validations do
    validate one_of(:entity_type, ["user", "project", "team", "global"])
    validate one_of(:period_type, ["daily", "weekly", "monthly", "quarterly", "yearly", "fixed"])
  end

  calculations do
    calculate :remaining_budget, :decimal, expr(limit_amount - current_spending)
    
    calculate :utilization_percentage, :decimal, expr(
      if limit_amount > 0 do
        (current_spending / limit_amount) * 100
      else
        0
      end
    )
    
    calculate :is_over_limit, :boolean, expr(current_spending > limit_amount)
    
    calculate :needs_reset, :boolean, expr(
      period_end != nil and period_end < now()
    )
  end

  identities do
    identity :unique_entity_budget, [:entity_type, :entity_id, :name]
  end

  postgres do
    table "token_budgets"
    repo RubberDuck.Repo

    references do
      # Note: Add references when user/project/team resources exist
    end
  end

  code_interface do
    define :create_budget, action: :create
    define :update_budget, action: :update
    define :update_spending, action: :update_spending
    define :reset_period, action: :reset_period
  end

  # Helper function to calculate period end based on period type
  defp calculate_period_end(changeset) do
    period_type = Ash.Changeset.get_attribute(changeset, :period_type)
    period_start = Ash.Changeset.get_attribute(changeset, :period_start) || DateTime.utc_now()
    
    period_end = case period_type do
      "daily" -> 
        period_start |> DateTime.add(1, :day) |> DateTime.truncate(:second)
      "weekly" -> 
        period_start |> DateTime.add(7, :day) |> DateTime.truncate(:second)
      "monthly" -> 
        period_start |> DateTime.add(30, :day) |> DateTime.truncate(:second)
      "quarterly" -> 
        period_start |> DateTime.add(90, :day) |> DateTime.truncate(:second)
      "yearly" -> 
        period_start |> DateTime.add(365, :day) |> DateTime.truncate(:second)
      "fixed" -> 
        nil # Fixed budgets don't auto-reset
      _ -> 
        nil
    end
    
    if period_end do
      Ash.Changeset.change_attribute(changeset, :period_end, period_end)
    else
      changeset
    end
  end
end