defmodule RubberDuck.Tool.ExternalRouter do
  @moduledoc """
  Routes external tool execution requests through the internal tool system.
  
  Provides:
  - Request routing with authentication/authorization
  - Parameter transformation and validation
  - Progress streaming for long-running operations
  - Result transformation to external formats
  """
  
  use GenServer
  
  alias RubberDuck.Tool.{ExternalAdapter, Registry, Authorizer}
  alias Phoenix.PubSub
  
  require Logger
  
  @execution_timeout 300_000  # 5 minutes default
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Routes an external tool call through the system.
  
  Returns {:ok, request_id} for tracking the execution.
  """
  def route_call(tool_name, params, context, opts \\ []) do
    request_id = generate_request_id()
    
    GenServer.cast(__MODULE__, {
      :route_call,
      request_id,
      tool_name,
      params,
      context,
      opts
    })
    
    {:ok, request_id}
  end
  
  @doc """
  Routes a synchronous tool call, waiting for the result.
  """
  def route_call_sync(tool_name, params, context, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @execution_timeout)
    
    GenServer.call(__MODULE__, {
      :route_call_sync,
      tool_name,
      params,
      context,
      opts
    }, timeout)
  end
  
  @doc """
  Gets the status of an ongoing execution.
  """
  def get_status(request_id) do
    GenServer.call(__MODULE__, {:get_status, request_id})
  end
  
  @doc """
  Cancels an ongoing execution.
  """
  def cancel(request_id) do
    GenServer.call(__MODULE__, {:cancel, request_id})
  end
  
  @doc """
  Subscribes to execution progress updates for a request.
  """
  def subscribe_to_progress(request_id) do
    PubSub.subscribe(RubberDuck.PubSub, "tool_execution:#{request_id}")
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    state = %{
      executions: %{},
      default_timeout: Keyword.get(opts, :default_timeout, @execution_timeout),
      max_concurrent: Keyword.get(opts, :max_concurrent, 100)
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:route_call, request_id, tool_name, params, context, opts}, state) do
    # Check concurrent execution limit
    if map_size(state.executions) >= state.max_concurrent do
      broadcast_error(request_id, :too_many_requests)
      {:noreply, state}
    else
      # Start async execution
      task = Task.async(fn ->
        execute_tool_call(request_id, tool_name, params, context, opts)
      end)
      
      execution = %{
        request_id: request_id,
        tool_name: tool_name,
        task: task,
        started_at: DateTime.utc_now(),
        status: :running,
        context: context
      }
      
      new_executions = Map.put(state.executions, request_id, execution)
      {:noreply, %{state | executions: new_executions}}
    end
  end
  
  @impl true
  def handle_call({:route_call_sync, tool_name, params, context, opts}, from, state) do
    request_id = generate_request_id()
    
    # Check concurrent execution limit
    if map_size(state.executions) >= state.max_concurrent do
      {:reply, {:error, :too_many_requests}, state}
    else
      # Start execution with reply tracking
      task = Task.async(fn ->
        result = execute_tool_call(request_id, tool_name, params, context, opts)
        GenServer.reply(from, result)
        result
      end)
      
      execution = %{
        request_id: request_id,
        tool_name: tool_name,
        task: task,
        started_at: DateTime.utc_now(),
        status: :running,
        context: context,
        sync: true,
        from: from
      }
      
      new_executions = Map.put(state.executions, request_id, execution)
      
      # Don't reply yet - the task will handle it
      {:noreply, %{state | executions: new_executions}}
    end
  end
  
  @impl true
  def handle_call({:get_status, request_id}, _from, state) do
    case Map.get(state.executions, request_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      execution ->
        status = %{
          request_id: request_id,
          tool_name: execution.tool_name,
          status: execution.status,
          started_at: execution.started_at,
          completed_at: execution[:completed_at],
          error: execution[:error]
        }
        
        {:reply, {:ok, status}, state}
    end
  end
  
  @impl true
  def handle_call({:cancel, request_id}, _from, state) do
    case Map.get(state.executions, request_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      execution ->
        # Cancel the task
        Task.shutdown(execution.task, :brutal_kill)
        
        # Update execution status
        updated_execution = execution
        |> Map.put(:status, :cancelled)
        |> Map.put(:completed_at, DateTime.utc_now())
        
        new_executions = Map.put(state.executions, request_id, updated_execution)
        
        # Broadcast cancellation
        broadcast_event(request_id, :cancelled, %{})
        
        {:reply, :ok, %{state | executions: new_executions}}
    end
  end
  
  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Find execution by task ref
    {request_id, execution} = Enum.find(state.executions, fn {_id, exec} ->
      exec.task.ref == ref
    end) || {nil, nil}
    
    if execution do
      # Update execution with result
      updated_execution = execution
      |> Map.put(:status, :completed)
      |> Map.put(:completed_at, DateTime.utc_now())
      |> Map.put(:result, result)
      
      new_executions = Map.put(state.executions, request_id, updated_execution)
      
      # Clean up completed executions after a delay
      Process.send_after(self(), {:cleanup, request_id}, 60_000)
      
      {:noreply, %{state | executions: new_executions}}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Find execution by task ref
    {request_id, execution} = Enum.find(state.executions, fn {_id, exec} ->
      exec.task.ref == ref
    end) || {nil, nil}
    
    if execution do
      # Update execution with error
      updated_execution = execution
      |> Map.put(:status, :failed)
      |> Map.put(:completed_at, DateTime.utc_now())
      |> Map.put(:error, reason)
      
      new_executions = Map.put(state.executions, request_id, updated_execution)
      
      # Broadcast error
      broadcast_error(request_id, reason)
      
      # Clean up after a delay
      Process.send_after(self(), {:cleanup, request_id}, 60_000)
      
      {:noreply, %{state | executions: new_executions}}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:cleanup, request_id}, state) do
    new_executions = Map.delete(state.executions, request_id)
    {:noreply, %{state | executions: new_executions}}
  end
  
  # Private functions
  
  defp execute_tool_call(request_id, tool_name, external_params, context, opts) do
    # Broadcast execution start
    broadcast_event(request_id, :started, %{tool_name: tool_name})
    
    try do
      # Get tool module
      with {:ok, tool_module} <- Registry.get(tool_name),
           # Check authorization
           :ok <- check_authorization(tool_module, context),
           # Broadcast authorization success
           _ <- broadcast_event(request_id, :authorized, %{}),
           # Map parameters
           {:ok, params} <- ExternalAdapter.map_parameters(tool_module, external_params),
           # Broadcast parameter mapping success
           _ <- broadcast_event(request_id, :parameters_mapped, %{params: params}),
           # Execute through adapter
           {:ok, result} <- execute_with_progress(request_id, tool_module, params, context, opts) do
        
        # Broadcast completion
        broadcast_event(request_id, :completed, %{result: result})
        
        {:ok, result}
      else
        {:error, :tool_not_found} ->
          error = %{type: :tool_not_found, message: "Tool '#{tool_name}' not found"}
          broadcast_error(request_id, error)
          {:error, error}
        
        {:error, :unauthorized} ->
          error = %{type: :unauthorized, message: "Not authorized to use tool '#{tool_name}'"}
          broadcast_error(request_id, error)
          {:error, error}
        
        {:error, reason} ->
          broadcast_error(request_id, reason)
          {:error, reason}
      end
    rescue
      exception ->
        error = %{
          type: :execution_error,
          message: Exception.message(exception),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        }
        broadcast_error(request_id, error)
        {:error, error}
    end
  end
  
  defp check_authorization(tool_module, context) do
    case Authorizer.authorize(context.user, tool_module, context) do
      :ok -> :ok
      {:error, _reason} -> {:error, :unauthorized}
    end
  end
  
  defp execute_with_progress(request_id, tool_module, params, context, opts) do
    # Create a progress callback
    progress_callback = fn progress_data ->
      broadcast_event(request_id, :progress, progress_data)
    end
    
    # Add progress callback to context
    enhanced_context = Map.put(context, :progress_callback, progress_callback)
    
    # Execute through adapter
    ExternalAdapter.execute(
      Tool.metadata(tool_module).name,
      params,
      enhanced_context,
      opts
    )
  end
  
  defp generate_request_id do
    "req_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end
  
  defp broadcast_event(request_id, event, data) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "tool_execution:#{request_id}",
      {:tool_execution_event, %{
        request_id: request_id,
        event: event,
        data: data,
        timestamp: DateTime.utc_now()
      }}
    )
  end
  
  defp broadcast_error(request_id, error) do
    broadcast_event(request_id, :error, %{error: error})
  end
end