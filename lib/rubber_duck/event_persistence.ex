defmodule RubberDuck.EventPersistence do
  @moduledoc """
  Event persistence service for audit trail and replay capabilities.
  
  This GenServer provides:
  - Persistent storage of system events in Mnesia
  - Event replay functionality for debugging and recovery
  - Audit trail capabilities for compliance
  - Event filtering and querying
  - Retention policy management
  - Compression for long-term storage
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.{EventSchemas, TransactionWrapper}
  alias RubberDuck.EventBroadcasting.EventBroadcaster
  
  @type persistence_options :: [
    persist_level: :all | :critical | :audit_only,
    retention_days: non_neg_integer(),
    compression_enabled: boolean(),
    batch_size: non_neg_integer()
  ]
  
  @type query_options :: [
    topic_pattern: String.t(),
    from_timestamp: DateTime.t(),
    to_timestamp: DateTime.t(),
    node_filter: node(),
    priority_filter: EventSchemas.event_priority(),
    limit: non_neg_integer(),
    offset: non_neg_integer()
  ]
  
  @default_retention_days 90
  @default_batch_size 100
  @cleanup_interval :timer.hours(6)
  @compression_threshold_days 7
  
  # Client API
  
  @doc """
  Start the EventPersistence GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Persist an event to storage.
  """
  def persist_event(event, opts \\ []) do
    GenServer.call(__MODULE__, {:persist_event, event, opts})
  end
  
  @doc """
  Query persisted events.
  
  ## Examples
  
      # Get all events from last 24 hours
      events = EventPersistence.query_events(
        from_timestamp: DateTime.add(DateTime.utc_now(), -24, :hour)
      )
      
      # Get model health events for specific node
      events = EventPersistence.query_events(
        topic_pattern: "model.health.*",
        node_filter: :node1@localhost,
        limit: 50
      )
  """
  def query_events(opts \\ []) do
    GenServer.call(__MODULE__, {:query_events, opts})
  end
  
  @doc """
  Replay events from a specific time range.
  
  This re-broadcasts events in chronological order, useful for:
  - System recovery after failures
  - Debugging distributed state issues
  - Testing event handlers
  """
  def replay_events(from_timestamp, to_timestamp, opts \\ []) do
    GenServer.call(__MODULE__, {:replay_events, from_timestamp, to_timestamp, opts})
  end
  
  @doc """
  Get audit trail for a specific entity.
  
  ## Examples
  
      # Get all events for a session
      trail = EventPersistence.get_audit_trail(:session, "session_123")
      
      # Get model coordination events
      trail = EventPersistence.get_audit_trail(:model, "gpt-4")
  """
  def get_audit_trail(entity_type, entity_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_audit_trail, entity_type, entity_id, opts})
  end
  
  @doc """
  Get persistence statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Manually trigger cleanup of old events.
  """
  def cleanup_old_events do
    GenServer.cast(__MODULE__, :cleanup_old_events)
  end
  
  @doc """
  Compress old events to save storage space.
  """
  def compress_old_events do
    GenServer.cast(__MODULE__, :compress_old_events)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Create event storage table if it doesn't exist
    create_event_tables()
    
    # Subscribe to all events for persistence
    EventBroadcaster.subscribe("*", ack_required: false)
    
    # Schedule cleanup
    schedule_cleanup()
    
    state = %{
      persist_level: Keyword.get(opts, :persist_level, :all),
      retention_days: Keyword.get(opts, :retention_days, @default_retention_days),
      compression_enabled: Keyword.get(opts, :compression_enabled, true),
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      stats: %{
        events_persisted: 0,
        events_queried: 0,
        events_replayed: 0,
        storage_size_bytes: 0,
        last_cleanup: nil,
        last_compression: nil
      },
      event_buffer: [],
      buffer_timer: nil
    }
    
    Logger.info("EventPersistence started with retention: #{state.retention_days} days")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:persist_event, event, opts}, _from, state) do
    if should_persist_event?(event, state) do
      case persist_single_event(event, opts) do
        :ok ->
          new_stats = %{state.stats | events_persisted: state.stats.events_persisted + 1}
          {:reply, :ok, %{state | stats: new_stats}}
        {:error, reason} ->
          Logger.error("Failed to persist event #{event.id}: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, :skipped, state}
    end
  end
  
  @impl true
  def handle_call({:query_events, opts}, _from, state) do
    case query_persisted_events(opts) do
      {:ok, events} ->
        new_stats = %{state.stats | events_queried: state.stats.events_queried + length(events)}
        {:reply, {:ok, events}, %{state | stats: new_stats}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:replay_events, from_ts, to_ts, opts}, _from, state) do
    case replay_persisted_events(from_ts, to_ts, opts) do
      {:ok, count} ->
        new_stats = %{state.stats | events_replayed: state.stats.events_replayed + count}
        {:reply, {:ok, count}, %{state | stats: new_stats}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:get_audit_trail, entity_type, entity_id, opts}, _from, state) do
    case build_audit_trail(entity_type, entity_id, opts) do
      {:ok, trail} ->
        {:reply, {:ok, trail}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    enhanced_stats = enhance_stats(state.stats)
    {:reply, enhanced_stats, state}
  end
  
  @impl true
  def handle_cast(:cleanup_old_events, state) do
    case cleanup_expired_events(state.retention_days) do
      {:ok, deleted_count} ->
        Logger.info("Cleaned up #{deleted_count} expired events")
        new_stats = %{state.stats | last_cleanup: DateTime.utc_now()}
        schedule_cleanup()
        {:noreply, %{state | stats: new_stats}}
      {:error, reason} ->
        Logger.error("Failed to cleanup events: #{inspect(reason)}")
        schedule_cleanup()
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_cast(:compress_old_events, state) do
    if state.compression_enabled do
      case compress_events_older_than_days(@compression_threshold_days) do
        {:ok, compressed_count} ->
          Logger.info("Compressed #{compressed_count} old events")
          new_stats = %{state.stats | last_compression: DateTime.utc_now()}
          {:noreply, %{state | stats: new_stats}}
        {:error, reason} ->
          Logger.error("Failed to compress events: #{inspect(reason)}")
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_cast({:buffer_event, event}, state) do
    updated_buffer = [event | state.event_buffer]
    
    if length(updated_buffer) >= state.batch_size do
      # Flush buffer
      persist_event_batch(updated_buffer)
      new_stats = %{state.stats | events_persisted: state.stats.events_persisted + length(updated_buffer)}
      
      if state.buffer_timer do
        Process.cancel_timer(state.buffer_timer)
      end
      
      {:noreply, %{state | event_buffer: [], buffer_timer: nil, stats: new_stats}}
    else
      # Schedule flush if no timer running
      timer = if state.buffer_timer do
        state.buffer_timer
      else
        Process.send_after(self(), :flush_buffer, 5000)
      end
      
      {:noreply, %{state | event_buffer: updated_buffer, buffer_timer: timer}}
    end
  end
  
  @impl true
  def handle_info({:event, event}, state) do
    # Event received from EventBroadcaster
    if should_persist_event?(event, state) do
      GenServer.cast(self(), {:buffer_event, event})
    end
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:flush_buffer, state) do
    if not Enum.empty?(state.event_buffer) do
      persist_event_batch(state.event_buffer)
      new_stats = %{state.stats | events_persisted: state.stats.events_persisted + length(state.event_buffer)}
      {:noreply, %{state | event_buffer: [], buffer_timer: nil, stats: new_stats}}
    else
      {:noreply, %{state | buffer_timer: nil}}
    end
  end
  
  @impl true
  def handle_info(:cleanup_events, state) do
    GenServer.cast(self(), :cleanup_old_events)
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Flush any remaining buffered events
    if not Enum.empty?(state.event_buffer) do
      persist_event_batch(state.event_buffer)
    end
    :ok
  end
  
  # Private Functions
  
  defp create_event_tables do
    # Main events table
    :mnesia.create_table(:event_store, [
      {:attributes, [:id, :topic, :payload, :timestamp, :source_node, :priority, :metadata, :compressed]},
      {:disc_copies, [node()]},
      {:type, :ordered_set},
      {:index, [:topic, :timestamp, :source_node, :priority]}
    ])
    
    # Audit trail index for fast entity lookups
    :mnesia.create_table(:event_audit_index, [
      {:attributes, [:entity_key, :event_id, :timestamp]},
      {:disc_copies, [node()]},
      {:type, :bag},
      {:index, [:timestamp]}
    ])
  end
  
  defp should_persist_event?(event, state) do
    case state.persist_level do
      :all -> true
      :critical -> event.priority in [:high, :critical]
      :audit_only -> is_audit_event?(event)
    end
  end
  
  defp is_audit_event?(event) do
    # Events that should always be persisted for audit purposes
    event.topic =~ ~r/^(context\.session\.|model\.health\.|provider\.status\.|cluster\.node\.)/
  end
  
  defp persist_single_event(event, _opts) do
    event_record = {
      :event_store,
      event.id,
      event.topic,
      event.payload,
      event.timestamp,
      event.source_node,
      event.priority,
      event.metadata,
      false  # not compressed
    }
    
    TransactionWrapper.create_record(:event_store, event_record, 
      metadata: %{operation: :persist_event})
    
    # Create audit index entries
    create_audit_index_entries(event)
    
    :ok
  rescue
    error -> {:error, error}
  end
  
  defp persist_event_batch(events) when is_list(events) do
    TransactionWrapper.sync_transaction(fn ->
      Enum.each(events, fn event ->
        event_record = {
          :event_store,
          event.id,
          event.topic,
          event.payload,
          event.timestamp,
          event.source_node,
          event.priority,
          event.metadata,
          false
        }
        
        :mnesia.write(event_record)
        create_audit_index_entries(event)
      end)
    end)
  rescue
    error -> 
      Logger.error("Failed to persist event batch: #{inspect(error)}")
      {:error, error}
  end
  
  defp create_audit_index_entries(event) do
    # Extract entity references from event payload
    entities = extract_entity_references(event)
    
    Enum.each(entities, fn {entity_type, entity_id} ->
      entity_key = "#{entity_type}:#{entity_id}"
      index_record = {:event_audit_index, entity_key, event.id, event.timestamp}
      :mnesia.write(index_record)
    end)
  end
  
  defp extract_entity_references(event) do
    entities = []
    
    # Extract session references
    entities = if session_id = get_in(event.payload, [:session_id]) do
      [{"session", session_id} | entities]
    else
      entities
    end
    
    # Extract model references
    entities = if model_name = get_in(event.payload, [:model_name]) do
      [{"model", model_name} | entities]
    else
      entities
    end
    
    # Extract provider references
    entities = if provider_name = get_in(event.payload, [:provider_name]) do
      [{"provider", provider_name} | entities]
    else
      entities
    end
    
    # Extract node references
    entities = if node_name = get_in(event.payload, [:node_name]) do
      [{"node", to_string(node_name)} | entities]
    else
      entities
    end
    
    entities
  end
  
  defp query_persisted_events(opts) do
    topic_pattern = Keyword.get(opts, :topic_pattern)
    from_ts = Keyword.get(opts, :from_timestamp)
    to_ts = Keyword.get(opts, :to_timestamp)
    node_filter = Keyword.get(opts, :node_filter)
    priority_filter = Keyword.get(opts, :priority_filter)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    
    match_spec = build_match_spec(topic_pattern, from_ts, to_ts, node_filter, priority_filter)
    
    case :mnesia.transaction(fn ->
      :mnesia.select(:event_store, match_spec)
    end) do
      {:atomic, {events, _continuation}} ->
        processed_events = events
        |> Enum.drop(offset)
        |> Enum.map(&record_to_event/1)
        
        {:ok, processed_events}
      {:atomic, events} when is_list(events) ->
        processed_events = events
        |> Enum.drop(offset)
        |> Enum.map(&record_to_event/1)
        
        {:ok, processed_events}
      {:aborted, reason} ->
        {:error, reason}
    end
  end
  
  defp build_match_spec(topic_pattern, from_ts, to_ts, node_filter, priority_filter) do
    # Build Mnesia match specification based on filters
    pattern = {:event_store, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8"}
    
    guards = []
    
    # Topic pattern matching
    guards = if topic_pattern do
      [{:like, :"$2", String.replace(topic_pattern, "*", "%")} | guards]
    else
      guards
    end
    
    # Timestamp range
    guards = if from_ts do
      from_ts_int = DateTime.to_unix(from_ts, :microsecond)
      [{:>=, :"$4", from_ts_int} | guards]
    else
      guards
    end
    
    guards = if to_ts do
      to_ts_int = DateTime.to_unix(to_ts, :microsecond)
      [{:"=<", :"$4", to_ts_int} | guards]
    else
      guards
    end
    
    # Node filter
    guards = if node_filter do
      [{:==, :"$5", node_filter} | guards]
    else
      guards
    end
    
    # Priority filter
    guards = if priority_filter do
      [{:==, :"$6", priority_filter} | guards]
    else
      guards
    end
    
    # Combine guards with AND
    final_guards = case guards do
      [] -> []
      [single] -> single
      multiple -> {:andalso, multiple}
    end
    
    [{pattern, [final_guards], [:"$$"]}]
  end
  
  defp record_to_event({:event_store, id, topic, payload, timestamp, source_node, priority, metadata, compressed}) do
    decoded_payload = if compressed do
      :erlang.binary_to_term(:zlib.uncompress(payload))
    else
      payload
    end
    
    %{
      id: id,
      topic: topic,
      payload: decoded_payload,
      timestamp: timestamp,
      source_node: source_node,
      priority: priority,
      metadata: metadata
    }
  end
  
  defp replay_persisted_events(from_ts, to_ts, opts) do
    replay_delay = Keyword.get(opts, :replay_delay_ms, 0)
    target_topic = Keyword.get(opts, :target_topic, nil)
    
    case query_persisted_events([
      from_timestamp: from_ts,
      to_timestamp: to_ts,
      limit: 10000  # Large limit for replay
    ]) do
      {:ok, events} ->
        sorted_events = Enum.sort_by(events, & &1.timestamp)
        
        Task.start(fn ->
          Enum.each(sorted_events, fn event ->
            if replay_delay > 0 do
              :timer.sleep(replay_delay)
            end
            
            replay_event = if target_topic do
              %{event | topic: target_topic, metadata: Map.put(event.metadata, :replayed, true)}
            else
              %{event | metadata: Map.put(event.metadata, :replayed, true)}
            end
            
            EventBroadcaster.broadcast_async(replay_event)
          end)
        end)
        
        {:ok, length(sorted_events)}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp build_audit_trail(entity_type, entity_id, opts) do
    entity_key = "#{entity_type}:#{entity_id}"
    limit = Keyword.get(opts, :limit, 500)
    
    case :mnesia.transaction(fn ->
      :mnesia.read(:event_audit_index, entity_key)
    end) do
      {:atomic, index_entries} ->
        event_ids = index_entries
        |> Enum.sort_by(fn {_, _, _, timestamp} -> timestamp end)
        |> Enum.take(limit)
        |> Enum.map(fn {_, _, event_id, _} -> event_id end)
        
        # Fetch actual events
        events = Enum.map(event_ids, fn event_id ->
          case :mnesia.transaction(fn -> :mnesia.read(:event_store, event_id) end) do
            {:atomic, [record]} -> record_to_event(record)
            _ -> nil
          end
        end)
        |> Enum.filter(& &1 != nil)
        
        {:ok, events}
        
      {:aborted, reason} ->
        {:error, reason}
    end
  end
  
  defp cleanup_expired_events(retention_days) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -retention_days, :day)
    cutoff_timestamp = DateTime.to_unix(cutoff_time, :microsecond)
    
    case :mnesia.transaction(fn ->
      match_spec = [{{:event_store, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8"}, 
                    [{:<, :"$4", cutoff_timestamp}], [:"$1"]}]
      
      expired_ids = :mnesia.select(:event_store, match_spec)
      
      Enum.each(expired_ids, fn event_id ->
        :mnesia.delete({:event_store, event_id})
        # Also cleanup audit index entries
        cleanup_audit_index_for_event(event_id)
      end)
      
      length(expired_ids)
    end) do
      {:atomic, count} -> {:ok, count}
      {:aborted, reason} -> {:error, reason}
    end
  end
  
  defp cleanup_audit_index_for_event(event_id) do
    # This would need a more sophisticated approach in production
    # For now, we'll leave audit index cleanup for a separate process
    :ok
  end
  
  defp compress_events_older_than_days(days) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -days, :day)
    cutoff_timestamp = DateTime.to_unix(cutoff_time, :microsecond)
    
    case :mnesia.transaction(fn ->
      match_spec = [{{:event_store, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", false}, 
                    [{:<, :"$4", cutoff_timestamp}], [:"$$"]}]
      
      uncompressed_events = :mnesia.select(:event_store, match_spec)
      
      Enum.each(uncompressed_events, fn [id, topic, payload, timestamp, source_node, priority, metadata, _compressed] ->
        compressed_payload = :zlib.compress(:erlang.term_to_binary(payload))
        compressed_record = {:event_store, id, topic, compressed_payload, timestamp, source_node, priority, metadata, true}
        :mnesia.write(compressed_record)
      end)
      
      length(uncompressed_events)
    end) do
      {:atomic, count} -> {:ok, count}
      {:aborted, reason} -> {:error, reason}
    end
  end
  
  defp enhance_stats(stats) do
    storage_info = case :mnesia.table_info(:event_store, :size) do
      size when is_integer(size) ->
        %{event_count: size, storage_size_estimate: size * 1024}  # Rough estimate
      _ ->
        %{event_count: 0, storage_size_estimate: 0}
    end
    
    Map.merge(stats, storage_info)
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_events, @cleanup_interval)
  end
end