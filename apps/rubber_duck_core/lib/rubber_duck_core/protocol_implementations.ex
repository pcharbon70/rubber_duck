defmodule RubberDuckCore.ProtocolImplementations do
  @moduledoc """
  Protocol implementations for core RubberDuck data structures.
  """

  alias RubberDuckCore.{Conversation, Message, Analysis}
  alias RubberDuckCore.Protocols.{Serializable, Cacheable, Analyzable}

  # Serializable implementations

  defimpl Serializable, for: Conversation do
    def to_map(%Conversation{} = conversation) do
      %{
        id: conversation.id,
        title: conversation.title,
        status: conversation.status,
        messages: Enum.map(conversation.messages, &Serializable.to_map/1),
        context: conversation.context,
        created_at: DateTime.to_iso8601(conversation.created_at),
        updated_at: DateTime.to_iso8601(conversation.updated_at)
      }
    end

    def from_map(map, _type) do
      {:ok, created_at} = DateTime.from_iso8601(map["created_at"])
      {:ok, updated_at} = DateTime.from_iso8601(map["updated_at"])
      
      messages = Enum.map(map["messages"] || [], fn msg_map ->
        Serializable.from_map(msg_map, Message)
      end)

      %Conversation{
        id: map["id"],
        title: map["title"],
        status: String.to_existing_atom(map["status"]),
        messages: messages,
        context: map["context"] || %{},
        created_at: created_at,
        updated_at: updated_at
      }
    end
  end

  defimpl Serializable, for: Message do
    def to_map(%Message{} = message) do
      %{
        id: message.id,
        role: message.role,
        content: message.content,
        content_type: message.content_type,
        metadata: message.metadata,
        timestamp: DateTime.to_iso8601(message.timestamp)
      }
    end

    def from_map(map, _type) do
      {:ok, timestamp} = DateTime.from_iso8601(map["timestamp"])
      
      %Message{
        id: map["id"],
        role: String.to_existing_atom(map["role"]),
        content: map["content"],
        content_type: String.to_existing_atom(map["content_type"]),
        metadata: map["metadata"] || %{},
        timestamp: timestamp
      }
    end
  end

  # Cacheable implementations

  defimpl Cacheable, for: Conversation do
    def cache_key(%Conversation{id: id}), do: "conversation:#{id}"
    def cache_ttl(_conversation), do: 3600  # 1 hour
    def cacheable?(%Conversation{status: :archived}), do: false
    def cacheable?(_conversation), do: true
  end

  defimpl Cacheable, for: Analysis do
    def cache_key(%Analysis{id: id}), do: "analysis:#{id}"
    def cache_ttl(_analysis), do: 1800  # 30 minutes
    def cacheable?(%Analysis{status: :completed}), do: true
    def cacheable?(_analysis), do: false
  end

  # Analyzable implementations

  defimpl Analyzable, for: Message do
    def analysis_type(%Message{content_type: :code}), do: :code_analysis
    def analysis_type(%Message{content_type: :error}), do: :error_analysis
    def analysis_type(_message), do: :content_analysis

    def extract_content(%Message{content: content}), do: content

    def analysis_metadata(%Message{} = message) do
      %{
        role: message.role,
        content_type: message.content_type,
        timestamp: message.timestamp,
        metadata: message.metadata
      }
    end
  end

  defimpl Analyzable, for: Conversation do
    def analysis_type(_conversation), do: :conversation_analysis

    def extract_content(%Conversation{messages: messages}) do
      messages
      |> Enum.map(&Analyzable.extract_content/1)
      |> Enum.join("\n")
    end

    def analysis_metadata(%Conversation{} = conversation) do
      %{
        id: conversation.id,
        title: conversation.title,
        status: conversation.status,
        message_count: length(conversation.messages),
        created_at: conversation.created_at,
        updated_at: conversation.updated_at
      }
    end
  end
end