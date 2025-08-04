defmodule RubberDuck.Jido.Actions.Middleware do
  @moduledoc """
  Protocol and behaviour for action middleware.
  
  Middleware provides cross-cutting concerns for actions like logging,
  authentication, rate limiting, caching, and monitoring. Middleware
  can intercept and modify action execution, parameters, and results.
  
  ## Example
  
      defmodule MyMiddleware do
        use RubberDuck.Jido.Actions.Middleware
        
        @impl true
        def call(action, params, context, next) do
          # Pre-processing
          Logger.info("Executing action: #{action}")
          
          # Call next middleware or action
          result = next.(params, context)
          
          # Post-processing
          Logger.info("Action completed")
          
          result
        end
      end
  """
  
  @doc """
  Middleware callback that intercepts action execution.
  
  The middleware receives:
  - `action` - The action module being executed
  - `params` - The action parameters
  - `context` - The execution context
  - `next` - Function to call the next middleware or action
  
  The middleware must call `next.(params, context)` to continue the chain,
  potentially with modified params/context.
  """
  @callback call(
    action :: module(),
    params :: map(),
    context :: map(),
    next :: (map(), map() -> {:ok, any(), map()} | {:error, any()})
  ) :: {:ok, any(), map()} | {:error, any()}
  
  @doc """
  Optional initialization callback for middleware.
  """
  @callback init(opts :: keyword()) :: {:ok, state :: any()} | {:error, reason :: any()}
  
  @doc """
  Optional priority for middleware ordering (higher = earlier execution).
  """
  @callback priority() :: integer()
  
  @optional_callbacks [init: 1, priority: 0]
  
  defmacro __using__(opts \\ []) do
    quote do
      @behaviour RubberDuck.Jido.Actions.Middleware
      
      @priority unquote(Keyword.get(opts, :priority, 50))
      
      @impl true
      def priority, do: @priority
      
      @impl true
      def init(opts), do: {:ok, opts}
      
      defoverridable [priority: 0, init: 1]
    end
  end
end