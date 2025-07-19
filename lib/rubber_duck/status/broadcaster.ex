defmodule RubberDuck.Status.Broadcaster do
  @moduledoc """
  Non-blocking message queue for status updates.
  Provides fire-and-forget broadcasting without impacting main processing.
  
  Messages are queued and broadcast in batches to Phoenix.PubSub topics
  based on conversation ID and category. The system is designed to handle
  high throughput with minimal performance impact.
  """
  use GenServer
  require Logger

  # Default configuration values
  @default_queue_limit 10_000
  @default_batch_size 100
  @default_flush_interval 50

  # Client API

  @doc """
  Start the status broadcaster.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Queue a status update for broadcasting. Fire-and-forget operation.
  
  ## Parameters
    - conversation_id: The conversation identifier (can be nil for system-wide)
    - category: Atom representing the category (:engine, :tool, :workflow, :progress, :error, :info)
    - text: The status message text
    - metadata: Optional map of additional metadata
  
  ## Examples
      
      Broadcaster.broadcast("conv-123", :engine, "Processing with GPT-4", %{model: "gpt-4"})
      Broadcaster.broadcast(nil, :info, "System startup complete", %{})
  """
  def broadcast(conversation_id, category, text, metadata \\ %{}) do
    message = %{
      conversation_id: conversation_id,
      category: category,
      text: text,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }
    
    GenServer.cast(__MODULE__, {:queue_message, message})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Get configuration with defaults
    queue_limit = opts[:queue_limit] || config(:queue_limit, @default_queue_limit)
    batch_size = opts[:batch_size] || config(:batch_size, @default_batch_size)
    flush_interval = opts[:flush_interval] || config(:flush_interval, @default_flush_interval)
    
    # Start periodic flush timer
    Process.send_after(self(), :flush_queue, flush_interval)
    
    state = %{
      queue: :queue.new(),
      queue_size: 0,
      queue_limit: queue_limit,
      batch_size: batch_size,
      flush_interval: flush_interval,
      task_supervisor: RubberDuck.TaskSupervisor
    }
    
    {:ok, state}
  end

  @impl true
  def handle_cast({:queue_message, message}, state) do
    if state.queue_size >= state.queue_limit do
      Logger.warning("Status broadcast queue full, dropping message",
        conversation_id: message.conversation_id,
        category: message.category,
        queue_size: state.queue_size
      )
      
      # Emit telemetry for dropped message
      :telemetry.execute(
        [:rubber_duck, :status, :broadcaster, :message_dropped],
        %{count: 1},
        %{
          conversation_id: message.conversation_id,
          category: message.category
        }
      )
      
      {:noreply, state}
    else
      new_queue = :queue.in(message, state.queue)
      new_state = %{state | queue: new_queue, queue_size: state.queue_size + 1}
      
      # Emit telemetry for queue depth
      :telemetry.execute(
        [:rubber_duck, :status, :broadcaster, :queue_depth],
        %{size: new_state.queue_size},
        %{}
      )
      
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:flush_queue, state) do
    # Process messages in batches
    case process_batch(state.queue, state.batch_size, []) do
      {[], remaining_queue} ->
        # No messages to process
        Process.send_after(self(), :flush_queue, state.flush_interval)
        {:noreply, %{state | queue: remaining_queue, queue_size: 0}}
      
      {messages, remaining_queue} ->
        # Spawn task to broadcast messages
        Task.Supervisor.start_child(state.task_supervisor, fn ->
          broadcast_messages(messages)
        end)
        
        # Emit telemetry for batch processing
        :telemetry.execute(
          [:rubber_duck, :status, :broadcaster, :batch_processed],
          %{
            batch_size: length(messages),
            remaining: :queue.len(remaining_queue)
          },
          %{}
        )
        
        remaining_size = :queue.len(remaining_queue)
        Process.send_after(self(), :flush_queue, state.flush_interval)
        {:noreply, %{state | queue: remaining_queue, queue_size: remaining_size}}
    end
  end

  # Handle task completion/failure
  @impl true
  def handle_info({ref, _result}, state) when is_reference(ref) do
    # Task completed successfully
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when is_reference(ref) do
    # Task failed - messages are ephemeral so we just log
    Logger.debug("Status broadcast task failed", reason: inspect(reason))
    
    :telemetry.execute(
      [:rubber_duck, :status, :broadcaster, :task_failed],
      %{count: 1},
      %{reason: inspect(reason)}
    )
    
    {:noreply, state}
  end

  # Catch-all for unexpected messages
  @impl true
  def handle_info(msg, state) do
    Logger.debug("Broadcaster received unexpected message", message: inspect(msg))
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # On shutdown, try to broadcast remaining messages
    if state.queue_size > 0 do
      Logger.info("Broadcasting remaining messages on shutdown", count: state.queue_size)
      
      messages = :queue.to_list(state.queue)
      broadcast_messages(messages)
    end
    
    :ok
  end

  # Private functions

  defp process_batch(queue, 0, acc), do: {Enum.reverse(acc), queue}
  defp process_batch(queue, count, acc) do
    case :queue.out(queue) do
      {{:value, message}, new_queue} ->
        process_batch(new_queue, count - 1, [message | acc])
      {:empty, queue} ->
        {Enum.reverse(acc), queue}
    end
  end

  defp broadcast_messages(messages) do
    start_time = System.monotonic_time()
    
    # Group messages by conversation and category for efficient broadcasting
    messages
    |> Enum.group_by(fn msg -> 
      {msg.conversation_id, msg.category} 
    end)
    |> Enum.each(fn {{conversation_id, category}, msgs} ->
      topic = build_topic(conversation_id, category)
      
      # Broadcast each message to the appropriate topic
      Enum.each(msgs, fn msg ->
        Phoenix.PubSub.broadcast(
          RubberDuck.PubSub,
          topic,
          {:status_update, msg.category, msg.text, msg.metadata}
        )
      end)
    end)
    
    # Emit telemetry for broadcast latency
    duration = System.monotonic_time() - start_time
    :telemetry.execute(
      [:rubber_duck, :status, :broadcaster, :broadcast_completed],
      %{
        duration: System.convert_time_unit(duration, :native, :microsecond),
        message_count: length(messages)
      },
      %{}
    )
  end

  defp build_topic(nil, category), do: "status:system:#{category}"
  defp build_topic(conversation_id, category), do: "status:#{conversation_id}:#{category}"


  defp config(key, default) do
    Application.get_env(:rubber_duck, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end