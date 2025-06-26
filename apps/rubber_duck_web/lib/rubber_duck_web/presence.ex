defmodule RubberDuckWeb.Presence do
  @moduledoc """
  Provides presence tracking for users connected to coding channels.
  
  This module tracks which users are actively connected to conversations
  and provides real-time updates when users join or leave.
  """

  use Phoenix.Presence,
    otp_app: :rubber_duck_web,
    pubsub_server: RubberDuckWeb.PubSub

  @doc """
  Tracks a user's presence in a conversation.
  """
  def track_user(socket, user_id, metadata \\ %{}) do
    track(socket, user_id, %{
      online_at: inspect(System.system_time(:second)),
      client_type: Map.get(metadata, "client_type", "web"),
      user_agent: Map.get(metadata, "user_agent", "unknown")
    })
  end

  @doc """
  Gets all users present in a conversation.
  """
  def list_users(conversation_id) do
    list("conversation:#{conversation_id}")
  end

  @doc """
  Gets the count of users in a conversation.
  """
  def user_count(conversation_id) do
    conversation_id
    |> list_users()
    |> map_size()
  end

  @doc """
  Updates user metadata (e.g., typing status).
  """
  def update_user(socket, user_id, metadata) do
    update(socket, user_id, fn current_meta ->
      Map.merge(current_meta, metadata)
    end)
  end
end