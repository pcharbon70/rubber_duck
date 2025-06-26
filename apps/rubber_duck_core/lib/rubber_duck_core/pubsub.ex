defmodule RubberDuckCore.PubSub do
  @moduledoc """
  Inter-app communication hub for the RubberDuck system.
  
  This module provides publish/subscribe functionality for communication
  between different apps in the umbrella project.
  """

  use GenServer

  alias RubberDuckCore.Event

  @registry_name RubberDuckCore.Registry
  @pubsub_name __MODULE__

  # Client API

  @doc """
  Starts the PubSub server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: via_tuple(@pubsub_name))
  end

  @doc """
  Subscribes to a topic.
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic) when is_binary(topic) do
    GenServer.call(via_tuple(@pubsub_name), {:subscribe, topic, self()})
  end

  @doc """
  Unsubscribes from a topic.
  """
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic) when is_binary(topic) do
    GenServer.call(via_tuple(@pubsub_name), {:unsubscribe, topic, self()})
  end

  @doc """
  Publishes an event to a topic.
  """
  @spec publish(String.t(), Event.t()) :: :ok
  def publish(topic, %Event{} = event) when is_binary(topic) do
    GenServer.cast(via_tuple(@pubsub_name), {:publish, topic, event})
  end

  @doc """
  Publishes a simple message to a topic (creates an Event wrapper).
  """
  @spec broadcast(String.t(), atom(), map()) :: :ok
  def broadcast(topic, event_type, data) when is_binary(topic) do
    event = Event.system_event(event_type, data)
    publish(topic, event)
  end

  @doc """
  Lists all active topics.
  """
  @spec list_topics() :: [String.t()]
  def list_topics do
    GenServer.call(via_tuple(@pubsub_name), :list_topics)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      topics: %{},  # topic -> [pid]
      subscribers: %{}  # pid -> [topic]
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, topic, pid}, _from, state) do
    # Monitor the subscriber process
    Process.monitor(pid)
    
    # Add to topics
    topics = Map.update(state.topics, topic, [pid], fn pids -> 
      if pid in pids, do: pids, else: [pid | pids]
    end)
    
    # Add to subscribers
    subscribers = Map.update(state.subscribers, pid, [topic], fn topics_list ->
      if topic in topics_list, do: topics_list, else: [topic | topics_list]
    end)
    
    new_state = %{state | topics: topics, subscribers: subscribers}
    {:reply, :ok, new_state}
  end

  def handle_call({:unsubscribe, topic, pid}, _from, state) do
    # Remove from topics
    topics = case Map.get(state.topics, topic) do
      nil -> state.topics
      pids -> 
        new_pids = List.delete(pids, pid)
        if new_pids == [], do: Map.delete(state.topics, topic), else: Map.put(state.topics, topic, new_pids)
    end
    
    # Remove from subscribers
    subscribers = case Map.get(state.subscribers, pid) do
      nil -> state.subscribers
      topics_list ->
        new_topics = List.delete(topics_list, topic)
        if new_topics == [], do: Map.delete(state.subscribers, pid), else: Map.put(state.subscribers, pid, new_topics)
    end
    
    new_state = %{state | topics: topics, subscribers: subscribers}
    {:reply, :ok, new_state}
  end

  def handle_call(:list_topics, _from, state) do
    topics = Map.keys(state.topics)
    {:reply, topics, state}
  end

  @impl true
  def handle_cast({:publish, topic, event}, state) do
    case Map.get(state.topics, topic) do
      nil -> :ok
      pids -> 
        Enum.each(pids, fn pid ->
          send(pid, {:pubsub_event, topic, event})
        end)
    end
    
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up when a subscriber process dies
    case Map.get(state.subscribers, pid) do
      nil -> {:noreply, state}
      topics_list ->
        # Remove from all topics
        topics = Enum.reduce(topics_list, state.topics, fn topic, acc ->
          case Map.get(acc, topic) do
            nil -> acc
            pids ->
              new_pids = List.delete(pids, pid)
              if new_pids == [], do: Map.delete(acc, topic), else: Map.put(acc, topic, new_pids)
          end
        end)
        
        # Remove from subscribers
        subscribers = Map.delete(state.subscribers, pid)
        
        new_state = %{state | topics: topics, subscribers: subscribers}
        {:noreply, new_state}
    end
  end

  # Registry helpers
  defp via_tuple(name) do
    {:via, Registry, {@registry_name, name}}
  end
end