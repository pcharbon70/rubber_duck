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
  def create(%CoreMessage{} = core_message, conversation_id) do
    attrs = %{
      id: core_message.id,
      role: core_message.role,
      content: core_message.content,
      content_type: core_message.content_type,
      metadata: core_message.metadata,
      timestamp: core_message.timestamp,
      conversation_id: conversation_id
    }

    %Message{}
    |> Message.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a message from attributes.
  """
  def create(attrs) when is_map(attrs) do
    %Message{}
    |> Message.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates multiple messages in a single transaction (batching).
  """
  def create_batch(messages_attrs) when is_list(messages_attrs) do
    Repo.transaction(fn ->
      Enum.map(messages_attrs, fn attrs ->
        case create(attrs) do
          {:ok, message} -> message
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Creates multiple messages from CoreMessage structs.
  """
  def create_batch_from_core(core_messages, conversation_id) when is_list(core_messages) do
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

    create_batch(messages_attrs)
  end

  @doc """
  Updates a message.
  """
  def update(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a message by id.
  """
  def update(id, attrs) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      message -> update(message, attrs)
    end
  end

  @doc """
  Deletes a message.
  """
  def delete(%Message{} = message) do
    Repo.delete(message)
  end

  @doc """
  Deletes a message by id.
  """
  def delete(id) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      message -> delete(message)
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