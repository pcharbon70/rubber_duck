defmodule RubberDuck.Interface.Behaviour do
  @moduledoc """
  Defines the behaviour contract that all interface adapters must implement.
  
  This behaviour ensures consistent handling of requests across different
  interfaces (CLI, Web, IDE) while allowing interface-specific customizations.
  Each adapter implementing this behaviour can transform requests and responses
  to match their specific requirements while maintaining a unified internal API.
  """

  @typedoc """
  Generic request structure that can represent requests from any interface.
  
  Required fields:
  - `:id` - Unique request identifier
  - `:operation` - The operation to perform (e.g., :chat, :complete, :analyze)
  - `:params` - Operation-specific parameters
  
  Optional fields:
  - `:context` - Request context (auth, session, metadata)
  - `:interface` - Source interface identifier
  - `:timestamp` - Request timestamp
  - `:priority` - Request priority level
  """
  @type request :: %{
    required(:id) => String.t(),
    required(:operation) => atom(),
    required(:params) => map(),
    optional(:context) => context(),
    optional(:interface) => atom(),
    optional(:timestamp) => DateTime.t(),
    optional(:priority) => :low | :normal | :high | :critical
  }

  @typedoc """
  Generic response structure for all interfaces.
  
  Required fields:
  - `:id` - Corresponding request ID
  - `:status` - Response status (:ok | :error | :partial)
  - `:data` - Response data (operation-specific)
  
  Optional fields:
  - `:metadata` - Additional response metadata
  - `:timestamp` - Response timestamp
  - `:duration_ms` - Processing duration
  """
  @type response :: %{
    required(:id) => String.t(),
    required(:status) => :ok | :error | :partial,
    required(:data) => term(),
    optional(:metadata) => map(),
    optional(:timestamp) => DateTime.t(),
    optional(:duration_ms) => non_neg_integer()
  }

  @typedoc """
  Request context containing auth, session, and metadata.
  """
  @type context :: %{
    optional(:user_id) => String.t(),
    optional(:session_id) => String.t(),
    optional(:auth_token) => String.t(),
    optional(:permissions) => [atom()],
    optional(:metadata) => map(),
    optional(:source_ip) => String.t(),
    optional(:user_agent) => String.t()
  }

  @typedoc """
  Interface capability atoms representing supported features.
  """
  @type capability :: 
    :chat |
    :complete |
    :analyze |
    :streaming |
    :file_upload |
    :file_download |
    :authentication |
    :session_management |
    :multi_model |
    :context_management |
    :history |
    :export |
    atom()

  @typedoc """
  Standardized error structure.
  """
  @type error :: {:error, error_type(), String.t(), map()}

  @typedoc """
  Error categories for consistent error handling.
  """
  @type error_type ::
    :validation_error |
    :authentication_error |
    :authorization_error |
    :not_found |
    :timeout |
    :rate_limit |
    :internal_error |
    :unsupported_operation

  @typedoc """
  Adapter state can be any term.
  """
  @type state :: term()

  @typedoc """
  Adapter initialization options.
  """
  @type options :: keyword()

  # Required callbacks

  @doc """
  Initialize the adapter with given options.
  
  This callback is called when the adapter is started and should set up
  any necessary state, connections, or resources.
  
  ## Parameters
  - `opts` - Adapter-specific configuration options
  
  ## Returns
  - `{:ok, state}` - Successful initialization with initial state
  - `{:error, reason}` - Initialization failure
  """
  @callback init(opts :: options()) :: {:ok, state()} | {:error, term()}

  @doc """
  Handle an incoming request from the interface.
  
  This is the main callback for processing requests. The adapter should
  validate the request, transform it to internal format, process it,
  and return an appropriate response.
  
  ## Parameters
  - `request` - The incoming request
  - `context` - Request context with auth and metadata
  - `state` - Current adapter state
  
  ## Returns
  - `{:ok, response, new_state}` - Successful processing
  - `{:error, error, new_state}` - Processing failure
  - `{:async, ref, new_state}` - Asynchronous processing started
  """
  @callback handle_request(request :: request(), context :: context(), state :: state()) ::
    {:ok, response(), state()} |
    {:error, error(), state()} |
    {:async, reference(), state()}

  @doc """
  Format a response for the specific interface.
  
  Transform the internal response format to match what the interface
  expects. This allows each interface to have its own response format
  while maintaining a consistent internal API.
  
  ## Parameters
  - `response` - Internal response to format
  - `request` - Original request (for context)
  - `state` - Current adapter state
  
  ## Returns
  - `{:ok, formatted_response}` - Formatted response ready for the interface
  - `{:error, reason}` - Formatting failure
  """
  @callback format_response(response :: response(), request :: request(), state :: state()) ::
    {:ok, term()} | {:error, term()}

  @doc """
  Handle and transform errors for the interface.
  
  Convert internal errors to interface-specific error formats. This ensures
  consistent error handling while allowing interfaces to present errors
  in their preferred format.
  
  ## Parameters
  - `error` - The error to handle
  - `request` - Original request (for context)
  - `state` - Current adapter state
  
  ## Returns
  - Transformed error in interface-specific format
  """
  @callback handle_error(error :: error(), request :: request(), state :: state()) :: term()

  @doc """
  Return the capabilities supported by this adapter.
  
  This allows dynamic feature discovery and helps the gateway understand
  what operations each adapter supports.
  
  ## Returns
  - List of supported capability atoms
  """
  @callback capabilities() :: [capability()]

  @doc """
  Validate an incoming request.
  
  Perform interface-specific validation to ensure the request is properly
  formatted and contains all required fields for the requested operation.
  
  ## Parameters
  - `request` - Request to validate
  
  ## Returns
  - `:ok` - Request is valid
  - `{:error, validation_errors}` - Request validation failed
  """
  @callback validate_request(request :: request()) ::
    :ok | {:error, validation_errors :: [String.t() | {atom(), String.t()}]}

  @doc """
  Clean up adapter resources on shutdown.
  
  Called when the adapter is being stopped. Should clean up any resources,
  close connections, and perform graceful shutdown procedures.
  
  ## Parameters
  - `reason` - Shutdown reason
  - `state` - Current adapter state
  
  ## Returns
  - Any term (return value is ignored)
  """
  @callback shutdown(reason :: term(), state :: state()) :: term()

  # Optional callbacks with default implementations

  @doc """
  Handle streaming responses.
  
  For adapters that support streaming, this callback handles chunks of
  streaming responses. The default implementation returns an error.
  
  ## Parameters
  - `chunk` - Response chunk
  - `stream_ref` - Stream reference
  - `state` - Current adapter state
  
  ## Returns
  - `{:ok, formatted_chunk, new_state}` - Formatted chunk
  - `{:error, reason, new_state}` - Streaming error
  - `{:done, final_response, new_state}` - Stream completed
  """
  @callback handle_stream(chunk :: term(), stream_ref :: reference(), state :: state()) ::
    {:ok, term(), state()} |
    {:error, term(), state()} |
    {:done, response(), state()}

  @doc """
  Handle interface-specific notifications or events.
  
  Some interfaces may need to handle notifications, websocket messages,
  or other events. The default implementation ignores these.
  
  ## Parameters
  - `event` - The event to handle
  - `state` - Current adapter state
  
  ## Returns
  - `{:ok, new_state}` - Event handled
  - `{:error, reason, new_state}` - Event handling failed
  """
  @callback handle_event(event :: term(), state :: state()) ::
    {:ok, state()} | {:error, term(), state()}

  @doc """
  Get adapter health status.
  
  Returns the current health status of the adapter. Used by the gateway
  for monitoring and circuit breaker decisions.
  
  ## Parameters
  - `state` - Current adapter state
  
  ## Returns
  - Health status and optional metadata
  """
  @callback health_check(state :: state()) ::
    {:healthy | :degraded | :unhealthy, metadata :: map()}

  @optional_callbacks handle_stream: 3, handle_event: 2, health_check: 1

  @doc """
  Generates a unique request ID.
  
  Helper function for adapters to generate consistent request IDs.
  """
  def generate_request_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
    |> then(&"req_#{&1}_#{System.system_time(:microsecond)}")
  end

  @doc """
  Creates a standard error tuple.
  
  Helper function for creating consistent error structures.
  """
  def error(type, message, metadata \\ %{}) when is_atom(type) do
    {:error, type, to_string(message), metadata}
  end

  @doc """
  Creates a successful response.
  
  Helper function for creating consistent response structures.
  """
  def success_response(request_id, data, metadata \\ %{}) do
    %{
      id: request_id,
      status: :ok,
      data: data,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates an error response.
  
  Helper function for creating error response structures.
  """
  def error_response(request_id, error, metadata \\ %{}) do
    %{
      id: request_id,
      status: :error,
      data: error,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }
  end
end