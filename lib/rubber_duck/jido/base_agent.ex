defmodule RubberDuck.Jido.BaseAgent do
  @moduledoc """
  Base behaviour and implementation for Jido agents.

  This module provides the foundation for all Jido agents in the RubberDuck
  system. It handles common functionality like signal reception, state management,
  and telemetry integration.

  ## Creating Custom Agents

  To create a custom agent, use this module and implement the required callbacks:

      defmodule MyAgent do
        use RubberDuck.Jido.BaseAgent

        @impl true
        def init(config) do
          # Initialize agent state
          {:ok, %{config: config, tasks: []}}
        end

        @impl true
        def handle_signal(signal, state) do
          # Process incoming signals
          case signal.type do
            "task.create" ->
              new_task = signal.data
              {:ok, %{state | tasks: [new_task | state.tasks]}}
            
            _ ->
              {:ok, state}
          end
        end
      end

  ## Callbacks

  - `init/1` - Initialize agent state
  - `handle_signal/2` - Process incoming signals
  - `handle_call/3` - Handle synchronous requests (optional)
  - `handle_cast/2` - Handle asynchronous messages (optional)
  - `handle_info/2` - Handle other messages (optional)
  - `terminate/2` - Cleanup on shutdown (optional)
  """

  @doc """
  Initializes the agent state.

  Called when the agent starts. Should return `{:ok, state}` or `{:error, reason}`.
  """
  @callback init(config :: map()) :: {:ok, term()} | {:error, term()}

  @doc """
  Handles incoming CloudEvents signals.

  Called when the agent receives a signal. Should return `{:ok, new_state}`.
  """
  @callback handle_signal(signal :: map(), state :: term()) :: {:ok, term()} | {:error, term()}

  # Optional callbacks
  @callback handle_call(request :: term(), from :: GenServer.from(), state :: term()) ::
              {:reply, term(), term()} | {:noreply, term()}
  @callback handle_cast(request :: term(), state :: term()) :: {:noreply, term()}
  @callback handle_info(info :: term(), state :: term()) :: {:noreply, term()}
  @callback terminate(reason :: term(), state :: term()) :: term()

  @optional_callbacks handle_call: 3, handle_cast: 2, handle_info: 2, terminate: 2

  defmacro __using__(_opts) do
    quote do
      use GenServer
      @behaviour RubberDuck.Jido.BaseAgent

      require Logger

      # Client API

      def start_link(config) do
        GenServer.start_link(__MODULE__, config)
      end

      # Server callbacks

      @impl GenServer
      def init(config) do
        # Set process metadata for logging
        Logger.metadata(
          agent_id: config[:id],
          agent_type: config[:type]
        )

        # Call the agent's init callback
        case __MODULE__.init(config) do
          {:ok, state} ->
            Logger.info("Agent #{config[:id]} initialized")
            
            # Emit telemetry
            :telemetry.execute(
              [:rubber_duck, :jido, :agent, :init],
              %{count: 1},
              %{agent_id: config[:id], agent_type: config[:type]}
            )
            
            {:ok, %{
              config: config,
              state: state,
              stats: %{
                signals_received: 0,
                signals_processed: 0,
                errors: 0
              }
            }}

          {:error, reason} = error ->
            Logger.error("Agent initialization failed: #{inspect(reason)}")
            {:stop, reason}
        end
      end

      @impl GenServer
      def handle_info({:signal, signal}, %{state: agent_state} = state) do
        # Update stats
        new_stats = Map.update!(state.stats, :signals_received, &(&1 + 1))
        
        # Process the signal
        case __MODULE__.handle_signal(signal, agent_state) do
          {:ok, new_agent_state} ->
            new_stats = Map.update!(new_stats, :signals_processed, &(&1 + 1))
            
            # Emit telemetry
            :telemetry.execute(
              [:rubber_duck, :jido, :signal, :receive],
              %{count: 1},
              %{
                agent_id: state.config[:id],
                signal_type: signal.type
              }
            )
            
            {:noreply, %{state | state: new_agent_state, stats: new_stats}}

          {:error, reason} ->
            Logger.error("Failed to process signal: #{inspect(reason)}")
            new_stats = Map.update!(new_stats, :errors, &(&1 + 1))
            {:noreply, %{state | stats: new_stats}}
        end
      end

      # Forward other callbacks if implemented
      @impl GenServer
      def handle_call(request, from, %{state: agent_state} = state) do
        if function_exported?(__MODULE__, :handle_call, 3) do
          case __MODULE__.handle_call(request, from, agent_state) do
            {:reply, reply, new_agent_state} ->
              {:reply, reply, %{state | state: new_agent_state}}
            
            {:noreply, new_agent_state} ->
              {:noreply, %{state | state: new_agent_state}}
          end
        else
          {:reply, {:error, :not_implemented}, state}
        end
      end

      @impl GenServer
      def handle_cast(request, %{state: agent_state} = state) do
        if function_exported?(__MODULE__, :handle_cast, 2) do
          case __MODULE__.handle_cast(request, agent_state) do
            {:noreply, new_agent_state} ->
              {:noreply, %{state | state: new_agent_state}}
          end
        else
          {:noreply, state}
        end
      end

      @impl GenServer
      def handle_info(info, %{state: agent_state} = state) when not is_tuple(info) or elem(info, 0) != :signal do
        if function_exported?(__MODULE__, :handle_info, 2) do
          case __MODULE__.handle_info(info, agent_state) do
            {:noreply, new_agent_state} ->
              {:noreply, %{state | state: new_agent_state}}
          end
        else
          Logger.warning("Unhandled message: #{inspect(info)}")
          {:noreply, state}
        end
      end

      @impl GenServer
      def terminate(reason, %{state: agent_state} = state) do
        if function_exported?(__MODULE__, :terminate, 2) do
          __MODULE__.terminate(reason, agent_state)
        end
        
        Logger.info("Agent #{state.config[:id]} terminating: #{inspect(reason)}")
        :ok
      end

      # Default implementations (can be overridden)

      @impl RubberDuck.Jido.BaseAgent
      def init(_config) do
        {:ok, %{}}
      end

      @impl RubberDuck.Jido.BaseAgent
      def handle_signal(_signal, state) do
        {:ok, state}
      end

      defoverridable init: 1, handle_signal: 2
    end
  end
end