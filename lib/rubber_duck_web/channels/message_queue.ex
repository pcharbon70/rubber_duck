defmodule RubberDuckWeb.MessageQueue do
  @moduledoc """
  Provides message queuing for offline users to ensure reliable message delivery.

  Messages are stored temporarily and delivered when users reconnect.
  """

  use GenServer

  require Logger

  @table_name :channel_message_queue
  @max_queue_size 1000
  @message_ttl :timer.hours(24)
  @cleanup_interval :timer.minutes(30)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Queue a message for a user who is currently offline.
  """
  def queue_message(user_id, channel, event, payload) do
    GenServer.cast(__MODULE__, {:queue_message, user_id, channel, event, payload})
  end

  @doc """
  Retrieve and remove all queued messages for a user.
  """
  def get_queued_messages(user_id) do
    GenServer.call(__MODULE__, {:get_messages, user_id})
  end

  @doc """
  Clear all messages for a specific user.
  """
  def clear_user_queue(user_id) do
    GenServer.cast(__MODULE__, {:clear_queue, user_id})
  end

  @doc """
  Get queue statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for message storage
    :ets.new(@table_name, [
      :named_table,
      :bag,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok,
     %{
       message_count: 0,
       users_with_queues: MapSet.new()
     }}
  end

  @impl true
  def handle_cast({:queue_message, user_id, channel, event, payload}, state) do
    message = %{
      id: generate_message_id(),
      channel: channel,
      event: event,
      payload: payload,
      queued_at: DateTime.utc_now(),
      expires_at: DateTime.add(DateTime.utc_now(), @message_ttl, :millisecond)
    }

    # Check queue size for user
    current_count = :ets.select_count(@table_name, [{{user_id, :_}, [], [true]}])

    if current_count < @max_queue_size do
      :ets.insert(@table_name, {user_id, message})

      new_state = %{
        state
        | message_count: state.message_count + 1,
          users_with_queues: MapSet.put(state.users_with_queues, user_id)
      }

      Logger.debug("Queued message for user #{user_id}: #{event}")
      {:noreply, new_state}
    else
      Logger.warning("Message queue full for user #{user_id}, dropping message")
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:clear_queue, user_id}, state) do
    count = :ets.select_delete(@table_name, [{{user_id, :_}, [], [true]}])

    new_state = %{
      state
      | message_count: max(0, state.message_count - count),
        users_with_queues: MapSet.delete(state.users_with_queues, user_id)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_messages, user_id}, _from, state) do
    messages =
      :ets.lookup(@table_name, user_id)
      |> Enum.map(fn {_user_id, message} -> message end)
      |> Enum.sort_by(& &1.queued_at, DateTime)
      |> Enum.filter(fn msg ->
        DateTime.compare(msg.expires_at, DateTime.utc_now()) == :gt
      end)

    # Delete retrieved messages
    :ets.delete(@table_name, user_id)

    new_state = %{
      state
      | message_count: max(0, state.message_count - length(messages)),
        users_with_queues: MapSet.delete(state.users_with_queues, user_id)
    }

    {:reply, messages, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_messages: state.message_count,
      users_with_queues: MapSet.size(state.users_with_queues),
      table_memory: :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove expired messages
    now = DateTime.utc_now()
    now_unix = DateTime.to_unix(now, :microsecond)

    # Get all messages and filter them manually since ETS select_delete has limitations 
    # with complex data types like DateTime structs in match specifications
    all_messages = :ets.tab2list(@table_name)

    expired_keys =
      for {key, message} <- all_messages,
          message.expires_at && DateTime.to_unix(message.expires_at, :microsecond) < now_unix do
        key
      end

    expired_count = length(expired_keys)

    # Delete expired messages
    for key <- expired_keys do
      :ets.delete(@table_name, key)
    end

    if expired_count > 0 do
      Logger.info("Cleaned up #{expired_count} expired messages from queue")
    end

    # Recalculate state
    all_users =
      :ets.select(@table_name, [{{:"$1", :_}, [], [:"$1"]}])
      |> Enum.uniq()
      |> MapSet.new()

    message_count = :ets.info(@table_name, :size)

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, %{state | message_count: message_count, users_with_queues: all_users}}
  end

  # Private functions

  defp generate_message_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
