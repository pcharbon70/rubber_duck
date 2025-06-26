defmodule RubberDuckCore.Event do
  @moduledoc """
  Core event structure for the RubberDuck system.
  
  Events are used for inter-app communication and system-wide notifications.
  """

  @type id :: String.t()
  @type event_type :: atom()
  @type source :: atom()

  @type t :: %__MODULE__{
    id: id(),
    type: event_type(),
    source: source(),
    data: map(),
    correlation_id: String.t() | nil,
    timestamp: DateTime.t(),
    metadata: map()
  }

  defstruct [
    :id,
    :type,
    :source,
    :data,
    :correlation_id,
    :timestamp,
    :metadata
  ]

  @doc """
  Creates a new event with the given parameters.
  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) do
    %__MODULE__{
      id: Keyword.get(attrs, :id, generate_id()),
      type: Keyword.get(attrs, :type),
      source: Keyword.get(attrs, :source),
      data: Keyword.get(attrs, :data, %{}),
      correlation_id: Keyword.get(attrs, :correlation_id),
      timestamp: Keyword.get(attrs, :timestamp, DateTime.utc_now()),
      metadata: Keyword.get(attrs, :metadata, %{})
    }
  end

  @doc """
  Creates a conversation event.
  """
  @spec conversation_event(atom(), map(), keyword()) :: t()
  def conversation_event(type, data, opts \\ []) do
    opts
    |> Keyword.put(:type, type)
    |> Keyword.put(:source, :conversation)
    |> Keyword.put(:data, data)
    |> new()
  end

  @doc """
  Creates an analysis event.
  """
  @spec analysis_event(atom(), map(), keyword()) :: t()
  def analysis_event(type, data, opts \\ []) do
    opts
    |> Keyword.put(:type, type)
    |> Keyword.put(:source, :analysis)
    |> Keyword.put(:data, data)
    |> new()
  end

  @doc """
  Creates a system event.
  """
  @spec system_event(atom(), map(), keyword()) :: t()
  def system_event(type, data, opts \\ []) do
    opts
    |> Keyword.put(:type, type)
    |> Keyword.put(:source, :system)
    |> Keyword.put(:data, data)
    |> new()
  end

  defp generate_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end