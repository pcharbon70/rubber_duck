defmodule RubberDuck.LLMAbstraction.Provider do
  @moduledoc """
  Behavior definition for LLM providers.
  
  This behavior establishes the contract that all LLM providers must implement,
  enabling unified access to different AI services while maintaining provider-specific
  optimizations and features through capability discovery.
  """

  alias RubberDuck.LLMAbstraction.{Message, Response, Capability}

  @type config :: map()
  @type options :: keyword()
  @type provider_state :: term()
  @type error :: {:error, term()}

  @doc """
  Initialize the provider with configuration.
  
  This callback is called when the provider is started and should return
  the initial state that will be passed to all subsequent calls.
  
  ## Parameters
    - config: Provider-specific configuration (API keys, endpoints, etc.)
    
  ## Returns
    - {:ok, state} on successful initialization
    - {:error, reason} on failure
  """
  @callback init(config) :: {:ok, provider_state} | error

  @doc """
  Execute a chat completion with the provider.
  
  This is the primary interface for conversational AI interactions,
  supporting both streaming and non-streaming responses.
  
  ## Parameters
    - messages: List of messages implementing the Message protocol
    - state: Current provider state
    - opts: Additional options (streaming, temperature, max_tokens, etc.)
    
  ## Returns
    - {:ok, response, new_state} for successful completion
    - {:error, reason, state} on failure
  """
  @callback chat([Message.t()], provider_state, options) :: 
    {:ok, Response.t(), provider_state} | {:error, term(), provider_state}

  @doc """
  Execute a text completion with the provider.
  
  Single-shot text generation without conversation context.
  
  ## Parameters
    - prompt: Text prompt for completion
    - state: Current provider state
    - opts: Additional options (temperature, max_tokens, etc.)
    
  ## Returns
    - {:ok, response, new_state} for successful completion
    - {:error, reason, state} on failure
  """
  @callback complete(String.t(), provider_state, options) ::
    {:ok, Response.t(), provider_state} | {:error, term(), provider_state}

  @doc """
  Generate embeddings for the given input.
  
  Creates vector representations for semantic search and similarity.
  
  ## Parameters
    - input: Text or list of texts to embed
    - state: Current provider state
    - opts: Additional options (model, dimensions, etc.)
    
  ## Returns
    - {:ok, embeddings, new_state} where embeddings is a list of vectors
    - {:error, reason, state} on failure
  """
  @callback embed(String.t() | [String.t()], provider_state, options) ::
    {:ok, [list(float())], provider_state} | {:error, term(), provider_state}

  @doc """
  Stream a chat completion response.
  
  Returns a stream that yields response chunks as they become available.
  This is optional and providers can return {:error, :not_supported}.
  
  ## Parameters
    - messages: List of messages implementing the Message protocol
    - state: Current provider state
    - opts: Streaming-specific options
    
  ## Returns
    - {:ok, stream, new_state} where stream is an Elixir Stream
    - {:error, reason, state} on failure or if not supported
  """
  @callback stream_chat([Message.t()], provider_state, options) ::
    {:ok, Enumerable.t(), provider_state} | {:error, term(), provider_state}

  @doc """
  Get provider capabilities.
  
  Returns a list of capabilities this provider supports, enabling
  intelligent routing and feature discovery.
  
  ## Parameters
    - state: Current provider state
    
  ## Returns
    - List of Capability structs describing supported features
  """
  @callback capabilities(provider_state) :: [Capability.t()]

  @doc """
  Get current provider health status.
  
  Used for monitoring and failover decisions.
  
  ## Parameters
    - state: Current provider state
    
  ## Returns
    - :healthy, :degraded, or :unhealthy
  """
  @callback health_check(provider_state) :: :healthy | :degraded | :unhealthy

  @doc """
  Handle provider-specific cleanup.
  
  Called when the provider is being shut down.
  
  ## Parameters
    - state: Current provider state
    
  ## Returns
    - :ok
  """
  @callback terminate(provider_state) :: :ok

  @doc """
  Validate provider configuration.
  
  Static function to validate configuration before initialization.
  
  ## Parameters
    - config: Configuration to validate
    
  ## Returns
    - :ok if valid
    - {:error, reason} if invalid
  """
  @callback validate_config(config) :: :ok | error

  @doc """
  Get provider metadata.
  
  Static information about the provider.
  
  ## Returns
    - Map with provider name, version, description, etc.
  """
  @callback metadata() :: map()

  # Optional callbacks with default implementations
  @optional_callbacks [stream_chat: 3, embed: 3]

  @doc """
  Helper to validate required configuration keys.
  """
  def validate_required_keys(config, required_keys) do
    missing_keys = required_keys -- Map.keys(config)
    
    if Enum.empty?(missing_keys) do
      :ok
    else
      {:error, {:missing_required_keys, missing_keys}}
    end
  end

  @doc """
  Helper to extract options with defaults.
  """
  def extract_options(opts, defaults) do
    Keyword.merge(defaults, opts)
  end
end