defmodule RubberDuck.CoT.Step do
  @moduledoc """
  Represents a reasoning step configuration in a Chain-of-Thought reasoning chain.
  
  This struct is created by the Spark DSL when defining steps in a reasoning chain.
  """
  
  defstruct [
    :name,
    :prompt,
    :depends_on,
    :validates,
    :max_tokens,
    :temperature,
    :retries,
    :optional,
    :__identifier__
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    prompt: String.t(),
    depends_on: atom() | [atom()] | nil,
    validates: atom() | [atom()] | nil,
    max_tokens: pos_integer(),
    temperature: float(),
    retries: non_neg_integer(),
    optional: boolean(),
    __identifier__: term()
  }
end