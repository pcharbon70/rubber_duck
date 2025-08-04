defmodule RubberDuck.Jido.Actions.Middleware.MonitoringMiddleware do
  @moduledoc """
  Middleware for monitoring and metrics collection.
  
  This middleware collects execution metrics, performance data, and
  health indicators for actions. It integrates with telemetry for
  observability and supports custom metric collectors.
  
  ## Options
  
  - `:collect_metrics` - List of metrics to collect. Default: [:duration, :success_rate, :error_rate]
  - `:sample_rate` - Sampling rate for detailed metrics (0.0-1.0). Default: 1.0
  - `:alert_thresholds` - Thresholds for alerting. Default: %{}
  - `:custom_metrics_fn` - Function to collect custom metrics
  """
  
  use RubberDuck.Jido.Actions.Middleware, priority: 80
  require Logger
  
  @ets_table :action_metrics
  
  @impl true
  def init(opts) do
    config = %{
      collect_metrics: Keyword.get(opts, :collect_metrics, [:duration, :success_rate, :error_rate]),
      sample_rate: Keyword.get(opts, :sample_rate, 1.0),
      alert_thresholds: Keyword.get(opts, :alert_thresholds, %{}),
      custom_metrics_fn: Keyword.get(opts, :custom_metrics_fn)
    }
    
    # Ensure ETS table exists
    ensure_ets_table()
    
    {:ok, config}
  end
  
  @impl true
  def call(action, params, context, next) do
    {:ok, config} = init([])
    
    # Decide if we should collect detailed metrics based on sampling
    should_sample = :rand.uniform() <= config.sample_rate
    
    # Start telemetry span
    metadata = %{
      action: inspect(action),
      sampled: should_sample
    }
    
    :telemetry.span(
      [:rubber_duck, :action, :execution],
      metadata,
      fn ->
        # Pre-execution metrics
        record_pre_execution_metrics(action, params, context, config)
        
        # Execute action with timing
        start_time = System.monotonic_time(:microsecond)
        memory_before = if should_sample, do: :erlang.memory(:total), else: 0
        
        result = try do
          next.(params, context)
        rescue
          error ->
            # Record error metrics
            record_error_metrics(action, error, config)
            reraise error, __STACKTRACE__
        end
        
        # Calculate metrics
        duration = System.monotonic_time(:microsecond) - start_time
        memory_after = if should_sample, do: :erlang.memory(:total), else: 0
        memory_used = memory_after - memory_before
        
        # Record post-execution metrics
        record_post_execution_metrics(
          action, 
          result, 
          duration, 
          memory_used, 
          config
        )
        
        # Check alert thresholds
        check_thresholds(action, duration, result, config)
        
        # Return telemetry measurements and result
        measurements = %{
          duration: duration,
          memory_used: memory_used
        }
        
        {result, Map.merge(metadata, measurements)}
      end
    )
  end
  
  # Private functions
  
  defp ensure_ets_table do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:set, :public, :named_table, {:read_concurrency, true}])
      _ ->
        :ok
    end
  end
  
  defp record_pre_execution_metrics(action, _params, _context, _config) do
    # Increment execution counter
    update_metric(action, :execution_count, 1, :counter)
    
    # Record concurrent executions
    update_metric(action, :concurrent_executions, 1, :gauge_inc)
  end
  
  defp record_post_execution_metrics(action, result, duration, memory_used, config) do
    # Decrement concurrent executions
    update_metric(action, :concurrent_executions, -1, :gauge_dec)
    
    # Record duration metrics
    if :duration in config.collect_metrics do
      update_metric(action, :total_duration, duration, :counter)
      update_metric(action, :duration_histogram, duration, :histogram)
      update_metric(action, :last_duration, duration, :gauge)
    end
    
    # Record memory metrics
    if :memory in config.collect_metrics do
      update_metric(action, :memory_used, memory_used, :histogram)
    end
    
    # Record success/failure
    case result do
      {:ok, _, _} ->
        update_metric(action, :success_count, 1, :counter)
      {:error, _} ->
        update_metric(action, :error_count, 1, :counter)
    end
    
    # Calculate and update rates
    update_rates(action, result, config)
    
    # Collect custom metrics if configured
    if config.custom_metrics_fn do
      custom_metrics = config.custom_metrics_fn.(action, result, duration)
      Enum.each(custom_metrics, fn {metric, value} ->
        update_metric(action, metric, value, :gauge)
      end)
    end
  end
  
  defp record_error_metrics(action, error, _config) do
    error_type = error.__struct__
    update_metric(action, {:error_type, error_type}, 1, :counter)
    update_metric(action, :crash_count, 1, :counter)
  end
  
  defp update_metric(action, metric, value, type) do
    key = {action, metric}
    
    case type do
      :counter ->
        :ets.update_counter(@ets_table, key, {2, value}, {key, 0})
        
      :gauge ->
        :ets.insert(@ets_table, {key, value})
        
      :gauge_inc ->
        current = case :ets.lookup(@ets_table, key) do
          [{^key, v}] -> v
          [] -> 0
        end
        :ets.insert(@ets_table, {key, current + value})
        
      :gauge_dec ->
        current = case :ets.lookup(@ets_table, key) do
          [{^key, v}] -> v
          [] -> 0
        end
        :ets.insert(@ets_table, {key, max(0, current + value)})
        
      :histogram ->
        # Store histogram data (simplified - in production would use HDR histogram)
        hist_key = {action, metric, :histogram}
        values = case :ets.lookup(@ets_table, hist_key) do
          [{^hist_key, vals}] -> vals
          [] -> []
        end
        
        # Keep last 1000 values for percentile calculation
        new_values = [value | values] |> Enum.take(1000)
        :ets.insert(@ets_table, {hist_key, new_values})
    end
  end
  
  defp update_rates(action, result, config) do
    if :success_rate in config.collect_metrics or :error_rate in config.collect_metrics do
      # Get current counts
      success_count = get_metric(action, :success_count, 0)
      error_count = get_metric(action, :error_count, 0)
      total = success_count + error_count
      
      if total > 0 do
        if :success_rate in config.collect_metrics do
          rate = success_count / total * 100
          update_metric(action, :success_rate, rate, :gauge)
        end
        
        if :error_rate in config.collect_metrics do
          rate = error_count / total * 100
          update_metric(action, :error_rate, rate, :gauge)
        end
      end
    end
  end
  
  defp get_metric(action, metric, default) do
    key = {action, metric}
    case :ets.lookup(@ets_table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end
  
  defp check_thresholds(action, duration, result, config) do
    Enum.each(config.alert_thresholds, fn {metric, threshold} ->
      case metric do
        :max_duration when duration > threshold * 1000 ->
          emit_alert(action, :slow_execution, %{
            duration_us: duration,
            threshold_ms: threshold
          })
          
        :error_rate ->
          rate = get_metric(action, :error_rate, 0)
          if rate > threshold do
            emit_alert(action, :high_error_rate, %{
              error_rate: rate,
              threshold: threshold
            })
          end
          
        :success_rate ->
          rate = get_metric(action, :success_rate, 100)
          if rate < threshold do
            emit_alert(action, :low_success_rate, %{
              success_rate: rate,
              threshold: threshold
            })
          end
          
        _ -> :ok
      end
    end)
  end
  
  defp emit_alert(action, alert_type, data) do
    Logger.warning("Monitoring alert triggered", %{
      middleware: "MonitoringMiddleware",
      action: inspect(action),
      alert_type: alert_type,
      data: data
    })
    
    # Also emit telemetry event for external monitoring
    :telemetry.execute(
      [:rubber_duck, :monitoring, :alert],
      data,
      %{
        action: inspect(action),
        alert_type: alert_type
      }
    )
  end
end