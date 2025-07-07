defmodule RubberDuck.Engine do
  @moduledoc """
  Behavior definition for RubberDuck engines.

  All engines must implement this behavior to be used in the engine system.
  Engines are pluggable components that handle specific tasks like code completion,
  generation, or analysis.
  """

  @type config :: keyword()
  @type state :: term()
  @type input :: map()
  @type result :: term()
  @type reason :: term()
  @type capability :: atom()

  @doc """
  Initialize the engine with the given configuration.

  This callback is called once when the engine is started. It should set up
  any necessary state based on the provided configuration.

  ## Parameters
    - `config`: Keyword list of engine-specific configuration
    
  ## Returns
    - `{:ok, state}` if initialization is successful
    - `{:error, reason}` if initialization fails
  """
  @callback init(config()) :: {:ok, state()} | {:error, reason()}

  @doc """
  Execute the engine with the given input.

  This is the main entry point for engine execution. The engine should process
  the input and return a result or error.

  ## Parameters
    - `input`: Map containing the input data for the engine
    - `state`: The current state of the engine
    
  ## Returns
    - `{:ok, result}` if execution is successful
    - `{:error, reason}` if execution fails
  """
  @callback execute(input(), state()) :: {:ok, result()} | {:error, reason()}

  @doc """
  Return the list of capabilities this engine provides.

  Capabilities are atoms that describe what the engine can do. These are used
  for engine discovery and routing.

  ## Examples
    - `:code_completion`
    - `:code_generation`
    - `:syntax_analysis`
    - `:refactoring`
    
  ## Returns
    List of capability atoms
  """
  @callback capabilities() :: [capability()]
end
