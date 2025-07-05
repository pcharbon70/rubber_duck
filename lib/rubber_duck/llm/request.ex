defmodule RubberDuck.LLM.Request do
  @moduledoc """
  Represents an LLM completion request.
  """
  
  @type status :: :pending | :processing | :completed | :failed
  @type priority :: :high | :normal | :low
  
  @type t :: %__MODULE__{
    id: String.t() | nil,
    model: String.t(),
    provider: atom(),
    messages: list(map()),
    options: map(),
    timestamp: DateTime.t(),
    status: status(),
    retries: non_neg_integer(),
    from: GenServer.from() | nil,
    async: boolean(),
    response: any(),
    error: any()
  }
  
  defstruct [
    :id,
    :model,
    :provider,
    :messages,
    :options,
    :timestamp,
    :from,
    status: :pending,
    retries: 0,
    async: false,
    response: nil,
    error: nil
  ]
  
  @doc """
  Creates a new request with the given attributes.
  """
  def new(attrs) do
    struct(__MODULE__, attrs)
  end
  
  @doc """
  Checks if the request has exceeded max retries.
  """
  def max_retries_exceeded?(%__MODULE__{retries: retries}, max_retries) do
    retries >= max_retries
  end
  
  @doc """
  Increments the retry count.
  """
  def increment_retries(%__MODULE__{retries: retries} = request) do
    %{request | retries: retries + 1}
  end
  
  @doc """
  Marks the request as processing.
  """
  def mark_processing(%__MODULE__{} = request) do
    %{request | status: :processing}
  end
  
  @doc """
  Marks the request as completed with a response.
  """
  def mark_completed(%__MODULE__{} = request, response) do
    %{request | 
      status: :completed,
      response: response
    }
  end
  
  @doc """
  Marks the request as failed with an error.
  """
  def mark_failed(%__MODULE__{} = request, error) do
    %{request | 
      status: :failed,
      error: error
    }
  end
end