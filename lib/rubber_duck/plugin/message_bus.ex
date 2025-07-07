defmodule RubberDuck.Plugin.MessageBus do
  @moduledoc """
  Provides inter-plugin communication capabilities.

  The MessageBus allows plugins to communicate with each other
  in a decoupled way through a publish/subscribe mechanism.
  """

  use GenServer
  require Logger

  @type topic :: atom() | String.t()
  @type message :: any()
  @type subscriber :: {pid(), tag :: any()}

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribes to messages on a specific topic.

  The subscriber will receive messages as `{:plugin_message, topic, message, metadata}`.
  """
  def subscribe(topic, tag \\ nil) do
    GenServer.call(__MODULE__, {:subscribe, topic, self(), tag})
  end

  @doc """
  Unsubscribes from a topic.
  """
  def unsubscribe(topic) do
    GenServer.call(__MODULE__, {:unsubscribe, topic, self()})
  end

  @doc """
  Publishes a message to a topic.

  All subscribers to the topic will receive the message.
  """
  def publish(topic, message, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:publish, topic, message, metadata})
  end

  @doc """
  Sends a request to a specific plugin and waits for a response.

  This provides request/response semantics on top of pub/sub.
  """
  def request(plugin_name, request, timeout \\ 5_000) do
    ref = make_ref()
    topic = {:request, plugin_name}
    reply_topic = {:reply, plugin_name, self(), ref}

    # Subscribe to reply
    :ok = subscribe(reply_topic, ref)

    # Send request
    publish(topic, request, %{reply_to: reply_topic, from: self()})

    # Wait for response
    receive do
      {:plugin_message, ^reply_topic, response, _metadata} ->
        unsubscribe(reply_topic)
        {:ok, response}
    after
      timeout ->
        unsubscribe(reply_topic)
        {:error, :timeout}
    end
  end

  @doc """
  Registers a plugin to handle requests.

  The handler function will be called with each request and should
  return the response to send back.
  """
  def handle_requests(plugin_name, handler) when is_function(handler, 2) do
    GenServer.call(__MODULE__, {:register_handler, plugin_name, handler})
  end

  @doc """
  Lists all active topics and their subscriber counts.
  """
  def list_topics do
    GenServer.call(__MODULE__, :list_topics)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Track subscribers by topic
    state = %{
      topics: %{},
      handlers: %{},
      monitors: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, topic, pid, tag}, _from, state) do
    # Monitor subscriber to clean up on exit
    ref = Process.monitor(pid)

    new_topics =
      Map.update(state.topics, topic, [{pid, tag}], fn subs ->
        [{pid, tag} | subs]
      end)

    new_monitors = Map.put(state.monitors, ref, {pid, topic})

    Logger.debug("Plugin subscribed to topic #{inspect(topic)}")

    {:reply, :ok, %{state | topics: new_topics, monitors: new_monitors}}
  end

  @impl true
  def handle_call({:unsubscribe, topic, pid}, _from, state) do
    new_topics =
      Map.update(state.topics, topic, [], fn subs ->
        Enum.reject(subs, fn {sub_pid, _} -> sub_pid == pid end)
      end)

    # Remove empty topics
    new_topics = if new_topics[topic] == [], do: Map.delete(new_topics, topic), else: new_topics

    {:reply, :ok, %{state | topics: new_topics}}
  end

  @impl true
  def handle_call({:register_handler, plugin_name, handler}, _from, state) do
    # Subscribe to request topic
    request_topic = {:request, plugin_name}

    new_handlers = Map.put(state.handlers, plugin_name, handler)

    # Set up handler process
    spawn_link(fn ->
      subscribe(request_topic)
      handle_request_loop(plugin_name, handler)
    end)

    {:reply, :ok, %{state | handlers: new_handlers}}
  end

  @impl true
  def handle_call(:list_topics, _from, state) do
    topics =
      Enum.map(state.topics, fn {topic, subs} ->
        {topic, length(subs)}
      end)

    {:reply, topics, state}
  end

  @impl true
  def handle_cast({:publish, topic, message, metadata}, state) do
    case Map.get(state.topics, topic, []) do
      [] ->
        Logger.debug("No subscribers for topic #{inspect(topic)}")

      subscribers ->
        metadata = Map.put(metadata, :timestamp, System.system_time())

        Enum.each(subscribers, fn {pid, _tag} ->
          send(pid, {:plugin_message, topic, message, metadata})
        end)

        Logger.debug("Published message to #{length(subscribers)} subscribers on topic #{inspect(topic)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.get(state.monitors, ref) do
      {^pid, topic} ->
        # Remove subscriber from topic
        new_topics =
          Map.update(state.topics, topic, [], fn subs ->
            Enum.reject(subs, fn {sub_pid, _} -> sub_pid == pid end)
          end)

        # Remove empty topics
        new_topics = if new_topics[topic] == [], do: Map.delete(new_topics, topic), else: new_topics

        new_monitors = Map.delete(state.monitors, ref)

        {:noreply, %{state | topics: new_topics, monitors: new_monitors}}

      nil ->
        {:noreply, state}
    end
  end

  # Private Functions

  defp handle_request_loop(plugin_name, handler) do
    receive do
      {:plugin_message, _topic, request, metadata} ->
        case metadata do
          %{reply_to: reply_topic, from: _from} ->
            # Handle request and send response
            try do
              response = handler.(request, metadata)
              publish(reply_topic, response, %{from: plugin_name})
            rescue
              e ->
                Logger.error("Plugin #{plugin_name} handler error: #{inspect(e)}")
                publish(reply_topic, {:error, :handler_error}, %{from: plugin_name})
            end

          _ ->
            Logger.warning("Plugin #{plugin_name} received request without reply_to")
        end

        handle_request_loop(plugin_name, handler)
    end
  end
end
