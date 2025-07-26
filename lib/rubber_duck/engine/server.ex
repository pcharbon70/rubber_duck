defmodule RubberDuck.Engine.Server do
  @moduledoc """
  GenServer wrapper for engine instances.

  This module provides a GenServer-based wrapper around engine implementations,
  handling lifecycle management, health checks, and request processing.
  """

  use GenServer

  require Logger
  
  alias RubberDuck.Engine.{TaskRegistry, CancellationToken}

  defmodule State do
    @moduledoc false
    defstruct [
      :engine_config,
      :engine_state,
      :status,
      :started_at,
      :last_health_check,
      :request_count,
      :error_count,
      :health_check_interval,
      :active_tasks
    ]
  end

  # 30 seconds
  @default_health_check_interval 30_000

  # Client API

  @doc """
  Starts an engine server with the given configuration.
  """
  def start_link(args) when is_tuple(args) do
    # Handle old tuple format for backward compatibility
    {engine_config, opts} = args
    start_link(engine_config, opts)
  end

  def start_link(engine_config, opts \\ []) do
    name = Keyword.get(opts, :name, via_tuple(engine_config.name))
    GenServer.start_link(__MODULE__, {engine_config, opts}, name: name)
  end

  @doc """
  Executes a request on the engine.
  """
  def execute(server, input, timeout \\ 5000) do
    GenServer.call(server, {:execute, input}, timeout)
  end

  @doc """
  Gets the current status of the engine.
  """
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Performs a health check on the engine.
  """
  def health_check(server) do
    GenServer.call(server, :health_check)
  end

  @doc """
  Stops the engine server.
  """
  def stop(server, reason \\ :normal) do
    GenServer.stop(server, reason)
  end

  # Server Callbacks

  @impl true
  def init({engine_config, opts}) do
    health_check_interval =
      Keyword.get(
        opts,
        :health_check_interval,
        @default_health_check_interval
      )

    state = %State{
      engine_config: engine_config,
      status: :initializing,
      started_at: DateTime.utc_now(),
      request_count: 0,
      error_count: 0,
      health_check_interval: health_check_interval,
      active_tasks: %{}
    }

    # Initialize the engine
    case engine_config.module.init(engine_config.config) do
      {:ok, engine_state} ->
        # Schedule first health check
        if health_check_interval > 0 do
          Process.send_after(self(), :scheduled_health_check, health_check_interval)
        end

        Logger.info("Started engine #{engine_config.name}")

        {:ok, %{state | engine_state: engine_state, status: :ready}}

      {:error, reason} ->
        Logger.error("Failed to initialize engine #{engine_config.name}: #{inspect(reason)}")
        {:stop, {:initialization_failed, reason}}
    end
  end

  @impl true
  def handle_call({:execute, input}, from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Extract conversation_id and cancellation token
    conversation_id = input[:conversation_id] || Map.get(input, "conversation_id")
    cancellation_token = CancellationToken.from_input(input)

    # Execute with timeout
    task =
      Task.async(fn ->
        # Add periodic cancellation checks if token provided
        if cancellation_token do
          # Check if already cancelled before starting
          if CancellationToken.cancelled?(cancellation_token) do
            {:error, :cancelled}
          else
            state.engine_config.module.execute(input, state.engine_state)
          end
        else
          state.engine_config.module.execute(input, state.engine_state)
        end
      end)

    # Register task in TaskRegistry if conversation_id is present
    task_id = if conversation_id do
      case TaskRegistry.register_task(task, conversation_id, state.engine_config.name, %{
        from: from,
        started_at: DateTime.utc_now(),
        input_size: map_size(input)
      }) do
        {:ok, id} -> id
        _ -> nil
      end
    else
      nil
    end
    
    # Track task locally
    new_active_tasks = if task_id do
      Map.put(state.active_tasks, task_id, {task, from})
    else
      state.active_tasks
    end

    result =
      case Task.yield(task, state.engine_config.timeout) || Task.shutdown(task) do
        {:ok, {:ok, result}} ->
          duration = System.monotonic_time(:microsecond) - start_time
          emit_telemetry(:execute, duration, state, %{status: :success})
          {:ok, result}

        {:ok, {:error, :cancelled}} ->
          duration = System.monotonic_time(:microsecond) - start_time
          emit_telemetry(:execute, duration, state, %{status: :cancelled})
          
          # Broadcast cancellation status if we have a conversation_id
          if conversation_id do
            RubberDuck.Status.engine(
              conversation_id,
              "Processing cancelled for #{state.engine_config.name}",
              %{
                engine: state.engine_config.name,
                duration_ms: div(duration, 1000),
                cancelled_at: DateTime.utc_now()
              }
            )
          end
          
          {:error, :cancelled}

        {:ok, {:error, reason}} ->
          duration = System.monotonic_time(:microsecond) - start_time
          emit_telemetry(:execute, duration, state, %{status: :error, error: reason})
          {:error, reason}

        {:exit, :cancelled} ->
          duration = System.monotonic_time(:microsecond) - start_time
          emit_telemetry(:execute, duration, state, %{status: :cancelled})
          {:error, :cancelled}

        {:exit, reason} ->
          duration = System.monotonic_time(:microsecond) - start_time
          emit_telemetry(:execute, duration, state, %{status: :crash, error: reason})
          {:error, {:crash, reason}}

        nil ->
          duration = System.monotonic_time(:microsecond) - start_time
          emit_telemetry(:execute, duration, state, %{status: :timeout})
          {:error, :timeout}
      end

    # Unregister task from TaskRegistry
    if task_id do
      TaskRegistry.unregister_task(task_id)
    end
    
    # Remove from local tracking
    final_active_tasks = if task_id do
      Map.delete(new_active_tasks, task_id)
    else
      new_active_tasks
    end

    new_state =
      case result do
        {:ok, _} ->
          %{state | request_count: state.request_count + 1, active_tasks: final_active_tasks}

        {:error, :cancelled} ->
          %{state | request_count: state.request_count + 1, active_tasks: final_active_tasks}

        {:error, _} ->
          %{state | request_count: state.request_count + 1, error_count: state.error_count + 1, active_tasks: final_active_tasks}
      end

    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      engine: state.engine_config.name,
      status: state.status,
      started_at: state.started_at,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at),
      request_count: state.request_count,
      error_count: state.error_count,
      last_health_check: state.last_health_check
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    {result, new_state} = perform_health_check(state)
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:cancel_task, task_id}, _from, state) do
    case Map.get(state.active_tasks, task_id) do
      {task, _from} ->
        # Cancel the task
        Task.shutdown(task, :brutal_kill)
        
        # Update TaskRegistry
        TaskRegistry.unregister_task(task_id)
        
        # Remove from local tracking
        new_state = %{state | active_tasks: Map.delete(state.active_tasks, task_id)}
        
        # Get conversation_id from TaskRegistry before it's removed
        conversation_id = case TaskRegistry.find_task(task_id) do
          {:ok, task_info} -> task_info.conversation_id
          _ -> nil
        end
        
        # Broadcast cancellation if we have a conversation_id
        if conversation_id do
          RubberDuck.Status.engine(
            conversation_id,
            "Task cancelled in #{state.engine_config.name}",
            %{
              engine: state.engine_config.name,
              task_id: task_id,
              cancelled_at: DateTime.utc_now()
            }
          )
        end
        
        Logger.info("Cancelled task #{task_id} in engine #{state.engine_config.name}")
        {:reply, :ok, new_state}
        
      nil ->
        {:reply, {:error, :task_not_found}, state}
    end
  end
  
  @impl true
  def handle_call(:get_active_tasks, _from, state) do
    tasks = Map.keys(state.active_tasks)
    {:reply, {:ok, tasks}, state}
  end

  @impl true
  def handle_info(:scheduled_health_check, state) do
    {_result, new_state} = perform_health_check(state)

    # Schedule next health check
    if state.health_check_interval > 0 do
      Process.send_after(self(), :scheduled_health_check, state.health_check_interval)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Engine #{state.engine_config.name} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Engine #{state.engine_config.name} terminating: #{inspect(reason)}")
    emit_telemetry(:terminate, 0, state, %{reason: reason})
    :ok
  end

  # Private Functions

  defp via_tuple(name) do
    {:via, Registry, {RubberDuck.Engine.Registry, name}}
  end

  defp perform_health_check(state) do
    # Simple health check - could be extended to call engine-specific health check
    health_status =
      case state.status do
        :ready -> :healthy
        :error -> :unhealthy
        _ -> :unknown
      end

    new_state = %{state | last_health_check: DateTime.utc_now()}
    emit_telemetry(:health_check, 0, new_state, %{status: health_status})

    {health_status, new_state}
  end

  defp emit_telemetry(event, duration, state, metadata) do
    :telemetry.execute(
      [:rubber_duck, :engine, event],
      %{duration: duration},
      Map.merge(metadata, %{
        engine: state.engine_config.name,
        module: state.engine_config.module
      })
    )
  end
end
