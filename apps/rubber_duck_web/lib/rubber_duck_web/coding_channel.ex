defmodule RubberDuckWeb.CodingChannel do
  @moduledoc """
  Phoenix Channel for coding assistant interactions.

  Handles real-time communication between clients and the RubberDuck
  coding assistant system, including conversation management and
  analysis requests.
  """

  use RubberDuckWeb, :channel

  alias RubberDuckCore.{ConversationManager, Message, PubSub}

  @impl true
  def join("coding:" <> conversation_id, payload, socket) do
    if authorized?(payload) do
      # Subscribe to conversation events
      PubSub.subscribe("conversation:#{conversation_id}")

      # Assign conversation ID to socket
      socket = assign(socket, :conversation_id, conversation_id)

      # Get or create conversation
      conversation = get_or_create_conversation(conversation_id)

      {:ok, %{conversation: conversation}, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Handle incoming messages from clients
  @impl true
  def handle_in("message", %{"content" => content, "type" => type}, socket)
      when is_binary(content) and is_binary(type) do
    conversation_id = socket.assigns.conversation_id
    user_id = socket.assigns.user_id

    # Create user message
    message =
      Message.user(content,
        content_type: String.to_existing_atom(type),
        metadata: %{user_id: user_id}
      )

    # Add to conversation
    case ConversationManager.add_message(ConversationManager, conversation_id, message) do
      {:ok, updated_conversation} ->
        # Broadcast to all clients in this conversation
        broadcast!(socket, "message", %{
          message: serialize_message(message),
          conversation: serialize_conversation(updated_conversation)
        })

        # Publish to core PubSub for processing
        PubSub.broadcast("conversation:#{conversation_id}", :message_added, %{
          conversation_id: conversation_id,
          message: message
        })

        {:reply, {:ok, %{message: serialize_message(message)}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("typing", %{"typing" => typing}, socket) do
    broadcast_from!(socket, "typing", %{
      user_id: socket.assigns.user_id,
      typing: typing
    })

    {:noreply, socket}
  end

  # Handle invalid message formats
  def handle_in("message", _invalid_payload, socket) do
    {:reply, {:error, %{reason: "invalid_message_format"}}, socket}
  end

  # Handle assistant responses from core system
  @impl true
  def handle_info({:pubsub_event, "conversation:" <> _conversation_id, event}, socket) do
    case event.type do
      :assistant_response ->
        push(socket, "assistant_response", %{
          message: serialize_message(event.data.message),
          analysis: event.data.analysis
        })

      :analysis_complete ->
        push(socket, "analysis_complete", %{
          analysis_id: event.data.analysis_id,
          result: event.data.result
        })

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  defp authorized?(_payload) do
    # TODO: Implement proper authorization
    # For now, allow all connections for development
    true
  end

  defp get_or_create_conversation(conversation_id) do
    case ConversationManager.get_conversation(ConversationManager, conversation_id) do
      {:ok, conversation} ->
        conversation

      {:error, :not_found} ->
        {:ok, conversation} =
          ConversationManager.create_conversation(ConversationManager,
            id: conversation_id,
            title: "WebSocket Conversation"
          )

        conversation
    end
  end

  defp serialize_message(%Message{} = message) do
    %{
      id: message.id,
      role: message.role,
      content: message.content,
      content_type: message.content_type,
      timestamp: DateTime.to_iso8601(message.timestamp),
      metadata: message.metadata
    }
  end

  defp serialize_conversation(conversation) do
    %{
      id: conversation.id,
      title: conversation.title,
      status: conversation.status,
      message_count: length(conversation.messages),
      updated_at: DateTime.to_iso8601(conversation.updated_at)
    }
  end
end
