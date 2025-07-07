defmodule RubberDuck.Engine.Pool.Worker do
  @moduledoc """
  Poolboy worker that wraps Engine.Server instances.

  This module implements the poolboy worker behavior and delegates
  to Engine.Server for actual engine functionality.
  """

  use GenServer

  alias RubberDuck.Engine.Server

  # Client API

  def start_link(engine_config) do
    GenServer.start_link(__MODULE__, engine_config)
  end

  # Delegate engine operations to Engine.Server functions

  def execute(worker, input, timeout \\ 5_000) do
    GenServer.call(worker, {:execute, input}, timeout)
  end

  def status(worker) do
    GenServer.call(worker, :status)
  end

  def health_check(worker) do
    GenServer.call(worker, :health_check)
  end

  # Server callbacks

  @impl true
  def init(engine_config) do
    # Initialize the actual engine server state
    case Server.init({engine_config, []}) do
      {:ok, state} ->
        {:ok, state}

      {:stop, reason} ->
        {:stop, reason}
    end
  end

  # Delegate all calls to Engine.Server handlers

  @impl true
  def handle_call(request, from, state) do
    Server.handle_call(request, from, state)
  end

  @impl true
  def handle_info(msg, state) do
    Server.handle_info(msg, state)
  end

  @impl true
  def terminate(reason, state) do
    Server.terminate(reason, state)
  end
end
