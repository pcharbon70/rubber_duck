defmodule RubberDuckStorage.Repo.Migrations.AddProjectIdToEngineSessions do
  use Ecto.Migration

  def change do
    alter table(:engine_sessions) do
      add :project_id, references(:projects, type: :string, on_delete: :delete_all), null: true
    end

    create index(:engine_sessions, [:project_id])
  end
end