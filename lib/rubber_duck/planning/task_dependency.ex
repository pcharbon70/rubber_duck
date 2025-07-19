defmodule RubberDuck.Planning.TaskDependency do
  @moduledoc """
  Join table for managing task dependencies.

  This resource tracks which tasks depend on other tasks, enabling
  dependency graph analysis and topological sorting for execution order.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Planning,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "task_dependencies"
    repo RubberDuck.Repo

    custom_indexes do
      index [:task_id]
      index [:dependency_id]
      index [:task_id, :dependency_id], unique: true
    end
  end

  actions do
    defaults [:create, :read, :destroy]
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :created_at
  end

  relationships do
    belongs_to :task, RubberDuck.Planning.Task do
      attribute_writable? true
      allow_nil? false
    end

    belongs_to :dependency, RubberDuck.Planning.Task do
      attribute_writable? true
      allow_nil? false
    end
  end

  identities do
    identity :unique_dependency, [:task_id, :dependency_id]
  end
end
