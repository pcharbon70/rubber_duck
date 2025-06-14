defmodule RubberDuck.LLMAbstraction.Provider do
  @moduledoc """
  Behavior definition for LLM providers.
  
  This behavior defines the standard interface that all LLM providers
  must implement to work with the distributed load balancing and
  abstraction system.
  """

  alias RubberDuck.LLMAbstraction.{Message, Response, Capability}

  @doc """
  Initialize the provider with configuration.
  
  ## Parameters
    - config: Provider-specific configuration map
    
  ## Returns
    - {:ok, state} | {:error, reason}
  """
  @callback init(config :: map()) :: {:ok, term()} | {:error, term()}

  @doc """
  Execute a chat completion request.
  
  ## Parameters
    - messages: List of messages in the conversation
    - state: Provider state
    - opts: Request options (model, temperature, etc.)
    
  ## Returns
    - {:ok, response, new_state} | {:error, reason, new_state}
  """
  @callback chat(messages :: [Message.t()], state :: term(), opts :: keyword()) ::
    {:ok, Response.t(), term()} | {:error, term(), term()}

  @doc """
  Execute a text completion request.
  
  ## Parameters
    - prompt: Text prompt to complete
    - state: Provider state
    - opts: Request options
    
  ## Returns
    - {:ok, response, new_state} | {:error, reason, new_state}
  """
  @callback complete(prompt :: String.t(), state :: term(), opts :: keyword()) ::
    {:ok, Response.t(), term()} | {:error, term(), term()}

  @doc """
  Generate embeddings for input text.
  
  ## Parameters
    - input: Text or list of texts to embed
    - state: Provider state
    - opts: Request options
    
  ## Returns
    - {:ok, embeddings, new_state} | {:error, reason, new_state}
  """
  @callback embed(input :: String.t() | [String.t()], state :: term(), opts :: keyword()) ::
    {:ok, [list(float())], term()} | {:error, term(), term()}

  @doc """
  Execute a streaming chat completion request.
  
  ## Parameters
    - messages: List of messages in the conversation
    - state: Provider state
    - opts: Request options
    
  ## Returns
    - {:ok, stream, new_state} | {:error, reason, new_state}
  """
  @callback stream_chat(messages :: [Message.t()], state :: term(), opts :: keyword()) ::
    {:ok, Enumerable.t(), term()} | {:error, term(), term()}

  @doc """
  Get the capabilities supported by this provider.
  
  ## Parameters
    - state: Provider state
    
  ## Returns
    - List of capabilities
  """
  @callback capabilities(state :: term()) :: [Capability.t()]

  @doc """
  Check the health status of the provider.
  
  ## Parameters
    - state: Provider state
    
  ## Returns
    - :healthy | :degraded | :unhealthy
  """
  @callback health_check(state :: term()) :: :healthy | :degraded | :unhealthy

  @doc """
  Clean up provider resources.
  
  ## Parameters
    - state: Provider state
    
  ## Returns
    - :ok
  """
  @callback terminate(state :: term()) :: :ok

  @doc """
  Validate provider configuration.
  
  ## Parameters
    - config: Configuration to validate
    
  ## Returns
    - :ok | {:error, reason}
  """
  @callback validate_config(config :: map()) :: :ok | {:error, term()}

  @doc """
  Get provider metadata and information.
  
  ## Returns
    - Map with provider metadata
  """
  @callback metadata() :: map()

  @optional_callbacks [embed: 3, stream_chat: 3]
end