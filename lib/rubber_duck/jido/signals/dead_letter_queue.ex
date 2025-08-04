defmodule RubberDuck.Jido.Signals.DeadLetterQueue do
  @moduledoc """
  Dead letter queue for handling undeliverable signals.
  
  This module manages signals that could not be delivered to their intended
  handlers, providing retry logic, TTL-based expiration, and cleanup policies.
  All signals are stored as proper Jido signals with CloudEvents compliance.
  """
  
  use GenServer
  require Logger
  
  @ets_table :dead_letter_signals
  @cleanup_interval :timer.minutes(5)
  @default_ttl :timer.hours(24)
  @max_retries 3
  
  @type dead_letter_entry :: %{
    signal: map(),
    reason: term(),
    attempts: non_neg_integer(),
    first_failure: DateTime.t(),
    last_failure: DateTime.t(),
    ttl: non_neg_integer(),
    metadata: map()
  }
  
  # Client API
  
  @doc """
  Starts the dead letter queue.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Adds a signal to the dead letter queue.
  """
  @spec enqueue(map(), term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def enqueue(signal, reason, opts \\ []) do
    GenServer.call(__MODULE__, {:enqueue, signal, reason, opts})
  end
  
  @doc """
  Attempts to retry a dead letter signal.
  """
  @spec retry(String.t()) :: {:ok, map()} | {:error, term()}
  def retry(signal_id) do
    GenServer.call(__MODULE__, {:retry, signal_id})
  end
  
  @doc """
  Retrieves a signal from the dead letter queue.
  """
  @spec get(String.t()) :: {:ok, dead_letter_entry()} | {:error, :not_found}
  def get(signal_id) do
    GenServer.call(__MODULE__, {:get, signal_id})
  end
  
  @doc """
  Lists all signals in the dead letter queue.
  """
  @spec list(keyword()) :: [dead_letter_entry()]
  def list(opts \\ []) do
    GenServer.call(__MODULE__, {:list, opts})
  end
  
  @doc """
  Removes a signal from the dead letter queue.
  """
  @spec remove(String.t()) :: :ok
  def remove(signal_id) do
    GenServer.call(__MODULE__, {:remove, signal_id})
  end
  
  @doc """
  Clears all expired signals from the queue.
  """
  @spec cleanup() :: {:ok, non_neg_integer()}
  def cleanup do
    GenServer.call(__MODULE__, :cleanup)
  end
  
  @doc """
  Returns dead letter queue statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Create ETS table for dead letter storage
    :ets.new(@ets_table, [:set, :protected, :named_table])
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    state = %{
      default_ttl: Keyword.get(opts, :default_ttl, @default_ttl),
      max_retries: Keyword.get(opts, :max_retries, @max_retries),
      retry_handler: Keyword.get(opts, :retry_handler),
      stats: %{
        total_enqueued: 0,
        total_retried: 0,
        total_expired: 0,
        total_removed: 0,
        by_reason: %{}
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:enqueue, signal, reason, opts}, _from, state) do
    signal_id = extract_signal_id(signal)
    
    # Check if signal already exists in DLQ
    case :ets.lookup(@ets_table, signal_id) do
      [{^signal_id, existing_entry}] ->
        # Update existing entry with new attempt
        updated_entry = %{existing_entry |
          attempts: existing_entry.attempts + 1,
          last_failure: DateTime.utc_now(),
          reason: reason
        }
        
        if updated_entry.attempts > state.max_retries do
          Logger.warning("Signal #{signal_id} exceeded max retries (#{state.max_retries})")
          {:reply, {:error, :max_retries_exceeded}, state}
        else
          :ets.insert(@ets_table, {signal_id, updated_entry})
          new_state = update_stats(state, :retry_enqueued, reason)
          {:reply, {:ok, signal_id}, new_state}
        end
        
      [] ->
        # Create new dead letter entry
        entry = %{
          signal: signal,
          reason: reason,
          attempts: 1,
          first_failure: DateTime.utc_now(),
          last_failure: DateTime.utc_now(),
          ttl: Keyword.get(opts, :ttl, state.default_ttl),
          metadata: Keyword.get(opts, :metadata, %{})
        }
        
        :ets.insert(@ets_table, {signal_id, entry})
        
        Logger.info("Signal #{signal_id} added to dead letter queue: #{inspect(reason)}")
        
        new_state = update_stats(state, :enqueued, reason)
        {:reply, {:ok, signal_id}, new_state}
    end
  end
  
  @impl true
  def handle_call({:retry, signal_id}, _from, state) do
    case :ets.lookup(@ets_table, signal_id) do
      [{^signal_id, entry}] ->
        # Attempt to retry the signal
        result = retry_signal(entry, state)
        
        case result do
          {:ok, _} ->
            # Remove from DLQ on successful retry
            :ets.delete(@ets_table, signal_id)
            new_state = update_stats(state, :retried)
            {:reply, {:ok, entry.signal}, new_state}
            
          {:error, new_reason} ->
            # Update entry with new failure
            updated_entry = %{entry |
              attempts: entry.attempts + 1,
              last_failure: DateTime.utc_now(),
              reason: new_reason
            }
            
            if updated_entry.attempts > state.max_retries do
              Logger.error("Signal #{signal_id} permanently failed after #{updated_entry.attempts} attempts")
              :ets.delete(@ets_table, signal_id)
              new_state = update_stats(state, :max_retries)
              {:reply, {:error, :permanently_failed}, new_state}
            else
              :ets.insert(@ets_table, {signal_id, updated_entry})
              {:reply, {:error, new_reason}, state}
            end
        end
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:get, signal_id}, _from, state) do
    case :ets.lookup(@ets_table, signal_id) do
      [{^signal_id, entry}] -> {:reply, {:ok, entry}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:list, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 100)
    filter_reason = Keyword.get(opts, :reason)
    sort_by = Keyword.get(opts, :sort_by, :last_failure)
    
    entries = :ets.tab2list(@ets_table)
      |> Enum.map(fn {_id, entry} -> entry end)
      |> maybe_filter_by_reason(filter_reason)
      |> sort_entries(sort_by)
      |> Enum.take(limit)
    
    {:reply, entries, state}
  end
  
  @impl true
  def handle_call({:remove, signal_id}, _from, state) do
    :ets.delete(@ets_table, signal_id)
    new_state = update_stats(state, :removed)
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:cleanup, _from, state) do
    expired_count = cleanup_expired_signals(state)
    new_state = update_stats(state, :expired, expired_count)
    {:reply, {:ok, expired_count}, new_state}
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    current_count = :ets.info(@ets_table, :size)
    
    stats = Map.merge(state.stats, %{
      current_count: current_count,
      oldest_entry: get_oldest_entry(),
      newest_entry: get_newest_entry()
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    expired_count = cleanup_expired_signals(state)
    
    if expired_count > 0 do
      Logger.info("Cleaned up #{expired_count} expired signals from dead letter queue")
    end
    
    # Schedule next cleanup
    schedule_cleanup()
    
    new_state = update_stats(state, :expired, expired_count)
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp extract_signal_id(%{id: id}), do: id
  defp extract_signal_id(%{"id" => id}), do: id
  defp extract_signal_id(_), do: UUID.uuid4()
  
  defp retry_signal(entry, state) do
    # Use custom retry handler if provided
    if state.retry_handler do
      apply(state.retry_handler, :retry, [entry.signal])
    else
      # Default retry: republish to signal bus
      case Jido.Signal.Bus.publish(RubberDuck.SignalBus, [entry.signal]) do
        {:ok, _} -> {:ok, :republished}
        error -> error
      end
    end
  end
  
  defp cleanup_expired_signals(state) do
    now = DateTime.utc_now()
    
    expired = :ets.tab2list(@ets_table)
      |> Enum.filter(fn {_id, entry} ->
        expired?(entry, now)
      end)
    
    Enum.each(expired, fn {id, _entry} ->
      :ets.delete(@ets_table, id)
    end)
    
    length(expired)
  end
  
  defp expired?(entry, now) do
    elapsed = DateTime.diff(now, entry.first_failure, :millisecond)
    elapsed > entry.ttl
  end
  
  defp maybe_filter_by_reason(entries, nil), do: entries
  defp maybe_filter_by_reason(entries, reason) do
    Enum.filter(entries, fn entry ->
      entry.reason == reason
    end)
  end
  
  defp sort_entries(entries, :last_failure) do
    Enum.sort_by(entries, & &1.last_failure, {:desc, DateTime})
  end
  
  defp sort_entries(entries, :first_failure) do
    Enum.sort_by(entries, & &1.first_failure, {:desc, DateTime})
  end
  
  defp sort_entries(entries, :attempts) do
    Enum.sort_by(entries, & &1.attempts, :desc)
  end
  
  defp get_oldest_entry do
    case :ets.tab2list(@ets_table) do
      [] -> nil
      entries ->
        entries
        |> Enum.map(fn {_id, entry} -> entry end)
        |> Enum.min_by(& &1.first_failure, DateTime, fn -> nil end)
    end
  end
  
  defp get_newest_entry do
    case :ets.tab2list(@ets_table) do
      [] -> nil
      entries ->
        entries
        |> Enum.map(fn {_id, entry} -> entry end)
        |> Enum.max_by(& &1.last_failure, DateTime, fn -> nil end)
    end
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
  
  defp update_stats(state, :enqueued, reason) do
    stats = state.stats
      |> Map.update!(:total_enqueued, &(&1 + 1))
      |> Map.update!(:by_reason, fn by_reason ->
        Map.update(by_reason, inspect(reason), 1, &(&1 + 1))
      end)
    
    %{state | stats: stats}
  end
  
  defp update_stats(state, :retry_enqueued, reason) do
    stats = Map.update!(state.stats, :by_reason, fn by_reason ->
      Map.update(by_reason, inspect(reason), 1, &(&1 + 1))
    end)
    
    %{state | stats: stats}
  end
  
  defp update_stats(state, :retried) do
    stats = Map.update!(state.stats, :total_retried, &(&1 + 1))
    %{state | stats: stats}
  end
  
  defp update_stats(state, :expired, count) do
    stats = Map.update!(state.stats, :total_expired, &(&1 + count))
    %{state | stats: stats}
  end
  
  defp update_stats(state, :removed) do
    stats = Map.update!(state.stats, :total_removed, &(&1 + 1))
    %{state | stats: stats}
  end
  
  defp update_stats(state, :max_retries) do
    stats = Map.update!(state.stats, :total_removed, &(&1 + 1))
    %{state | stats: stats}
  end
end