defmodule RubberDuck.Instructions.RateLimiter do
  @moduledoc """
  Rate limiting for template processing.

  Implements hierarchical rate limiting with multiple levels:
  - Per-user limits
  - Per-template limits  
  - Global system limits

  Features adaptive throttling based on security scores and supports
  configurable limits for different user tiers.
  """

  use GenServer
  require Logger

  alias RubberDuck.Instructions.SecurityConfig

  @type level :: :user | :template | :global
  @type limit_config :: {integer(), :second | :minute | :hour}

  ## Client API

  @doc """
  Starts the rate limiter.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if a request is within rate limits.

  Returns `:ok` if within limits, `{:error, :rate_limit_exceeded}` if exceeded.
  """
  @spec check_rate(String.t(), level()) :: :ok | {:error, :rate_limit_exceeded}
  def check_rate(key, level) do
    GenServer.call(__MODULE__, {:check_rate, key, level})
  end

  @doc """
  Configures rate limit for a specific user.
  """
  def configure_user(user_id, opts) do
    GenServer.call(__MODULE__, {:configure_user, user_id, opts})
  end

  @doc """
  Adjusts limits based on user behavior (suspicious activity, etc).
  """
  def adjust_limits(user_id, adjustment) when adjustment in [:decrease, :increase] do
    GenServer.call(__MODULE__, {:adjust_limits, user_id, adjustment})
  end

  @doc """
  Clears all rate limit data. Useful for testing.
  """
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  @doc """
  Gets current rate limit status for a key.
  """
  def get_status(key, level) do
    GenServer.call(__MODULE__, {:get_status, key, level})
  end

  ## Server Implementation

  def init(opts) do
    # Initialize ETS tables for each level
    :ets.new(:rate_limiter_user, [:set, :public, :named_table])
    :ets.new(:rate_limiter_template, [:set, :public, :named_table])
    :ets.new(:rate_limiter_global, [:set, :public, :named_table])
    :ets.new(:rate_limiter_config, [:set, :public, :named_table])
    :ets.new(:rate_limiter_adjustments, [:set, :public, :named_table])

    # Schedule cleanup
    schedule_cleanup()

    default_limits = SecurityConfig.get_rate_limit_config()

    state = %{
      limits: Map.merge(default_limits, Keyword.get(opts, :limits, %{})),
      started_at: System.monotonic_time(:millisecond)
    }

    {:ok, state}
  end

  def handle_call({:check_rate, key, level}, _from, state) do
    limit_config = get_limit_config(key, level, state)
    bucket_name = get_bucket_name(key, level)

    result = check_rate_internal(bucket_name, limit_config, key, level)
    {:reply, result, state}
  end

  def handle_call({:configure_user, user_id, opts}, _from, state) do
    limit = Keyword.get(opts, :limit)
    window = Keyword.get(opts, :window, :minute)

    :ets.insert(:rate_limiter_config, {user_id, {limit, window}})
    {:reply, :ok, state}
  end

  def handle_call({:adjust_limits, user_id, :decrease}, _from, state) do
    current_factor = get_adjustment_factor(user_id)
    adaptive_factors = SecurityConfig.get_adaptive_factors()
    new_factor = max(current_factor - 0.3, Map.get(adaptive_factors, :suspicious, 0.2))

    :ets.insert(:rate_limiter_adjustments, {user_id, new_factor})
    Logger.info("Decreased rate limit for user #{user_id} to factor #{new_factor}")

    {:reply, :ok, state}
  end

  def handle_call({:adjust_limits, user_id, :increase}, _from, state) do
    current_factor = get_adjustment_factor(user_id)
    adaptive_factors = SecurityConfig.get_adaptive_factors()
    new_factor = min(current_factor + 0.2, Map.get(adaptive_factors, :trusted, 2.0))

    :ets.insert(:rate_limiter_adjustments, {user_id, new_factor})
    Logger.info("Increased rate limit for user #{user_id} to factor #{new_factor}")

    {:reply, :ok, state}
  end

  def handle_call(:clear_all, _from, state) do
    :ets.delete_all_objects(:rate_limiter_user)
    :ets.delete_all_objects(:rate_limiter_template)
    :ets.delete_all_objects(:rate_limiter_global)
    :ets.delete_all_objects(:rate_limiter_config)
    :ets.delete_all_objects(:rate_limiter_adjustments)

    {:reply, :ok, state}
  end

  def handle_call({:get_status, key, level}, _from, state) do
    bucket_name = get_bucket_name(key, level)
    table = get_table_for_level(level)

    status =
      case :ets.lookup(table, bucket_name) do
        [{^bucket_name, count, last_reset}] ->
          limit_config = get_limit_config(key, level, state)
          {limit, _window} = limit_config

          %{
            current_count: count,
            limit: limit,
            last_reset: last_reset,
            remaining: max(0, limit - count)
          }

        [] ->
          {limit, _window} = get_limit_config(key, level, state)

          %{
            current_count: 0,
            limit: limit,
            last_reset: System.monotonic_time(:millisecond),
            remaining: limit
          }
      end

    {:reply, {:ok, status}, state}
  end

  def handle_info(:cleanup, state) do
    # Clean up old entries
    cleanup_old_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp check_rate_internal(bucket_name, {limit, window}, key, level) do
    table = get_table_for_level(level)
    now = System.monotonic_time(:millisecond)
    window_ms = window_to_ms(window)

    # Apply adjustment factor for user level
    adjusted_limit =
      if level == :user do
        factor = get_adjustment_factor(key)
        round(limit * factor)
      else
        limit
      end

    result =
      case :ets.lookup(table, bucket_name) do
        [{^bucket_name, count, last_reset}] ->
          if now - last_reset > window_ms do
            # Window expired, reset counter
            :ets.insert(table, {bucket_name, 1, now})
            :ok
          else
            if count >= adjusted_limit do
              {:error, :rate_limit_exceeded}
            else
              :ets.update_counter(table, bucket_name, {2, 1})
              :ok
            end
          end

        [] ->
          # First request
          :ets.insert(table, {bucket_name, 1, now})
          :ok
      end

    # Emit telemetry event
    emit_rate_limit_event(level, key, result)

    result
  end

  defp get_bucket_name(key, level) do
    "#{level}:#{key}"
  end

  defp get_table_for_level(:user), do: :rate_limiter_user
  defp get_table_for_level(:template), do: :rate_limiter_template
  defp get_table_for_level(:global), do: :rate_limiter_global

  defp get_limit_config(key, :user, state) do
    # Check for user-specific config first
    case :ets.lookup(:rate_limiter_config, key) do
      [{^key, config}] ->
        config

      [] ->
        default_limits = SecurityConfig.get_rate_limit_config()
        Map.get(state.limits, :user, Map.get(default_limits, :user))
    end
  end

  defp get_limit_config(_key, level, state) do
    default_limits = SecurityConfig.get_rate_limit_config()
    Map.get(state.limits, level, Map.get(default_limits, level))
  end

  defp get_adjustment_factor(user_id) do
    case :ets.lookup(:rate_limiter_adjustments, user_id) do
      [{^user_id, factor}] ->
        factor

      [] ->
        adaptive_factors = SecurityConfig.get_adaptive_factors()
        Map.get(adaptive_factors, :normal, 1.0)
    end
  end

  defp window_to_ms(:second), do: 1_000
  defp window_to_ms(:minute), do: 60_000
  defp window_to_ms(:hour), do: 3_600_000

  defp schedule_cleanup do
    # Cleanup every 5 minutes
    Process.send_after(self(), :cleanup, 5 * 60 * 1000)
  end

  defp cleanup_old_entries do
    now = System.monotonic_time(:millisecond)
    # 1 hour
    max_window = 3_600_000

    # Clean up entries older than max window
    [:rate_limiter_user, :rate_limiter_template, :rate_limiter_global]
    |> Enum.each(fn table ->
      :ets.select_delete(table, [
        {
          {:"$1", :"$2", :"$3"},
          [{:<, {:-, now, :"$3"}, max_window}],
          [true]
        }
      ])
    end)
  end

  ## Telemetry Integration

  defp emit_rate_limit_event(level, key, result) do
    :telemetry.execute(
      [:rubber_duck, :instructions, :rate_limiter, level],
      %{count: 1},
      %{
        key: key,
        result: result,
        timestamp: System.system_time(:millisecond)
      }
    )
  end
end
