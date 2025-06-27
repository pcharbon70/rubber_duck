defmodule RubberDuckStorage.Schemas.AnalysisResult do
  use Ecto.Schema
  import Ecto.Changeset

  alias RubberDuckStorage.Schemas.{EngineSession, Project}

  @primary_key {:id, :string, []}
  @foreign_key_type :string

  schema "analysis_results" do
    field(:result_type, :string)
    field(:content, :map)
    field(:confidence, :float)
    field(:metadata, :map, default: %{})
    field(:tags, {:array, :string}, default: [])

    belongs_to(:project, Project, foreign_key: :project_id, type: :string)
    belongs_to(:engine_session, EngineSession, foreign_key: :engine_session_id, type: :string)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(analysis_result, attrs) do
    analysis_result
    |> cast(attrs, [
      :id,
      :result_type,
      :content,
      :confidence,
      :metadata,
      :tags,
      :project_id,
      :engine_session_id
    ])
    |> validate_required([:id, :result_type, :content, :project_id, :engine_session_id])
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:engine_session_id)
    |> unique_constraint(:id, name: :analysis_results_pkey)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> put_change(:id, attrs[:id] || generate_id())
  end

  defp generate_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end
