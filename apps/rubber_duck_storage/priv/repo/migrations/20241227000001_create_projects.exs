defmodule RubberDuckStorage.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :settings, :map, default: %{}
      add :archived, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:name], name: :projects_name_index)
    create index(:projects, [:archived])
    create index(:projects, [:inserted_at])
    create index(:projects, [:updated_at])
  end
end