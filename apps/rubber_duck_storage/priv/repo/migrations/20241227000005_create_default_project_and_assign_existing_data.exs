defmodule RubberDuckStorage.Repo.Migrations.CreateDefaultProjectAndAssignExistingData do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Create default project
    default_project_id = "default"
    default_project_name = "Default Project"
    
    execute("""
      INSERT INTO projects (id, name, description, settings, archived, inserted_at, updated_at)
      VALUES ('#{default_project_id}', '#{default_project_name}', 'Default project for existing data', '{}', false, NOW(), NOW())
    """)

    # Assign all existing conversations to default project
    execute("""
      UPDATE conversations 
      SET project_id = '#{default_project_id}' 
      WHERE project_id IS NULL
    """)

    # Assign all existing engine sessions to default project
    execute("""
      UPDATE engine_sessions 
      SET project_id = '#{default_project_id}' 
      WHERE project_id IS NULL
    """)

    # Assign all existing analysis results to default project
    execute("""
      UPDATE analysis_results 
      SET project_id = '#{default_project_id}' 
      WHERE project_id IS NULL
    """)

    # Now make project_id NOT NULL after assigning values
    alter table(:conversations) do
      modify :project_id, :string, null: false
    end

    alter table(:engine_sessions) do
      modify :project_id, :string, null: false
    end

    alter table(:analysis_results) do
      modify :project_id, :string, null: false
    end
  end

  def down do
    # Allow NULLs again
    alter table(:conversations) do
      modify :project_id, :string, null: true
    end

    alter table(:engine_sessions) do
      modify :project_id, :string, null: true
    end

    alter table(:analysis_results) do
      modify :project_id, :string, null: true
    end

    # Remove default project (this will cascade delete all related data)
    execute("DELETE FROM projects WHERE id = 'default'")
  end
end