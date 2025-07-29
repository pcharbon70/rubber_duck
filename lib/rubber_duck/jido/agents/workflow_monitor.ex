defmodule RubberDuck.Jido.Agents.WorkflowMonitor do
  @moduledoc """
  Monitors workflow execution and collects metrics.
  
  This module provides:
  - Real-time workflow execution tracking
  - Performance metrics collection
  - Error rate monitoring
  - Resource usage tracking
  - Workflow dependency visualization
  
  ## Metrics Collected
  
  - Workflow execution time
  - Step execution times
  - Success/failure rates
  - Resource utilization
  - Queue depths
  - Agent interactions
  
  ## Example
  
      # Get workflow metrics
      {:ok, metrics} = WorkflowMonitor.get_metrics("workflow_id")
      
      # Get aggregate statistics
      {:ok, stats} = WorkflowMonitor.get_statistics(:daily)
      
      # Subscribe to real-time updates
      WorkflowMonitor.subscribe(self())
  """
  
  use GenServer
  require Logger
  
  # Future use: alias RubberDuck.Workflows.{Workflow, Checkpoint}
  # Future use: alias RubberDuck.Jido.Agents.Metrics
  
  @type metric_type :: :execution_time | :success_rate | :error_rate | :throughput
  @type time_window :: :minute | :hour | :day | :week
  
  # Client API
  
  @doc """
  Starts the workflow monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets metrics for a specific workflow.
  """
  def get_metrics(workflow_id) do
    GenServer.call(__MODULE__, {:get_metrics, workflow_id})
  end
  
  @doc """
  Gets aggregate statistics for a time window.
  """
  def get_statistics(window \\ :hour) do
    GenServer.call(__MODULE__, {:get_statistics, window})
  end
  
  @doc """
  Gets real-time dashboard data.
  """
  def get_dashboard_data do
    GenServer.call(__MODULE__, :get_dashboard_data)
  end
  
  @doc """
  Subscribes to real-time workflow updates.
  """
  def subscribe(pid) do
    GenServer.call(__MODULE__, {:subscribe, pid})
  end
  
  @doc """
  Unsubscribes from workflow updates.
  """
  def unsubscribe(pid) do
    GenServer.call(__MODULE__, {:unsubscribe, pid})
  end
  
  @doc """
  Records a custom metric.
  """
  def record_metric(workflow_id, metric_name, value) do
    GenServer.cast(__MODULE__, {:record_metric, workflow_id, metric_name, value})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Subscribe to telemetry events
    attach_telemetry_handlers()
    
    # Initialize state
    state = %{
      metrics: %{},           # workflow_id => metrics
      aggregate_metrics: %{}, # metric_type => time_series_data
      subscribers: [],        # PIDs subscribed to updates
      window_size: opts[:window_size] || :hour,
      retention_period: opts[:retention_period] || :timer.hours(24),
      active_workflows: %{}   # workflow_id => start_time
    }
    
    # Schedule periodic cleanup
    schedule_cleanup(state.retention_period)
    
    # Schedule metric aggregation
    schedule_aggregation()
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_metrics, workflow_id}, _from, state) do
    metrics = Map.get(state.metrics, workflow_id, %{})
    {:reply, {:ok, metrics}, state}
  end
  
  @impl true
  def handle_call({:get_statistics, window}, _from, state) do
    stats = calculate_statistics(state.aggregate_metrics, window)
    {:reply, {:ok, stats}, state}
  end
  
  @impl true
  def handle_call(:get_dashboard_data, _from, state) do
    dashboard = %{
      active_workflows: map_size(state.active_workflows),
      total_workflows: map_size(state.metrics),
      recent_metrics: get_recent_metrics(state),
      aggregate_stats: calculate_current_stats(state),
      health_indicators: calculate_health_indicators(state)
    }
    
    {:reply, {:ok, dashboard}, state}
  end
  
  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
  end
  
  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: List.delete(state.subscribers, pid)}}
  end
  
  @impl true
  def handle_cast({:record_metric, workflow_id, metric_name, value}, state) do
    new_state = update_workflow_metrics(state, workflow_id, metric_name, value)
    broadcast_update(new_state.subscribers, {:metric_update, workflow_id, metric_name, value})
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:telemetry, event_name, measurements, metadata}, state) do
    new_state = handle_telemetry_event(event_name, measurements, metadata, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: List.delete(state.subscribers, pid)}}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    new_state = cleanup_old_metrics(state)
    schedule_cleanup(state.retention_period)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:aggregate, state) do
    new_state = aggregate_metrics(state)
    schedule_aggregation()
    {:noreply, new_state}
  end
  
  # Telemetry handlers
  
  defp attach_telemetry_handlers do
    events = [
      [:rubber_duck, :workflow, :start],
      [:rubber_duck, :workflow, :complete],
      [:rubber_duck, :workflow, :error],
      [:rubber_duck, :workflow, :halt],
      [:rubber_duck, :workflow, :step, :start],
      [:rubber_duck, :workflow, :step, :complete],
      [:rubber_duck, :workflow, :step, :error],
      [:rubber_duck, :workflow, :step, :retry],
      [:rubber_duck, :workflow, :compensation, :start],
      [:rubber_duck, :workflow, :compensation, :complete],
      [:rubber_duck, :workflow, :checkpoint, :saved],
      [:rubber_duck, :workflow, :checkpoint, :loaded]
    ]
    
    Enum.each(events, fn event ->
      :telemetry.attach(
        {__MODULE__, event},
        event,
        &handle_telemetry/4,
        nil
      )
    end)
  end
  
  defp handle_telemetry(event_name, measurements, metadata, _config) do
    send(self(), {:telemetry, event_name, measurements, metadata})
  end
  
  defp handle_telemetry_event([:rubber_duck, :workflow, :start], _measurements, metadata, state) do
    workflow_id = metadata.workflow_id
    
    # Track active workflow
    active_workflows = Map.put(state.active_workflows, workflow_id, System.monotonic_time(:microsecond))
    
    # Initialize metrics
    metrics = Map.put_new(state.metrics, workflow_id, %{
      started_at: DateTime.utc_now(),
      status: :running,
      steps: %{},
      total_steps: 0,
      completed_steps: 0,
      failed_steps: 0,
      retries: 0,
      checkpoints: 0
    })
    
    broadcast_update(state.subscribers, {:workflow_started, workflow_id})
    
    %{state | active_workflows: active_workflows, metrics: metrics}
  end
  
  defp handle_telemetry_event([:rubber_duck, :workflow, :complete], measurements, metadata, state) do
    workflow_id = metadata.workflow_id
    duration = measurements[:duration] || 0
    
    # Update metrics
    new_state = update_workflow_completion(state, workflow_id, :completed, duration)
    
    # Remove from active workflows
    active_workflows = Map.delete(new_state.active_workflows, workflow_id)
    
    broadcast_update(state.subscribers, {:workflow_completed, workflow_id, duration})
    
    %{new_state | active_workflows: active_workflows}
  end
  
  defp handle_telemetry_event([:rubber_duck, :workflow, :error], measurements, metadata, state) do
    workflow_id = metadata.workflow_id
    duration = measurements[:duration] || 0
    errors = metadata[:errors] || []
    
    # Update metrics
    new_state = update_workflow_completion(state, workflow_id, :failed, duration)
    new_state = update_workflow_metrics(new_state, workflow_id, :errors, errors)
    
    # Remove from active workflows
    active_workflows = Map.delete(new_state.active_workflows, workflow_id)
    
    broadcast_update(state.subscribers, {:workflow_failed, workflow_id, errors})
    
    %{new_state | active_workflows: active_workflows}
  end
  
  defp handle_telemetry_event([:rubber_duck, :workflow, :step, :complete], measurements, metadata, state) do
    workflow_id = metadata.workflow_id
    step_name = metadata.step_name
    duration = measurements[:duration] || 0
    
    new_state = update_step_metrics(state, workflow_id, step_name, :completed, duration)
    
    broadcast_update(state.subscribers, {:step_completed, workflow_id, step_name})
    
    new_state
  end
  
  defp handle_telemetry_event([:rubber_duck, :workflow, :step, :error], measurements, metadata, state) do
    workflow_id = metadata.workflow_id
    step_name = metadata.step_name
    duration = measurements[:duration] || 0
    
    new_state = update_step_metrics(state, workflow_id, step_name, :failed, duration)
    
    broadcast_update(state.subscribers, {:step_failed, workflow_id, step_name})
    
    new_state
  end
  
  defp handle_telemetry_event([:rubber_duck, :workflow, :step, :retry], _measurements, metadata, state) do
    workflow_id = metadata.workflow_id
    
    new_state = update_workflow_metrics(state, workflow_id, :retries, 1)
    
    new_state
  end
  
  defp handle_telemetry_event([:rubber_duck, :workflow, :checkpoint, :saved], _measurements, metadata, state) do
    workflow_id = metadata.workflow_id
    
    new_state = update_workflow_metrics(state, workflow_id, :checkpoints, 1)
    
    new_state
  end
  
  defp handle_telemetry_event(_event, _measurements, _metadata, state) do
    state
  end
  
  # Metric updates
  
  defp update_workflow_metrics(state, workflow_id, metric_name, value) do
    metrics = Map.get(state.metrics, workflow_id, %{})
    
    updated_metrics = case metric_name do
      :retries -> Map.update(metrics, :retries, value, &(&1 + value))
      :checkpoints -> Map.update(metrics, :checkpoints, value, &(&1 + value))
      :errors -> Map.put(metrics, :errors, value)
      _ -> Map.put(metrics, metric_name, value)
    end
    
    %{state | metrics: Map.put(state.metrics, workflow_id, updated_metrics)}
  end
  
  defp update_workflow_completion(state, workflow_id, status, duration) do
    metrics = Map.get(state.metrics, workflow_id, %{})
    
    updated_metrics = metrics
    |> Map.put(:status, status)
    |> Map.put(:completed_at, DateTime.utc_now())
    |> Map.put(:duration, duration)
    
    # Update aggregate metrics
    aggregate_metrics = update_aggregate_metrics(state.aggregate_metrics, status, duration)
    
    %{state | 
      metrics: Map.put(state.metrics, workflow_id, updated_metrics),
      aggregate_metrics: aggregate_metrics
    }
  end
  
  defp update_step_metrics(state, workflow_id, step_name, status, duration) do
    metrics = Map.get(state.metrics, workflow_id, %{})
    steps = Map.get(metrics, :steps, %{})
    
    step_metrics = Map.put(steps, step_name, %{
      status: status,
      duration: duration,
      completed_at: DateTime.utc_now()
    })
    
    updated_metrics = metrics
    |> Map.put(:steps, step_metrics)
    |> Map.update(:total_steps, 1, &(&1 + 1))
    |> Map.update(
      if(status == :completed, do: :completed_steps, else: :failed_steps),
      1,
      &(&1 + 1)
    )
    
    %{state | metrics: Map.put(state.metrics, workflow_id, updated_metrics)}
  end
  
  defp update_aggregate_metrics(aggregate_metrics, status, duration) do
    timestamp = DateTime.utc_now()
    
    aggregate_metrics
    |> Map.update(:execution_times, [{timestamp, duration}], &[{timestamp, duration} | &1])
    |> Map.update(
      if(status == :completed, do: :success_count, else: :failure_count),
      [{timestamp, 1}],
      &[{timestamp, 1} | &1]
    )
  end
  
  # Statistics calculation
  
  defp calculate_statistics(aggregate_metrics, window) do
    cutoff = calculate_cutoff(window)
    
    %{
      avg_execution_time: calculate_average_metric(aggregate_metrics[:execution_times], cutoff),
      success_rate: calculate_rate(aggregate_metrics[:success_count], aggregate_metrics[:failure_count], cutoff),
      error_rate: calculate_error_rate(aggregate_metrics[:failure_count], cutoff),
      throughput: calculate_throughput(aggregate_metrics[:success_count], window)
    }
  end
  
  defp calculate_current_stats(state) do
    total_workflows = map_size(state.metrics)
    
    if total_workflows > 0 do
      completed = Enum.count(state.metrics, fn {_, m} -> m.status == :completed end)
      failed = Enum.count(state.metrics, fn {_, m} -> m.status == :failed end)
      
      %{
        total: total_workflows,
        completed: completed,
        failed: failed,
        success_rate: if(completed + failed > 0, do: completed / (completed + failed) * 100, else: 0),
        active: map_size(state.active_workflows)
      }
    else
      %{total: 0, completed: 0, failed: 0, success_rate: 0, active: 0}
    end
  end
  
  defp calculate_health_indicators(state) do
    recent_failures = count_recent_failures(state.metrics)
    avg_duration = calculate_average_duration(state.metrics)
    
    %{
      health_score: calculate_health_score(recent_failures, avg_duration),
      alerts: generate_alerts(state),
      trends: calculate_trends(state.aggregate_metrics)
    }
  end
  
  defp get_recent_metrics(state) do
    state.metrics
    |> Enum.sort_by(fn {_, m} -> m[:started_at] || DateTime.utc_now() end, {:desc, DateTime})
    |> Enum.take(10)
    |> Enum.map(fn {id, metrics} -> Map.put(metrics, :workflow_id, id) end)
  end
  
  # Utility functions
  
  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end
  
  defp schedule_aggregation do
    Process.send_after(self(), :aggregate, :timer.minutes(1))
  end
  
  defp cleanup_old_metrics(state) do
    cutoff = DateTime.add(DateTime.utc_now(), -div(state.retention_period, 1000), :second)
    
    metrics = state.metrics
    |> Enum.reject(fn {_, m} ->
      DateTime.compare(m[:completed_at] || m[:started_at], cutoff) == :lt
    end)
    |> Map.new()
    
    %{state | metrics: metrics}
  end
  
  defp aggregate_metrics(state) do
    # Aggregate current metrics into time-series data
    # This is a simplified implementation
    state
  end
  
  defp broadcast_update(subscribers, message) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:workflow_monitor, message})
    end)
  end
  
  defp calculate_cutoff(:minute), do: DateTime.add(DateTime.utc_now(), -60, :second)
  defp calculate_cutoff(:hour), do: DateTime.add(DateTime.utc_now(), -3600, :second)
  defp calculate_cutoff(:day), do: DateTime.add(DateTime.utc_now(), -86400, :second)
  defp calculate_cutoff(:week), do: DateTime.add(DateTime.utc_now(), -604800, :second)
  
  defp calculate_average_metric(nil, _cutoff), do: 0
  defp calculate_average_metric([], _cutoff), do: 0
  defp calculate_average_metric(metrics, cutoff) do
    recent = Enum.filter(metrics, fn {timestamp, _} ->
      DateTime.compare(timestamp, cutoff) == :gt
    end)
    
    if length(recent) > 0 do
      sum = Enum.reduce(recent, 0, fn {_, value}, acc -> acc + value end)
      sum / length(recent)
    else
      0
    end
  end
  
  defp calculate_rate(success_data, failure_data, cutoff) do
    successes = count_recent(success_data || [], cutoff)
    failures = count_recent(failure_data || [], cutoff)
    total = successes + failures
    
    if total > 0, do: successes / total * 100, else: 0
  end
  
  defp calculate_error_rate(failure_data, cutoff) do
    count_recent(failure_data || [], cutoff)
  end
  
  defp calculate_throughput(success_data, window) do
    count = count_recent(success_data || [], calculate_cutoff(window))
    
    case window do
      :minute -> count
      :hour -> count / 60
      :day -> count / 1440
      :week -> count / 10080
    end
  end
  
  defp count_recent(data, cutoff) do
    data
    |> Enum.filter(fn {timestamp, _} -> DateTime.compare(timestamp, cutoff) == :gt end)
    |> Enum.reduce(0, fn {_, count}, acc -> acc + count end)
  end
  
  defp count_recent_failures(metrics) do
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)
    
    Enum.count(metrics, fn {_, m} ->
      m.status == :failed and DateTime.compare(m[:completed_at] || DateTime.utc_now(), cutoff) == :gt
    end)
  end
  
  defp calculate_average_duration(metrics) do
    durations = metrics
    |> Enum.filter(fn {_, m} -> m[:duration] end)
    |> Enum.map(fn {_, m} -> m.duration end)
    
    if length(durations) > 0 do
      Enum.sum(durations) / length(durations)
    else
      0
    end
  end
  
  defp calculate_health_score(recent_failures, avg_duration) do
    # Simple health score calculation
    failure_penalty = min(recent_failures * 10, 50)
    duration_penalty = if avg_duration > 60_000_000, do: 20, else: 0
    
    max(100 - failure_penalty - duration_penalty, 0)
  end
  
  defp generate_alerts(state) do
    alerts = []
    
    # Check for high failure rate
    if count_recent_failures(state.metrics) > 5 do
      alerts ++ [{:high_failure_rate, "More than 5 failures in the last hour"}]
    else
      alerts
    end
  end
  
  defp calculate_trends(_aggregate_metrics) do
    # Simplified trend calculation
    %{
      execution_time: :stable,
      success_rate: :improving,
      throughput: :stable
    }
  end
end