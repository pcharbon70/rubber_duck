defmodule RubberDuck.CodingAssistant.EngineBehaviour do
  @moduledoc """
  Defines the behaviour contract that all coding assistance engines must implement.
  
  This behaviour ensures consistent operation of engines within the distributed system
  while allowing engine-specific functionality. Each engine implementing this behaviour
  can process requests in real-time (<100ms) or batch mode while maintaining state
  and providing health monitoring capabilities.
  """

  @typedoc """
  Engine result structure for all operations.
  
  Required fields:
  - `:status` - Operation status (:success | :error | :partial)
  - `:data` - Engine-specific result data
  
  Optional fields:
  - `:metadata` - Additional result metadata
  - `:processing_time` - Processing duration in microseconds
  """
  @type engine_result :: %{
    required(:status) => :success | :error | :partial,
    required(:data) => term(),
    optional(:metadata) => map(),
    optional(:processing_time) => integer()
  }

  @typedoc """
  Engine configuration map passed during initialization.
  """
  @type config :: map()

  @typedoc """
  Engine state maintained between operations.
  """
  @type state :: term()

  @typedoc """
  Data passed to engine operations (requests, content, etc.).
  """
  @type data :: term()

  @typedoc """
  List of data items for batch processing.
  """
  @type data_list :: [data()]

  @typedoc """
  Engine event for inter-engine communication.
  """
  @type engine_event :: term()

  @typedoc """
  Engine health status.
  """
  @type health_status :: :healthy | :degraded | :unhealthy

  @typedoc """
  Engine capabilities list.
  """
  @type capabilities :: [atom()]

  @doc """
  Initialize the engine with configuration.
  
  ## Parameters
    - config: Engine-specific configuration map
    
  ## Returns
    - {:ok, state} | {:error, reason}
  """
  @callback init(config()) :: {:ok, state()} | {:error, term()}

  @doc """
  Process data in real-time mode (target < 100ms).
  
  ## Parameters
    - data: Data to process
    - state: Current engine state
    
  ## Returns
    - {:ok, result, new_state} | {:error, reason, new_state}
  """
  @callback process_real_time(data(), state()) ::
    {:ok, engine_result(), state()} | {:error, term(), state()}

  @doc """
  Process multiple data items in batch mode.
  
  ## Parameters
    - data_list: List of data items to process
    - state: Current engine state
    
  ## Returns
    - {:ok, results, new_state} | {:error, reason, new_state}
  """
  @callback process_batch(data_list(), state()) ::
    {:ok, [engine_result()], state()} | {:error, term(), state()}

  @doc """
  Get the capabilities supported by this engine.
  
  ## Returns
    - List of capability atoms
  """
  @callback capabilities() :: capabilities()

  @doc """
  Check the health status of the engine.
  
  ## Parameters
    - state: Current engine state
    
  ## Returns
    - Health status atom
  """
  @callback health_check(state()) :: health_status()

  @doc """
  Handle inter-engine communication events.
  
  ## Parameters
    - event: Engine event to handle
    - state: Current engine state
    
  ## Returns
    - {:ok, new_state} | {:error, reason}
  """
  @callback handle_engine_event(engine_event(), state()) ::
    {:ok, state()} | {:error, term()}

  @doc """
  Clean up engine resources during shutdown.
  
  ## Parameters
    - reason: Shutdown reason
    - state: Current engine state
    
  ## Returns
    - :ok
  """
  @callback terminate(term(), state()) :: :ok
end