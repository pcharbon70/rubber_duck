defmodule RubberDuckCore.BaseServer do
  @moduledoc """
  Base GenServer pattern for RubberDuck system components.

  This module provides common patterns and utilities that can be used
  by other GenServer implementations throughout the umbrella project.
  """

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      use GenServer
      require Logger

      @timeout Keyword.get(opts, :timeout, 5_000)
      @registry_name Keyword.get(opts, :registry, RubberDuckCore.Registry)

      def start_link(args \\ []) do
        name = Keyword.get(args, :name, __MODULE__)
        GenServer.start_link(__MODULE__, args, name: via_tuple(name))
      end

      def child_spec(args) do
        name = Keyword.get(args, :name, __MODULE__)

        %{
          id: name,
          start: {__MODULE__, :start_link, [args]},
          restart: :permanent,
          shutdown: 5_000,
          type: :worker
        }
      end

      # Registry helpers
      defp via_tuple(name) do
        {:via, Registry, {@registry_name, name}}
      end

      defp lookup(name) do
        Registry.lookup(@registry_name, name)
      end

      # Common GenServer callbacks with defaults
      def init(args) do
        state = initial_state(args)
        {:ok, state}
      end

      def handle_call({:get_state}, _from, state) do
        {:reply, state, state}
      end

      def handle_call({:ping}, _from, state) do
        {:reply, :pong, state}
      end

      def handle_call(msg, from, state) do
        Logger.warning("Unhandled call #{inspect(msg)} from #{inspect(from)}")
        {:reply, {:error, :unhandled_call}, state}
      end

      def handle_cast({:update_state, new_state}, _state) do
        {:noreply, new_state}
      end

      def handle_cast(msg, state) do
        Logger.warning("Unhandled cast #{inspect(msg)}")
        {:noreply, state}
      end

      def handle_info(msg, state) do
        Logger.debug("Unhandled info #{inspect(msg)}")
        {:noreply, state}
      end

      def terminate(reason, state) do
        Logger.info("#{__MODULE__} terminating: #{inspect(reason)}")
        cleanup(state)
        :ok
      end

      # Overridable functions
      def initial_state(_args), do: %{}
      def cleanup(_state), do: :ok

      defoverridable initial_state: 1, cleanup: 1
      defoverridable handle_call: 3, handle_cast: 2, handle_info: 2
    end
  end
end
