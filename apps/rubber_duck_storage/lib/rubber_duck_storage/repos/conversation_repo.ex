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
  Adds a conversation from a RubberDuckCore.Conversation struct or attributes.
  """
  def add(%CoreConversation{} = core_conversation) do
    attrs = %{
      id: core_conversation.id,
      title: core_conversation.title,
      status: core_conversation.status,
      context: core_conversation.context
    }

    Conversation.create_changeset(attrs)
    |> Repo.insert()
  end

  def add(attrs) when is_map(attrs) do
    Conversation.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Changes a conversation by struct or id.
  """
  def change(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  def change(id, attrs) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      conversation -> change(conversation, attrs)
    end
  end

  @doc """
  Removes a conversation by struct or id.
  """
  def remove(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  def remove(id) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      conversation -> remove(conversation)
    end
  end

  @doc """
  Archives a conversation (sets status to :archived).
  """
  def archive(id) when is_binary(id) do
    change(id, %{status: :archived})
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