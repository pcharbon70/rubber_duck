defmodule RubberDuck.Planning.Phase do
  @moduledoc """
  Represents a phase within a plan.

  Phases are high-level groupings of related tasks that represent major milestones
  or components in the planning system. They provide the top level of the hierarchical
  task structure and enable better organization of complex plans.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Planning,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "phases"
    repo RubberDuck.Repo

    custom_indexes do
      index [:plan_id]
      index [:position]
      index [:plan_id, :position]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:plan_id, :name, :description, :position, :metadata]

      change set_attribute(:created_at, &DateTime.utc_now/0)
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    update :update do
      primary? true
      accept [:name, :description, :position, :metadata]

      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    read :list_by_plan do
      argument :plan_id, :uuid do
        allow_nil? false
      end

      filter expr(plan_id == ^arg(:plan_id))
      
      prepare fn query, _ ->
        Ash.Query.sort(query, position: :asc)
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Name of the phase (e.g., 'Design', 'Implementation', 'Testing')"
    end

    attribute :description, :string do
      allow_nil? true
      public? true
      description "Detailed description of what this phase encompasses"
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
      default 0
      description "Position of the phase within the plan for ordering"
    end

    attribute :metadata, :map do
      allow_nil? true
      public? true
      default %{}
      description "Additional metadata for the phase"
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :plan, RubberDuck.Planning.Plan do
      attribute_writable? true
      allow_nil? false
    end

    has_many :tasks, RubberDuck.Planning.Task do
      destination_attribute :phase_id
      sort :position
    end
  end

  calculations do
    calculate :task_count, :integer do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case record.tasks do
            %Ash.NotLoaded{} -> 0
            tasks -> length(tasks)
          end
        end)
      end
    end

    calculate :completed_task_count, :integer do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case record.tasks do
            %Ash.NotLoaded{} -> 0
            tasks -> Enum.count(tasks, &(&1.status == :completed))
          end
        end)
      end
    end

    calculate :progress_percentage, :float do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case record.tasks do
            %Ash.NotLoaded{} -> 0.0
            [] -> 0.0
            tasks ->
              completed = Enum.count(tasks, &(&1.status == :completed))
              Float.round(completed / length(tasks) * 100, 2)
          end
        end)
      end
    end
  end
end