defmodule RubberDuck.Tool.StatePersistence do
  @moduledoc """
  Manages tool state persistence across sessions.
  
  Features:
  - Session-based state storage
  - Tool execution history tracking
  - Result caching and retrieval
  - State versioning and migration
  """
  
  use GenServer
  
  alias RubberDuck.Cache.ETS, as: Cache
  alias RubberDuck.Storage.FileSystem, as: Storage
  
  require Logger
  
  @table_name :tool_state_persistence
  @history_limit 100
  @state_ttl 86_400  # 24 hours
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Saves tool execution state for a session.
  """
  def save_state(session_id, tool_name, state) do
    GenServer.call(__MODULE__, {:save_state, session_id, tool_name, state})
  end
  
  @doc """
  Retrieves tool state for a session.
  """
  def get_state(session_id, tool_name) do
    GenServer.call(__MODULE__, {:get_state, session_id, tool_name})
  end
  
  @doc """
  Saves tool execution history.
  """
  def save_execution(execution_record) do
    GenServer.cast(__MODULE__, {:save_execution, execution_record})
  end
  
  @doc """
  Gets execution history for a tool or session.
  """
  def get_history(filter \\ %{}) do
    GenServer.call(__MODULE__, {:get_history, filter})
  end
  
  @doc """
  Clears state for a session.
  """
  def clear_session(session_id) do
    GenServer.call(__MODULE__, {:clear_session, session_id})
  end
  
  @doc """
  Gets statistics about tool usage.
  """
  def get_statistics(tool_name \\ nil) do
    GenServer.call(__MODULE__, {:get_statistics, tool_name})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Create ETS table for fast access
    :ets.new(@table_name, [:set, :public, :named_table, {:read_concurrency, true}])
    
    state = %{
      storage_backend: Keyword.get(opts, :storage_backend, Storage),
      cache_backend: Keyword.get(opts, :cache_backend, Cache),
      history_limit: Keyword.get(opts, :history_limit, @history_limit),
      persist_to_disk: Keyword.get(opts, :persist_to_disk, true)
    }
    
    # Restore persisted state on startup
    if state.persist_to_disk do
      restore_from_disk(state)
    end
    
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, 3600_000)  # 1 hour
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:save_state, session_id, tool_name, tool_state}, _from, state) do
    key = state_key(session_id, tool_name)
    
    state_record = %{
      session_id: session_id,
      tool_name: tool_name,
      state: tool_state,
      updated_at: DateTime.utc_now(),
      version: 1
    }
    
    # Save to ETS
    :ets.insert(@table_name, {key, state_record})
    
    # Save to cache with TTL
    state.cache_backend.put(key, state_record, ttl: @state_ttl)
    
    # Persist to disk if enabled
    if state.persist_to_disk do
      persist_state(key, state_record, state)
    end
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:get_state, session_id, tool_name}, _from, state) do
    key = state_key(session_id, tool_name)
    
    # Try ETS first
    result = case :ets.lookup(@table_name, key) do
      [{^key, state_record}] ->
        {:ok, state_record.state}
      
      [] ->
        # Try cache
        case state.cache_backend.get(key) do
          {:ok, state_record} ->
            # Restore to ETS
            :ets.insert(@table_name, {key, state_record})
            {:ok, state_record.state}
          
          _ ->
            # Try disk storage
            if state.persist_to_disk do
              restore_state_from_disk(key, state)
            else
              {:error, :not_found}
            end
        end
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:get_history, filter}, _from, state) do
    history = get_filtered_history(filter)
    {:reply, {:ok, history}, state}
  end
  
  @impl true
  def handle_call({:clear_session, session_id}, _from, state) do
    # Find all keys for this session
    pattern = {{:state, session_id, :_}, :_}
    keys_to_delete = :ets.match(@table_name, pattern)
    |> Enum.map(fn [key] -> key end)
    
    # Delete from ETS
    Enum.each(keys_to_delete, &:ets.delete(@table_name, &1))
    
    # Delete from cache
    Enum.each(keys_to_delete, fn key ->
      state.cache_backend.delete(cache_key(key))
    end)
    
    # Delete from disk if enabled
    if state.persist_to_disk do
      clear_session_from_disk(session_id, state)
    end
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:get_statistics, tool_name}, _from, state) do
    stats = calculate_statistics(tool_name)
    {:reply, {:ok, stats}, state}
  end
  
  @impl true
  def handle_cast({:save_execution, execution_record}, state) do
    # Add to history
    history_key = history_key(execution_record.tool_name)
    
    # Get current history
    history = case :ets.lookup(@table_name, history_key) do
      [{^history_key, records}] -> records
      [] -> []
    end
    
    # Add new record and limit size
    updated_history = [execution_record | history]
    |> Enum.take(state.history_limit)
    
    # Save to ETS
    :ets.insert(@table_name, {history_key, updated_history})
    
    # Also save individual execution for quick lookup
    exec_key = execution_key(execution_record.request_id)
    :ets.insert(@table_name, {exec_key, execution_record})
    
    # Persist if enabled
    if state.persist_to_disk do
      persist_execution(execution_record, state)
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Clean up old states
    cleanup_old_states()
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup, 3600_000)
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp state_key(session_id, tool_name) do
    {:state, session_id, tool_name}
  end
  
  defp history_key(tool_name) do
    {:history, tool_name}
  end
  
  defp execution_key(request_id) do
    {:execution, request_id}
  end
  
  defp cache_key({type, id, name}) do
    "tool_state:#{type}:#{id}:#{name}"
  end
  
  defp persist_state(key, state_record, state) do
    storage_key = "tool_states/#{encode_key(key)}"
    state.storage_backend.store(storage_key, state_record)
  end
  
  defp persist_execution(execution_record, state) do
    # Save to execution log
    date = Date.utc_today()
    storage_key = "tool_executions/#{date}/#{execution_record.request_id}"
    state.storage_backend.store(storage_key, execution_record)
    
    # Update daily index
    index_key = "tool_executions/#{date}/index"
    case state.storage_backend.retrieve(index_key) do
      {:ok, index} ->
        updated_index = [execution_record.request_id | index] |> Enum.uniq()
        state.storage_backend.store(index_key, updated_index)
      
      _ ->
        state.storage_backend.store(index_key, [execution_record.request_id])
    end
  end
  
  defp restore_from_disk(state) do
    # Restore recent states
    case state.storage_backend.list() do
      {:ok, keys} ->
        # Filter for tool states
        tool_state_keys = Enum.filter(keys, &String.starts_with?(&1, "tool_states/"))
        
        Enum.each(tool_state_keys, fn storage_key ->
          case state.storage_backend.retrieve(storage_key) do
            {:ok, state_record} ->
              key = decode_key(Path.basename(storage_key))
              :ets.insert(@table_name, {key, state_record})
            
            _ ->
              :ok
          end
        end)
      
      _ ->
        :ok
    end
  end
  
  defp restore_state_from_disk(key, state) do
    storage_key = "tool_states/#{encode_key(key)}"
    
    case state.storage_backend.retrieve(storage_key) do
      {:ok, state_record} ->
        # Restore to ETS and cache
        :ets.insert(@table_name, {key, state_record})
        state.cache_backend.put(cache_key(key), state_record, ttl: @state_ttl)
        {:ok, state_record.state}
      
      _ ->
        {:error, :not_found}
    end
  end
  
  defp clear_session_from_disk(session_id, state) do
    case state.storage_backend.list() do
      {:ok, keys} ->
        # Filter keys matching the session
        session_keys = Enum.filter(keys, fn key ->
          String.contains?(key, session_id)
        end)
        
        Enum.each(session_keys, &state.storage_backend.delete/1)
      
      _ ->
        :ok
    end
  end
  
  defp get_filtered_history(filter) do
    cond do
      filter[:tool_name] ->
        # Get history for specific tool
        case :ets.lookup(@table_name, history_key(filter.tool_name)) do
          [{_, records}] -> filter_records(records, filter)
          [] -> []
        end
      
      filter[:session_id] ->
        # Get all executions for a session
        pattern = {{:execution, :_}, %{session_id: filter.session_id}}
        :ets.match_object(@table_name, pattern)
        |> Enum.map(fn {_, record} -> record end)
        |> filter_records(filter)
      
      filter[:request_id] ->
        # Get specific execution
        case :ets.lookup(@table_name, execution_key(filter.request_id)) do
          [{_, record}] -> [record]
          [] -> []
        end
      
      true ->
        # Get all recent executions
        :ets.match_object(@table_name, {{:execution, :_}, :_})
        |> Enum.map(fn {_, record} -> record end)
        |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
        |> Enum.take(filter[:limit] || 50)
    end
  end
  
  defp filter_records(records, filter) do
    records
    |> apply_date_filter(filter[:from_date], filter[:to_date])
    |> apply_status_filter(filter[:status])
    |> Enum.take(filter[:limit] || 50)
  end
  
  defp apply_date_filter(records, nil, nil), do: records
  defp apply_date_filter(records, from_date, to_date) do
    Enum.filter(records, fn record ->
      date = record.started_at
      
      (is_nil(from_date) or DateTime.compare(date, from_date) != :lt) and
      (is_nil(to_date) or DateTime.compare(date, to_date) != :gt)
    end)
  end
  
  defp apply_status_filter(records, nil), do: records
  defp apply_status_filter(records, status) do
    Enum.filter(records, & &1.status == status)
  end
  
  defp calculate_statistics(nil) do
    # Global statistics
    all_executions = :ets.match_object(@table_name, {{:execution, :_}, :_})
    |> Enum.map(fn {_, record} -> record end)
    
    calculate_stats_from_records(all_executions, "all tools")
  end
  
  defp calculate_statistics(tool_name) do
    # Tool-specific statistics
    case :ets.lookup(@table_name, history_key(tool_name)) do
      [{_, records}] ->
        calculate_stats_from_records(records, tool_name)
      
      [] ->
        empty_stats(tool_name)
    end
  end
  
  defp calculate_stats_from_records(records, name) do
    total = length(records)
    
    if total == 0 do
      empty_stats(name)
    else
      successful = Enum.count(records, & &1[:status] == :success)
      failed = Enum.count(records, & &1[:status] == :failed)
      
      durations = records
      |> Enum.filter(& &1[:duration_ms])
      |> Enum.map(& &1.duration_ms)
      
      %{
        tool_name: name,
        total_executions: total,
        successful: successful,
        failed: failed,
        success_rate: if(total > 0, do: successful / total * 100, else: 0),
        average_duration_ms: if(length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0),
        min_duration_ms: if(length(durations) > 0, do: Enum.min(durations), else: 0),
        max_duration_ms: if(length(durations) > 0, do: Enum.max(durations), else: 0)
      }
    end
  end
  
  defp empty_stats(name) do
    %{
      tool_name: name,
      total_executions: 0,
      successful: 0,
      failed: 0,
      success_rate: 0.0,
      average_duration_ms: 0,
      min_duration_ms: 0,
      max_duration_ms: 0
    }
  end
  
  defp cleanup_old_states do
    cutoff = DateTime.add(DateTime.utc_now(), -@state_ttl, :second)
    
    # Clean up old states
    :ets.match_object(@table_name, {{:state, :_, :_}, :_})
    |> Enum.filter(fn {_, record} ->
      DateTime.compare(record.updated_at, cutoff) == :lt
    end)
    |> Enum.each(fn {key, _} ->
      :ets.delete(@table_name, key)
    end)
    
    Logger.debug("Cleaned up old tool states")
  end
  
  defp encode_key(key) do
    key
    |> :erlang.term_to_binary()
    |> Base.encode64(padding: false)
  end
  
  defp decode_key(encoded) do
    encoded
    |> Base.decode64!(padding: false)
    |> :erlang.binary_to_term()
  end
end