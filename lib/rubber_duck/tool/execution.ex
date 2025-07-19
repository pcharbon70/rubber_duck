defmodule RubberDuck.Tool.Execution do
  @moduledoc """
  Represents tool execution configuration.
  """

  defstruct [
    :handler,
    :timeout,
    :async,
    :retries,
    :__identifier__
  ]

  @type t :: %__MODULE__{
          handler: (map(), map() -> {:ok, any()} | {:error, any()}),
          timeout: pos_integer(),
          async: boolean(),
          retries: non_neg_integer(),
          __identifier__: term()
        }
end
