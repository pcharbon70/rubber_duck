defmodule RubberDuck.Telemetry.Reporter do
  @moduledoc """
  Custom telemetry reporter for RubberDuck application.
  Handles structured logging and metric reporting.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    metrics = Keyword.get(opts, :metrics, [])

    groups = Enum.group_by(metrics, & &1.event_name)

    for {event, metrics} <- groups do
      id = {__MODULE__, event, self()}
      :telemetry.attach(id, event, &handle_event/4, metrics)
    end

    {:ok, %{metrics: metrics}}
  end

  def handle_event(_event_name, measurements, metadata, metrics) do
    Enum.each(metrics, fn metric ->
      case metric do
        %{__struct__: module} = metric ->
          measurement = extract_measurement(metric, measurements)
          tags = extract_tags(metric, metadata)

          log_metric(module, metric.name, measurement, tags)
      end
    end)
  end

  defp extract_measurement(metric, measurements) do
    case metric.measurement do
      fun when is_function(fun, 1) -> fun.(measurements)
      key -> Map.get(measurements, key)
    end
  end

  defp extract_tags(metric, metadata) do
    tag_values =
      for tag <- metric.tags do
        {tag, Map.get(metadata, tag)}
      end

    Map.new(tag_values)
  end

  defp log_metric(module, name, value, tags) when is_number(value) do
    type = metric_type(module)

    Logger.info(
      "[METRIC] #{inspect(name)} #{type}=#{value}",
      metric_type: type,
      metric_name: name,
      metric_value: value,
      metric_tags: tags
    )
  end

  defp log_metric(_, _, _, _), do: :ok

  defp metric_type(module) do
    case Module.split(module) |> List.last() do
      "Counter" -> "count"
      "Sum" -> "sum"
      "LastValue" -> "gauge"
      "Summary" -> "summary"
      "Distribution" -> "distribution"
      _ -> "unknown"
    end
  end
end
