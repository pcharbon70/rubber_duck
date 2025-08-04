defmodule RubberDuck.Jido.Actions.Base.ProcessingAction do
  @moduledoc """
  Base action for complex business logic processing with standardized patterns.
  
  This base module provides common patterns for actions that perform complex
  business logic processing, including input validation, pipeline execution,
  progress tracking, and comprehensive error handling.
  
  ## Usage
  
      defmodule MyApp.Actions.DataProcessingAction do
        use RubberDuck.Jido.Actions.Base.ProcessingAction,
          name: "data_processing",
          description: "Processes data through multiple stages",
          schema: [
            input_data: [type: :any, required: true],
            processing_steps: [type: {:list, :atom}, default: [:validate, :transform, :analyze]]
          ]
        
        @impl true
        def process_data(params, context) do
          with {:ok, validated} <- validate_input(params.input_data),
               {:ok, transformed} <- transform_data(validated),
               {:ok, analyzed} <- analyze_data(transformed) do
            {:ok, %{result: analyzed, steps_completed: [:validate, :transform, :analyze]}}
          end
        end
      end
  
  ## Hooks Available
  
  - `before_processing/2` - Called before starting processing
  - `process_data/2` - Main processing logic (must be implemented)
  - `after_processing/3` - Called after successful processing
  - `handle_processing_error/3` - Called when processing fails
  - `track_progress/3` - Called during processing for progress updates
  """
  
  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.fetch!(opts, :description)
    schema = Keyword.get(opts, :schema, [])
    
    # Add common processing parameters to schema
    enhanced_schema = schema ++ [
      enable_progress_tracking: [
        type: :boolean,
        default: false,
        doc: "Whether to track and report processing progress"
      ],
      progress_callback: [
        type: {:fun, 1},
        default: nil,
        doc: "Optional callback function for progress updates"
      ],
      enable_checkpoints: [
        type: :boolean,
        default: false,
        doc: "Whether to create recovery checkpoints during processing"
      ],
      checkpoint_interval: [
        type: :pos_integer,
        default: 10,
        doc: "Number of operations between checkpoints"
      ],
      max_processing_time: [
        type: :pos_integer,
        default: 300_000,
        doc: "Maximum processing time in milliseconds"
      ],
      enable_telemetry: [
        type: :boolean,
        default: true,
        doc: "Whether to emit telemetry events"
      ]
    ]
    
    quote do
      use Jido.Action,
        name: unquote(name),
        description: unquote(description),
        schema: unquote(enhanced_schema)
      
      require Logger
      
      @behaviour RubberDuck.Jido.Actions.Base.ProcessingAction
      
      @impl true
      def run(params, context) do
        Logger.info("Starting processing: #{unquote(name)}")
        start_time = System.monotonic_time(:millisecond)
        
        with {:ok, prepared_params} <- validate_processing_params(params),
             {:ok, prepared_context} <- before_processing(prepared_params, context),
             {:ok, result} <- execute_with_timeout(prepared_params, prepared_context),
             {:ok, final_result} <- after_processing(result, prepared_params, prepared_context) do
          
          end_time = System.monotonic_time(:millisecond)
          processing_time = end_time - start_time
          
          Logger.info("Processing completed successfully: #{unquote(name)} in #{processing_time}ms")
          
          if prepared_params.enable_telemetry do
            emit_telemetry_event(:processing_completed, %{
              action: unquote(name),
              processing_time: processing_time,
              success: true
            })
          end
          
          format_success_response(final_result, prepared_params, processing_time)
        else
          {:error, reason} = error ->
            end_time = System.monotonic_time(:millisecond)
            processing_time = end_time - start_time
            
            Logger.error("Processing failed: #{unquote(name)} after #{processing_time}ms, reason: #{inspect(reason)}")
            
            if params.enable_telemetry do
              emit_telemetry_event(:processing_failed, %{
                action: unquote(name),
                processing_time: processing_time,
                error: reason,
                success: false
              })
            end
            
            case handle_processing_error(reason, params, context) do
              {:ok, recovery_result} -> 
                format_success_response(recovery_result, params, processing_time)
              {:error, final_reason} -> 
                format_error_response(final_reason, params, processing_time)
              :continue -> 
                format_error_response(reason, params, processing_time)
            end
        end
      end
      
      # Default implementations - can be overridden
      
      def before_processing(params, context), do: {:ok, context}
      
      def after_processing(result, _params, _context), do: {:ok, result}
      
      def handle_processing_error(reason, _params, _context), do: {:error, reason}
      
      def track_progress(stage, progress, _params) do
        Logger.debug("Processing progress: #{stage} - #{progress}%")
        :ok
      end
      
      defoverridable before_processing: 2, after_processing: 3, handle_processing_error: 3, track_progress: 3
      
      # Private helper functions
      
      defp validate_processing_params(params) do
        # Add any processing-specific validation here
        if params.max_processing_time < 1000 do
          {:error, :invalid_processing_time}
        else
          {:ok, params}
        end
      end
      
      defp execute_with_timeout(params, context) do
        task = Task.async(fn -> 
          process_with_progress_tracking(params, context)
        end)
        
        case Task.yield(task, params.max_processing_time) || Task.shutdown(task) do
          {:ok, result} -> result
          nil -> {:error, :processing_timeout}
        end
      end
      
      defp process_with_progress_tracking(params, context) do
        if params.enable_progress_tracking do
          track_progress("started", 0, params)
        end
        
        result = process_data(params, context)
        
        if params.enable_progress_tracking do
          track_progress("completed", 100, params)
        end
        
        result
      end
      
      defp emit_telemetry_event(event_name, metadata) do
        :telemetry.execute(
          [:rubber_duck, :actions, :processing, event_name],
          %{count: 1},
          metadata
        )
      end
      
      defp format_success_response(result, params, processing_time) do
        response = %{
          success: true,
          data: result,
          metadata: %{
            timestamp: DateTime.utc_now(),
            action: unquote(name),
            processing_time: processing_time,
            progress_tracking_enabled: params.enable_progress_tracking,
            checkpoints_enabled: params.enable_checkpoints
          }
        }
        {:ok, response}
      end
      
      defp format_error_response(reason, params, processing_time) do
        error_response = %{
          success: false,
          error: reason,
          metadata: %{
            timestamp: DateTime.utc_now(),
            action: unquote(name),
            processing_time: processing_time,
            progress_tracking_enabled: params.enable_progress_tracking,
            checkpoints_enabled: params.enable_checkpoints
          }
        }
        {:error, error_response}
      end
    end
  end
  
  @doc """
  Callback for handling the main processing logic.
  
  This callback must be implemented by modules using this base action.
  It should contain the core business logic for data processing.
  
  ## Parameters
  - `params` - Validated parameters including processing configuration
  - `context` - Context including agent state and other relevant data
  
  ## Returns
  - `{:ok, result}` - Processing succeeded with result data
  - `{:error, reason}` - Processing failed with error reason
  """
  @callback process_data(params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  @doc """
  Optional callback called before starting processing.
  
  Can be used for setup, resource allocation, or parameter preparation.
  """
  @callback before_processing(params :: map(), context :: map()) :: 
    {:ok, map()} | {:error, any()}
  
  @doc """
  Optional callback called after successful processing.
  
  Can be used for cleanup, result transformation, or side effects.
  """
  @callback after_processing(result :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  @doc """
  Optional callback called when processing fails.
  
  Can be used for error recovery, cleanup, or custom error handling.
  
  ## Returns
  - `{:ok, result}` - Error recovered with result
  - `{:error, reason}` - Error handled with new reason
  - `:continue` - Continue with original error
  """
  @callback handle_processing_error(reason :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()} | :continue
  
  @doc """
  Optional callback for tracking processing progress.
  
  Called during processing to report progress updates.
  """
  @callback track_progress(stage :: String.t(), progress :: integer(), params :: map()) :: :ok
  
  # Default implementations
  @optional_callbacks before_processing: 2, after_processing: 3, handle_processing_error: 3, track_progress: 3
end