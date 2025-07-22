defmodule RubberDuck.Telemetry.WorkflowHandler do
  @moduledoc """
  Telemetry handler for workflow and reactor-related events.
  
  Handles events from:
  - Reactor step execution
  - Workflow orchestration
  - Hybrid bridge events
  - Engine pool and lifecycle events
  """
  
  require Logger
  
  @doc """
  Attaches telemetry handlers for workflow events.
  """
  def attach do
    events = [
      # Reactor events
      [:reactor, :step, :run, :start],
      [:reactor, :step, :run, :stop],
      [:reactor, :step, :run, :exception],
      
      # Hybrid bridge events
      [:rubber_duck, :hybrid, :bridge, :start],
      [:rubber_duck, :hybrid, :bridge, :stop],
      [:rubber_duck, :hybrid, :bridge, :exception],
      
      # Engine events
      [:rubber_duck, :engine, :pool, :checkout],
      [:rubber_duck, :engine, :pool, :checkin],
      [:rubber_duck, :engine, :pool, :overflow],
      [:rubber_duck, :engine, :lifecycle, :start],
      [:rubber_duck, :engine, :lifecycle, :stop],
      
      # Workflow metrics
      [:rubber_duck, :workflows, :metrics, :reported]
    ]
    
    :telemetry.attach_many(
      "rubber-duck-workflow-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end
  
  @doc """
  Handles workflow telemetry events.
  """
  # Reactor events
  def handle_event([:reactor, :step, :run, :start], _measurements, metadata, _config) do
    Logger.debug("Reactor step started",
      step_name: metadata[:name],
      reactor: metadata[:reactor],
      inputs: inspect(metadata[:inputs], limit: :infinity, printable_limit: :infinity)
    )
    :ok
  end
  
  def handle_event([:reactor, :step, :run, :stop], measurements, metadata, _config) do
    Logger.info("Reactor step completed",
      step_name: metadata[:name],
      reactor: metadata[:reactor],
      duration_ms: div(measurements.duration, 1_000),
      result: inspect(metadata[:result], limit: :infinity, printable_limit: :infinity)
    )
    :ok
  end
  
  def handle_event([:reactor, :step, :run, :exception], measurements, metadata, _config) do
    Logger.error("Reactor step failed",
      step_name: metadata[:name],
      reactor: metadata[:reactor],
      error: inspect(metadata[:error]),
      stacktrace: inspect(metadata[:stacktrace]),
      duration_ms: div(measurements[:duration] || 0, 1_000)
    )
    :ok
  end
  
  # Hybrid bridge events
  def handle_event([:rubber_duck, :hybrid, :bridge, :start], _measurements, metadata, _config) do
    Logger.info("Hybrid bridge operation started",
      operation: metadata.operation,
      bridge_type: metadata[:bridge_type],
      request_id: metadata[:request_id]
    )
    :ok
  end
  
  def handle_event([:rubber_duck, :hybrid, :bridge, :stop], measurements, metadata, _config) do
    Logger.info("Hybrid bridge operation completed",
      operation: metadata.operation,
      bridge_type: metadata[:bridge_type],
      request_id: metadata[:request_id],
      duration_ms: div(measurements.duration, 1_000),
      success: metadata[:success]
    )
    :ok
  end
  
  def handle_event([:rubber_duck, :hybrid, :bridge, :exception], measurements, metadata, _config) do
    Logger.error("Hybrid bridge operation failed",
      operation: metadata.operation,
      bridge_type: metadata[:bridge_type],
      request_id: metadata[:request_id],
      error: inspect(metadata.error),
      duration_ms: div(measurements[:duration] || 0, 1_000)
    )
    :ok
  end
  
  # Engine pool events
  def handle_event([:rubber_duck, :engine, :pool, :checkout], measurements, metadata, _config) do
    Logger.debug("Engine checked out from pool",
      engine_type: metadata.engine_type,
      pool_size: measurements[:pool_size],
      available: measurements[:available_count],
      wait_time_ms: div(measurements[:wait_time] || 0, 1_000)
    )
    :ok
  end
  
  def handle_event([:rubber_duck, :engine, :pool, :checkin], measurements, metadata, _config) do
    Logger.debug("Engine returned to pool",
      engine_type: metadata.engine_type,
      pool_size: measurements[:pool_size],
      available: measurements[:available_count],
      usage_time_ms: div(measurements[:usage_time] || 0, 1_000)
    )
    :ok
  end
  
  def handle_event([:rubber_duck, :engine, :pool, :overflow], measurements, metadata, _config) do
    Logger.warning("Engine pool overflow",
      engine_type: metadata.engine_type,
      pool_size: measurements.pool_size,
      overflow_count: measurements.overflow_count,
      wait_queue_length: measurements[:wait_queue_length]
    )
    :ok
  end
  
  # Engine lifecycle events
  def handle_event([:rubber_duck, :engine, :lifecycle, :start], _measurements, metadata, _config) do
    Logger.info("Engine started",
      engine_type: metadata.engine_type,
      engine_id: metadata.engine_id,
      capabilities: metadata[:capabilities]
    )
    :ok
  end
  
  def handle_event([:rubber_duck, :engine, :lifecycle, :stop], measurements, metadata, _config) do
    Logger.info("Engine stopped",
      engine_type: metadata.engine_type,
      engine_id: metadata.engine_id,
      uptime_seconds: div(measurements[:uptime] || 0, 1_000_000),
      requests_handled: measurements[:requests_handled]
    )
    :ok
  end
  
  # Workflow metrics
  def handle_event([:rubber_duck, :workflows, :metrics, :reported], measurements, metadata, _config) do
    Logger.debug("Workflow metrics reported",
      workflow_type: metadata[:workflow_type],
      success_rate: measurements[:success_rate],
      avg_duration_ms: measurements[:avg_duration_ms],
      total_executions: measurements[:total_executions],
      period: metadata[:period]
    )
    :ok
  end
  
  def handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end