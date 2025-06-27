defmodule RubberDuck do
  @moduledoc """
  Main entry point for the RubberDuck coding assistant system.

  This module provides the primary interface for interacting with the
  RubberDuck system, preserving the original API while delegating to
  the enhanced core functionality.
  """

  alias RubberDuckCore.{ConversationManager, PubSub}

  @doc """
  Hello world - preserved from original implementation.

  ## Examples

      iex> RubberDuck.hello()
      :world

  """
  def hello do
    :world
  end

  @doc """
  Creates a new conversation using the core conversation manager.

  ## Examples

      iex> {:ok, conversation} = RubberDuck.start_conversation()
      iex> conversation.status
      :active
  """
  def start_conversation(attrs \\ []) do
    ConversationManager.create_conversation(ConversationManager, attrs)
  end

  @doc """
  Subscribes to system events.

  ## Examples

      iex> RubberDuck.subscribe("conversations")
      :ok
  """
  def subscribe(topic) do
    PubSub.subscribe(topic)
  end

  @doc """
  Publishes a system event.
  """
  def broadcast(topic, event_type, data) do
    PubSub.broadcast(topic, event_type, data)
  end
end
