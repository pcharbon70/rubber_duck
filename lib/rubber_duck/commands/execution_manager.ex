defmodule RubberDuck.Commands.ExecutionManager do
  @moduledoc """
  Orchestrator for command lifecycle management with distributed execution capabilities.
  
  Coordinates command execution across the distributed cluster by managing:
  - Command handler spawning and monitoring through CommandSupervisor
  - Circuit breaker integration for fault tolerance
  - Performance monitoring and telemetry collection
  - Command cancellation and timeout handling
  - Execution context management and state tracking
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Commands.{CommandSupervisor, CommandHandler, CommandRegistry}
  alias RubberDuck.LoadBalancing.CircuitBreaker
  alias RubberDuck.Commands.CommandTelemetry
  
  defstruct [
    :config,
    :circuit_breakers,
    :active_executions,
    :execution_stats,
    :start_time,
    :telemetry_ref
  ]
  
  @type execution_context :: %{
    user_id: String.t(),
    session_id: String.t(),
    request_id: String.t(),
    priority: :low | :normal | :high | :critical,
    timeout: non_neg_integer(),
    metadata: map()
  }
  
  @type execution_options :: %{
    placement_strategy: atom() | tuple(),
    circuit_breaker: boolean(),
    telemetry: boolean(),
    async: boolean(),
    timeout: non_neg_integer()
  }
  
  @default_timeout 30_000
  @circuit_breaker_threshold 5
  @circuit_breaker_timeout 60_000
  @telemetry_interval 5_000
  
  # Client API
  
  @doc """
  Starts the execution manager.
  """
  def start_link(opts \\ []) do
    config = Keyword.get(opts, :config, %{})
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end
  
  @doc """
  Executes a command with the given parameters and context.
  
  ## Options
  - `:placement_strategy` - How to place the command (see CommandSupervisor)
  - `:circuit_breaker` - Enable circuit breaker protection (default: true)
  - `:telemetry` - Enable telemetry tracking (default: true)
  - `:async` - Execute asynchronously (default: false)
  - `:timeout` - Execution timeout in milliseconds
  """
  def execute_command(command_module, parameters, context, opts \\ %{}) do
    GenServer.call(__MODULE__, {:execute_command, command_module, parameters, context, opts}, :infinity)
  end
  
  @doc """
  Executes a command asynchronously and returns execution tracking information.
  """
  def execute_command_async(command_module, parameters, context, opts \\ %{}) do
    opts = Map.put(opts, :async, true)
    GenServer.call(__MODULE__, {:execute_command, command_module, parameters, context, opts})
  end
  
  @doc """
  Cancels a running command execution.
  """
  def cancel_execution(execution_id) do
    GenServer.call(__MODULE__, {:cancel_execution, execution_id})
  end
  
  @doc """
  Gets the status of a command execution.
  """
  def get_execution_status(execution_id) do
    GenServer.call(__MODULE__, {:get_execution_status, execution_id})
  end
  
  @doc """
  Lists all active executions.
  """
  def list_active_executions do
    GenServer.call(__MODULE__, :list_active_executions)
  end
  
  @doc """
  Gets execution statistics and performance metrics.
  """
  def get_execution_stats do
    GenServer.call(__MODULE__, :get_execution_stats)
  end
  
  @doc """
  Gets circuit breaker status for a command type.
  """
  def get_circuit_breaker_status(command_module) do
    GenServer.call(__MODULE__, {:get_circuit_breaker_status, command_module})
  end
  
  @doc """
  Resets circuit breaker for a command type.
  """
  def reset_circuit_breaker(command_module) do
    GenServer.call(__MODULE__, {:reset_circuit_breaker, command_module})
  end
  
  @doc """
  Performs health check on the execution manager.
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end
  
  # Server Implementation
  
  @impl true
  def init(config) do
    # Initialize telemetry
    telemetry_ref = if Map.get(config, :telemetry_enabled, true) do
      schedule_telemetry_collection()
    else
      nil
    end
    
    state = %__MODULE__{
      config: config,
      circuit_breakers: %{},
      active_executions: %{},
      execution_stats: initialize_stats(),
      start_time: System.monotonic_time(:millisecond),
      telemetry_ref: telemetry_ref
    }
    
    Logger.info("Command Execution Manager started")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:execute_command, command_module, parameters, context, opts}, from, state) do
    execution_id = generate_execution_id()
    
    # Check circuit breaker
    case check_circuit_breaker(command_module, state) do
      :open ->
        {:reply, {:error, :circuit_breaker_open}, state}
        
      _ ->
        # Prepare execution configuration
        config = prepare_execution_config(command_module, parameters, context, execution_id, opts)
        
        # Start telemetry tracking if enabled
        telemetry_enabled = Map.get(opts, :telemetry, true)
        if telemetry_enabled do
          CommandTelemetry.track_execution_start(execution_id, command_module, context)
        end
        
        # Execute command
        case start_command_execution(config, opts, state) do
          {:ok, handler_pid} ->
            # Track execution
            execution_info = %{
              id: execution_id,
              command_module: command_module,
              handler_pid: handler_pid,
              context: context,
              start_time: System.monotonic_time(:millisecond),
              status: :running,
              from: from,
              telemetry_enabled: telemetry_enabled,
              async: Map.get(opts, :async, false)
            }
            
            new_state = %{state | 
              active_executions: Map.put(state.active_executions, execution_id, execution_info)
            }
            
            if Map.get(opts, :async, false) do
              {:reply, {:ok, execution_id}, new_state}
            else
              {:noreply, new_state}
            end
            
          {:error, reason} ->
            # Track failure
            if telemetry_enabled do
              CommandTelemetry.track_execution_error(execution_id, command_module, reason, context)
            end
            
            # Update circuit breaker
            new_state = update_circuit_breaker(command_module, :error, state)
            
            {:reply, {:error, reason}, new_state}
        end
    end
  end
  
  @impl true
  def handle_call({:cancel_execution, execution_id}, _from, state) do
    case Map.get(state.active_executions, execution_id) do
      nil ->
        {:reply, {:error, :execution_not_found}, state}
        
      execution_info ->
        case CommandHandler.cancel(execution_info.handler_pid) do
          {:ok, :cancelled} ->
            # Track cancellation
            if execution_info.telemetry_enabled do
              CommandTelemetry.track_execution_cancelled(execution_id, execution_info.command_module, execution_info.context)
            end
            
            # Update execution status
            updated_execution = %{execution_info | status: :cancelled}
            new_state = %{state | 
              active_executions: Map.put(state.active_executions, execution_id, updated_execution)
            }
            
            {:reply, {:ok, :cancelled}, new_state}
            
          error ->
            {:reply, error, state}
        end
    end
  end
  
  @impl true
  def handle_call({:get_execution_status, execution_id}, _from, state) do
    case Map.get(state.active_executions, execution_id) do
      nil ->
        {:reply, {:error, :execution_not_found}, state}
        
      execution_info ->
        # Get current status from handler
        handler_state = CommandHandler.get_state(execution_info.handler_pid)
        
        status_info = %{
          execution_id: execution_id,
          command_module: execution_info.command_module,
          status: handler_state.status,
          start_time: execution_info.start_time,
          duration: System.monotonic_time(:millisecond) - execution_info.start_time,
          context: execution_info.context
        }
        
        {:reply, {:ok, status_info}, state}
    end
  end
  
  @impl true
  def handle_call(:list_active_executions, _from, state) do
    executions = Enum.map(state.active_executions, fn {id, info} ->
      %{
        execution_id: id,
        command_module: info.command_module,
        status: info.status,
        start_time: info.start_time,
        duration: System.monotonic_time(:millisecond) - info.start_time
      }
    end)
    
    {:reply, executions, state}
  end
  
  @impl true
  def handle_call(:get_execution_stats, _from, state) do
    current_time = System.monotonic_time(:millisecond)
    uptime = current_time - state.start_time
    
    stats = %{
      uptime_ms: uptime,
      active_executions: map_size(state.active_executions),
      total_executions: state.execution_stats.total_executions,
      successful_executions: state.execution_stats.successful_executions,
      failed_executions: state.execution_stats.failed_executions,
      cancelled_executions: state.execution_stats.cancelled_executions,
      average_execution_time: state.execution_stats.average_execution_time,
      circuit_breakers: get_circuit_breaker_summary(state),
      executions_per_minute: calculate_executions_per_minute(state.execution_stats, uptime)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:get_circuit_breaker_status, command_module}, _from, state) do
    status = case Map.get(state.circuit_breakers, command_module) do
      nil -> :closed
      breaker -> CircuitBreaker.get_status(breaker)
    end
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_call({:reset_circuit_breaker, command_module}, _from, state) do
    case Map.get(state.circuit_breakers, command_module) do
      nil ->
        {:reply, {:error, :circuit_breaker_not_found}, state}
        
      breaker ->
        CircuitBreaker.reset(breaker)
        {:reply, :ok, state}
    end
  end
  
  @impl true
  def handle_call(:health_check, _from, state) do
    health = %{
      status: :healthy,
      active_executions: map_size(state.active_executions),
      circuit_breakers: map_size(state.circuit_breakers),
      uptime_ms: System.monotonic_time(:millisecond) - state.start_time
    }
    
    {:reply, {:ok, health}, state}
  end
  
  @impl true
  def handle_info({:execution_completed, execution_id, result}, state) do
    case Map.get(state.active_executions, execution_id) do
      nil ->
        {:noreply, state}
        
      execution_info ->
        # Calculate execution time
        execution_time = System.monotonic_time(:millisecond) - execution_info.start_time
        
        # Track completion
        if execution_info.telemetry_enabled do
          case result do
            {:ok, _} ->
              CommandTelemetry.track_execution_success(execution_id, execution_info.command_module, execution_time, execution_info.context)
            {:error, reason} ->
              CommandTelemetry.track_execution_error(execution_id, execution_info.command_module, reason, execution_info.context)
          end
        end
        
        # Update circuit breaker
        breaker_result = case result do
          {:ok, _} -> :success
          {:error, _} -> :error
        end
        new_state = update_circuit_breaker(execution_info.command_module, breaker_result, state)
        
        # Update execution stats
        updated_stats = update_execution_stats(new_state.execution_stats, breaker_result, execution_time)
        
        # Reply to caller if synchronous
        if not execution_info.async do
          GenServer.reply(execution_info.from, result)
        end
        
        # Remove from active executions
        final_state = %{new_state | 
          active_executions: Map.delete(new_state.active_executions, execution_id),
          execution_stats: updated_stats
        }
        
        {:noreply, final_state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find execution by handler PID
    case find_execution_by_pid(pid, state.active_executions) do
      nil ->
        {:noreply, state}
        
      {execution_id, execution_info} ->
        Logger.warning("Command handler process died: #{inspect(reason)}")
        
        # Track failure
        if execution_info.telemetry_enabled do
          CommandTelemetry.track_execution_error(execution_id, execution_info.command_module, {:process_died, reason}, execution_info.context)
        end
        
        # Update circuit breaker
        new_state = update_circuit_breaker(execution_info.command_module, :error, state)
        
        # Reply to caller if synchronous
        if not execution_info.async do
          GenServer.reply(execution_info.from, {:error, {:process_died, reason}})
        end
        
        # Remove from active executions
        final_state = %{new_state | 
          active_executions: Map.delete(new_state.active_executions, execution_id)
        }
        
        {:noreply, final_state}
    end
  end
  
  @impl true
  def handle_info(:collect_telemetry, state) do
    # Collect and report execution manager telemetry
    if state.telemetry_ref do
      CommandTelemetry.track_manager_stats(state.execution_stats, map_size(state.active_executions))
      schedule_telemetry_collection()
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  # Private Functions
  
  defp generate_execution_id do
    "exec_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
  
  defp prepare_execution_config(command_module, parameters, context, execution_id, _opts) do
    %{
      command_module: command_module,
      command_id: execution_id,
      context: context,
      parameters: parameters,
      timeout: Map.get(context, :timeout, @default_timeout)
    }
  end
  
  defp start_command_execution(config, opts, _state) do
    placement_strategy = Map.get(opts, :placement_strategy, :automatic)
    CommandSupervisor.start_command(config, placement_strategy: placement_strategy)
  end
  
  defp check_circuit_breaker(command_module, state) do
    case Map.get(state.circuit_breakers, command_module) do
      nil -> :closed
      breaker -> CircuitBreaker.check(breaker)
    end
  end
  
  defp update_circuit_breaker(command_module, result, state) do
    breaker = Map.get(state.circuit_breakers, command_module) || create_circuit_breaker(command_module)
    
    case result do
      :success -> CircuitBreaker.record_success(breaker)
      :error -> CircuitBreaker.record_failure(breaker)
    end
    
    %{state | circuit_breakers: Map.put(state.circuit_breakers, command_module, breaker)}
  end
  
  defp create_circuit_breaker(command_module) do
    config = %{
      failure_threshold: @circuit_breaker_threshold,
      timeout: @circuit_breaker_timeout,
      name: "command_#{command_module}"
    }
    
    {:ok, breaker} = CircuitBreaker.start_link(config)
    breaker
  end
  
  defp initialize_stats do
    %{
      total_executions: 0,
      successful_executions: 0,
      failed_executions: 0,
      cancelled_executions: 0,
      total_execution_time: 0,
      average_execution_time: 0.0
    }
  end
  
  defp update_execution_stats(stats, result, execution_time) do
    new_total = stats.total_executions + 1
    new_total_time = stats.total_execution_time + execution_time
    new_average = new_total_time / new_total
    
    case result do
      :success ->
        %{stats |
          total_executions: new_total,
          successful_executions: stats.successful_executions + 1,
          total_execution_time: new_total_time,
          average_execution_time: new_average
        }
        
      :error ->
        %{stats |
          total_executions: new_total,
          failed_executions: stats.failed_executions + 1,
          total_execution_time: new_total_time,
          average_execution_time: new_average
        }
        
      :cancelled ->
        %{stats |
          total_executions: new_total,
          cancelled_executions: stats.cancelled_executions + 1,
          total_execution_time: new_total_time,
          average_execution_time: new_average
        }
    end
  end
  
  defp find_execution_by_pid(pid, active_executions) do
    Enum.find(active_executions, fn {_id, execution_info} ->
      execution_info.handler_pid == pid
    end)
  end
  
  defp get_circuit_breaker_summary(state) do
    Enum.into(state.circuit_breakers, %{}, fn {command_module, breaker} ->
      {command_module, CircuitBreaker.get_status(breaker)}
    end)
  end
  
  defp calculate_executions_per_minute(stats, uptime_ms) do
    if uptime_ms > 0 do
      (stats.total_executions * 60_000) / uptime_ms
    else
      0.0
    end
  end
  
  defp schedule_telemetry_collection do
    Process.send_after(self(), :collect_telemetry, @telemetry_interval)
  end
end