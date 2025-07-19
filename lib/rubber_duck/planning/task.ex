defmodule RubberDuck.Planning.Task do
  @moduledoc """
  Represents an individual task within a plan.

  Tasks are the atomic units of work in the planning system. They have
  dependencies on other tasks, success criteria, and track execution results.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Planning,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "tasks"
    repo RubberDuck.Repo

    custom_indexes do
      index [:plan_id]
      index [:status]
      index [:position]
      index [:plan_id, :position]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:plan_id, :name, :description, :complexity, :position, :success_criteria, :validation_rules, :metadata]

      change set_attribute(:status, :pending)
      change set_attribute(:created_at, &DateTime.utc_now/0)
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    update :update do
      primary? true
      accept [:name, :description, :complexity, :position, :status, :success_criteria, :validation_rules, :metadata]

      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    update :transition_status do
      accept [:status]

      argument :new_status, :atom do
        allow_nil? false
        constraints one_of: [:pending, :ready, :in_progress, :completed, :failed, :skipped]
      end

      change set_attribute(:status, arg(:new_status))
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    update :record_execution do
      accept []
      require_atomic? false

      argument :execution_result, :map do
        allow_nil? false
      end

      change fn changeset, _ ->
        result = Map.put(changeset.arguments.execution_result, :timestamp, DateTime.utc_now())
        Ash.Changeset.change_attribute(changeset, :execution_result, result)
      end

      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    update :add_dependency do
      accept []
      require_atomic? false

      argument :dependency_id, :uuid do
        allow_nil? false
      end

      change fn changeset, context ->
        task_id = changeset.data.id
        dependency_id = changeset.arguments.dependency_id

        # Create the dependency relationship through TaskDependency
        {:ok, _} =
          RubberDuck.Planning.TaskDependency
          |> Ash.Changeset.for_create(:create, %{
            task_id: task_id,
            dependency_id: dependency_id
          })
          |> Ash.create!(authorize?: context[:authorize?])

        changeset
      end
    end

    update :remove_dependency do
      accept []
      require_atomic? false

      argument :dependency_id, :uuid do
        allow_nil? false
      end

      change fn changeset, context ->
        task_id = changeset.data.id
        dependency_id = changeset.arguments.dependency_id

        # Find and destroy the dependency relationship
        RubberDuck.Planning.TaskDependency
        |> Ash.Query.filter(task_id: task_id, dependency_id: dependency_id)
        |> Ash.read_one!(authorize?: context[:authorize?])
        |> case do
          nil ->
            changeset

          dep ->
            Ash.destroy!(dep, authorize?: context[:authorize?])
            changeset
        end
      end
    end

    read :list_by_plan do
      argument :plan_id, :uuid do
        allow_nil? false
      end

      filter expr(plan_id == ^arg(:plan_id))
    end

    read :list_ready do
      argument :plan_id, :uuid do
        allow_nil? false
      end

      filter expr(plan_id == ^arg(:plan_id) and status == :ready)
    end

    read :find_dependents do
      argument :task_id, :uuid do
        allow_nil? false
      end

      prepare fn query, _context ->
        # This will need to be implemented with a custom query
        # to find tasks that depend on the given task_id
        query
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Short, descriptive name for the task"
    end

    attribute :description, :string do
      allow_nil? true
      public? true
      description "Detailed description of what this task accomplishes"
    end

    attribute :complexity, :atom do
      allow_nil? false
      public? true
      default :medium
      constraints one_of: [:trivial, :simple, :medium, :complex, :very_complex]
      description "Estimated complexity of the task"
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :pending
      constraints one_of: [:pending, :ready, :in_progress, :completed, :failed, :skipped]
      description "Current status of the task"
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
      default 0
      description "Position in the task list for ordering"
    end

    attribute :success_criteria, :map do
      allow_nil? true
      public? true
      description "Criteria that must be met for task completion"
    end

    attribute :validation_rules, :map do
      allow_nil? true
      public? true
      description "Rules for validating task execution"
    end

    attribute :execution_result, :map do
      allow_nil? true
      public? true
      description "Result from task execution including output and metrics"
    end

    attribute :metadata, :map do
      allow_nil? true
      public? true
      default %{}
      description "Additional metadata for the task"
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :plan, RubberDuck.Planning.Plan do
      attribute_writable? true
      allow_nil? false
    end

    many_to_many :dependencies, __MODULE__ do
      through RubberDuck.Planning.TaskDependency
      source_attribute :id
      source_attribute_on_join_resource :task_id
      destination_attribute :id
      destination_attribute_on_join_resource :dependency_id
    end

    many_to_many :dependents, __MODULE__ do
      through RubberDuck.Planning.TaskDependency
      source_attribute :id
      source_attribute_on_join_resource :dependency_id
      destination_attribute :id
      destination_attribute_on_join_resource :task_id
    end

    has_many :validations, RubberDuck.Planning.Validation do
      destination_attribute :task_id
      sort :created_at
    end
  end

  calculations do
    calculate :is_ready, :boolean do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          # A task is ready if all its dependencies are completed
          case record.dependencies do
            %Ash.NotLoaded{} -> nil
            dependencies -> Enum.all?(dependencies, &(&1.status == :completed))
          end
        end)
      end
    end

    calculate :dependency_count, :integer do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case record.dependencies do
            %Ash.NotLoaded{} -> 0
            dependencies -> length(dependencies)
          end
        end)
      end
    end

    calculate :dependent_count, :integer do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case record.dependents do
            %Ash.NotLoaded{} -> 0
            dependents -> length(dependents)
          end
        end)
      end
    end

    calculate :execution_duration, :integer do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case record.execution_result do
            %{started_at: started_at, completed_at: completed_at}
            when not is_nil(started_at) and not is_nil(completed_at) ->
              DateTime.diff(completed_at, started_at, :second)

            _ ->
              nil
          end
        end)
      end
    end

    calculate :complexity_score, :integer do
      calculation fn records, _opts ->
        complexity_scores = %{
          trivial: 1,
          simple: 2,
          medium: 5,
          complex: 8,
          very_complex: 13
        }

        Enum.map(records, fn record ->
          Map.get(complexity_scores, record.complexity, 5)
        end)
      end
    end
  end
end
