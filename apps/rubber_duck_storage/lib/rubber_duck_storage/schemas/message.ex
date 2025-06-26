defmodule RubberDuckStorage.Schemas.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias RubberDuckStorage.Schemas.Conversation

  @primary_key {:id, :string, []}
  @foreign_key_type :string

  schema "messages" do
    field :role, Ecto.Enum, values: [:user, :assistant, :system], default: :user
    field :content, :string
    field :content_type, Ecto.Enum, values: [:text, :code, :error, :analysis], default: :text
    field :metadata, :map, default: %{}
    field :timestamp, :utc_datetime

    belongs_to :conversation, Conversation, foreign_key: :conversation_id, type: :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:id, :role, :content, :content_type, :metadata, :timestamp, :conversation_id])
    |> validate_required([:id, :role, :content, :content_type, :conversation_id])
    |> validate_inclusion(:role, [:user, :assistant, :system])
    |> validate_inclusion(:content_type, [:text, :code, :error, :analysis])
    |> foreign_key_constraint(:conversation_id)
    |> unique_constraint(:id, name: :messages_pkey)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> put_change(:id, attrs[:id] || generate_id())
    |> put_change(:timestamp, attrs[:timestamp] || DateTime.utc_now())
  end

  defp generate_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end