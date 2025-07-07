defmodule RubberDuck.Telemetry.AshHandler do
  @moduledoc """
  Telemetry event handlers for Ash framework operations.
  Captures metrics for resource actions, queries, and errors.
  """

  require Logger

  def attach do
    events = [
      [:ash, :request, :start],
      [:ash, :request, :stop],
      [:ash, :request, :error],
      [:ash, :query, :preparation],
      [:ash, :changeset, :preparation],
      [:ash, :flow, :start],
      [:ash, :flow, :stop]
    ]

    for event <- events do
      :telemetry.attach(
        {__MODULE__, event},
        event,
        &__MODULE__.handle_event/4,
        nil
      )
    end
  end

  def handle_event([:ash, :request, :start], _measurements, metadata, _config) do
    Logger.debug("Ash request started",
      resource: inspect(metadata.resource),
      action: metadata.action_name
    )

    :telemetry.execute(
      [:rubber_duck, :ash, :request, :start],
      %{count: 1},
      %{
        resource: resource_name(metadata.resource),
        action: metadata.action_name
      }
    )
  end

  def handle_event([:ash, :request, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug("Ash request completed",
      resource: inspect(metadata.resource),
      action: metadata.action_name,
      duration_ms: duration_ms
    )

    :telemetry.execute(
      [:rubber_duck, :ash, :request, :stop],
      %{duration: duration_ms},
      %{
        resource: resource_name(metadata.resource),
        action: metadata.action_name,
        success: metadata.success?
      }
    )
  end

  def handle_event([:ash, :request, :error], _measurements, metadata, _config) do
    Logger.error("Ash request failed",
      resource: inspect(metadata.resource),
      action: metadata.action_name,
      error: inspect(metadata.error)
    )

    :telemetry.execute(
      [:rubber_duck, :ash, :request, :error],
      %{count: 1},
      %{
        resource: resource_name(metadata.resource),
        action: metadata.action_name,
        error_type: error_type(metadata.error)
      }
    )
  end

  def handle_event([:ash, :query, :preparation], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug("Ash query preparation",
      resource: inspect(metadata.resource),
      preparation: metadata.preparation,
      duration_ms: duration_ms
    )
  end

  def handle_event([:ash, :changeset, :preparation], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug("Ash changeset preparation",
      resource: inspect(metadata.resource),
      preparation: metadata.preparation,
      duration_ms: duration_ms
    )
  end

  def handle_event([:ash, :flow, :start], _measurements, metadata, _config) do
    Logger.debug("Ash flow started",
      flow: metadata.flow,
      steps: length(Map.get(metadata, :steps, []))
    )
  end

  def handle_event([:ash, :flow, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug("Ash flow completed",
      flow: metadata.flow,
      duration_ms: duration_ms,
      success: metadata.success?
    )
  end

  defp resource_name(resource) when is_atom(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> String.downcase()
  end

  defp resource_name(_), do: "unknown"

  defp error_type(%{class: class}), do: to_string(class)
  defp error_type(_), do: "unknown"
end
