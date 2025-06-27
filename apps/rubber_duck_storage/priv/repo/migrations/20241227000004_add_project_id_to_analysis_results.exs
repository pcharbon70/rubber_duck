defmodule RubberDuckStorage.Repo.Migrations.AddProjectIdToAnalysisResults do
  use Ecto.Migration

  def change do
    alter table(:analysis_results) do
      add :project_id, references(:projects, type: :string, on_delete: :delete_all), null: true
    end

    create index(:analysis_results, [:project_id])
  end
end