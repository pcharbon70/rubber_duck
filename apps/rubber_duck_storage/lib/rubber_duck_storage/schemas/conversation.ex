defmodule RubberDuckStorage.Schemas.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias RubberDuckStorage.Schemas.Message

  @primary_key {:id, :string, []}
  @foreign_key_type :string

  schema "conversations" do
    field :title, :string
    field :status, Ecto.Enum, values: [:active, :paused, :completed, :archived], default: :active
    field :context, :map, default: %{}
    
    has_many :messages, Message, foreign_key: :conversation_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:id, :title, :status, :context])
    |> validate_required([:id, :status])
    |> validate_inclusion(:status, [:active, :paused, :completed, :archived])
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