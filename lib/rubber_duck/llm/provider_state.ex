defmodule RubberDuck.LLM.ProviderState do
  @moduledoc """
  Runtime state for an LLM provider.
  """

  alias RubberDuck.LLM.ProviderConfig

  @type circuit_state :: :closed | :open | :half_open
  @type health_status :: :healthy | :degraded | :unhealthy | :unknown

  @type t :: %__MODULE__{
          config: ProviderConfig.t(),
          circuit_state: circuit_state(),
          circuit_failures: non_neg_integer(),
          circuit_last_failure: DateTime.t() | nil,
          circuit_half_open_attempts: non_neg_integer(),
          rate_limiter: map() | nil,
          last_health_check: DateTime.t(),
          health_status: health_status(),
          active_requests: non_neg_integer(),
          total_requests: non_neg_integer(),
          total_errors: non_neg_integer(),
          average_latency_ms: float(),
          last_request_at: DateTime.t() | nil
        }

  defstruct [
    :config,
    :rate_limiter,
    :last_health_check,
    :circuit_last_failure,
    :last_request_at,
    circuit_state: :closed,
    circuit_failures: 0,
    circuit_half_open_attempts: 0,
    health_status: :unknown,
    active_requests: 0,
    total_requests: 0,
    total_errors: 0,
    average_latency_ms: 0.0
  ]

  @doc """
  Records a successful request.
  """
  def record_success(%__MODULE__{} = state, latency_ms) do
    %{
      state
      | circuit_state: :closed,
        circuit_failures: 0,
        circuit_half_open_attempts: 0,
        total_requests: state.total_requests + 1,
        average_latency_ms: update_average_latency(state, latency_ms),
        last_request_at: DateTime.utc_now()
    }
  end

  @doc """
  Records a failed request.
  """
  def record_failure(%__MODULE__{} = state) do
    failures = state.circuit_failures + 1

    new_circuit_state =
      cond do
        failures >= 5 -> :open
        state.circuit_state == :half_open -> :open
        true -> state.circuit_state
      end

    %{
      state
      | circuit_failures: failures,
        circuit_state: new_circuit_state,
        circuit_last_failure: DateTime.utc_now(),
        total_requests: state.total_requests + 1,
        total_errors: state.total_errors + 1,
        last_request_at: DateTime.utc_now()
    }
  end

  @doc """
  Checks if the circuit breaker should transition to half-open.
  """
  def maybe_half_open(%__MODULE__{circuit_state: :open} = state) do
    if should_try_half_open?(state) do
      %{state | circuit_state: :half_open, circuit_half_open_attempts: 0}
    else
      state
    end
  end

  def maybe_half_open(state), do: state

  @doc """
  Increments active request count.
  """
  def increment_active(%__MODULE__{} = state) do
    %{state | active_requests: state.active_requests + 1}
  end

  @doc """
  Decrements active request count.
  """
  def decrement_active(%__MODULE__{} = state) do
    %{state | active_requests: max(0, state.active_requests - 1)}
  end

  @doc """
  Updates health status based on metrics.
  """
  def update_health_status(%__MODULE__{} = state) do
    health = calculate_health_status(state)
    %{state | health_status: health, last_health_check: DateTime.utc_now()}
  end

  # Private functions

  defp update_average_latency(state, new_latency_ms) do
    if state.total_requests == 0 do
      new_latency_ms
    else
      # Simple moving average
      # Weight for new value
      weight = 0.1
      state.average_latency_ms * (1 - weight) + new_latency_ms * weight
    end
  end

  defp should_try_half_open?(state) do
    case state.circuit_last_failure do
      nil ->
        false

      last_failure ->
        # Try half-open after 30 seconds
        diff = DateTime.diff(DateTime.utc_now(), last_failure, :second)
        diff >= 30
    end
  end

  defp calculate_health_status(state) do
    error_rate =
      if state.total_requests > 0 do
        state.total_errors / state.total_requests
      else
        0.0
      end

    cond do
      state.circuit_state == :open -> :unhealthy
      error_rate > 0.5 -> :unhealthy
      error_rate > 0.1 -> :degraded
      state.average_latency_ms > 5000 -> :degraded
      true -> :healthy
    end
  end
end
