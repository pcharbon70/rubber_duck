defmodule RubberDuck.Jido.Actions.Base.MonitoringAction do
  @moduledoc """
  Base action for metrics collection, health checks, and system monitoring.
  
  This base module provides common patterns for actions that monitor
  system health, collect metrics, perform health checks, and track
  performance indicators with standardized reporting.
  
  ## Usage
  
      defmodule MyApp.Actions.SystemHealthCheckAction do
        use RubberDuck.Jido.Actions.Base.MonitoringAction,
          name: "system_health_check",
          description: "Performs comprehensive system health monitoring",
          schema: [
            check_components: [type: {:list, :atom}, default: [:database, :cache, :external_apis]],
            include_detailed_metrics: [type: :boolean, default: true]
          ]
        
        @impl true
        def collect_metrics(params, context) do
          checks = %{
            database: check_database_health(),
            cache: check_cache_health(),
            external_apis: check_external_apis_health()
          }
          
          {:ok, %{
            status: determine_overall_status(checks),
            checks: checks,
            timestamp: DateTime.utc_now()
          }}
        end
      end
  
  ## Hooks Available
  
  - `before_monitoring/2` - Called before starting monitoring
  - `collect_metrics/2` - Main metrics collection logic (must be implemented)
  - `after_monitoring/3` - Called after successful monitoring
  - `handle_monitoring_error/3` - Called when monitoring fails
  - `format_metrics/3` - Called to format collected metrics
  - `should_alert/3` - Called to determine if alerts should be sent
  """
  
  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.fetch!(opts, :description)
    schema = Keyword.get(opts, :schema, [])
    
    # Add common monitoring parameters to schema
    enhanced_schema = schema ++ [
      monitoring_interval: [
        type: :pos_integer,
        default: 60_000,
        doc: "Monitoring interval in milliseconds"
      ],
      health_check_timeout: [
        type: :pos_integer,
        default: 10_000,
        doc: "Timeout for individual health checks in milliseconds"
      ],
      metric_retention_period: [
        type: :pos_integer,
        default: 24 * 60 * 60 * 1000,
        doc: "How long to retain metrics in milliseconds"
      ],
      alert_thresholds: [
        type: :map,
        default: %{
          error_rate: 0.05,
          response_time: 5000,
          availability: 0.99
        },
        doc: "Thresholds that trigger alerts"
      ],
      enable_alerting: [
        type: :boolean,
        default: true,
        doc: "Whether to send alerts for threshold violations"
      ],
      metric_tags: [
        type: :map,
        default: %{},
        doc: "Additional tags to include with metrics"
      ],
      export_format: [
        type: :atom,
        default: :json,
        values: [:json, :prometheus, :statsd, :influx],
        doc: "Format for exporting metrics"
      ],
      sampling_rate: [
        type: :float,
        default: 1.0,
        doc: "Sampling rate for metrics collection (0.0 to 1.0)"
      ]
    ]
    
    quote do
      use Jido.Action,
        name: unquote(name),
        description: unquote(description),
        schema: unquote(enhanced_schema)
      
      require Logger
      
      @behaviour RubberDuck.Jido.Actions.Base.MonitoringAction
      
      @impl true
      def run(params, context) do
        if should_sample?(params.sampling_rate) do
          execute_monitoring(params, context)
        else
          Logger.debug("Skipping monitoring due to sampling rate: #{params.sampling_rate}")
          
          {:ok, %{
            success: true,
            data: %{skipped: true, reason: :sampling},
            metadata: create_metadata(params, 0)
          }}
        end
      end
      
      defp execute_monitoring(params, context) do
        Logger.info("Starting monitoring: #{unquote(name)}")
        start_time = System.monotonic_time(:millisecond)
        
        with {:ok, prepared_params} <- validate_monitoring_params(params),
             {:ok, prepared_context} <- before_monitoring(prepared_params, context),
             {:ok, raw_metrics} <- collect_metrics_with_timeout(prepared_params, prepared_context),
             {:ok, formatted_metrics} <- format_metrics(raw_metrics, prepared_params, prepared_context),
             {:ok, final_result} <- after_monitoring(formatted_metrics, prepared_params, prepared_context) do
          
          end_time = System.monotonic_time(:millisecond)
          monitoring_time = end_time - start_time
          
          # Check if alerts should be sent
          if prepared_params.enable_alerting do
            case should_alert(final_result, prepared_params, prepared_context) do
              {:alert, alert_data} ->
                Logger.warning("Monitoring alert triggered: #{inspect(alert_data)}")
                send_alert(alert_data, prepared_params)
              :no_alert ->
                :ok
            end
          end
          
          Logger.info("Monitoring completed successfully: #{unquote(name)} in #{monitoring_time}ms")
          
          emit_monitoring_event(:monitoring_completed, %{
            action: unquote(name),
            monitoring_time: monitoring_time,
            metrics_count: count_metrics(final_result),
            success: true
          })
          
          format_success_response(final_result, prepared_params, monitoring_time)
        else
          {:error, reason} = error ->
            end_time = System.monotonic_time(:millisecond)
            monitoring_time = end_time - start_time
            
            Logger.error("Monitoring failed: #{unquote(name)} after #{monitoring_time}ms, reason: #{inspect(reason)}")
            
            emit_monitoring_event(:monitoring_failed, %{
              action: unquote(name),
              monitoring_time: monitoring_time,
              error: reason,
              success: false
            })
            
            case handle_monitoring_error(reason, params, context) do
              {:ok, recovery_result} -> 
                format_success_response(recovery_result, params, monitoring_time)
              {:error, final_reason} -> 
                format_error_response(final_reason, params, monitoring_time)
              :continue -> 
                format_error_response(reason, params, monitoring_time)
            end
        end
      end
      
      # Default implementations - can be overridden
      
      def before_monitoring(params, context), do: {:ok, context}
      
      def after_monitoring(metrics, _params, _context), do: {:ok, metrics}
      
      def handle_monitoring_error(reason, _params, _context), do: {:error, reason}
      
      def format_metrics(metrics, params, _context) do
        formatted = %{
          metrics: metrics,
          tags: params.metric_tags,
          format: params.export_format,
          timestamp: DateTime.utc_now()
        }
        {:ok, formatted}
      end
      
      def should_alert(metrics, params, _context) do
        thresholds = params.alert_thresholds
        
        alerts = []
        |> check_threshold(metrics, :error_rate, thresholds.error_rate)
        |> check_threshold(metrics, :response_time, thresholds.response_time)
        |> check_threshold(metrics, :availability, thresholds.availability)
        
        case alerts do
          [] -> :no_alert
          violations -> {:alert, %{violations: violations, timestamp: DateTime.utc_now()}}
        end
      end
      
      defoverridable before_monitoring: 2, after_monitoring: 3, handle_monitoring_error: 3,
                     format_metrics: 3, should_alert: 3
      
      # Private helper functions
      
      defp should_sample?(rate) when rate >= 1.0, do: true
      defp should_sample?(rate) when rate <= 0.0, do: false
      defp should_sample?(rate), do: :rand.uniform() <= rate
      
      defp validate_monitoring_params(params) do
        cond do
          params.health_check_timeout < 1000 ->
            {:error, :invalid_health_check_timeout}
          params.sampling_rate < 0.0 or params.sampling_rate > 1.0 ->
            {:error, :invalid_sampling_rate}
          true ->
            {:ok, params}
        end
      end
      
      defp collect_metrics_with_timeout(params, context) do
        task = Task.async(fn -> 
          collect_metrics(params, context)
        end)
        
        case Task.yield(task, params.health_check_timeout) || Task.shutdown(task) do
          {:ok, result} -> result
          nil -> {:error, :monitoring_timeout}
        end
      end
      
      defp check_threshold(alerts, metrics, key, threshold) do
        case get_in(metrics, [:metrics, key]) do
          nil -> alerts
          value when is_number(value) ->
            if value > threshold do
              [%{metric: key, value: value, threshold: threshold} | alerts]
            else
              alerts
            end
          _ -> alerts
        end
      end
      
      defp send_alert(alert_data, params) do
        # Emit telemetry event for alert
        :telemetry.execute(
          [:rubber_duck, :monitoring, :alert],
          %{count: length(alert_data.violations)},
          Map.put(alert_data, :action, unquote(name))
        )
      end
      
      defp count_metrics(%{metrics: metrics}) when is_map(metrics), do: map_size(metrics)
      defp count_metrics(%{metrics: metrics}) when is_list(metrics), do: length(metrics)
      defp count_metrics(_), do: 0
      
      defp emit_monitoring_event(event_name, metadata) do
        :telemetry.execute(
          [:rubber_duck, :actions, :monitoring, event_name],
          %{count: 1},
          metadata
        )
      end
      
      defp create_metadata(params, monitoring_time) do
        %{
          timestamp: DateTime.utc_now(),
          action: unquote(name),
          monitoring_time: monitoring_time,
          export_format: params.export_format,
          alerting_enabled: params.enable_alerting,
          sampling_rate: params.sampling_rate
        }
      end
      
      defp format_success_response(result, params, monitoring_time) do
        response = %{
          success: true,
          data: result,
          metadata: create_metadata(params, monitoring_time)
        }
        {:ok, response}
      end
      
      defp format_error_response(reason, params, monitoring_time) do
        error_response = %{
          success: false,
          error: reason,
          metadata: create_metadata(params, monitoring_time)
        }
        {:error, error_response}
      end
    end
  end
  
  @doc """
  Callback for collecting metrics and performing health checks.
  
  This callback must be implemented by modules using this base action.
  It should contain the core logic for metrics collection.
  
  ## Parameters
  - `params` - Validated parameters including monitoring configuration
  - `context` - Context including agent state and other relevant data
  
  ## Returns
  - `{:ok, metrics}` - Monitoring succeeded with metrics data
  - `{:error, reason}` - Monitoring failed with error reason
  """
  @callback collect_metrics(params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  @doc """
  Optional callback called before starting monitoring.
  
  Can be used for setup, resource allocation, or parameter preparation.
  """
  @callback before_monitoring(params :: map(), context :: map()) :: 
    {:ok, map()} | {:error, any()}
  
  @doc """
  Optional callback called after successful monitoring.
  
  Can be used for cleanup, metric aggregation, or side effects.
  """
  @callback after_monitoring(metrics :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  @doc """
  Optional callback called when monitoring fails.
  
  Can be used for error recovery, fallback metrics, or custom error handling.
  
  ## Returns
  - `{:ok, result}` - Error recovered with result
  - `{:error, reason}` - Error handled with new reason
  - `:continue` - Continue with original error
  """
  @callback handle_monitoring_error(reason :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()} | :continue
  
  @doc """
  Optional callback for formatting collected metrics.
  
  Can be used to transform metrics into specific formats or add metadata.
  """
  @callback format_metrics(metrics :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  @doc """
  Optional callback for determining if alerts should be sent.
  
  Evaluates metrics against thresholds and returns alert information.
  
  ## Returns
  - `:no_alert` - No alerts needed
  - `{:alert, alert_data}` - Alert should be sent with data
  """
  @callback should_alert(metrics :: any(), params :: map(), context :: map()) :: 
    :no_alert | {:alert, map()}
  
  # Default implementations
  @optional_callbacks before_monitoring: 2, after_monitoring: 3, handle_monitoring_error: 3,
                      format_metrics: 3, should_alert: 3
end