defmodule RubberDuckStorage.Schemas.Project do
  @moduledoc """
  Schema for projects - the top-level organizational unit for all data.

  Projects provide data segregation and organization for conversations,
  messages, engine sessions, and analysis results.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias RubberDuckStorage.Schemas.{Conversation, EngineSession, AnalysisResult}

  @primary_key {:id, :string, []}
  @foreign_key_type :string

  schema "projects" do
    field(:name, :string)
    field(:description, :string)
    field(:settings, :map, default: %{})
    field(:archived, :boolean, default: false)

    has_many(:conversations, Conversation, foreign_key: :project_id)
    has_many(:engine_sessions, EngineSession, foreign_key: :project_id)
    has_many(:analysis_results, AnalysisResult, foreign_key: :project_id)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:id, :name, :description, :settings, :archived])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 1000)
    |> unique_constraint(:id, name: :projects_pkey)
    |> unique_constraint(:name, name: :projects_name_index)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :description, :settings, :archived])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 1000)
    |> put_change(:id, attrs[:id] || generate_id())
    |> unique_constraint(:id, name: :projects_pkey)
    |> unique_constraint(:name, name: :projects_name_index)
  end

  @doc """
  Changeset for archiving a project.
  """
  def archive_changeset(project) do
    change(project, archived: true)
  end

  @doc """
  Changeset for updating project settings.
  """
  def settings_changeset(project, settings) when is_map(settings) do
    change(project, settings: settings)
  end

  defp generate_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end
