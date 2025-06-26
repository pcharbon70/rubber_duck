defmodule RubberDuckStorage.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :string, primary_key: true
      add :role, :string, null: false, default: "user"
      add :content, :text, null: false
      add :content_type, :string, null: false, default: "text"
      add :metadata, :map, default: %{}
      add :timestamp, :utc_datetime, null: false
      add :conversation_id, references(:conversations, type: :string, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:conversation_id])
    create index(:messages, [:role])
    create index(:messages, [:content_type])
    create index(:messages, [:timestamp])
    create index(:messages, [:inserted_at])
  end
end