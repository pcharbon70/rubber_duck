defmodule RubberDuckStorage.Repos.ConversationRepo do
  @moduledoc """
  Repository for managing conversation persistence operations.
  """

  import Ecto.Query, warn: false
  alias RubberDuckStorage.Repo
  alias RubberDuckStorage.Schemas.Conversation
  alias RubberDuckCore.Conversation, as: CoreConversation

  @doc """
  Gets a single conversation by id.
  """
  def get(id) do
    Repo.get(Conversation, id)
  end

  @doc """
  Gets a single conversation by id, raising if not found.
  """
  def get!(id) do
    Repo.get!(Conversation, id)
  end

  @doc """
  Gets a conversation with its messages preloaded.
  """
  def get_with_messages(id) do
    Conversation
    |> where([c], c.id == ^id)
    |> preload(:messages)
    |> Repo.one()
  end

  @doc """
  Lists all conversations with optional filtering.
  """
  def list(opts \\ []) do
    query = from(c in Conversation)

    query
    |> maybe_filter_by_status(opts[:status])
    |> maybe_limit(opts[:limit])
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Creates a conversation from a RubberDuckCore.Conversation struct.
  """
  def create(%CoreConversation{} = core_conversation) do
    attrs = %{
      id: core_conversation.id,
      title: core_conversation.title,
      status: core_conversation.status,
      context: core_conversation.context
    }

    %Conversation{}
    |> Conversation.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a conversation from attributes.
  """
  def create(attrs) when is_map(attrs) do
    %Conversation{}
    |> Conversation.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a conversation.
  """
  def update(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a conversation by id.
  """
  def update(id, attrs) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      conversation -> update(conversation, attrs)
    end
  end

  @doc """
  Deletes a conversation.
  """
  def delete(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  @doc """
  Deletes a conversation by id.
  """
  def delete(id) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      conversation -> delete(conversation)
    end
  end

  @doc """
  Archives a conversation (sets status to :archived).
  """
  def archive(id) when is_binary(id) do
    update(id, %{status: :archived})
  end

  @doc """
  Gets conversations that have been updated recently.
  """
  def get_recent(hours \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours, :hour)

    from(c in Conversation,
      where: c.updated_at >= ^cutoff,
      order_by: [desc: c.updated_at]
    )
    |> Repo.all()
  end

  defp maybe_filter_by_status(query, nil), do: query
  defp maybe_filter_by_status(query, status) do
    from(c in query, where: c.status == ^status)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) do
    from(c in query, limit: ^limit)
  end
end