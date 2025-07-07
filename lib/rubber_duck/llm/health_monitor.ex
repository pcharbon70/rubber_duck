defmodule RubberDuck.LLM.HealthMonitor do
  @moduledoc """
  Monitors the health of LLM providers.
  """

  @type health_status :: :healthy | :degraded | :unhealthy | :unknown

  @type health_record :: %{
          status: health_status(),
          timestamp: DateTime.t(),
          latency_ms: float() | nil,
          error_rate: float() | nil,
          details: map()
        }

  @type t :: %__MODULE__{
          providers: %{atom() => list(health_record())},
          check_interval: non_neg_integer(),
          retention_period: non_neg_integer()
        }

  defstruct providers: %{},
            # 30 seconds
            check_interval: 30_000,
            # 24 hours in milliseconds
            retention_period: 86_400_000

  @doc """
  Creates a new health monitor.
  """
  def new(opts \\ []) do
    %__MODULE__{
      check_interval: Keyword.get(opts, :check_interval, 30_000),
      retention_period: Keyword.get(opts, :retention_period, 86_400_000)
    }
  end

  @doc """
  Records a health check result for a provider.
  """
  def record_health(%__MODULE__{} = monitor, provider, status, details \\ %{}) do
    record = %{
      status: status,
      timestamp: DateTime.utc_now(),
      latency_ms: details[:latency_ms],
      error_rate: details[:error_rate],
      details: details
    }

    provider_records = Map.get(monitor.providers, provider, [])

    updated_records =
      [record | provider_records]
      |> prune_old_records(monitor.retention_period)
      # Keep max 100 records per provider
      |> Enum.take(100)

    %{monitor | providers: Map.put(monitor.providers, provider, updated_records)}
  end

  @doc """
  Gets the current health status for a provider.
  """
  def get_status(%__MODULE__{} = monitor, provider) do
    case Map.get(monitor.providers, provider, []) do
      [] -> :unknown
      [latest | _] -> latest.status
    end
  end

  @doc """
  Gets health status for all providers.
  """
  def get_all_status(%__MODULE__{} = monitor) do
    Map.new(monitor.providers, fn {provider, records} ->
      status =
        case records do
          [] -> :unknown
          [latest | _] -> latest.status
        end

      {provider,
       %{
         status: status,
         last_check: get_last_check_time(records),
         uptime_percentage: calculate_uptime(records),
         average_latency: calculate_average_latency(records),
         recent_errors: count_recent_errors(records)
       }}
    end)
  end

  @doc """
  Checks if a provider is available (healthy or degraded).
  """
  def is_available?(%__MODULE__{} = monitor, provider) do
    get_status(monitor, provider) in [:healthy, :degraded]
  end

  @doc """
  Gets health history for a provider.
  """
  def get_history(%__MODULE__{} = monitor, provider, limit \\ 50) do
    Map.get(monitor.providers, provider, [])
    |> Enum.take(limit)
  end

  @doc """
  Calculates health metrics for a provider over a time period.
  """
  def get_metrics(%__MODULE__{} = monitor, provider, period_minutes \\ 60) do
    cutoff = DateTime.add(DateTime.utc_now(), -period_minutes * 60, :second)

    records =
      Map.get(monitor.providers, provider, [])
      |> Enum.filter(fn record ->
        DateTime.compare(record.timestamp, cutoff) in [:gt, :eq]
      end)

    %{
      total_checks: length(records),
      healthy_checks: count_by_status(records, :healthy),
      degraded_checks: count_by_status(records, :degraded),
      unhealthy_checks: count_by_status(records, :unhealthy),
      uptime_percentage: calculate_uptime(records),
      average_latency: calculate_average_latency(records),
      max_latency: calculate_max_latency(records),
      error_rate: calculate_error_rate(records)
    }
  end

  # Private functions

  defp prune_old_records(records, retention_period) do
    cutoff = DateTime.add(DateTime.utc_now(), -retention_period, :millisecond)

    Enum.filter(records, fn record ->
      DateTime.compare(record.timestamp, cutoff) in [:gt, :eq]
    end)
  end

  defp get_last_check_time([]), do: nil
  defp get_last_check_time([latest | _]), do: latest.timestamp

  defp calculate_uptime([]), do: 0.0

  defp calculate_uptime(records) do
    total = length(records)
    available = Enum.count(records, &(&1.status in [:healthy, :degraded]))

    if total > 0 do
      available / total * 100
    else
      0.0
    end
  end

  defp calculate_average_latency(records) do
    latencies =
      records
      |> Enum.map(& &1.latency_ms)
      |> Enum.filter(&(&1 != nil))

    if length(latencies) > 0 do
      Enum.sum(latencies) / length(latencies)
    else
      nil
    end
  end

  defp calculate_max_latency(records) do
    records
    |> Enum.map(& &1.latency_ms)
    |> Enum.filter(&(&1 != nil))
    |> Enum.max(fn -> nil end)
  end

  defp calculate_error_rate(records) do
    total = length(records)
    errors = Enum.count(records, &(&1.status == :unhealthy))

    if total > 0 do
      errors / total * 100
    else
      0.0
    end
  end

  defp count_recent_errors(records) do
    # Count errors in the last 5 minutes
    cutoff = DateTime.add(DateTime.utc_now(), -5 * 60, :second)

    Enum.count(records, fn record ->
      record.status == :unhealthy &&
        DateTime.compare(record.timestamp, cutoff) in [:gt, :eq]
    end)
  end

  defp count_by_status(records, status) do
    Enum.count(records, &(&1.status == status))
  end
end
