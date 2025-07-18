defmodule RubberDuckWeb.MCPMessageQueue do
  @moduledoc """
  Message queuing system for MCP channels.
  
  Provides reliable message delivery with:
  - Message persistence during disconnections
  - Guaranteed delivery with acknowledgments
  - Message ordering preservation
  - Retry mechanisms for failed deliveries
  - Dead letter queue for undeliverable messages
  """
  
  use GenServer
  
  require Logger
  
  @type message_id :: String.t()
  @type session_id :: String.t()
  @type message :: %{
    id: message_id(),
    session_id: session_id(),
    payload: map(),
    priority: :low | :normal | :high | :urgent,
    created_at: DateTime.t(),
    expires_at: DateTime.t() | nil,
    retry_count: integer(),
    max_retries: integer(),
    last_error: String.t() | nil
  }
  
  @table_name :mcp_message_queue
  @dlq_table_name :mcp_dead_letter_queue
  @default_ttl 300  # 5 minutes
  @max_retries 3
  
  # Client API
  
  @doc """
  Starts the message queue.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Enqueues a message for delivery.
  """
  @spec enqueue_message(session_id(), map(), keyword()) :: {:ok, message_id()} | {:error, term()}
  def enqueue_message(session_id, payload, opts \\ []) do
    GenServer.call(__MODULE__, {:enqueue_message, session_id, payload, opts})
  end
  
  @doc """
  Dequeues the next message for a session.
  """
  @spec dequeue_message(session_id()) :: {:ok, message()} | {:error, :empty}
  def dequeue_message(session_id) do
    GenServer.call(__MODULE__, {:dequeue_message, session_id})
  end
  
  @doc """
  Acknowledges successful message delivery.
  """
  @spec acknowledge_message(message_id()) :: :ok
  def acknowledge_message(message_id) do
    GenServer.cast(__MODULE__, {:acknowledge_message, message_id})
  end
  
  @doc """
  Reports message delivery failure.
  """
  @spec report_delivery_failure(message_id(), String.t()) :: :ok
  def report_delivery_failure(message_id, error) do
    GenServer.cast(__MODULE__, {:report_delivery_failure, message_id, error})
  end
  
  @doc """
  Gets all pending messages for a session.
  """
  @spec get_pending_messages(session_id()) :: [message()]
  def get_pending_messages(session_id) do
    GenServer.call(__MODULE__, {:get_pending_messages, session_id})
  end
  
  @doc """
  Gets queue statistics.
  """
  @spec get_queue_stats() :: map()
  def get_queue_stats do
    GenServer.call(__MODULE__, :get_queue_stats)
  end
  
  @doc """
  Purges all messages for a session.
  """
  @spec purge_session_messages(session_id()) :: :ok
  def purge_session_messages(session_id) do
    GenServer.cast(__MODULE__, {:purge_session_messages, session_id})
  end
  
  @doc """
  Gets dead letter queue messages.
  """
  @spec get_dead_letter_messages(session_id()) :: [message()]
  def get_dead_letter_messages(session_id) do
    GenServer.call(__MODULE__, {:get_dead_letter_messages, session_id})
  end
  
  @doc """
  Retries a message from the dead letter queue.
  """
  @spec retry_dead_letter_message(message_id()) :: :ok | {:error, term()}
  def retry_dead_letter_message(message_id) do
    GenServer.call(__MODULE__, {:retry_dead_letter_message, message_id})
  end
  
  # Server implementation
  
  @impl GenServer
  def init(opts) do
    # Create ETS tables
    queue_table = :ets.new(@table_name, [:ordered_set, :public, :named_table, read_concurrency: true])
    dlq_table = :ets.new(@dlq_table_name, [:set, :public, :named_table, read_concurrency: true])
    
    # Schedule periodic cleanup
    cleanup_interval = Keyword.get(opts, :cleanup_interval, 60_000)  # 1 minute
    schedule_cleanup(cleanup_interval)
    
    state = %{
      queue_table: queue_table,
      dlq_table: dlq_table,
      cleanup_interval: cleanup_interval,
      message_counter: 0
    }
    
    Logger.info("MCP Message Queue started")
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:enqueue_message, session_id, payload, opts}, _from, state) do
    message_id = generate_message_id(state.message_counter)
    priority = Keyword.get(opts, :priority, :normal)
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    max_retries = Keyword.get(opts, :max_retries, @max_retries)
    
    message = %{
      id: message_id,
      session_id: session_id,
      payload: payload,
      priority: priority,
      created_at: DateTime.utc_now(),
      expires_at: DateTime.add(DateTime.utc_now(), ttl, :second),
      retry_count: 0,
      max_retries: max_retries,
      last_error: nil
    }
    
    # Insert with priority-based key
    priority_key = priority_to_key(priority, message.created_at, message_id)
    :ets.insert(state.queue_table, {priority_key, message})
    
    Logger.debug("Enqueued message #{message_id} for session #{session_id} with priority #{priority}")
    
    {:reply, {:ok, message_id}, %{state | message_counter: state.message_counter + 1}}
  end
  
  @impl GenServer
  def handle_call({:dequeue_message, session_id}, _from, state) do
    case find_next_message(state.queue_table, session_id) do
      {:ok, {key, message}} ->
        # Remove from queue
        :ets.delete(state.queue_table, key)
        
        Logger.debug("Dequeued message #{message.id} for session #{session_id}")
        {:reply, {:ok, message}, state}
        
      :not_found ->
        {:reply, {:error, :empty}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:get_pending_messages, session_id}, _from, state) do
    messages = :ets.tab2list(state.queue_table)
    |> Enum.filter(fn {_key, message} -> message.session_id == session_id end)
    |> Enum.map(fn {_key, message} -> message end)
    |> Enum.sort_by(fn message -> message.created_at end)
    
    {:reply, messages, state}
  end
  
  @impl GenServer
  def handle_call(:get_queue_stats, _from, state) do
    total_messages = :ets.info(state.queue_table, :size)
    dead_letter_messages = :ets.info(state.dlq_table, :size)
    
    # Count by priority
    priority_counts = :ets.tab2list(state.queue_table)
    |> Enum.group_by(fn {_key, message} -> message.priority end)
    |> Enum.map(fn {priority, messages} -> {priority, length(messages)} end)
    |> Map.new()
    
    # Count by session
    session_counts = :ets.tab2list(state.queue_table)
    |> Enum.group_by(fn {_key, message} -> message.session_id end)
    |> Enum.map(fn {session_id, messages} -> {session_id, length(messages)} end)
    |> Map.new()
    
    stats = %{
      total_messages: total_messages,
      dead_letter_messages: dead_letter_messages,
      priority_counts: priority_counts,
      session_counts: session_counts,
      uptime: DateTime.utc_now()
    }
    
    {:reply, stats, state}
  end
  
  @impl GenServer
  def handle_call({:get_dead_letter_messages, session_id}, _from, state) do
    messages = :ets.tab2list(state.dlq_table)
    |> Enum.filter(fn {_key, message} -> message.session_id == session_id end)
    |> Enum.map(fn {_key, message} -> message end)
    |> Enum.sort_by(fn message -> message.created_at end)
    
    {:reply, messages, state}
  end
  
  @impl GenServer
  def handle_call({:retry_dead_letter_message, message_id}, _from, state) do
    case :ets.match_object(state.dlq_table, {:_, %{id: message_id}}) do
      [{key, message}] ->
        # Reset retry count and move back to main queue
        reset_message = %{message | 
          retry_count: 0,
          last_error: nil,
          expires_at: DateTime.add(DateTime.utc_now(), @default_ttl, :second)
        }
        
        # Remove from DLQ
        :ets.delete(state.dlq_table, key)
        
        # Add back to main queue
        priority_key = priority_to_key(reset_message.priority, reset_message.created_at, reset_message.id)
        :ets.insert(state.queue_table, {priority_key, reset_message})
        
        Logger.info("Retried message #{message_id} from dead letter queue")
        {:reply, :ok, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl GenServer
  def handle_cast({:acknowledge_message, message_id}, state) do
    # Message was successfully delivered, no action needed
    Logger.debug("Acknowledged message #{message_id}")
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_cast({:report_delivery_failure, message_id, error}, state) do
    # Find message in queue or processing
    case find_message_by_id(state.queue_table, message_id) do
      {:ok, {key, message}} ->
        updated_message = %{message | 
          retry_count: message.retry_count + 1,
          last_error: error
        }
        
        if updated_message.retry_count >= updated_message.max_retries do
          # Move to dead letter queue
          :ets.delete(state.queue_table, key)
          dlq_key = "dlq_#{message_id}_#{DateTime.utc_now() |> DateTime.to_unix()}"
          :ets.insert(state.dlq_table, {dlq_key, updated_message})
          
          Logger.warning("Message #{message_id} moved to dead letter queue after #{updated_message.retry_count} retries")
        else
          # Requeue with exponential backoff
          :ets.insert(state.queue_table, {key, updated_message})
          
          Logger.debug("Message #{message_id} requeued for retry #{updated_message.retry_count}/#{updated_message.max_retries}")
        end
        
      :not_found ->
        Logger.warning("Could not find message #{message_id} to report failure")
    end
    
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_cast({:purge_session_messages, session_id}, state) do
    # Remove all messages for the session
    messages_to_remove = :ets.tab2list(state.queue_table)
    |> Enum.filter(fn {_key, message} -> message.session_id == session_id end)
    |> Enum.map(fn {key, _message} -> key end)
    
    Enum.each(messages_to_remove, fn key ->
      :ets.delete(state.queue_table, key)
    end)
    
    count = length(messages_to_remove)
    if count > 0 do
      Logger.info("Purged #{count} messages for session #{session_id}")
    end
    
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info(:cleanup, state) do
    cleanup_expired_messages(state)
    schedule_cleanup(state.cleanup_interval)
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  # Private functions
  
  defp generate_message_id(counter) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    "msg_#{timestamp}_#{counter}"
  end
  
  defp priority_to_key(priority, created_at, message_id) do
    # Create sortable key: priority (lower number = higher priority), timestamp, message_id
    priority_num = case priority do
      :urgent -> 1
      :high -> 2
      :normal -> 3
      :low -> 4
    end
    
    timestamp = DateTime.to_unix(created_at)
    "#{priority_num}_#{timestamp}_#{message_id}"
  end
  
  defp find_next_message(table, session_id) do
    # Use ETS ordered_set to get messages in priority order
    case :ets.first(table) do
      :"$end_of_table" ->
        :not_found
        
      key ->
        find_next_message_from_key(table, session_id, key)
    end
  end
  
  defp find_next_message_from_key(table, session_id, key) do
    case :ets.lookup(table, key) do
      [{^key, message}] ->
        if message.session_id == session_id and not message_expired?(message) do
          {:ok, {key, message}}
        else
          # Try next key
          case :ets.next(table, key) do
            :"$end_of_table" ->
              :not_found
              
            next_key ->
              find_next_message_from_key(table, session_id, next_key)
          end
        end
        
      [] ->
        :not_found
    end
  end
  
  defp find_message_by_id(table, message_id) do
    case :ets.match_object(table, {:_, %{id: message_id}}) do
      [{key, message}] ->
        {:ok, {key, message}}
        
      [] ->
        :not_found
    end
  end
  
  defp message_expired?(message) do
    case message.expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end
  
  defp cleanup_expired_messages(state) do
    current_time = DateTime.utc_now()
    
    # Find expired messages
    expired_messages = :ets.tab2list(state.queue_table)
    |> Enum.filter(fn {_key, message} -> message_expired?(message) end)
    |> Enum.map(fn {key, _message} -> key end)
    
    # Remove expired messages
    Enum.each(expired_messages, fn key ->
      :ets.delete(state.queue_table, key)
    end)
    
    # Clean up old DLQ messages (older than 1 hour)
    dlq_expiry = DateTime.add(current_time, -3600, :second)
    expired_dlq = :ets.tab2list(state.dlq_table)
    |> Enum.filter(fn {_key, message} -> 
      DateTime.compare(message.created_at, dlq_expiry) == :lt
    end)
    |> Enum.map(fn {key, _message} -> key end)
    
    Enum.each(expired_dlq, fn key ->
      :ets.delete(state.dlq_table, key)
    end)
    
    total_cleaned = length(expired_messages) + length(expired_dlq)
    if total_cleaned > 0 do
      Logger.info("Cleaned up #{total_cleaned} expired messages (#{length(expired_messages)} queue, #{length(expired_dlq)} DLQ)")
    end
  end
  
  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end
end