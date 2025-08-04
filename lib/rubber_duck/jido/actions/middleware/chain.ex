defmodule RubberDuck.Jido.Actions.Middleware.Chain do
  @moduledoc """
  Middleware chain execution for actions.
  
  This module manages the composition and execution of middleware chains,
  allowing multiple middleware to be applied to action execution in a
  configurable order.
  
  ## Example
  
      chain = Chain.new()
        |> Chain.add(LoggingMiddleware)
        |> Chain.add(AuthMiddleware, roles: [:admin])
        |> Chain.add(CacheMiddleware, ttl: 300)
      
      result = Chain.execute(chain, MyAction, params, context)
  """
  
  alias RubberDuck.Jido.Actions.Middleware
  require Logger
  
  defstruct middlewares: []
  
  @type t :: %__MODULE__{
    middlewares: [{module(), keyword()}]
  }
  
  @doc """
  Creates a new middleware chain.
  """
  def new do
    %__MODULE__{}
  end
  
  @doc """
  Adds a middleware to the chain with optional configuration.
  """
  def add(%__MODULE__{} = chain, middleware, opts \\ []) do
    %{chain | middlewares: chain.middlewares ++ [{middleware, opts}]}
  end
  
  @doc """
  Prepends a middleware to the beginning of the chain.
  """
  def prepend(%__MODULE__{} = chain, middleware, opts \\ []) do
    %{chain | middlewares: [{middleware, opts} | chain.middlewares]}
  end
  
  @doc """
  Inserts a middleware at a specific position in the chain.
  """
  def insert_at(%__MODULE__{} = chain, index, middleware, opts \\ []) do
    %{chain | middlewares: List.insert_at(chain.middlewares, index, {middleware, opts})}
  end
  
  @doc """
  Removes a middleware from the chain.
  """
  def remove(%__MODULE__{} = chain, middleware) do
    %{chain | middlewares: Enum.reject(chain.middlewares, fn {m, _} -> m == middleware end)}
  end
  
  @doc """
  Sorts middlewares by priority (higher priority executes first).
  """
  def sort_by_priority(%__MODULE__{} = chain) do
    sorted = Enum.sort_by(chain.middlewares, fn {middleware, _opts} ->
      if function_exported?(middleware, :priority, 0) do
        -middleware.priority()
      else
        -50  # Default priority
      end
    end)
    
    %{chain | middlewares: sorted}
  end
  
  @doc """
  Executes the middleware chain for an action.
  """
  def execute(%__MODULE__{} = chain, action, params, context) do
    # Build the nested function chain
    final_fn = fn p, c -> 
      try do
        action.run(p, c)
      rescue
        error ->
          Logger.error("Action execution failed: #{inspect(error)}")
          {:error, {:action_failed, error}}
      end
    end
    
    # Build middleware chain in reverse order
    chain_fn = chain.middlewares
      |> Enum.reverse()
      |> Enum.reduce(final_fn, fn {middleware, opts}, next ->
        fn p, c ->
          # Initialize middleware if needed
          case maybe_init_middleware(middleware, opts) do
            {:ok, _state} ->
              middleware.call(action, p, c, next)
            {:error, reason} ->
              {:error, {:middleware_init_failed, middleware, reason}}
          end
        end
      end)
    
    # Execute the chain
    chain_fn.(params, context)
  end
  
  @doc """
  Executes the chain with timing and telemetry.
  """
  def execute_with_telemetry(%__MODULE__{} = chain, action, params, context) do
    start_time = System.monotonic_time(:microsecond)
    
    # Emit start event
    :telemetry.execute(
      [:rubber_duck, :middleware, :chain, :start],
      %{system_time: System.system_time()},
      %{
        action: action,
        middleware_count: length(chain.middlewares),
        params: params
      }
    )
    
    # Execute chain
    result = execute(chain, action, params, context)
    
    # Calculate duration
    duration = System.monotonic_time(:microsecond) - start_time
    
    # Emit completion event
    status = case result do
      {:ok, _, _} -> :success
      {:error, _} -> :failure
    end
    
    :telemetry.execute(
      [:rubber_duck, :middleware, :chain, :stop],
      %{duration: duration, system_time: System.system_time()},
      %{
        action: action,
        middleware_count: length(chain.middlewares),
        status: status,
        result: result
      }
    )
    
    result
  end
  
  @doc """
  Creates a chain from a list of middleware specs.
  """
  def from_specs(specs) when is_list(specs) do
    Enum.reduce(specs, new(), fn
      {middleware, opts}, chain -> add(chain, middleware, opts)
      middleware, chain -> add(chain, middleware)
    end)
  end
  
  @doc """
  Returns the list of middleware modules in the chain.
  """
  def list_middlewares(%__MODULE__{} = chain) do
    Enum.map(chain.middlewares, fn {middleware, _} -> middleware end)
  end
  
  @doc """
  Checks if a middleware is in the chain.
  """
  def has_middleware?(%__MODULE__{} = chain, middleware) do
    Enum.any?(chain.middlewares, fn {m, _} -> m == middleware end)
  end
  
  # Private functions
  
  defp maybe_init_middleware(middleware, opts) do
    if function_exported?(middleware, :init, 1) do
      middleware.init(opts)
    else
      {:ok, opts}
    end
  end
end