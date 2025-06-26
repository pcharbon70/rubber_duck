defmodule RubberDuckStorage.Schemas.EngineSession do
  use Ecto.Schema
  import Ecto.Changeset

  alias RubberDuckStorage.Schemas.{Conversation, AnalysisResult}

  @primary_key {:id, :string, []}
  @foreign_key_type :string

  schema "engine_sessions" do
    field :engine_type, :string
    field :engine_config, :map, default: %{}
    field :status, Ecto.Enum, values: [:pending, :running, :completed, :failed], default: :pending
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :error_message, :string
    field :metadata, :map, default: %{}

    belongs_to :conversation, Conversation, foreign_key: :conversation_id, type: :string
    has_many :analysis_results, AnalysisResult, foreign_key: :engine_session_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(engine_session, attrs) do
    engine_session
    |> cast(attrs, [:id, :engine_type, :engine_config, :status, :started_at, :completed_at, :error_message, :metadata, :conversation_id])
    |> validate_required([:id, :engine_type, :conversation_id])
    |> validate_inclusion(:status, [:pending, :running, :completed, :failed])
    |> foreign_key_constraint(:conversation_id)
    |> unique_constraint(:id, name: :engine_sessions_pkey)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> put_change(:id, attrs[:id] || generate_id())
  end

  def start_changeset(engine_session) do
    engine_session
    |> change(status: :running, started_at: DateTime.utc_now())
  end

  def complete_changeset(engine_session) do
    engine_session
    |> change(status: :completed, completed_at: DateTime.utc_now())
  end

  def fail_changeset(engine_session, error_message) do
    engine_session
    |> change(status: :failed, completed_at: DateTime.utc_now(), error_message: error_message)
  end

  defp generate_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end