defmodule RubberDuckStorage.Schemas.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias RubberDuckStorage.Schemas.{Message, Project}

  @primary_key {:id, :string, []}
  @foreign_key_type :string

  schema "conversations" do
    field :title, :string
    field :status, Ecto.Enum, values: [:active, :paused, :completed, :archived], default: :active
    field :context, :map, default: %{}
    
    belongs_to :project, Project, foreign_key: :project_id, type: :string
    has_many :messages, Message, foreign_key: :conversation_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:id, :title, :status, :context, :project_id])
    |> validate_required([:id, :status, :project_id])
    |> validate_inclusion(:status, [:active, :paused, :completed, :archived])
    |> foreign_key_constraint(:project_id)
    |> unique_constraint(:id, name: :conversations_pkey)
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