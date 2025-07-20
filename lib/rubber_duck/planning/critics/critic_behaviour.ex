defmodule RubberDuck.Planning.Critics.CriticBehaviour do
  @moduledoc """
  Behaviour definition for plan and task critics.
  
  Critics are external validators that check plans and tasks for correctness
  (hard critics) or quality (soft critics). They follow the LLM-Modulo framework
  principle of external validation.
  
  ## Implementing a Critic
  
  Critics must implement the following callbacks:
  - `name/0` - Returns the critic's name
  - `type/0` - Returns :hard or :soft
  - `priority/0` - Returns execution priority (lower = higher priority)
  - `validate/2` - Performs the validation
  
  ## Example
  
      defmodule MyCustomCritic do
        @behaviour RubberDuck.Planning.Critics.CriticBehaviour
        
        @impl true
        def name, do: "Custom Syntax Validator"
        
        @impl true
        def type, do: :hard
        
        @impl true
        def priority, do: 100
        
        @impl true
        def validate(target, opts) do
          # Validation logic here
          {:ok, %{status: :passed, message: "Validation passed"}}
        end
      end
  """
  
  alias RubberDuck.Planning.{Plan, Task}
  
  @type target :: Plan.t() | Task.t() | map()
  @type critic_type :: :hard | :soft
  @type priority :: non_neg_integer()
  @type status :: :passed | :failed | :warning
  @type severity :: :info | :warning | :error | :critical
  
  @type validation_result :: %{
    required(:status) => status(),
    required(:message) => String.t(),
    optional(:severity) => severity(),
    optional(:details) => map(),
    optional(:suggestions) => [String.t()],
    optional(:metadata) => map()
  }
  
  @type validation_error :: {:error, String.t() | map()}
  
  @doc """
  Returns the name of the critic.
  """
  @callback name() :: String.t()
  
  @doc """
  Returns the type of critic (:hard for correctness, :soft for quality).
  """
  @callback type() :: critic_type()
  
  @doc """
  Returns the priority of this critic. Lower numbers = higher priority.
  Critics with higher priority are executed first.
  """
  @callback priority() :: priority()
  
  @doc """
  Validates the given target (Plan or Task).
  
  Returns {:ok, validation_result} on success or {:error, reason} on failure.
  The validation can also be performed asynchronously by returning {:async, task}.
  """
  @callback validate(target :: target(), opts :: keyword()) :: 
    {:ok, validation_result()} | 
    validation_error() |
    {:async, Task.t()}
    
  @doc """
  Optional callback for configuring the critic.
  Returns a keyword list of configuration options.
  """
  @callback configure(opts :: keyword()) :: keyword()
  
  @doc """
  Optional callback to check if the critic can handle the given target.
  Defaults to true if not implemented.
  """
  @callback can_validate?(target :: target()) :: boolean()
  
  @optional_callbacks [configure: 1, can_validate?: 1]
  
  @doc """
  Helper function to create a validation result.
  """
  def validation_result(status, message, opts \\ []) do
    base = %{
      status: status,
      message: message
    }
    
    base
    |> maybe_add(:severity, Keyword.get(opts, :severity))
    |> maybe_add(:details, Keyword.get(opts, :details))
    |> maybe_add(:suggestions, Keyword.get(opts, :suggestions))
    |> maybe_add(:metadata, Keyword.get(opts, :metadata))
  end
  
  @doc """
  Helper to determine default severity based on status and critic type.
  """
  def default_severity(status, critic_type) do
    case {status, critic_type} do
      {:passed, _} -> :info
      {:warning, :soft} -> :warning
      {:warning, :hard} -> :error
      {:failed, :soft} -> :warning
      {:failed, :hard} -> :critical
      _ -> :info
    end
  end
  
  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end