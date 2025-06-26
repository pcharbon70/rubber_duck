defmodule RubberDuckStorage.Repo.Migrations.CreateEngineSessions do
  use Ecto.Migration

  def change do
    create table(:engine_sessions, primary_key: false) do
      add :id, :string, primary_key: true
      add :engine_type, :string, null: false
      add :engine_config, :map, default: %{}
      add :status, :string, null: false, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :error_message, :text
      add :metadata, :map, default: %{}
      add :conversation_id, references(:conversations, type: :string, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:engine_sessions, [:conversation_id])
    create index(:engine_sessions, [:engine_type])
    create index(:engine_sessions, [:status])
    create index(:engine_sessions, [:started_at])
    create index(:engine_sessions, [:completed_at])
    create index(:engine_sessions, [:inserted_at])
  end
end