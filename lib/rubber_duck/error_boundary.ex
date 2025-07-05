defmodule RubberDuck.ErrorBoundary do
  @moduledoc """
  A GenServer that acts as an error boundary for critical operations.
  
  This module provides crash isolation and automatic error reporting
  through Tower. It can be used to wrap risky operations and ensure
  that failures are properly tracked and the system remains stable.
  
  ## Usage
  
      {:ok, result} = ErrorBoundary.run(fn ->
        # potentially crashing code
        risky_operation()
      end)
      
      # With options
      {:ok, result} = ErrorBoundary.run(
        fn -> process_data(data) end,
        timeout: 10_000,
        metadata: %{user_id: user.id}
      )
  """

  use GenServer
  require Logger
  alias RubberDuck.Errors

  @default_timeout 5_000

  # Client API

  @doc """
  Starts the error boundary GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes the given function within the error boundary.
  
  If the function succeeds, returns `{:ok, result}`.
  If the function raises, crashes, or times out, the error is reported
  to Tower and `{:error, reason}` is returned.
  
  ## Options
  
    * `:timeout` - Maximum time to wait for the operation (default: 5000ms)
    * `:metadata` - Additional metadata to include in error reports
    * `:retry` - Number of times to retry on failure (default: 0)
    * `:retry_delay` - Delay between retries in ms (default: 1000)
  """
  def run(fun, opts \\ []) when is_function(fun, 0) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    metadata = Keyword.get(opts, :metadata, %{})
    retry = Keyword.get(opts, :retry, 0)
    retry_delay = Keyword.get(opts, :retry_delay, 1_000)

    do_run(fun, timeout, metadata, retry, retry_delay)
  end

  @doc """
  Executes an async operation within the error boundary.
  
  Returns a task that can be awaited. Errors are automatically
  reported to Tower when the task is awaited.
  """
  def run_async(fun, opts \\ []) when is_function(fun, 0) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    metadata = Keyword.get(opts, :metadata, %{})

    Task.async(fn ->
      case run(fun, timeout: timeout, metadata: metadata) do
        {:ok, result} -> result
        {:error, reason} -> raise "Async operation failed: #{inspect(reason)}"
      end
    end)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    
    state = %{
      stats: %{
        success_count: 0,
        error_count: 0,
        last_error: nil
      },
      opts: opts
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:execute, fun, timeout, metadata}, _from, state) do
    task = Task.async(fn ->
      try do
        {:ok, fun.()}
      rescue
        error ->
          stacktrace = __STACKTRACE__
          report_error(error, stacktrace, metadata)
          {:error, {:exception, error}}
      catch
        kind, reason ->
          stacktrace = __STACKTRACE__
          report_catch(kind, reason, stacktrace, metadata)
          {:error, {kind, reason}}
      end
    end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        state = update_stats(state, result)
        {:reply, result, state}
        
      nil ->
        error = Errors.ServiceUnavailableError.exception(
          service: "error_boundary",
          message: "Operation timed out after #{timeout}ms"
        )
        Errors.report_exception(error, [], metadata)
        
        state = update_stats(state, {:error, :timeout})
        {:reply, {:error, :timeout}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) when reason != :normal do
    Logger.error("ErrorBoundary received EXIT signal: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp do_run(fun, timeout, metadata, 0, _retry_delay) do
    GenServer.call(__MODULE__, {:execute, fun, timeout, metadata}, timeout + 1_000)
  end

  defp do_run(fun, timeout, metadata, retries, retry_delay) do
    case GenServer.call(__MODULE__, {:execute, fun, timeout, metadata}, timeout + 1_000) do
      {:ok, _result} = success ->
        success
        
      {:error, _reason} ->
        Logger.warning("Operation failed, #{retries} retries remaining")
        Process.sleep(retry_delay)
        do_run(fun, timeout, metadata, retries - 1, retry_delay)
    end
  end

  defp report_error(error, stacktrace, metadata) do
    enhanced_metadata = Map.merge(metadata, %{
      error_boundary: true,
      error_type: error.__struct__
    })
    
    Errors.report_exception(error, stacktrace, enhanced_metadata)
  end

  defp report_catch(kind, reason, _stacktrace, metadata) do
    enhanced_metadata = Map.merge(metadata, %{
      error_boundary: true,
      catch_kind: kind
    })
    
    message = "Caught #{kind}: #{inspect(reason)}"
    # Convert to keyword list for Tower
    Tower.report_message(:error, message, Map.to_list(enhanced_metadata))
  end

  defp update_stats(state, {:ok, _result}) do
    stats = state.stats
    |> Map.update!(:success_count, &(&1 + 1))
    
    %{state | stats: stats}
  end

  defp update_stats(state, {:error, reason}) do
    stats = state.stats
    |> Map.update!(:error_count, &(&1 + 1))
    |> Map.put(:last_error, {reason, DateTime.utc_now()})
    
    %{state | stats: stats}
  end

  @doc """
  Returns statistics about error boundary usage.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end
end