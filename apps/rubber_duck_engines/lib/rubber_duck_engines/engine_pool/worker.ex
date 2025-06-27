defmodule RubberDuckEngines.EnginePool.Worker do
  @moduledoc """
  Individual engine pool worker managing a pool of engine processes.

  Each worker manages a pool of engines of a specific type (e.g., code_analysis,
  documentation, testing) and handles checkout/checkin operations.
  """

  use GenServer

  alias RubberDuckEngines.{EngineSupervisor, EnginePool}

  defstruct [
    :pool_type,
    :engine_module,
    :pool_size,
    :max_overflow,
    :timeout,
    available: [],
    busy: %{},
    overflow_count: 0,
    stats: %{
      checkouts: 0,
      checkins: 0,
      timeouts: 0,
      errors: 0
    }
  ]

  # Client API

  @doc """
  Starts a pool worker for a specific engine type.
  """
  def start_link(opts) do
    pool_type = Keyword.fetch!(opts, :pool_type)
    config = Keyword.fetch!(opts, :config)

    GenServer.start_link(__MODULE__, {pool_type, config}, name: via_tuple(pool_type))
  end

  @doc """
  Checks out an engine from the pool.
  """
  def checkout_engine(pool_type, timeout \\ 5000) do
    GenServer.call(via_tuple(pool_type), :checkout_engine, timeout)
  end

  @doc """
  Returns an engine to the pool.
  """
  def checkin_engine(pool_type, engine_pid) do
    GenServer.cast(via_tuple(pool_type), {:checkin_engine, engine_pid})
  end

  @doc """
  Gets pool statistics.
  """
  def pool_stats(pool_type) do
    GenServer.call(via_tuple(pool_type), :pool_stats)
  end

  @doc """
  Updates pool configuration.
  """
  def update_config(pool_type, new_config) do
    GenServer.call(via_tuple(pool_type), {:update_config, new_config})
  end

  # Server implementation

  @impl true
  def init({pool_type, config}) do
    # Register this worker in the pool registry
    Registry.register(EnginePool.Registry, {:pool, pool_type}, %{
      pool_type: pool_type,
      pid: self()
    })

    Registry.register(EnginePool.Registry, {:pool_worker, self()}, %{
      type: pool_type,
      status: :initializing
    })

    state = %__MODULE__{
      pool_type: pool_type,
      engine_module: config.engine_module,
      pool_size: config.pool_size,
      max_overflow: config.max_overflow,
      timeout: config.timeout
    }

    # Initialize the pool with engines
    send(self(), :initialize_pool)
    emit_telemetry(:worker_started, %{pool_type: pool_type}, %{})

    {:ok, state}
  end

  @impl true
  def handle_call(:checkout_engine, {from_pid, _tag}, state) do
    case checkout_available_engine(state) do
      {:ok, engine_pid, new_state} ->
        # Monitor the checking out process
        Process.monitor(from_pid)

        new_state = %{
          new_state
          | busy: Map.put(new_state.busy, engine_pid, {from_pid, DateTime.utc_now()}),
            stats: update_in(new_state.stats, [:checkouts], &(&1 + 1))
        }

        emit_telemetry(
          :engine_checked_out,
          %{
            pool_type: state.pool_type,
            engine_pid: engine_pid,
            client_pid: from_pid
          },
          %{}
        )

        {:reply, {:ok, engine_pid}, new_state}

      {:error, :pool_empty} ->
        emit_telemetry(
          :checkout_failed,
          %{
            pool_type: state.pool_type,
            reason: :pool_empty
          },
          %{}
        )

        {:reply, {:error, :pool_empty}, state}

      {:error, reason} ->
        new_state = update_in(state.stats, [:errors], &(&1 + 1))

        emit_telemetry(
          :checkout_failed,
          %{
            pool_type: state.pool_type,
            reason: reason
          },
          %{}
        )

        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:pool_stats, _from, state) do
    stats = %{
      pool_type: state.pool_type,
      pool_size: state.pool_size,
      available_count: length(state.available),
      busy_count: map_size(state.busy),
      overflow_count: state.overflow_count,
      max_overflow: state.max_overflow,
      stats: state.stats,
      timestamp: DateTime.utc_now()
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    # Update configuration and resize pool if needed
    old_size = state.pool_size
    new_size = Map.get(new_config, :pool_size, old_size)

    updated_state = %{
      state
      | engine_module: Map.get(new_config, :engine_module, state.engine_module),
        pool_size: new_size,
        max_overflow: Map.get(new_config, :max_overflow, state.max_overflow),
        timeout: Map.get(new_config, :timeout, state.timeout)
    }

    # Resize pool if needed
    resized_state = resize_pool(updated_state, old_size, new_size)

    emit_telemetry(
      :config_updated,
      %{
        pool_type: state.pool_type,
        old_size: old_size,
        new_size: new_size
      },
      %{}
    )

    {:reply, :ok, resized_state}
  end

  @impl true
  def handle_cast({:checkin_engine, engine_pid}, state) do
    case Map.pop(state.busy, engine_pid) do
      {nil, _} ->
        # Engine not found in busy list, might be from overflow
        new_state = maybe_terminate_overflow_engine(state, engine_pid)
        {:noreply, new_state}

      {{_client_pid, _checkout_time}, remaining_busy} ->
        # Return engine to available pool
        new_state = %{
          state
          | available: [engine_pid | state.available],
            busy: remaining_busy,
            stats: update_in(state.stats, [:checkins], &(&1 + 1))
        }

        emit_telemetry(
          :engine_checked_in,
          %{
            pool_type: state.pool_type,
            engine_pid: engine_pid
          },
          %{}
        )

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:initialize_pool, state) do
    new_state = create_initial_engines(state)

    # Update registry status
    Registry.update_value(EnginePool.Registry, {:pool_worker, self()}, fn info ->
      Map.put(info, :status, :ready)
    end)

    emit_telemetry(
      :pool_initialized,
      %{
        pool_type: state.pool_type,
        engine_count: length(new_state.available)
      },
      %{}
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Handle engine or client process termination
    new_state = handle_process_down(state, pid)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private helper functions

  defp via_tuple(pool_type) do
    {:via, Registry, {EnginePool.Registry, {:pool, pool_type}}}
  end

  defp checkout_available_engine(state) do
    case state.available do
      [engine_pid | rest] ->
        if Process.alive?(engine_pid) do
          new_state = %{state | available: rest}
          {:ok, engine_pid, new_state}
        else
          # Engine is dead, remove it and try next
          new_available = List.delete(state.available, engine_pid)
          checkout_available_engine(%{state | available: new_available})
        end

      [] ->
        # No available engines, try to create overflow
        if state.overflow_count < state.max_overflow do
          case create_overflow_engine(state) do
            {:ok, engine_pid} ->
              new_state = %{state | overflow_count: state.overflow_count + 1}
              {:ok, engine_pid, new_state}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:error, :pool_empty}
        end
    end
  end

  defp create_initial_engines(state) do
    engines =
      1..state.pool_size
      |> Enum.map(fn _ -> create_engine(state.engine_module) end)
      |> Enum.filter(fn
        {:ok, _pid} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, pid} -> pid end)

    %{state | available: engines}
  end

  defp create_engine(engine_module) do
    config = %{pool_managed: true}
    EngineSupervisor.start_engine(engine_module, config)
  end

  defp create_overflow_engine(state) do
    create_engine(state.engine_module)
  end

  defp resize_pool(state, old_size, new_size) when new_size > old_size do
    # Add more engines
    additional_count = new_size - old_size

    new_engines =
      1..additional_count
      |> Enum.map(fn _ -> create_engine(state.engine_module) end)
      |> Enum.filter(fn
        {:ok, _pid} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, pid} -> pid end)

    %{state | available: state.available ++ new_engines}
  end

  defp resize_pool(state, old_size, new_size) when new_size < old_size do
    # Remove excess engines
    excess_count = old_size - new_size
    {to_remove, to_keep} = Enum.split(state.available, excess_count)

    # Terminate excess engines
    Enum.each(to_remove, &EngineSupervisor.stop_engine/1)

    %{state | available: to_keep}
  end

  defp resize_pool(state, _old_size, _new_size), do: state

  defp maybe_terminate_overflow_engine(state, engine_pid) do
    if state.overflow_count > 0 do
      EngineSupervisor.stop_engine(engine_pid)
      %{state | overflow_count: state.overflow_count - 1}
    else
      state
    end
  end

  defp handle_process_down(state, pid) do
    cond do
      # Check if it's an available engine
      pid in state.available ->
        new_available = List.delete(state.available, pid)
        # Replace with new engine if below pool size
        if length(new_available) < state.pool_size do
          case create_engine(state.engine_module) do
            {:ok, new_pid} ->
              %{state | available: [new_pid | new_available]}

            _ ->
              %{state | available: new_available}
          end
        else
          %{state | available: new_available}
        end

      # Check if it's a busy engine
      Map.has_key?(state.busy, pid) ->
        new_busy = Map.delete(state.busy, pid)
        # Create replacement engine
        case create_engine(state.engine_module) do
          {:ok, new_pid} ->
            %{state | busy: new_busy, available: [new_pid | state.available]}

          _ ->
            %{state | busy: new_busy}
        end

      # Must be a client process
      true ->
        # Find and return any engines checked out by this client
        {returned_engines, remaining_busy} =
          state.busy
          |> Enum.reduce({[], %{}}, fn {engine_pid, {client_pid, checkout_time}},
                                       {returned, remaining} ->
            if client_pid == pid do
              {[engine_pid | returned], remaining}
            else
              {returned, Map.put(remaining, engine_pid, {client_pid, checkout_time})}
            end
          end)

        %{state | available: returned_engines ++ state.available, busy: remaining_busy}
    end
  end

  defp emit_telemetry(event, metadata, measurements) do
    :telemetry.execute(
      [:rubber_duck_engines, :engine_pool, :worker, event],
      measurements,
      metadata
    )
  end
end
