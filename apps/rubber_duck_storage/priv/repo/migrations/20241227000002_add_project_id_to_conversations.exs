defmodule RubberDuckStorage.Repo.Migrations.AddProjectIdToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :project_id, references(:projects, type: :string, on_delete: :delete_all), null: true
    end

    create index(:conversations, [:project_id])
  end
end