defmodule RubberDuck.Jido.Actions.Base.RequestAction do
  @moduledoc """
  Base action for handling external requests with standardized patterns.
  
  This base module provides common patterns for actions that handle external requests,
  including parameter validation, authentication, rate limiting, error handling,
  and response formatting.
  
  ## Usage
  
      defmodule MyApp.Actions.ApiRequestAction do
        use RubberDuck.Jido.Actions.Base.RequestAction,
          name: "api_request",
          description: "Makes API requests to external service",
          schema: [
            url: [type: :string, required: true],
            method: [type: :atom, default: :get, values: [:get, :post, :put, :delete]],
            headers: [type: :map, default: %{}],
            body: [type: :any, default: nil]
          ]
        
        @impl true
        def handle_request(params, context) do
          # Your request logic here
          case make_http_request(params) do
            {:ok, response} -> {:ok, %{status: response.status, body: response.body}}
            {:error, reason} -> {:error, reason}
          end
        end
      end
  
  ## Hooks Available
  
  - `before_request/2` - Called before making the request
  - `handle_request/2` - Main request logic (must be implemented)
  - `after_request/3` - Called after successful request
  - `handle_error/3` - Called when request fails
  """
  
  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.fetch!(opts, :description)
    schema = Keyword.get(opts, :schema, [])
    
    # Add common request parameters to schema
    enhanced_schema = schema ++ [
      timeout: [
        type: :pos_integer,
        default: 30_000,
        doc: "Request timeout in milliseconds"
      ],
      retry_attempts: [
        type: :non_neg_integer,
        default: 3,
        doc: "Number of retry attempts on failure"
      ],
      retry_delay: [
        type: :pos_integer,
        default: 1_000,
        doc: "Delay between retry attempts in milliseconds"
      ],
      validate_response: [
        type: :boolean,
        default: true,
        doc: "Whether to validate response format"
      ]
    ]
    
    quote do
      use Jido.Action,
        name: unquote(name),
        description: unquote(description),
        schema: unquote(enhanced_schema)
      
      require Logger
      
      @behaviour RubberDuck.Jido.Actions.Base.RequestAction
      
      @impl true
      def run(params, context) do
        Logger.info("Starting request: #{unquote(name)}")
        
        with {:ok, validated_params} <- validate_request_params(params),
             {:ok, prepared_context} <- before_request(validated_params, context),
             {:ok, result} <- execute_with_retry(validated_params, prepared_context),
             {:ok, final_result} <- after_request(result, validated_params, prepared_context) do
          
          Logger.info("Request completed successfully: #{unquote(name)}")
          format_success_response(final_result, validated_params)
        else
          {:error, reason} = error ->
            Logger.error("Request failed: #{unquote(name)}, reason: #{inspect(reason)}")
            
            case handle_error(reason, params, context) do
              {:ok, recovery_result} -> 
                format_success_response(recovery_result, params)
              {:error, final_reason} -> 
                format_error_response(final_reason, params)
              :continue -> 
                format_error_response(reason, params)
            end
        end
      end
      
      # Default implementations - can be overridden
      
      def before_request(params, context), do: {:ok, context}
      
      def after_request(result, _params, _context), do: {:ok, result}
      
      def handle_error(reason, _params, _context), do: {:error, reason}
      
      defoverridable before_request: 2, after_request: 3, handle_error: 3
      
      # Private helper functions
      
      defp validate_request_params(params) do
        # Add any request-specific validation here
        {:ok, params}
      end
      
      defp execute_with_retry(params, context, attempt \\ 1) do
        retry_attempts = Map.get(params, :retry_attempts, 3)
        retry_delay = Map.get(params, :retry_delay, 1_000)
        
        case handle_request(params, context) do
          {:ok, result} -> {:ok, result}
          {:error, reason} when attempt < retry_attempts ->
            Logger.warning("Request attempt #{attempt} failed, retrying: #{inspect(reason)}")
            :timer.sleep(retry_delay)
            execute_with_retry(params, context, attempt + 1)
          {:error, reason} ->
            {:error, {:max_retries_exceeded, reason}}
        end
      end
      
      defp format_success_response(result, params) do
        response = %{
          success: true,
          data: result,
          metadata: %{
            timestamp: DateTime.utc_now(),
            action: unquote(name),
            timeout: Map.get(params, :timeout, 30_000),
            retry_attempts: Map.get(params, :retry_attempts, 3)
          }
        }
        {:ok, response}
      end
      
      defp format_error_response(reason, params) do
        error_response = %{
          success: false,
          error: reason,
          metadata: %{
            timestamp: DateTime.utc_now(),
            action: unquote(name),
            timeout: Map.get(params, :timeout, 30_000),
            retry_attempts: Map.get(params, :retry_attempts, 3)
          }
        }
        {:error, error_response}
      end
    end
  end
  
  @doc """
  Callback for handling the main request logic.
  
  This callback must be implemented by modules using this base action.
  It should contain the core business logic for making the external request.
  
  ## Parameters
  - `params` - Validated parameters including common request options
  - `context` - Context including agent state and other relevant data
  
  ## Returns
  - `{:ok, result}` - Request succeeded with result data
  - `{:error, reason}` - Request failed with error reason
  """
  @callback handle_request(params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  @doc """
  Optional callback called before making the request.
  
  Can be used for authentication, parameter transformation, or context preparation.
  """
  @callback before_request(params :: map(), context :: map()) :: 
    {:ok, map()} | {:error, any()}
  
  @doc """
  Optional callback called after successful request.
  
  Can be used for response transformation, caching, or side effects.
  """
  @callback after_request(result :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  @doc """
  Optional callback called when a request fails.
  
  Can be used for error recovery, fallback behavior, or custom error handling.
  
  ## Returns
  - `{:ok, result}` - Error recovered with result
  - `{:error, reason}` - Error handled with new reason
  - `:continue` - Continue with original error
  """
  @callback handle_error(reason :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()} | :continue
  
  # Default implementations
  @optional_callbacks before_request: 2, after_request: 3, handle_error: 3
end