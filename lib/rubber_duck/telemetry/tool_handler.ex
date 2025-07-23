defmodule RubberDuck.Telemetry.ToolHandler do
  @moduledoc """
  Telemetry handler for tool-related events.

  Handles events from the Tool system including:
  - Tool execution lifecycle
  - Tool validation and authorization
  - Tool composition workflows
  - Performance and error tracking
  """

  require Logger

  @doc """
  Attaches telemetry handlers for tool events.
  """
  def attach do
    events = [
      # Tool execution events
      [:rubber_duck, :tool, :execute, :start],
      [:rubber_duck, :tool, :execute, :stop],
      [:rubber_duck, :tool, :execute, :exception],

      # Tool validation events
      [:rubber_duck, :tool, :validate, :start],
      [:rubber_duck, :tool, :validate, :stop],

      # Tool authorization events
      [:rubber_duck, :tool, :authorize, :start],
      [:rubber_duck, :tool, :authorize, :stop],

      # Tool sandbox events
      [:rubber_duck, :tool, :sandbox, :start],
      [:rubber_duck, :tool, :sandbox, :stop],

      # Tool result events
      [:rubber_duck, :tool, :result, :success],
      [:rubber_duck, :tool, :result, :failure],

      # Composition workflow events
      [:rubber_duck, :tool, :composition, :workflow, :start],
      [:rubber_duck, :tool, :composition, :workflow, :complete],
      [:rubber_duck, :tool, :composition, :workflow, :error],
      [:rubber_duck, :tool, :composition, :workflow, :step, :start],
      [:rubber_duck, :tool, :composition, :workflow, :step, :complete],
      [:rubber_duck, :tool, :composition, :workflow, :step, :error]
    ]

    :telemetry.attach_many(
      "rubber-duck-tool-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc """
  Handles tool telemetry events.
  """
  # Tool execution events
  def handle_event([:rubber_duck, :tool, :execute, :start], _measurements, metadata, _config) do
    Logger.debug("Tool execution started",
      tool_name: metadata.tool_name,
      tool_id: metadata.tool_id,
      input: inspect(metadata.input, limit: :infinity, printable_limit: :infinity)
    )

    :ok
  end

  def handle_event([:rubber_duck, :tool, :execute, :stop], measurements, metadata, _config) do
    Logger.info("Tool execution completed",
      tool_name: metadata.tool_name,
      tool_id: metadata.tool_id,
      duration_ms: div(measurements.duration, 1_000),
      success: metadata.success
    )

    :ok
  end

  def handle_event([:rubber_duck, :tool, :execute, :exception], measurements, metadata, _config) do
    Logger.error("Tool execution failed",
      tool_name: metadata.tool_name,
      tool_id: metadata.tool_id,
      error: inspect(metadata.error),
      duration_ms: div(measurements.duration || 0, 1_000)
    )

    :ok
  end

  # Tool validation events
  def handle_event([:rubber_duck, :tool, :validate, event_type], measurements, metadata, _config)
      when event_type in [:start, :stop] do
    level = if event_type == :start, do: :debug, else: :info

    Logger.log(level, "Tool validation #{event_type}",
      tool_name: metadata.tool_name,
      valid: metadata[:valid],
      duration_ms: div(measurements[:duration] || 0, 1_000)
    )

    :ok
  end

  # Tool authorization events
  def handle_event([:rubber_duck, :tool, :authorize, event_type], measurements, metadata, _config)
      when event_type in [:start, :stop] do
    level = if event_type == :start, do: :debug, else: :info

    Logger.log(level, "Tool authorization #{event_type}",
      tool_name: metadata.tool_name,
      authorized: metadata[:authorized],
      duration_ms: div(measurements[:duration] || 0, 1_000)
    )

    :ok
  end

  # Tool sandbox events
  def handle_event([:rubber_duck, :tool, :sandbox, event_type], measurements, metadata, _config)
      when event_type in [:start, :stop] do
    Logger.debug("Tool sandbox #{event_type}",
      tool_name: metadata.tool_name,
      sandbox_id: metadata[:sandbox_id],
      duration_ms: div(measurements[:duration] || 0, 1_000)
    )

    :ok
  end

  # Tool result events
  def handle_event([:rubber_duck, :tool, :result, result_type], measurements, metadata, _config) do
    level = if result_type == :success, do: :info, else: :warning

    Logger.log(level, "Tool result: #{result_type}",
      tool_name: metadata.tool_name,
      tool_id: metadata.tool_id,
      duration_ms: div(measurements[:duration] || 0, 1_000)
    )

    :ok
  end

  # Composition workflow events
  def handle_event([:rubber_duck, :tool, :composition, :workflow, action], measurements, metadata, _config) do
    case action do
      :start ->
        Logger.info("Workflow started",
          workflow_id: metadata.workflow_id,
          steps_count: metadata[:steps_count]
        )

      :complete ->
        Logger.info("Workflow completed",
          workflow_id: metadata.workflow_id,
          duration_ms: div(measurements.duration, 1_000),
          success: true
        )

      :error ->
        Logger.error("Workflow failed",
          workflow_id: metadata.workflow_id,
          error: inspect(metadata.error),
          duration_ms: div(measurements[:duration] || 0, 1_000)
        )
    end

    :ok
  end

  # Composition workflow step events
  def handle_event([:rubber_duck, :tool, :composition, :workflow, :step, action], measurements, metadata, _config) do
    case action do
      :start ->
        Logger.debug("Workflow step started",
          workflow_id: metadata.workflow_id,
          step_name: metadata.step_name,
          step_index: metadata[:step_index]
        )

      :complete ->
        Logger.debug("Workflow step completed",
          workflow_id: metadata.workflow_id,
          step_name: metadata.step_name,
          duration_ms: div(measurements.duration, 1_000)
        )

      :error ->
        Logger.warning("Workflow step failed",
          workflow_id: metadata.workflow_id,
          step_name: metadata.step_name,
          error: inspect(metadata.error),
          duration_ms: div(measurements[:duration] || 0, 1_000)
        )
    end

    :ok
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
