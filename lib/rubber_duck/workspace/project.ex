defmodule RubberDuck.Workspace.Project do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Workspace,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "projects"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? true
      public? true
    end

    attribute :configuration, :map do
      allow_nil? true
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :code_files, RubberDuck.Workspace.CodeFile
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
