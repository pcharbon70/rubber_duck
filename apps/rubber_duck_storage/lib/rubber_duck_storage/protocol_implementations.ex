defmodule RubberDuckStorage.ProtocolImplementations do
  @moduledoc """
  Protocol implementations for RubberDuckCore protocols in the storage layer.
  """

  alias RubberDuckCore.Protocols.{Serializable, Cacheable}
  alias RubberDuckStorage.Schemas.{Conversation, Message, EngineSession, AnalysisResult}

  # Serializable protocol implementation for Conversation
  defimpl Serializable, for: Conversation do
    def to_map(%Conversation{} = conversation) do
      %{
        id: conversation.id,
        title: conversation.title,
        status: conversation.status,
        context: conversation.context,
        messages: Enum.map(conversation.messages || [], &Serializable.to_map/1),
        inserted_at: conversation.inserted_at,
        updated_at: conversation.updated_at
      }
    end

    def from_map(map, _type) do
      %Conversation{
        id: map["id"] || map[:id],
        title: map["title"] || map[:title],
        status: String.to_existing_atom(map["status"] || map[:status] || "active"),
        context: map["context"] || map[:context] || %{},
        inserted_at: parse_datetime(map["inserted_at"] || map[:inserted_at]),
        updated_at: parse_datetime(map["updated_at"] || map[:updated_at])
      }
    end

    defp parse_datetime(nil), do: nil
    defp parse_datetime(dt) when is_binary(dt), do: DateTime.from_iso8601(dt) |> elem(1)
    defp parse_datetime(%DateTime{} = dt), do: dt
  end

  # Cacheable protocol implementation for Conversation
  defimpl Cacheable, for: Conversation do
    def cache_key(%Conversation{id: id}), do: "conversation:#{id}"
    # 1 hour
    def cache_ttl(_conversation), do: 3600
    def cacheable?(_conversation), do: true
  end

  # Serializable protocol implementation for Message
  defimpl Serializable, for: Message do
    def to_map(%Message{} = message) do
      %{
        id: message.id,
        role: message.role,
        content: message.content,
        content_type: message.content_type,
        metadata: message.metadata,
        timestamp: message.timestamp,
        conversation_id: message.conversation_id,
        inserted_at: message.inserted_at,
        updated_at: message.updated_at
      }
    end

    def from_map(map, _type) do
      %Message{
        id: map["id"] || map[:id],
        role: String.to_existing_atom(map["role"] || map[:role] || "user"),
        content: map["content"] || map[:content],
        content_type:
          String.to_existing_atom(map["content_type"] || map[:content_type] || "text"),
        metadata: map["metadata"] || map[:metadata] || %{},
        timestamp: parse_datetime(map["timestamp"] || map[:timestamp]),
        conversation_id: map["conversation_id"] || map[:conversation_id],
        inserted_at: parse_datetime(map["inserted_at"] || map[:inserted_at]),
        updated_at: parse_datetime(map["updated_at"] || map[:updated_at])
      }
    end

    defp parse_datetime(nil), do: nil
    defp parse_datetime(dt) when is_binary(dt), do: DateTime.from_iso8601(dt) |> elem(1)
    defp parse_datetime(%DateTime{} = dt), do: dt
  end

  # Cacheable protocol implementation for Message
  defimpl Cacheable, for: Message do
    def cache_key(%Message{id: id}), do: "message:#{id}"
    # 30 minutes
    def cache_ttl(_message), do: 1800
    # Don't cache error messages
    def cacheable?(%Message{content_type: :error}), do: false
    def cacheable?(_message), do: true
  end

  # Serializable protocol implementation for EngineSession
  defimpl Serializable, for: EngineSession do
    def to_map(%EngineSession{} = session) do
      %{
        id: session.id,
        engine_type: session.engine_type,
        engine_config: session.engine_config,
        status: session.status,
        started_at: session.started_at,
        completed_at: session.completed_at,
        error_message: session.error_message,
        metadata: session.metadata,
        conversation_id: session.conversation_id,
        analysis_results: Enum.map(session.analysis_results || [], &Serializable.to_map/1),
        inserted_at: session.inserted_at,
        updated_at: session.updated_at
      }
    end

    def from_map(map, _type) do
      %EngineSession{
        id: map["id"] || map[:id],
        engine_type: map["engine_type"] || map[:engine_type],
        engine_config: map["engine_config"] || map[:engine_config] || %{},
        status: String.to_existing_atom(map["status"] || map[:status] || "pending"),
        started_at: parse_datetime(map["started_at"] || map[:started_at]),
        completed_at: parse_datetime(map["completed_at"] || map[:completed_at]),
        error_message: map["error_message"] || map[:error_message],
        metadata: map["metadata"] || map[:metadata] || %{},
        conversation_id: map["conversation_id"] || map[:conversation_id],
        inserted_at: parse_datetime(map["inserted_at"] || map[:inserted_at]),
        updated_at: parse_datetime(map["updated_at"] || map[:updated_at])
      }
    end

    defp parse_datetime(nil), do: nil
    defp parse_datetime(dt) when is_binary(dt), do: DateTime.from_iso8601(dt) |> elem(1)
    defp parse_datetime(%DateTime{} = dt), do: dt
  end

  # Cacheable protocol implementation for EngineSession
  defimpl Cacheable, for: EngineSession do
    def cache_key(%EngineSession{id: id}), do: "engine_session:#{id}"
    # 5 minutes for running sessions
    def cache_ttl(%EngineSession{status: :running}), do: 300
    # 10 minutes for pending sessions
    def cache_ttl(%EngineSession{status: :pending}), do: 600
    # 30 minutes for completed/failed sessions
    def cache_ttl(_session), do: 1800
    def cacheable?(_session), do: true
  end

  # Serializable protocol implementation for AnalysisResult
  defimpl Serializable, for: AnalysisResult do
    def to_map(%AnalysisResult{} = result) do
      %{
        id: result.id,
        result_type: result.result_type,
        content: result.content,
        confidence: result.confidence,
        metadata: result.metadata,
        tags: result.tags,
        engine_session_id: result.engine_session_id,
        inserted_at: result.inserted_at,
        updated_at: result.updated_at
      }
    end

    def from_map(map, _type) do
      %AnalysisResult{
        id: map["id"] || map[:id],
        result_type: map["result_type"] || map[:result_type],
        content: map["content"] || map[:content],
        confidence: map["confidence"] || map[:confidence],
        metadata: map["metadata"] || map[:metadata] || %{},
        tags: map["tags"] || map[:tags] || [],
        engine_session_id: map["engine_session_id"] || map[:engine_session_id],
        inserted_at: parse_datetime(map["inserted_at"] || map[:inserted_at]),
        updated_at: parse_datetime(map["updated_at"] || map[:updated_at])
      }
    end

    defp parse_datetime(nil), do: nil
    defp parse_datetime(dt) when is_binary(dt), do: DateTime.from_iso8601(dt) |> elem(1)
    defp parse_datetime(%DateTime{} = dt), do: dt
  end

  # Cacheable protocol implementation for AnalysisResult
  defimpl Cacheable, for: AnalysisResult do
    def cache_key(%AnalysisResult{id: id}), do: "analysis_result:#{id}"
    # 2 hours for high confidence
    def cache_ttl(%AnalysisResult{confidence: confidence}) when confidence >= 0.8, do: 7200
    # 30 minutes for lower confidence
    def cache_ttl(_result), do: 1800
    # Don't cache low confidence results
    def cacheable?(%AnalysisResult{confidence: confidence}) when confidence < 0.3, do: false
    def cacheable?(_result), do: true
  end
end
