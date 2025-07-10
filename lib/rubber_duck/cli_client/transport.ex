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
    url = Keyword.fetch!(opts, :url)
    params = Keyword.get(opts, :params, %{})
    
    {:connect, url, params, %{parent: self()}}
  end

  @impl true
  def handle_connected(transport, state) do
    Logger.info("WebSocket connected")
    GenServer.cast(state.parent, {:connected, transport})
    {:ok, state}
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