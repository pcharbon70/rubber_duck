defmodule RubberDuck.Planning.Validation do
  @moduledoc """
  Represents validation results from critic evaluations.

  Validations are the results of running critics (hard and soft) against
  plans and tasks. They track pass/fail status, explanations, and suggestions
  for improvement.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Planning,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "validations"
    repo RubberDuck.Repo

    custom_indexes do
      index [:plan_id]
      index [:task_id]
      index [:status]
      index [:critic_type]
      index [:created_at]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :plan_id,
        :task_id,
        :critic_name,
        :critic_type,
        :status,
        :severity,
        :message,
        :details,
        :suggestions,
        :metadata
      ]

      change set_attribute(:created_at, &DateTime.utc_now/0)
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    update :update do
      primary? true
      accept [:status, :severity, :message, :details, :suggestions, :metadata]
      require_atomic? false

      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    create :batch_create do
      accept []

      argument :validations, {:array, :map} do
        allow_nil? false
      end

      change fn changeset, _context ->
        validations =
          changeset.arguments.validations
          |> Enum.map(fn v ->
            Map.merge(v, %{
              created_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now()
            })
          end)

        # This would need custom implementation for batch insert
        changeset
      end
    end

    read :list_by_plan do
      argument :plan_id, :uuid do
        allow_nil? false
      end

      filter expr(plan_id == ^arg(:plan_id))
    end

    read :list_by_task do
      argument :task_id, :uuid do
        allow_nil? false
      end

      filter expr(task_id == ^arg(:task_id))
    end

    read :list_by_status do
      argument :status, :atom do
        allow_nil? false
        constraints one_of: [:pending, :passed, :failed, :warning]
      end

      filter expr(status == ^arg(:status))
    end

    read :list_failures do
      filter expr(status == :failed)
    end

    read :list_by_critic_type do
      argument :critic_type, :atom do
        allow_nil? false
        constraints one_of: [:hard, :soft]
      end

      filter expr(critic_type == ^arg(:critic_type))
    end
  end

  validations do
    validate fn changeset, _context ->
      plan_id = Ash.Changeset.get_attribute(changeset, :plan_id)
      task_id = Ash.Changeset.get_attribute(changeset, :task_id)

      if is_nil(plan_id) and is_nil(task_id) do
        {:error, field: :base, message: "Either plan_id or task_id must be provided"}
      else
        :ok
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :critic_name, :string do
      allow_nil? false
      public? true
      description "Name of the critic that performed the validation"
    end

    attribute :critic_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:hard, :soft]
      description "Whether this is a hard (correctness) or soft (quality) critic"
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :pending
      constraints one_of: [:pending, :passed, :failed, :warning]
      description "The validation result status"
    end

    attribute :severity, :atom do
      allow_nil? false
      public? true
      default :info
      constraints one_of: [:info, :warning, :error, :critical]
      description "Severity level of the validation result"
    end

    attribute :message, :string do
      allow_nil? false
      public? true
      description "Human-readable validation message"
    end

    attribute :details, :map do
      allow_nil? true
      public? true
      description "Detailed validation results and findings"
    end

    attribute :suggestions, {:array, :string} do
      allow_nil? true
      public? true
      default []
      description "Suggestions for fixing validation issues"
    end

    attribute :metadata, :map do
      allow_nil? true
      public? true
      default %{}
      description "Additional metadata from the validation"
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :plan, RubberDuck.Planning.Plan do
      attribute_writable? true
      allow_nil? true
    end

    belongs_to :task, RubberDuck.Planning.Task do
      attribute_writable? true
      allow_nil? true
    end
  end

  calculations do
    calculate :target_type, :atom do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          cond do
            not is_nil(record.task_id) -> :task
            not is_nil(record.plan_id) -> :plan
            true -> :unknown
          end
        end)
      end
    end

    calculate :is_blocking, :boolean do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          record.critic_type == :hard and record.status == :failed
        end)
      end
    end

    calculate :impact_score, :integer do
      calculation fn records, _opts ->
        severity_scores = %{
          info: 1,
          warning: 5,
          error: 10,
          critical: 20
        }

        status_multipliers = %{
          passed: 0,
          warning: 1,
          failed: 2,
          pending: 0
        }

        Enum.map(records, fn record ->
          severity_score = Map.get(severity_scores, record.severity, 1)
          status_multiplier = Map.get(status_multipliers, record.status, 0)
          type_multiplier = if record.critic_type == :hard, do: 2, else: 1

          severity_score * status_multiplier * type_multiplier
        end)
      end
    end
  end
end
