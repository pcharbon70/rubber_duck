defmodule RubberDuckCore.Message do
  @moduledoc """
  Core message structure for the RubberDuck system.

  This module defines the message data structure used in conversations
  between users and the coding assistant.
  """

  @type id :: String.t()
  @type role :: :user | :assistant | :system
  @type content_type :: :text | :code | :error | :analysis

  @type t :: %__MODULE__{
          id: id(),
          role: role(),
          content: String.t(),
          content_type: content_type(),
          metadata: map(),
          timestamp: DateTime.t()
        }

  defstruct [
    :id,
    :role,
    :content,
    :content_type,
    :metadata,
    :timestamp
  ]

  @doc """
  Creates a new message with the given parameters.
  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) do
    %__MODULE__{
      id: Keyword.get(attrs, :id, generate_id()),
      role: Keyword.get(attrs, :role, :user),
      content: Keyword.get(attrs, :content, ""),
      content_type: Keyword.get(attrs, :content_type, :text),
      metadata: Keyword.get(attrs, :metadata, %{}),
      timestamp: Keyword.get(attrs, :timestamp, DateTime.utc_now())
    }
  end

  @doc """
  Creates a user message.
  """
  @spec user(String.t(), keyword()) :: t()
  def user(content, opts \\ []) do
    opts
    |> Keyword.put(:role, :user)
    |> Keyword.put(:content, content)
    |> new()
  end

  @doc """
  Creates an assistant message.
  """
  @spec assistant(String.t(), keyword()) :: t()
  def assistant(content, opts \\ []) do
    opts
    |> Keyword.put(:role, :assistant)
    |> Keyword.put(:content, content)
    |> new()
  end

  @doc """
  Creates a system message.
  """
  @spec system(String.t(), keyword()) :: t()
  def system(content, opts \\ []) do
    opts
    |> Keyword.put(:role, :system)
    |> Keyword.put(:content, content)
    |> new()
  end

  defp generate_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end
