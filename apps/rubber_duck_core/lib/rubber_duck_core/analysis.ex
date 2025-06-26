defmodule RubberDuckCore.Analysis do
  @moduledoc """
  Core analysis domain for the RubberDuck system.
  
  This module defines the analysis data structures and operations
  used by various analysis engines in the system.
  """

  @type id :: String.t()
  @type status :: :pending | :running | :completed | :failed
  @type analysis_type :: :code_review | :security | :performance | :documentation | :testing

  @type t :: %__MODULE__{
    id: id(),
    type: analysis_type(),
    status: status(),
    input: map(),
    result: map() | nil,
    error: String.t() | nil,
    engine: atom(),
    conversation_id: String.t() | nil,
    created_at: DateTime.t(),
    completed_at: DateTime.t() | nil
  }

  defstruct [
    :id,
    :type,
    :status,
    :input,
    :result,
    :error,
    :engine,
    :conversation_id,
    :created_at,
    :completed_at
  ]

  @doc """
  Creates a new analysis with the given parameters.
  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) do
    %__MODULE__{
      id: Keyword.get(attrs, :id, generate_id()),
      type: Keyword.get(attrs, :type, :code_review),
      status: Keyword.get(attrs, :status, :pending),
      input: Keyword.get(attrs, :input, %{}),
      result: Keyword.get(attrs, :result),
      error: Keyword.get(attrs, :error),
      engine: Keyword.get(attrs, :engine),
      conversation_id: Keyword.get(attrs, :conversation_id),
      created_at: Keyword.get(attrs, :created_at, DateTime.utc_now()),
      completed_at: Keyword.get(attrs, :completed_at)
    }
  end

  @doc """
  Marks an analysis as running.
  """
  @spec start(t()) :: t()
  def start(%__MODULE__{} = analysis) do
    %{analysis | status: :running}
  end

  @doc """
  Marks an analysis as completed with a result.
  """
  @spec complete(t(), map()) :: t()
  def complete(%__MODULE__{} = analysis, result) do
    %{analysis | 
      status: :completed,
      result: result,
      completed_at: DateTime.utc_now()
    }
  end

  @doc """
  Marks an analysis as failed with an error.
  """
  @spec fail(t(), String.t()) :: t()
  def fail(%__MODULE__{} = analysis, error) do
    %{analysis | 
      status: :failed,
      error: error,
      completed_at: DateTime.utc_now()
    }
  end

  defp generate_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end