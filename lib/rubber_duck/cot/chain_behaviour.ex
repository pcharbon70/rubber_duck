defmodule RubberDuck.CoT.ChainBehaviour do
  @moduledoc """
  Behaviour for Chain-of-Thought reasoning chains.

  Chains must implement config/0 and steps/0 functions.
  """

  @callback config() :: %{
              required(:name) => atom(),
              required(:description) => String.t(),
              required(:max_steps) => pos_integer(),
              required(:timeout) => pos_integer(),
              required(:template) => atom(),
              required(:cache_ttl) => pos_integer()
            }

  @callback steps() :: [
              %{
                required(:name) => atom(),
                required(:prompt) => String.t(),
                optional(:depends_on) => atom() | [atom()],
                optional(:validates) => [atom()],
                optional(:timeout) => pos_integer(),
                optional(:max_tokens) => pos_integer(),
                optional(:temperature) => float(),
                optional(:retries) => non_neg_integer(),
                optional(:optional) => boolean()
              }
            ]
end
