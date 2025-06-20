defmodule RubberDuck.Commands.CommandHandler do
  @moduledoc """
  GenServer for individual command execution with distributed state management.
  
  Each CommandHandler manages the lifecycle of a single command execution,
  including:
  - Parameter validation
  - Command execution (sync/async)
  - State tracking and persistence
  - Cancellation and timeout handling
  - State handoff for node migration
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Commands.CommandBehaviour
  
  defstruct [
    :command_id,
    :command_module,
    :context,
    :parameters,
    :metadata,
    :status,
    :created_at,
    :start_time,
    :end_time,
    :cancelled_at,
    :result,
    :error,
    :execution_task,
    :execution_state,
    :timeout,
    :timeout_ref
  ]
  
  @type status :: :ready | :validating | :executing | :completed | :failed | :cancelled | :timeout
  
  @type t :: %__MODULE__{
    command_id: String.t(),
    command_module: module(),
    context: map(),
    parameters: map() | nil,
    metadata: map(),
    status: status(),
    created_at: DateTime.t(),
    start_time: DateTime.t() | nil,
    end_time: DateTime.t() | nil,
    cancelled_at: DateTime.t() | nil,
    result: :success | :error | nil,
    error: any() | nil,
    execution_task: Task.t() | nil,
    execution_state: map(),
    timeout: non_neg_integer(),
    timeout_ref: reference() | nil
  }
  
  @default_timeout 30_000  # 30 seconds
  
  # Client API
  
  @doc """
  Starts a CommandHandler process.
  
  ## Options
  - `:command_module` (required) - Module implementing CommandBehaviour
  - `:command_id` (required) - Unique identifier for this command instance
  - `:context` (required) - Execution context (user_id, session_id, etc.)
  - `:parameters` - Pre-validated command parameters
  - `:metadata` - Additional metadata for the command
  - `:execution_state` - State for resuming execution (for handoff)
  - `:timeout` - Execution timeout in milliseconds (default: 30000)
  """
  def start_link(config) do
    case validate_config(config) do
      :ok ->
        GenServer.start_link(__MODULE__, config)
      {:error, reason} ->
        {:error, {:invalid_config, reason}}
    end
  end
  
  @doc """
  Executes the command synchronously.
  """
  def execute(handler, params) do
    GenServer.call(handler, {:execute, params}, :infinity)
  end
  
  @doc """
  Executes the command asynchronously.
  """
  def execute_async(handler, params) do
    GenServer.call(handler, {:execute_async, params})
  end
  
  @doc """
  Checks the status of an async command execution.
  """
  def check_status(handler) do
    GenServer.call(handler, :check_status)
  end
  
  @doc """
  Cancels a running command.
  """
  def cancel(handler) do
    GenServer.call(handler, :cancel)
  end
  
  @doc """
  Gets the current state of the handler.
  """
  def get_state(handler) do
    GenServer.call(handler, :get_state)
  end
  
  @doc """
  Gets state for handoff to another node.
  """
  def handoff_state(handler) do
    GenServer.call(handler, :handoff_state)
  end
  
  # Server Implementation
  
  @impl true
  def init(config) do
    state = %__MODULE__{
      command_id: config.command_id,
      command_module: config.command_module,
      context: config.context,
      parameters: config[:parameters],
      metadata: config[:metadata] || %{},
      status: :ready,
      created_at: DateTime.utc_now(),
      execution_state: config[:execution_state] || %{},
      timeout: config[:timeout] || @default_timeout
    }
    
    Logger.debug("CommandHandler started for #{state.command_module} with id #{state.command_id}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:execute, params}, _from, state) do
    case state.status do
      :ready ->
        state = %{state | parameters: params, status: :validating}
        
        case validate_parameters(state) do
          :ok ->
            state = %{state | status: :executing, start_time: DateTime.utc_now()}
            
            # Execute synchronously in a monitored task to allow state checking
            parent = self()
            task_ref = make_ref()
            
            spawn_monitor(fn ->
              result = execute_command(state)
              send(parent, {:sync_result, task_ref, result})
            end)
            
            # Wait for result
            receive do
              {:sync_result, ^task_ref, result} ->
                {reply, new_state} = handle_execution_result(result, state)
                {:reply, reply, new_state}
                
              {:DOWN, _ref, :process, _pid, reason} ->
                state = %{state |
                  status: :failed,
                  end_time: DateTime.utc_now(),
                  result: :error,
                  error: {:execution_crashed, reason}
                }
                {:reply, {:error, {:execution_failed, reason}}, state}
            after
              state.timeout ->
                state = %{state |
                  status: :failed,
                  end_time: DateTime.utc_now(),
                  result: :error,
                  error: :timeout
                }
                {:reply, {:error, :timeout}, state}
            end
            
          {:error, errors} ->
            state = %{state | 
              status: :failed, 
              end_time: DateTime.utc_now(),
              error: {:validation_failed, errors}
            }
            {:reply, {:error, {:validation_failed, errors}}, state}
        end
        
      _ ->
        {:reply, {:error, :command_already_executed}, state}
    end
  end
  
  @impl true
  def handle_call({:execute_async, params}, _from, state) do
    case state.status do
      :ready ->
        state = %{state | parameters: params, status: :validating}
        
        case validate_parameters(state) do
          :ok ->
            state = %{state | status: :executing, start_time: DateTime.utc_now()}
            
            # Execute asynchronously
            task = Task.async(fn -> execute_command(state) end)
            
            # Set execution timeout
            timeout_ref = Process.send_after(self(), :execution_timeout, state.timeout)
            
            state = %{state | execution_task: task, timeout_ref: timeout_ref}
            {:reply, {:ok, :executing}, state}
            
          {:error, errors} ->
            state = %{state | 
              status: :failed, 
              end_time: DateTime.utc_now(),
              error: {:validation_failed, errors}
            }
            {:reply, {:error, {:validation_failed, errors}}, state}
        end
        
      _ ->
        {:reply, {:error, :command_already_executed}, state}
    end
  end
  
  @impl true
  def handle_call(:check_status, _from, state) do
    {:reply, {:ok, state.status}, state}
  end
  
  @impl true
  def handle_call(:cancel, _from, state) do
    case state.status do
      :executing ->
        # Cancel the execution task if it exists
        if state.execution_task do
          Task.shutdown(state.execution_task, :brutal_kill)
        end
        
        # Cancel timeout
        if state.timeout_ref do
          Process.cancel_timer(state.timeout_ref)
        end
        
        state = %{state | 
          status: :cancelled,
          cancelled_at: DateTime.utc_now(),
          end_time: DateTime.utc_now(),
          execution_task: nil,
          timeout_ref: nil
        }
        
        {:reply, {:ok, :cancelled}, state}
        
      status when status in [:completed, :failed, :cancelled] ->
        {:reply, {:error, :not_cancellable}, state}
        
      _ ->
        state = %{state | status: :cancelled, cancelled_at: DateTime.utc_now()}
        {:reply, {:ok, :cancelled}, state}
    end
  end
  
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
  
  @impl true
  def handle_call(:handoff_state, _from, state) do
    handoff_data = %{
      command_module: state.command_module,
      command_id: state.command_id,
      context: state.context,
      parameters: state.parameters,
      metadata: state.metadata,
      execution_state: state.execution_state,
      timeout: state.timeout
    }
    
    {:reply, {:ok, handoff_data}, state}
  end
  
  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completion
    if state.execution_task && state.execution_task.ref == ref do
      # Cancel timeout
      if state.timeout_ref do
        Process.cancel_timer(state.timeout_ref)
      end
      
      {_, new_state} = handle_execution_result(result, state)
      new_state = %{new_state | execution_task: nil, timeout_ref: nil}
      
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Task crashed
    if state.execution_task && state.execution_task.ref == ref do
      state = %{state | 
        status: :failed,
        end_time: DateTime.utc_now(),
        result: :error,
        error: {:execution_crashed, reason},
        execution_task: nil,
        timeout_ref: nil
      }
      
      {:noreply, state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:execution_timeout, state) do
    if state.status == :executing do
      # Kill the execution task
      if state.execution_task do
        Task.shutdown(state.execution_task, :brutal_kill)
      end
      
      state = %{state |
        status: :failed,
        end_time: DateTime.utc_now(),
        result: :error,
        error: :timeout,
        execution_task: nil,
        timeout_ref: nil
      }
      
      Logger.warning("Command #{state.command_id} timed out after #{state.timeout}ms")
      
      {:noreply, state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  # Private Functions
  
  defp validate_config(config) do
    cond do
      not Map.has_key?(config, :command_module) ->
        {:error, "command_module is required"}
        
      not Map.has_key?(config, :command_id) ->
        {:error, "command_id is required"}
        
      not Map.has_key?(config, :context) ->
        {:error, "context is required"}
        
      true ->
        :ok
    end
  end
  
  defp validate_parameters(state) do
    CommandBehaviour.validate_implementation!(state.command_module)
    state.command_module.validate(state.parameters || %{})
  end
  
  defp execute_command(state) do
    try do
      result = state.command_module.execute(state.parameters || %{}, state.context)
      
      case result do
        {:ok, value} -> {:ok, value}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_result, other}}
      end
    catch
      kind, reason ->
        Logger.error("Command execution failed: #{inspect({kind, reason})}")
        {:error, {:execution_failed, {kind, reason, __STACKTRACE__}}}
    end
  end
  
  defp handle_execution_result(result, state) do
    case result do
      {:ok, value} ->
        state = %{state |
          status: :completed,
          end_time: DateTime.utc_now(),
          result: :success,
          error: nil
        }
        {{:ok, value}, state}
        
      {:error, reason} ->
        state = %{state |
          status: :failed,
          end_time: DateTime.utc_now(),
          result: :error,
          error: reason
        }
        {{:error, reason}, state}
    end
  end
end