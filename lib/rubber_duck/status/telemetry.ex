defmodule RubberDuck.Status.Telemetry do
  @moduledoc """
  Telemetry integration for the Status Broadcasting System.

  Provides comprehensive metrics collection for monitoring status message
  flow, performance, and system health.

  ## Telemetry Events

  - `[:rubber_duck, :status, :message, :queued]` - Message queued for processing
  - `[:rubber_duck, :status, :batch, :processed]` - Batch of messages processed
  - `[:rubber_duck, :status, :broadcast, :sent]` - Messages broadcast via PubSub
  - `[:rubber_duck, :status, :channel, :subscribed]` - Channel subscription created
  - `[:rubber_duck, :status, :queue, :overflow]` - Queue overflow occurred
  - `[:rubber_duck, :status, :error, :occurred]` - Error in status system

  ## Metrics

  - Queue depth
  - Message throughput
  - Broadcast latency
  - Channel subscription count
  - Error rates
  """

  require Logger

  # Event names
  @message_queued [:rubber_duck, :status, :message, :queued]
  @batch_processed [:rubber_duck, :status, :batch, :processed]
  @broadcast_sent [:rubber_duck, :status, :broadcast, :sent]
  @channel_subscribed [:rubber_duck, :status, :channel, :subscribed]
  @channel_unsubscribed [:rubber_duck, :status, :channel, :unsubscribed]
  @queue_overflow [:rubber_duck, :status, :queue, :overflow]
  @error_occurred [:rubber_duck, :status, :error, :occurred]

  @doc """
  Attaches telemetry handlers for status system monitoring.

  This should be called during application startup.
  """
  def attach_handlers do
    handlers = [
      {[:message_queued], &handle_message_queued/4},
      {[:batch_processed], &handle_batch_processed/4},
      {[:broadcast_sent], &handle_broadcast_sent/4},
      {[:channel_subscribed], &handle_channel_subscribed/4},
      {[:channel_unsubscribed], &handle_channel_unsubscribed/4},
      {[:queue_overflow], &handle_queue_overflow/4},
      {[:error_occurred], &handle_error_occurred/4}
    ]

    Enum.each(handlers, fn {event_suffix, handler} ->
      event = @message_queued |> Enum.take(3) |> Kernel.++(event_suffix)
      handler_id = "status-telemetry-#{Enum.join(event_suffix, "-")}"

      :telemetry.attach(
        handler_id,
        event,
        handler,
        nil
      )
    end)

    Logger.info("Status telemetry handlers attached")
    :ok
  end

  @doc """
  Emits a telemetry event when a message is queued.
  """
  def message_queued(conversation_id, category, metadata \\ %{}) do
    measurements = %{
      count: 1,
      timestamp: System.monotonic_time(:millisecond)
    }

    metadata =
      Map.merge(metadata, %{
        conversation_id: conversation_id,
        category: category
      })

    :telemetry.execute(@message_queued, measurements, metadata)
  end

  @doc """
  Emits a telemetry event when a batch is processed.
  """
  def batch_processed(batch_size, processing_time, metadata \\ %{}) do
    measurements = %{
      batch_size: batch_size,
      processing_time_ms: processing_time,
      throughput: calculate_throughput(batch_size, processing_time)
    }

    :telemetry.execute(@batch_processed, measurements, metadata)
  end

  @doc """
  Emits a telemetry event when messages are broadcast.
  """
  def broadcast_sent(message_count, latency, metadata \\ %{}) do
    measurements = %{
      message_count: message_count,
      latency_ms: latency,
      timestamp: System.monotonic_time(:millisecond)
    }

    :telemetry.execute(@broadcast_sent, measurements, metadata)
  end

  @doc """
  Emits a telemetry event when a channel subscription is created.
  """
  def channel_subscribed(conversation_id, categories, metadata \\ %{}) do
    measurements = %{
      count: 1,
      category_count: length(categories)
    }

    metadata =
      Map.merge(metadata, %{
        conversation_id: conversation_id,
        categories: categories
      })

    :telemetry.execute(@channel_subscribed, measurements, metadata)
  end

  @doc """
  Emits a telemetry event when a channel subscription is removed.
  """
  def channel_unsubscribed(conversation_id, metadata \\ %{}) do
    measurements = %{
      count: 1
    }

    metadata = Map.put(metadata, :conversation_id, conversation_id)

    :telemetry.execute(@channel_unsubscribed, measurements, metadata)
  end

  @doc """
  Emits a telemetry event when queue overflow occurs.
  """
  def queue_overflow(dropped_count, queue_size, metadata \\ %{}) do
    measurements = %{
      dropped_count: dropped_count,
      queue_size: queue_size,
      timestamp: System.monotonic_time(:millisecond)
    }

    :telemetry.execute(@queue_overflow, measurements, metadata)
  end

  @doc """
  Emits a telemetry event when an error occurs.
  """
  def error_occurred(error_type, metadata \\ %{}) do
    measurements = %{
      count: 1,
      timestamp: System.monotonic_time(:millisecond)
    }

    metadata = Map.put(metadata, :error_type, error_type)

    :telemetry.execute(@error_occurred, measurements, metadata)
  end

  @doc """
  Records the current queue depth.
  """
  def record_queue_depth(depth, metadata \\ %{}) do
    measurements = %{
      depth: depth,
      timestamp: System.monotonic_time(:millisecond)
    }

    :telemetry.execute(
      [:rubber_duck, :status, :queue, :depth],
      measurements,
      metadata
    )
  end

  @doc """
  Records channel metrics.
  """
  def record_channel_metrics(active_channels, total_subscribers, metadata \\ %{}) do
    measurements = %{
      active_channels: active_channels,
      total_subscribers: total_subscribers,
      avg_subscribers_per_channel: safe_divide(total_subscribers, active_channels)
    }

    :telemetry.execute(
      [:rubber_duck, :status, :channel, :metrics],
      measurements,
      metadata
    )
  end

  # Handler functions

  defp handle_message_queued(_event, _measurements, metadata, _config) do
    Logger.debug("Status message queued",
      conversation_id: metadata.conversation_id,
      category: metadata.category
    )
  end

  defp handle_batch_processed(_event, measurements, _metadata, _config) do
    Logger.debug("Status batch processed",
      batch_size: measurements.batch_size,
      processing_time_ms: measurements.processing_time_ms,
      throughput: measurements.throughput
    )
  end

  defp handle_broadcast_sent(_event, measurements, _metadata, _config) do
    Logger.debug("Status broadcast sent",
      message_count: measurements.message_count,
      latency_ms: measurements.latency_ms
    )
  end

  defp handle_channel_subscribed(_event, _measurements, metadata, _config) do
    Logger.debug("Channel subscription created",
      conversation_id: metadata.conversation_id,
      categories: metadata.categories
    )
  end

  defp handle_channel_unsubscribed(_event, _measurements, metadata, _config) do
    Logger.debug("Channel subscription removed",
      conversation_id: metadata.conversation_id
    )
  end

  defp handle_queue_overflow(_event, measurements, _metadata, _config) do
    Logger.warning("Status queue overflow!",
      dropped_count: measurements.dropped_count,
      queue_size: measurements.queue_size
    )
  end

  defp handle_error_occurred(_event, _measurements, metadata, _config) do
    Logger.error("Status system error",
      error_type: metadata.error_type,
      details: metadata[:error_details]
    )
  end

  # Helper functions

  defp calculate_throughput(batch_size, processing_time) when processing_time > 0 do
    # messages per second
    batch_size / processing_time * 1000
  end

  defp calculate_throughput(_, _), do: 0

  defp safe_divide(a, b) when b > 0, do: a / b
  defp safe_divide(_, _), do: 0
end
