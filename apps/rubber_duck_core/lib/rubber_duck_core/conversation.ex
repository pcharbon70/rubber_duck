defmodule RubberDuckCore.Conversation do
  @moduledoc """
  Core conversation management for the RubberDuck system.
  
  This module defines the conversation domain logic and data structures
  used throughout the system for managing coding assistant interactions.
  """

  @type id :: String.t()
  @type status :: :active | :paused | :completed | :archived

  @type t :: %__MODULE__{
    id: id(),
    title: String.t() | nil,
    status: status(),
    messages: [RubberDuckCore.Message.t()],
    context: map(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  defstruct [
    :id,
    :title,
    :status,
    :messages,
    :context,
    :created_at,
    :updated_at
  ]

  @doc """
  Creates a new conversation with the given parameters.
  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) do
    now = DateTime.utc_now()
    
    %__MODULE__{
      id: Keyword.get(attrs, :id, generate_id()),
      title: Keyword.get(attrs, :title),
      status: Keyword.get(attrs, :status, :active),
      messages: Keyword.get(attrs, :messages, []),
      context: Keyword.get(attrs, :context, %{}),
      created_at: Keyword.get(attrs, :created_at, now),
      updated_at: Keyword.get(attrs, :updated_at, now)
    }
  end

  @doc """
  Adds a message to the conversation.
  """
  @spec add_message(t(), RubberDuckCore.Message.t()) :: t()
  def add_message(%__MODULE__{} = conversation, message) do
    %{conversation | 
      messages: conversation.messages ++ [message],
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Updates the conversation status.
  """
  @spec update_status(t(), status()) :: t()
  def update_status(%__MODULE__{} = conversation, status) when status in [:active, :paused, :completed, :archived] do
    %{conversation | 
      status: status,
      updated_at: DateTime.utc_now()
    }
  end

  defp generate_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end