defmodule RubberDuck.Telemetry.StatusHandler do
  @moduledoc """
  Telemetry handler for status monitoring and broadcasting events.

  Handles events from:
  - Status monitoring system
  - Health checks and alerts
  - Performance optimizations
  - Status broadcasting and channel events
  """

  require Logger

  @doc """
  Attaches telemetry handlers for status events.
  """
  def attach do
    events = [
      # Monitor events
      [:rubber_duck, :status, :monitor, :health],
      [:rubber_duck, :status, :monitor, :alert],
      [:rubber_duck, :status, :optimizer, :adjusted],

      # Broadcaster events
      [:rubber_duck, :status, :broadcaster, :message_dropped],
      [:rubber_duck, :status, :broadcaster, :queue_depth],
      [:rubber_duck, :status, :broadcaster, :batch_processed],
      [:rubber_duck, :status, :broadcaster, :task_failed],
      [:rubber_duck, :status, :broadcaster, :broadcast_completed],

      # Channel events
      [:rubber_duck, :status_channel, :message_delivered],
      [:rubber_duck, :status_channel, :disconnected]
    ]

    :telemetry.attach_many(
      "rubber-duck-status-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc """
  Handles status telemetry events.
  """
  # Monitor events
  def handle_event([:rubber_duck, :status, :monitor, :health], measurements, metadata, _config) do
    Logger.info("Health check performed",
      component: metadata.component,
      status: metadata.status,
      latency_ms: measurements[:latency_ms],
      memory_mb: measurements[:memory_mb]
    )

    :ok
  end

  def handle_event([:rubber_duck, :status, :monitor, :alert], measurements, metadata, _config) do
    Logger.warning("Health alert triggered",
      component: metadata.component,
      alert_type: metadata.alert_type,
      threshold: metadata.threshold,
      current_value: measurements[:value]
    )

    :ok
  end

  def handle_event([:rubber_duck, :status, :optimizer, :adjusted], _measurements, metadata, _config) do
    Logger.info("Performance optimizer adjusted settings",
      component: metadata.component,
      adjustment_type: metadata.adjustment_type,
      old_value: metadata.old_value,
      new_value: metadata.new_value,
      reason: metadata.reason
    )

    :ok
  end

  # Broadcaster events
  def handle_event([:rubber_duck, :status, :broadcaster, :message_dropped], measurements, metadata, _config) do
    Logger.warning("Status broadcaster dropped message",
      reason: metadata.reason,
      queue_size: measurements.queue_size,
      message_type: metadata[:message_type]
    )

    :ok
  end

  def handle_event([:rubber_duck, :status, :broadcaster, :queue_depth], measurements, _metadata, _config) do
    # The broadcaster sends 'size' not 'depth'
    queue_size = measurements[:size] || 0
    
    if queue_size > 1000 do
      Logger.warning("Status broadcaster queue depth high",
        depth: queue_size,
        processing_rate: measurements[:processing_rate]
      )
    else
      Logger.debug("Status broadcaster queue depth",
        depth: queue_size
      )
    end

    :ok
  end

  def handle_event([:rubber_duck, :status, :broadcaster, :batch_processed], measurements, _metadata, _config) do
    Logger.debug("Status broadcaster processed batch",
      batch_size: measurements.batch_size,
      remaining: measurements[:remaining]
    )

    :ok
  end

  def handle_event([:rubber_duck, :status, :broadcaster, :task_failed], _measurements, metadata, _config) do
    Logger.error("Status broadcaster task failed",
      error: inspect(metadata.error),
      task_type: metadata[:task_type],
      retry_count: metadata[:retry_count]
    )

    :ok
  end

  def handle_event([:rubber_duck, :status, :broadcaster, :broadcast_completed], measurements, metadata, _config) do
    Logger.debug("Status broadcast completed",
      recipients_count: measurements.recipients_count,
      duration_ms: div(measurements.duration, 1_000),
      message_type: metadata.message_type
    )

    :ok
  end

  # Channel events
  def handle_event([:rubber_duck, :status_channel, :message_delivered], measurements, metadata, _config) do
    Logger.debug("Status channel message delivered",
      channel: metadata.channel,
      message_type: metadata.message_type,
      latency_ms: measurements[:latency_ms]
    )

    :ok
  end

  def handle_event([:rubber_duck, :status_channel, :disconnected], measurements, metadata, _config) do
    # Handle metadata safely - channel key might not be present
    log_metadata = [
      conversation_id: metadata[:conversation_id],
      user_id: metadata[:user_id],
      subscribed_categories: metadata[:subscribed_categories],
      duration_ms: measurements[:duration_ms]
    ]
    
    # Only add non-nil values
    log_metadata = Enum.filter(log_metadata, fn {_k, v} -> v != nil end)
    
    Logger.info("Status channel disconnected", log_metadata)

    :ok
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
