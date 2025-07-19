defmodule RubberDuck.Planning.Constraint do
  @moduledoc """
  Represents constraints and requirements for plans.

  Constraints define rules that must be satisfied by plans and tasks.
  They can be hard (must pass) or soft (should pass) and are evaluated
  by the critics system during validation.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Planning,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "constraints"
    repo RubberDuck.Repo

    custom_indexes do
      index [:plan_id]
      index [:type]
      index [:enforcement_level]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:plan_id, :name, :description, :type, :enforcement_level, :scope, :conditions, :metadata]

      change set_attribute(:created_at, &DateTime.utc_now/0)
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    update :update do
      primary? true
      accept [:name, :description, :type, :enforcement_level, :scope, :conditions, :active, :metadata]

      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    update :toggle_active do
      accept []
      require_atomic? false

      change fn changeset, _ ->
        current_active = Ash.Changeset.get_attribute(changeset, :active)
        Ash.Changeset.change_attribute(changeset, :active, !current_active)
      end

      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    read :list_by_plan do
      argument :plan_id, :uuid do
        allow_nil? false
      end

      filter expr(plan_id == ^arg(:plan_id))
    end

    read :list_active do
      argument :plan_id, :uuid do
        allow_nil? false
      end

      filter expr(plan_id == ^arg(:plan_id) and active == true)
    end

    read :list_by_type do
      argument :type, :atom do
        allow_nil? false
        constraints one_of: [:dependency, :resource, :timing, :quality, :security, :custom]
      end

      filter expr(type == ^arg(:type))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Name of the constraint"
    end

    attribute :description, :string do
      allow_nil? true
      public? true
      description "Detailed description of what this constraint enforces"
    end

    attribute :type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:dependency, :resource, :timing, :quality, :security, :custom]
      description "The type of constraint"
    end

    attribute :enforcement_level, :atom do
      allow_nil? false
      public? true
      default :hard
      constraints one_of: [:hard, :soft]
      description "Whether this is a hard requirement or soft suggestion"
    end

    attribute :scope, :atom do
      allow_nil? false
      public? true
      default :plan
      constraints one_of: [:plan, :task, :global]
      description "The scope this constraint applies to"
    end

    attribute :conditions, :map do
      allow_nil? false
      public? true
      description "The conditions that must be satisfied"
    end

    attribute :active, :boolean do
      allow_nil? false
      public? true
      default true
      description "Whether this constraint is currently active"
    end

    attribute :metadata, :map do
      allow_nil? true
      public? true
      default %{}
      description "Additional metadata for the constraint"
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :plan, RubberDuck.Planning.Plan do
      attribute_writable? true
      allow_nil? false
    end
  end

  calculations do
    calculate :validation_function, :string do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          # Generate a validation function name based on type and conditions
          "validate_#{record.type}_constraint"
        end)
      end
    end

    calculate :priority_score, :integer do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          base_score = if record.enforcement_level == :hard, do: 100, else: 50

          type_modifier =
            case record.type do
              :security -> 20
              :dependency -> 15
              :resource -> 10
              :timing -> 10
              :quality -> 5
              :custom -> 0
            end

          base_score + type_modifier
        end)
      end
    end
  end
end
