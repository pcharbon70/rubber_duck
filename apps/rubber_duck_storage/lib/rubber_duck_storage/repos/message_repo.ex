defmodule RubberDuckStorage.Repos.MessageRepo do
  @moduledoc """
  Repository for managing message persistence operations with batching support.
  """

  import Ecto.Query, warn: false
  alias RubberDuckStorage.Repo
  alias RubberDuckStorage.Schemas.Message
  alias RubberDuckCore.Message, as: CoreMessage

  @doc """
  Gets a single message by id.
  """
  def get(id) do
    Repo.get(Message, id)
  end

  @doc """
  Gets a single message by id, raising if not found.
  """
  def get!(id) do
    Repo.get!(Message, id)
  end

  @doc """
  Lists messages for a conversation.
  """
  def list_for_conversation(conversation_id, opts \\ []) do
    query = from(m in Message, where: m.conversation_id == ^conversation_id)

    query
    |> maybe_filter_by_role(opts[:role])
    |> maybe_filter_by_content_type(opts[:content_type])
    |> maybe_limit(opts[:limit])
    |> order_by([m], asc: m.timestamp)
    |> Repo.all()
  end

  @doc """
  Creates a message from a RubberDuckCore.Message struct.
  """
  def add(%CoreMessage{} = core_message, conversation_id) do
    attrs = %{
      id: core_message.id,
      role: core_message.role,
      content: core_message.content,
      content_type: core_message.content_type,
      metadata: core_message.metadata,
      timestamp: core_message.timestamp,
      conversation_id: conversation_id
    }

    Message.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a message from attributes.
  """
  def add(attrs) when is_map(attrs) do
    Message.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates multiple messages in a single transaction (batching).
  """
  def add_batch(messages_attrs) when is_list(messages_attrs) do
    Repo.transaction(fn ->
      Enum.map(messages_attrs, fn attrs ->
        case add(attrs) do
          {:ok, message} -> message
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Creates multiple messages from CoreMessage structs.
  """
  def add_batch_from_core(core_messages, conversation_id) when is_list(core_messages) do
    messages_attrs = 
      Enum.map(core_messages, fn core_message ->
        %{
          id: core_message.id,
          role: core_message.role,
          content: core_message.content,
          content_type: core_message.content_type,
          metadata: core_message.metadata,
          timestamp: core_message.timestamp,
          conversation_id: conversation_id
        }
      end)

    add_batch(messages_attrs)
  end

  @doc """
  Changes a message by struct or id.
  """
  def change(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
  end

  def change(id, attrs) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      message -> change(message, attrs)
    end
  end

  @doc """
  Removes a message by struct or id.
  """
  def remove(%Message{} = message) do
    Repo.delete(message)
  end

  def remove(id) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      message -> remove(message)
    end
  end

  @doc """
  Gets the latest message for a conversation.
  """
  def get_latest_for_conversation(conversation_id) do
    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      order_by: [desc: m.timestamp],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Counts messages for a conversation.
  """
  def count_for_conversation(conversation_id) do
    from(m in Message, where: m.conversation_id == ^conversation_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets messages by content type for analysis purposes.
  """
  def get_by_content_type(content_type, opts \\ []) do
    query = from(m in Message, where: m.content_type == ^content_type)

    query
    |> maybe_limit(opts[:limit])
    |> order_by([m], desc: m.timestamp)
    |> Repo.all()
  end

  defp maybe_filter_by_role(query, nil), do: query
  defp maybe_filter_by_role(query, role) do
    from(m in query, where: m.role == ^role)
  end

  defp maybe_filter_by_content_type(query, nil), do: query
  defp maybe_filter_by_content_type(query, content_type) do
    from(m in query, where: m.content_type == ^content_type)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) do
    from(m in query, limit: ^limit)
  end
end