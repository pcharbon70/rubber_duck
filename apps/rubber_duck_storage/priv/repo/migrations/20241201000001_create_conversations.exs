defmodule RubberDuckStorage.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :string, primary_key: true
      add :title, :string
      add :status, :string, null: false, default: "active"
      add :context, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:status])
    create index(:conversations, [:inserted_at])
    create index(:conversations, [:updated_at])
  end
end