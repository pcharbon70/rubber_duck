defmodule RubberDuck.CLIClient.Client.Transport do
  @moduledoc """
  Transport implementation for Phoenix.Channels.GenSocketClient.
  """

  @behaviour Phoenix.Channels.GenSocketClient

  require Logger

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {Phoenix.Channels.GenSocketClient, :start_link, [__MODULE__, opts]},
      type: :worker,
      restart: :temporary
    }
  end

  @impl true
  def init(opts) do
    Logger.debug("Transport init called with opts: #{inspect(opts)}")
    
    url = Keyword.fetch!(opts, :url)
    params = Keyword.get(opts, :params, %{})
    
    # Convert params map to keyword list for Phoenix.Socket
    socket_params = 
      params
      |> Map.to_list()
      |> Keyword.new()
    
    {:connect, url, socket_params, %{parent: self()}}
  end

  @impl true
  def handle_connected(transport, state) do
    Logger.info("WebSocket connected")
    
    # Automatically join the CLI channel once connected
    case Phoenix.Channels.GenSocketClient.join(transport, "cli:commands", %{}) do
      {:ok, _ref} ->
        Logger.info("Joining cli:commands channel")
        {:ok, Map.put(state, :transport, transport)}
        
      {:error, reason} ->
        Logger.error("Failed to join channel: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_disconnected(reason, state) do
    Logger.warning("WebSocket disconnected: #{inspect(reason)}")
    Process.send(state.parent, {:disconnected, reason}, [])
    {:stop, :disconnected, state}
  end

  @impl true
  def handle_joined(topic, _payload, _transport, state) do
    Logger.info("Joined channel: #{topic}")
    {:ok, state}
  end

  @impl true
  def handle_join_error(topic, payload, _transport, state) do
    Logger.error("Failed to join #{topic}: #{inspect(payload)}")
    {:ok, state}
  end

  @impl true
  def handle_channel_closed(topic, _payload, _transport, state) do
    Logger.warning("Channel closed: #{topic}")
    {:ok, state}
  end

  @impl true
  def handle_message(topic, event, payload, _transport, state) do
    Process.send(state.parent, {:channel_event, topic, event, payload}, [])
    {:ok, state}
  end

  @impl true
  def handle_reply(topic, ref, payload, _transport, state) do
    Process.send(state.parent, {:channel_reply, topic, %{ref: ref, payload: payload}}, [])
    {:ok, state}
  end

  @impl true
  def handle_info({:push, topic, event, payload, ref, from}, transport, state) do
    # Forward push requests to the channel
    case Phoenix.Channels.GenSocketClient.push(transport, topic, event, payload) do
      {:ok, push_ref} ->
        # Store the mapping between our ref and the push ref
        state = Map.put(state, {:pending, push_ref}, {ref, from})
        {:ok, state}
        
      {:error, reason} ->
        send(from, {:push_error, ref, reason})
        {:ok, state}
    end
  end
  
  def handle_info(message, _transport, state) do
    Logger.debug("Unhandled transport message: #{inspect(message)}")
    {:ok, state}
  end

  @impl true
  def handle_call(message, _from, _transport, state) do
    Logger.warning("Unhandled call: #{inspect(message)}")
    {:reply, {:error, :not_implemented}, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end