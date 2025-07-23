defmodule RubberDuck.Telemetry.SecurityHandler do
  @moduledoc """
  Telemetry handler for security-related events.

  Handles events from:
  - MCP security authentication and authorization
  - Security event monitoring
  - Audit logging
  """

  require Logger

  @doc """
  Attaches telemetry handlers for security events.
  """
  def attach do
    events = [
      # MCP Security events
      [:mcp, :security, :authenticate],
      [:mcp, :security, :authorize],

      # Security monitoring events
      [:rubber_duck, :security, :event],

      # Audit events
      [:mcp, :audit, :log]
    ]

    :telemetry.attach_many(
      "rubber-duck-security-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc """
  Handles security telemetry events.
  """
  # MCP Security events
  def handle_event([:mcp, :security, :authenticate], measurements, metadata, _config) do
    case metadata[:result] do
      :success ->
        Logger.info("MCP authentication successful",
          user_id: metadata[:user_id],
          method: metadata[:method],
          duration_ms: div(measurements[:duration] || 0, 1_000)
        )

      :failure ->
        Logger.warning("MCP authentication failed",
          reason: metadata[:reason],
          method: metadata[:method],
          duration_ms: div(measurements[:duration] || 0, 1_000)
        )
    end

    :ok
  end

  def handle_event([:mcp, :security, :authorize], measurements, metadata, _config) do
    case metadata[:result] do
      :granted ->
        Logger.debug("MCP authorization granted",
          user_id: metadata[:user_id],
          resource: metadata[:resource],
          action: metadata[:action],
          duration_ms: div(measurements[:duration] || 0, 1_000)
        )

      :denied ->
        Logger.warning("MCP authorization denied",
          user_id: metadata[:user_id],
          resource: metadata[:resource],
          action: metadata[:action],
          reason: metadata[:reason],
          duration_ms: div(measurements[:duration] || 0, 1_000)
        )
    end

    :ok
  end

  # Security monitoring events
  def handle_event([:rubber_duck, :security, :event], measurements, metadata, _config) do
    severity = metadata[:severity] || :info

    case severity do
      :critical ->
        Logger.error("Critical security event",
          event_type: metadata.event_type,
          details: metadata.details,
          source: metadata[:source],
          timestamp: measurements[:timestamp]
        )

      :warning ->
        Logger.warning("Security warning event",
          event_type: metadata.event_type,
          details: metadata.details,
          source: metadata[:source],
          timestamp: measurements[:timestamp]
        )

      _ ->
        Logger.info("Security event",
          event_type: metadata.event_type,
          details: metadata.details,
          source: metadata[:source],
          timestamp: measurements[:timestamp]
        )
    end

    :ok
  end

  # Audit events
  def handle_event([:mcp, :audit, :log], measurements, metadata, _config) do
    Logger.info("Audit log entry",
      action: metadata.action,
      user_id: metadata[:user_id],
      resource: metadata[:resource],
      resource_id: metadata[:resource_id],
      changes: metadata[:changes],
      result: metadata[:result],
      timestamp: measurements[:timestamp]
    )

    # Could write to dedicated audit log here
    :ok
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
