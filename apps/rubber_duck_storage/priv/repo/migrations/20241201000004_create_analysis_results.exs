defmodule RubberDuckStorage.Repo.Migrations.CreateAnalysisResults do
  use Ecto.Migration

  def change do
    create table(:analysis_results, primary_key: false) do
      add :id, :string, primary_key: true
      add :result_type, :string, null: false
      add :content, :map, null: false
      add :confidence, :float
      add :metadata, :map, default: %{}
      add :tags, {:array, :string}, default: []
      add :engine_session_id, references(:engine_sessions, type: :string, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:analysis_results, [:engine_session_id])
    create index(:analysis_results, [:result_type])
    create index(:analysis_results, [:confidence])
    create index(:analysis_results, [:tags], using: :gin)
    create index(:analysis_results, [:inserted_at])
  end
end