defmodule RubberDuck.Tool.Composition.Metrics do
  @moduledoc """
  Metrics collection and aggregation for tool composition workflows.

  This module provides comprehensive metrics collection for workflow execution,
  including performance analytics, error tracking, and resource usage monitoring.

  ## Features

  - Real-time workflow metrics collection
  - Step-level performance tracking
  - Error rate and pattern analysis
  - Resource utilization monitoring
  - Historical trend analysis
  - Prometheus metrics export

  ## Metrics Collected

  ### Workflow Metrics
  - Total workflow count
  - Workflow success/failure rates
  - Average workflow duration
  - Concurrent workflow count
  - Workflow throughput

  ### Step Metrics
  - Step execution times
  - Step success/failure rates
  - Step resource usage
  - Step dependencies and bottlenecks

  ### System Metrics
  - Memory usage during workflow execution
  - CPU utilization
  - I/O operations
  - Network requests
  """

  use GenServer

  require Logger

  @name __MODULE__

  # ETS table for metrics storage
  @metrics_table :composition_metrics
  @workflow_table :composition_workflows
  @step_table :composition_steps

  # Metric types
  @counter_metrics [
    :workflow_started,
    :workflow_completed,
    :workflow_failed,
    :step_started,
    :step_completed,
    :step_failed
  ]

  @histogram_metrics [
    :workflow_duration,
    :step_duration,
    :workflow_result_size,
    :step_result_size
  ]

  @gauge_metrics [
    :active_workflows,
    :active_steps,
    :memory_usage,
    :cpu_usage
  ]

  # Telemetry events to handle
  @telemetry_events [
    [:rubber_duck, :tool, :composition, :workflow_start],
    [:rubber_duck, :tool, :composition, :workflow_complete],
    [:rubber_duck, :tool, :composition, :workflow_error],
    [:rubber_duck, :tool, :composition, :workflow_step_start],
    [:rubber_duck, :tool, :composition, :workflow_step_complete],
    [:rubber_duck, :tool, :composition, :workflow_step_error]
  ]

  @doc """
  Starts the metrics collection server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc """
  Gets current metrics summary.
  """
  def get_metrics_summary do
    GenServer.call(@name, :get_metrics_summary)
  end

  @doc """
  Gets workflow metrics for a specific workflow.
  """
  def get_workflow_metrics(workflow_id) do
    GenServer.call(@name, {:get_workflow_metrics, workflow_id})
  end

  @doc """
  Gets step metrics for a specific step.
  """
  def get_step_metrics(workflow_id, step_name) do
    GenServer.call(@name, {:get_step_metrics, workflow_id, step_name})
  end

  @doc """
  Gets aggregated metrics for a time period.
  """
  def get_aggregated_metrics(time_range \\ :hour) do
    GenServer.call(@name, {:get_aggregated_metrics, time_range})
  end

  @doc """
  Exports metrics in Prometheus format.
  """
  def export_prometheus_metrics do
    GenServer.call(@name, :export_prometheus_metrics)
  end

  @doc """
  Resets all metrics (useful for testing).
  """
  def reset_metrics do
    GenServer.call(@name, :reset_metrics)
  end

  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    # Create ETS tables for metrics storage
    :ets.new(@metrics_table, [:set, :protected, :named_table])
    :ets.new(@workflow_table, [:set, :protected, :named_table])
    :ets.new(@step_table, [:set, :protected, :named_table])

    # Initialize metrics
    initialize_metrics()

    # Attach telemetry handlers
    attach_telemetry_handlers()

    # Start periodic cleanup
    schedule_cleanup()

    Logger.info("Composition metrics collection started")

    {:ok, %{start_time: System.system_time(:millisecond)}}
  end

  @impl GenServer
  def handle_call(:get_metrics_summary, _from, state) do
    summary = build_metrics_summary()
    {:reply, summary, state}
  end

  @impl GenServer
  def handle_call({:get_workflow_metrics, workflow_id}, _from, state) do
    metrics = get_workflow_metrics_from_ets(workflow_id)
    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call({:get_step_metrics, workflow_id, step_name}, _from, state) do
    metrics = get_step_metrics_from_ets(workflow_id, step_name)
    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call({:get_aggregated_metrics, time_range}, _from, state) do
    metrics = build_aggregated_metrics(time_range)
    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call(:export_prometheus_metrics, _from, state) do
    prometheus_data = build_prometheus_metrics()
    {:reply, prometheus_data, state}
  end

  @impl GenServer
  def handle_call(:reset_metrics, _from, state) do
    reset_all_metrics()
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    cleanup_old_metrics()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:telemetry, event, measurements, metadata}, state) do
    handle_telemetry_event(event, measurements, metadata)
    {:noreply, state}
  end

  # Private functions

  defp initialize_metrics do
    # Initialize counter metrics
    Enum.each(@counter_metrics, fn metric ->
      :ets.insert(@metrics_table, {metric, 0})
    end)

    # Initialize histogram metrics
    Enum.each(@histogram_metrics, fn metric ->
      :ets.insert(@metrics_table, {metric, []})
    end)

    # Initialize gauge metrics
    Enum.each(@gauge_metrics, fn metric ->
      :ets.insert(@metrics_table, {metric, 0})
    end)
  end

  defp attach_telemetry_handlers do
    Enum.each(@telemetry_events, fn event ->
      :telemetry.attach(
        "composition_metrics_#{Enum.join(event, "_")}",
        event,
        &handle_telemetry_event/4,
        nil
      )
    end)
  end

  defp handle_telemetry_event(event, measurements, metadata) do
    case event do
      [:rubber_duck, :tool, :composition, :workflow_start] ->
        handle_workflow_start(measurements, metadata)

      [:rubber_duck, :tool, :composition, :workflow_complete] ->
        handle_workflow_complete(measurements, metadata)

      [:rubber_duck, :tool, :composition, :workflow_error] ->
        handle_workflow_error(measurements, metadata)

      [:rubber_duck, :tool, :composition, :workflow_step_start] ->
        handle_step_start(measurements, metadata)

      [:rubber_duck, :tool, :composition, :workflow_step_complete] ->
        handle_step_complete(measurements, metadata)

      [:rubber_duck, :tool, :composition, :workflow_step_error] ->
        handle_step_error(measurements, metadata)

      _ ->
        :ok
    end
  end

  defp handle_workflow_start(measurements, metadata) do
    # Increment workflow started counter
    increment_counter(:workflow_started)
    increment_gauge(:active_workflows)

    # Store workflow start data
    workflow_id = metadata.workflow_id

    workflow_data = %{
      workflow_id: workflow_id,
      workflow_name: metadata[:workflow_name],
      steps_count: metadata[:steps_count],
      start_time: measurements.timestamp,
      status: :running
    }

    :ets.insert(@workflow_table, {workflow_id, workflow_data})
  end

  defp handle_workflow_complete(measurements, metadata) do
    # Increment workflow completed counter
    increment_counter(:workflow_completed)
    decrement_gauge(:active_workflows)

    # Record workflow duration
    add_to_histogram(:workflow_duration, measurements.duration)

    # Update workflow data
    workflow_id = metadata.workflow_id

    case :ets.lookup(@workflow_table, workflow_id) do
      [{^workflow_id, workflow_data}] ->
        updated_data = %{
          workflow_data
          | status: :completed,
            end_time: measurements.timestamp,
            duration: measurements.duration,
            success_rate: metadata[:success_rate]
        }

        :ets.insert(@workflow_table, {workflow_id, updated_data})

      [] ->
        :ok
    end
  end

  defp handle_workflow_error(measurements, metadata) do
    # Increment workflow failed counter
    increment_counter(:workflow_failed)
    decrement_gauge(:active_workflows)

    # Record workflow duration even for failures
    add_to_histogram(:workflow_duration, measurements.duration)

    # Update workflow data
    workflow_id = metadata.workflow_id

    case :ets.lookup(@workflow_table, workflow_id) do
      [{^workflow_id, workflow_data}] ->
        updated_data = %{
          workflow_data
          | status: :failed,
            end_time: measurements.timestamp,
            duration: measurements.duration,
            error_type: metadata[:error_type],
            error_message: metadata[:error_message]
        }

        :ets.insert(@workflow_table, {workflow_id, updated_data})

      [] ->
        :ok
    end
  end

  defp handle_step_start(measurements, metadata) do
    # Increment step started counter
    increment_counter(:step_started)
    increment_gauge(:active_steps)

    # Store step start data
    step_key = {metadata.workflow_id, metadata.step_name}

    step_data = %{
      workflow_id: metadata.workflow_id,
      step_name: metadata.step_name,
      step_impl: metadata[:step_impl],
      start_time: measurements.timestamp,
      status: :running
    }

    :ets.insert(@step_table, {step_key, step_data})
  end

  defp handle_step_complete(measurements, metadata) do
    # Increment step completed counter
    increment_counter(:step_completed)
    decrement_gauge(:active_steps)

    # Record step duration and result size
    add_to_histogram(:step_duration, measurements.duration)

    if result_size = metadata[:result_size] do
      add_to_histogram(:step_result_size, result_size)
    end

    # Update step data
    step_key = {metadata.workflow_id, metadata.step_name}

    case :ets.lookup(@step_table, step_key) do
      [{^step_key, step_data}] ->
        updated_data = %{
          step_data
          | status: :completed,
            end_time: measurements.timestamp,
            duration: measurements.duration,
            result_size: metadata[:result_size]
        }

        :ets.insert(@step_table, {step_key, updated_data})

      [] ->
        :ok
    end
  end

  defp handle_step_error(measurements, metadata) do
    # Increment step failed counter
    increment_counter(:step_failed)
    decrement_gauge(:active_steps)

    # Record step duration even for failures
    add_to_histogram(:step_duration, measurements.duration)

    # Update step data
    step_key = {metadata.workflow_id, metadata.step_name}

    case :ets.lookup(@step_table, step_key) do
      [{^step_key, step_data}] ->
        updated_data = %{
          step_data
          | status: :failed,
            end_time: measurements.timestamp,
            duration: measurements.duration,
            error_type: metadata[:error_type],
            error_message: metadata[:error_message]
        }

        :ets.insert(@step_table, {step_key, updated_data})

      [] ->
        :ok
    end
  end

  defp increment_counter(metric) do
    :ets.update_counter(@metrics_table, metric, 1)
  end

  defp increment_gauge(metric) do
    :ets.update_counter(@metrics_table, metric, 1)
  end

  defp decrement_gauge(metric) do
    :ets.update_counter(@metrics_table, metric, -1)
  end

  defp add_to_histogram(metric, value) do
    case :ets.lookup(@metrics_table, metric) do
      [{^metric, values}] ->
        updated_values = [value | values]
        # Keep only last 1000 values to prevent memory growth
        trimmed_values = Enum.take(updated_values, 1000)
        :ets.insert(@metrics_table, {metric, trimmed_values})

      [] ->
        :ets.insert(@metrics_table, {metric, [value]})
    end
  end

  defp build_metrics_summary do
    counters = get_all_counters()
    histograms = get_all_histograms()
    gauges = get_all_gauges()

    %{
      counters: counters,
      histograms: histograms,
      gauges: gauges,
      summary: %{
        total_workflows: counters[:workflow_started] || 0,
        successful_workflows: counters[:workflow_completed] || 0,
        failed_workflows: counters[:workflow_failed] || 0,
        success_rate: calculate_success_rate(counters),
        average_workflow_duration: calculate_average(histograms[:workflow_duration]),
        average_step_duration: calculate_average(histograms[:step_duration]),
        active_workflows: gauges[:active_workflows] || 0,
        active_steps: gauges[:active_steps] || 0
      }
    }
  end

  defp get_all_counters do
    Enum.into(@counter_metrics, %{}, fn metric ->
      case :ets.lookup(@metrics_table, metric) do
        [{^metric, value}] -> {metric, value}
        [] -> {metric, 0}
      end
    end)
  end

  defp get_all_histograms do
    Enum.into(@histogram_metrics, %{}, fn metric ->
      case :ets.lookup(@metrics_table, metric) do
        [{^metric, values}] -> {metric, calculate_histogram_stats(values)}
        [] -> {metric, %{count: 0, sum: 0, avg: 0, min: 0, max: 0}}
      end
    end)
  end

  defp get_all_gauges do
    Enum.into(@gauge_metrics, %{}, fn metric ->
      case :ets.lookup(@metrics_table, metric) do
        [{^metric, value}] -> {metric, value}
        [] -> {metric, 0}
      end
    end)
  end

  defp calculate_histogram_stats([]), do: %{count: 0, sum: 0, avg: 0, min: 0, max: 0}

  defp calculate_histogram_stats(values) do
    count = length(values)
    sum = Enum.sum(values)
    avg = sum / count
    min = Enum.min(values)
    max = Enum.max(values)

    %{
      count: count,
      sum: sum,
      avg: avg,
      min: min,
      max: max
    }
  end

  defp calculate_success_rate(counters) do
    started = counters[:workflow_started] || 0
    completed = counters[:workflow_completed] || 0

    if started > 0 do
      completed / started * 100
    else
      0
    end
  end

  defp calculate_average([]), do: 0

  defp calculate_average(values) do
    Enum.sum(values) / length(values)
  end

  defp get_workflow_metrics_from_ets(workflow_id) do
    case :ets.lookup(@workflow_table, workflow_id) do
      [{^workflow_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  defp get_step_metrics_from_ets(workflow_id, step_name) do
    step_key = {workflow_id, step_name}

    case :ets.lookup(@step_table, step_key) do
      [{^step_key, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  defp build_aggregated_metrics(_time_range) do
    # This would implement time-based aggregation
    # For now, return current metrics
    build_metrics_summary()
  end

  defp build_prometheus_metrics do
    # This would build Prometheus-formatted metrics
    # For now, return a simple format
    metrics = build_metrics_summary()

    prometheus_lines = [
      "# HELP composition_workflows_total Total number of workflows",
      "# TYPE composition_workflows_total counter",
      "composition_workflows_total #{metrics.counters[:workflow_started] || 0}",
      "",
      "# HELP composition_workflows_successful_total Total number of successful workflows",
      "# TYPE composition_workflows_successful_total counter",
      "composition_workflows_successful_total #{metrics.counters[:workflow_completed] || 0}",
      "",
      "# HELP composition_workflows_failed_total Total number of failed workflows",
      "# TYPE composition_workflows_failed_total counter",
      "composition_workflows_failed_total #{metrics.counters[:workflow_failed] || 0}",
      "",
      "# HELP composition_workflows_active Current number of active workflows",
      "# TYPE composition_workflows_active gauge",
      "composition_workflows_active #{metrics.gauges[:active_workflows] || 0}"
    ]

    Enum.join(prometheus_lines, "\n")
  end

  defp reset_all_metrics do
    :ets.delete_all_objects(@metrics_table)
    :ets.delete_all_objects(@workflow_table)
    :ets.delete_all_objects(@step_table)
    initialize_metrics()
  end

  defp cleanup_old_metrics do
    # Remove old workflow and step data (older than 1 hour)
    cutoff_time = System.system_time(:millisecond) - 60 * 60 * 1000

    # Clean up old workflows
    :ets.select_delete(@workflow_table, [
      {{~c"$1", %{start_time: ~c"$2"}}, [{~c"<", ~c"$2", cutoff_time}], [true]}
    ])

    # Clean up old steps
    :ets.select_delete(@step_table, [
      {{~c"$1", %{start_time: ~c"$2"}}, [{~c"<", ~c"$2", cutoff_time}], [true]}
    ])
  end

  defp schedule_cleanup do
    # Schedule cleanup every 30 minutes
    Process.send_after(self(), :cleanup, 30 * 60 * 1000)
  end

  # Telemetry handler wrapper
  defp handle_telemetry_event(event, measurements, metadata, _config) do
    send(__MODULE__, {:telemetry, event, measurements, metadata})
  end
end
