defmodule RubberDuck.Jido.SignalRouter.DeadLetterQueue do
  @moduledoc """
  Dead Letter Queue for signals that cannot be routed or processed.
  
  This module handles:
  - Storage of failed signals with error metadata
  - Retry mechanism with exponential backoff
  - Admin interface for inspection and manual replay
  - Automatic cleanup of old entries
  
  Failed signals are stored with:
  - Original CloudEvent data
  - Error reason and stack trace
  - Retry count and next retry time
  - Processing history
  """
  
  use GenServer
  require Logger
  
  @table_name :rubber_duck_signal_dlq
  @max_retries 3
  @base_retry_delay 1_000  # 1 second
  @max_retry_delay 300_000 # 5 minutes
  @cleanup_interval 3_600_000 # 1 hour
  @retention_period 7 * 24 * 60 * 60 * 1000 # 7 days in milliseconds
  
  @type dlq_entry :: %{
    id: String.t(),
    signal: map(),
    error: term(),
    error_message: String.t(),
    retry_count: non_neg_integer(),
    next_retry_at: DateTime.t() | nil,
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    processing_history: [map()]
  }
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Adds a failed signal to the dead letter queue.
  
  The signal will be retried automatically based on the retry policy.
  """
  @spec add(map(), term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def add(signal, error, opts \\ []) do
    GenServer.call(__MODULE__, {:add, signal, error, opts})
  end
  
  @doc """
  Manually retries a signal from the DLQ.
  """
  @spec retry(String.t()) :: :ok | {:error, term()}
  def retry(id) do
    GenServer.call(__MODULE__, {:retry, id})
  end
  
  @doc """
  Removes a signal from the DLQ.
  """
  @spec remove(String.t()) :: :ok | {:error, :not_found}
  def remove(id) do
    GenServer.call(__MODULE__, {:remove, id})
  end
  
  @doc """
  Lists all signals in the DLQ with optional filters.
  
  ## Options
  - `:status` - Filter by status (:pending_retry, :failed, :all)
  - `:limit` - Maximum number of entries to return
  - `:offset` - Offset for pagination
  """
  @spec list(keyword()) :: [dlq_entry()]
  def list(opts \\ []) do
    GenServer.call(__MODULE__, {:list, opts})
  end
  
  @doc """
  Gets a specific DLQ entry by ID.
  """
  @spec get(String.t()) :: {:ok, dlq_entry()} | {:error, :not_found}
  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  end
  
  @doc """
  Returns statistics about the DLQ.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end
  
  @doc """
  Clears all entries from the DLQ. Use with caution!
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table for DLQ entries
    :ets.new(@table_name, [
      :named_table,
      :set,
      :public,
      read_concurrency: true
    ])
    
    # Schedule automatic retry processing
    schedule_retry_processing()
    
    # Schedule cleanup of old entries
    schedule_cleanup()
    
    state = %{
      stats: %{
        total_added: 0,
        total_retried: 0,
        total_failed: 0,
        total_removed: 0
      }
    }
    
    Logger.info("DeadLetterQueue started")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:add, signal, error, opts}, _from, state) do
    id = generate_id()
    
    entry = %{
      id: id,
      signal: signal,
      error: error,
      error_message: format_error(error),
      retry_count: 0,
      next_retry_at: calculate_next_retry(0),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      processing_history: [
        %{
          timestamp: DateTime.utc_now(),
          action: "added",
          error: format_error(error),
          metadata: Keyword.get(opts, :metadata, %{})
        }
      ]
    }
    
    :ets.insert(@table_name, {id, entry})
    
    Logger.warning("Signal added to DLQ: #{id} - #{entry.error_message}")
    
    state = update_in(state.stats.total_added, &(&1 + 1))
    
    # Emit telemetry event
    :telemetry.execute(
      [:rubber_duck, :signal_router, :dlq, :added],
      %{count: 1},
      %{signal_type: signal["type"], error: error}
    )
    
    {:reply, {:ok, id}, state}
  end
  
  @impl true
  def handle_call({:retry, id}, _from, state) do
    case :ets.lookup(@table_name, id) do
      [{^id, entry}] ->
        # Attempt to process the signal
        Task.start(fn -> process_retry(entry) end)
        
        {:reply, :ok, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:remove, id}, _from, state) do
    case :ets.take(@table_name, id) do
      [{^id, _entry}] ->
        state = update_in(state.stats.total_removed, &(&1 + 1))
        {:reply, :ok, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:list, opts}, _from, state) do
    status = Keyword.get(opts, :status, :all)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    
    entries = 
      :ets.tab2list(@table_name)
      |> Enum.map(fn {_id, entry} -> entry end)
      |> filter_by_status(status)
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
      |> Enum.drop(offset)
      |> Enum.take(limit)
    
    {:reply, entries, state}
  end
  
  @impl true
  def handle_call({:get, id}, _from, state) do
    case :ets.lookup(@table_name, id) do
      [{^id, entry}] -> {:reply, {:ok, entry}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    current_stats = Map.merge(state.stats, %{
      current_size: :ets.info(@table_name, :size),
      pending_retry: count_by_status(:pending_retry),
      permanently_failed: count_by_status(:failed)
    })
    
    {:reply, current_stats, state}
  end
  
  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    Logger.warning("Dead Letter Queue cleared")
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_info(:process_retries, state) do
    # Find entries ready for retry
    now = DateTime.utc_now()
    
    ready_entries = 
      :ets.tab2list(@table_name)
      |> Enum.filter(fn {_id, entry} ->
        entry.retry_count < @max_retries and
        entry.next_retry_at != nil and
        DateTime.compare(entry.next_retry_at, now) == :lt
      end)
    
    # Process each ready entry
    Enum.each(ready_entries, fn {_id, entry} ->
      Task.start(fn -> process_retry(entry) end)
    end)
    
    # Schedule next check
    schedule_retry_processing()
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:cleanup_old_entries, state) do
    # Remove entries older than retention period
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_period, :millisecond)
    
    old_entries = 
      :ets.tab2list(@table_name)
      |> Enum.filter(fn {_id, entry} ->
        DateTime.compare(entry.created_at, cutoff) == :lt
      end)
    
    Enum.each(old_entries, fn {id, _entry} ->
      :ets.delete(@table_name, id)
    end)
    
    if length(old_entries) > 0 do
      Logger.info("Cleaned up #{length(old_entries)} old DLQ entries")
    end
    
    # Schedule next cleanup
    schedule_cleanup()
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp generate_id do
    "dlq_#{Uniq.UUID.uuid4()}"
  end
  
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error) when is_atom(error), do: to_string(error)
  defp format_error(error), do: inspect(error)
  
  defp calculate_next_retry(retry_count) when retry_count >= @max_retries, do: nil
  defp calculate_next_retry(retry_count) do
    delay = min(@base_retry_delay * :math.pow(2, retry_count), @max_retry_delay)
    |> round()
    
    DateTime.add(DateTime.utc_now(), delay, :millisecond)
  end
  
  defp schedule_retry_processing do
    Process.send_after(self(), :process_retries, 5_000) # Check every 5 seconds
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_old_entries, @cleanup_interval)
  end
  
  defp filter_by_status(entries, :all), do: entries
  defp filter_by_status(entries, :pending_retry) do
    Enum.filter(entries, fn entry ->
      entry.retry_count < @max_retries and entry.next_retry_at != nil
    end)
  end
  defp filter_by_status(entries, :failed) do
    Enum.filter(entries, fn entry ->
      entry.retry_count >= @max_retries
    end)
  end
  
  defp count_by_status(status) do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {_id, entry} -> entry end)
    |> filter_by_status(status)
    |> length()
  end
  
  defp process_retry(entry) do
    Logger.info("Retrying DLQ entry #{entry.id} (attempt #{entry.retry_count + 1})")
    
    # Get the SignalRouter to retry
    case RubberDuck.Jido.SignalRouter.route_with_validation(entry.signal) do
      :ok ->
        # Success - remove from DLQ
        :ets.delete(@table_name, entry.id)
        
        Logger.info("Successfully processed DLQ entry #{entry.id}")
        
        # Update stats
        GenServer.cast(__MODULE__, {:update_stats, :retried})
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :signal_router, :dlq, :retry_success],
          %{count: 1},
          %{signal_type: entry.signal["type"], retry_count: entry.retry_count}
        )
        
      {:error, reason} ->
        # Failed again - update entry
        updated_entry = %{entry |
          retry_count: entry.retry_count + 1,
          next_retry_at: calculate_next_retry(entry.retry_count + 1),
          updated_at: DateTime.utc_now(),
          processing_history: [
            %{
              timestamp: DateTime.utc_now(),
              action: "retry_failed",
              error: format_error(reason),
              retry_count: entry.retry_count + 1
            } | entry.processing_history
          ]
        }
        
        :ets.insert(@table_name, {entry.id, updated_entry})
        
        if updated_entry.retry_count >= @max_retries do
          Logger.error("DLQ entry #{entry.id} permanently failed after #{@max_retries} retries")
          GenServer.cast(__MODULE__, {:update_stats, :failed})
        end
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :signal_router, :dlq, :retry_failed],
          %{count: 1},
          %{signal_type: entry.signal["type"], retry_count: updated_entry.retry_count}
        )
    end
  end
  
  @impl true
  def handle_cast({:update_stats, type}, state) do
    state = case type do
      :retried -> update_in(state.stats.total_retried, &(&1 + 1))
      :failed -> update_in(state.stats.total_failed, &(&1 + 1))
      _ -> state
    end
    
    {:noreply, state}
  end
end