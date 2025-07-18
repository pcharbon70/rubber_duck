defmodule RubberDuck.MCP.WorkflowAdapter.StreamingHandler do
  @moduledoc """
  Real-time streaming handler for MCP-enhanced workflows.
  
  Provides streaming capabilities for workflow execution with real-time
  progress updates, intermediate results, and event notifications.
  Integrates with Phoenix PubSub for efficient event distribution.
  """
  
  alias RubberDuck.Tool.Composition
  alias Phoenix.PubSub
  
  require Logger
  
  @type stream_event :: %{
    type: String.t(),
    workflow_id: String.t(),
    step_name: String.t() | nil,
    timestamp: DateTime.t(),
    data: map() | nil,
    metadata: map() | nil
  }
  
  @doc """
  Creates a streaming workflow execution.
  
  Returns a stream that emits events throughout the workflow lifecycle.
  Events include step progress, intermediate results, and completion status.
  """
  @spec create_workflow_stream(Reactor.t(), map(), map()) :: {:ok, Stream.t()} | {:error, term()}
  def create_workflow_stream(workflow, context, options \\ %{}) do
    _workflow_id = generate_workflow_id()
    stream_id = generate_stream_id()
    
    # Set up PubSub subscription for workflow events
    topic = "workflow_stream:#{stream_id}"
    
    try do
      # Subscribe to workflow events
      PubSub.subscribe(RubberDuck.PubSub, topic)
      
      # Create the event stream
      stream = Stream.resource(
        fn -> start_workflow_execution(workflow, context, options, stream_id) end,
        fn state -> handle_stream_events(state, topic) end,
        fn state -> cleanup_stream_execution(state, topic) end
      )
      
      {:ok, stream}
    rescue
      error ->
        Logger.error("Failed to create workflow stream: #{inspect(error)}")
        {:error, error}
    end
  end
  
  @doc """
  Executes a workflow with streaming enabled.
  
  Similar to standard execution but with real-time progress events
  published to PubSub for streaming consumers.
  """
  @spec execute_with_streaming(Reactor.t(), map(), map()) :: {:ok, term()} | {:error, term()}
  def execute_with_streaming(workflow, context, options \\ %{}) do
    workflow_id = generate_workflow_id()
    stream_id = generate_stream_id()
    
    # Enhance context with streaming information
    streaming_context = Map.merge(context, %{
      streaming_enabled: true,
      workflow_id: workflow_id,
      stream_id: stream_id
    })
    
    # Set up progress monitoring
    setup_progress_monitoring(workflow_id, stream_id, options)
    
    try do
      # Execute workflow with streaming middleware
      case execute_workflow_with_monitoring(workflow, streaming_context, options) do
        {:ok, result} ->
          # Emit completion event
          emit_workflow_event(stream_id, "workflow_completed", %{
            workflow_id: workflow_id,
            result: result,
            execution_time: DateTime.utc_now()
          })
          
          {:ok, result}
          
        {:error, reason} ->
          # Emit failure event
          emit_workflow_event(stream_id, "workflow_failed", %{
            workflow_id: workflow_id,
            error: reason,
            execution_time: DateTime.utc_now()
          })
          
          {:error, reason}
      end
    after
      # Clean up monitoring
      cleanup_progress_monitoring(workflow_id, stream_id)
    end
  end
  
  @doc """
  Publishes a workflow event to the streaming system.
  
  Events are published to PubSub and can be consumed by streaming clients.
  """
  @spec publish_workflow_event(String.t(), String.t(), map()) :: :ok
  def publish_workflow_event(stream_id, event_type, event_data) do
    emit_workflow_event(stream_id, event_type, event_data)
  end
  
  @doc """
  Creates a progress reporter for individual workflow steps.
  
  Returns a function that can be called to report step progress,
  which will be automatically streamed to connected clients.
  """
  @spec create_step_progress_reporter(String.t(), String.t()) :: function()
  def create_step_progress_reporter(stream_id, step_name) do
    fn progress_data ->
      emit_workflow_event(stream_id, "step_progress", %{
        step_name: step_name,
        progress: progress_data,
        timestamp: DateTime.utc_now()
      })
    end
  end
  
  @doc """
  Handles streaming of intermediate results during workflow execution.
  
  Formats and publishes intermediate results from workflow steps
  as they become available.
  """
  @spec stream_intermediate_result(String.t(), String.t(), term()) :: :ok
  def stream_intermediate_result(stream_id, step_name, result) do
    formatted_result = format_intermediate_result(result)
    
    emit_workflow_event(stream_id, "intermediate_result", %{
      step_name: step_name,
      result: formatted_result,
      timestamp: DateTime.utc_now()
    })
  end
  
  @doc """
  Handles streaming of step completion events.
  
  Publishes events when individual workflow steps complete,
  including execution time and result information.
  """
  @spec stream_step_completion(String.t(), String.t(), term(), integer()) :: :ok
  def stream_step_completion(stream_id, step_name, result, execution_time_ms) do
    emit_workflow_event(stream_id, "step_completed", %{
      step_name: step_name,
      result: format_step_result(result),
      execution_time_ms: execution_time_ms,
      timestamp: DateTime.utc_now()
    })
  end
  
  @doc """
  Handles streaming of step failure events.
  
  Publishes events when workflow steps fail, including error
  information and debugging context.
  """
  @spec stream_step_failure(String.t(), String.t(), term()) :: :ok
  def stream_step_failure(stream_id, step_name, error) do
    emit_workflow_event(stream_id, "step_failed", %{
      step_name: step_name,
      error: sanitize_error(error),
      timestamp: DateTime.utc_now()
    })
  end
  
  # Private helper functions
  
  defp start_workflow_execution(workflow, context, options, stream_id) do
    # Emit workflow start event
    emit_workflow_event(stream_id, "workflow_started", %{
      workflow_id: Map.get(context, :workflow_id),
      context: sanitize_context(context),
      options: sanitize_options(options),
      timestamp: DateTime.utc_now()
    })
    
    # Start async workflow execution
    task = Task.async(fn ->
      execute_workflow_with_monitoring(workflow, context, options)
    end)
    
    %{
      task: task,
      stream_id: stream_id,
      workflow_id: Map.get(context, :workflow_id),
      started_at: DateTime.utc_now(),
      events_received: 0
    }
  end
  
  defp handle_stream_events(state, topic) do
    receive do
      # Workflow events from PubSub
      {_from, ^topic, event} ->
        updated_state = %{state | events_received: state.events_received + 1}
        {[event], updated_state}
        
      # Task completion
      {ref, {:ok, result}} when ref == state.task.ref ->
        final_event = create_completion_event(state.workflow_id, result)
        Process.demonitor(ref, [:flush])
        {[final_event], :completed}
        
      # Task failure
      {ref, {:error, reason}} when ref == state.task.ref ->
        final_event = create_failure_event(state.workflow_id, reason)
        Process.demonitor(ref, [:flush])
        {[final_event], :failed}
        
      # Task exit
      {:DOWN, ref, :process, _pid, reason} when ref == state.task.ref ->
        final_event = create_failure_event(state.workflow_id, reason)
        {[final_event], :failed}
        
    after
      1000 ->
        # Heartbeat event to keep stream alive
        heartbeat_event = create_heartbeat_event(state)
        {[heartbeat_event], state}
    end
  end
  
  defp cleanup_stream_execution(state, topic) do
    # Unsubscribe from events
    PubSub.unsubscribe(RubberDuck.PubSub, topic)
    
    # Cancel task if still running
    if state != :completed and state != :failed do
      Task.shutdown(state.task, :brutal_kill)
    end
    
    Logger.info("Cleaned up workflow stream: #{state.stream_id}")
  end
  
  defp execute_workflow_with_monitoring(workflow, context, options) do
    # Add telemetry and monitoring hooks
    monitored_workflow = add_streaming_middleware(workflow, context, options)
    
    # Execute with enhanced monitoring
    timeout = Map.get(options, "timeout", 30_000)
    
    case Composition.execute(monitored_workflow, context, timeout: timeout) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp add_streaming_middleware(workflow, _context, _options) do
    # Add middleware for streaming events
    # This would integrate with Reactor's middleware system
    workflow
  end
  
  defp setup_progress_monitoring(workflow_id, stream_id, _options) do
    # Set up telemetry handlers for progress monitoring
    telemetry_metadata = %{
      workflow_id: workflow_id,
      stream_id: stream_id,
      streaming_enabled: true
    }
    
    # Attach telemetry handlers
    :telemetry.attach_many(
      "workflow_streaming_#{stream_id}",
      [
        [:reactor, :step, :start],
        [:reactor, :step, :stop],
        [:reactor, :step, :exception]
      ],
      &handle_telemetry_event/4,
      telemetry_metadata
    )
  end
  
  defp cleanup_progress_monitoring(workflow_id, stream_id) do
    # Detach telemetry handlers
    :telemetry.detach("workflow_streaming_#{stream_id}")
    
    Logger.debug("Cleaned up progress monitoring for workflow: #{workflow_id}")
  end
  
  defp handle_telemetry_event([:reactor, :step, :start], measurements, metadata, config) do
    emit_workflow_event(config.stream_id, "step_started", %{
      step_name: metadata.step_name,
      workflow_id: config.workflow_id,
      measurements: measurements,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp handle_telemetry_event([:reactor, :step, :stop], measurements, metadata, config) do
    emit_workflow_event(config.stream_id, "step_completed", %{
      step_name: metadata.step_name,
      workflow_id: config.workflow_id,
      measurements: measurements,
      result: sanitize_result(metadata.result),
      timestamp: DateTime.utc_now()
    })
  end
  
  defp handle_telemetry_event([:reactor, :step, :exception], measurements, metadata, config) do
    emit_workflow_event(config.stream_id, "step_failed", %{
      step_name: metadata.step_name,
      workflow_id: config.workflow_id,
      measurements: measurements,
      error: sanitize_error(metadata.error),
      timestamp: DateTime.utc_now()
    })
  end
  
  defp emit_workflow_event(stream_id, event_type, event_data) do
    event = %{
      type: event_type,
      stream_id: stream_id,
      data: event_data,
      timestamp: DateTime.utc_now()
    }
    
    topic = "workflow_stream:#{stream_id}"
    PubSub.broadcast(RubberDuck.PubSub, topic, event)
  end
  
  defp create_completion_event(workflow_id, result) do
    %{
      type: "workflow_completed",
      workflow_id: workflow_id,
      result: sanitize_result(result),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp create_failure_event(workflow_id, reason) do
    %{
      type: "workflow_failed",
      workflow_id: workflow_id,
      error: sanitize_error(reason),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp create_heartbeat_event(state) do
    %{
      type: "heartbeat",
      workflow_id: state.workflow_id,
      stream_id: state.stream_id,
      events_received: state.events_received,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp format_intermediate_result(result) do
    case result do
      binary when is_binary(binary) -> %{type: "text", content: binary}
      map when is_map(map) -> %{type: "json", content: map}
      list when is_list(list) -> %{type: "list", content: list}
      other -> %{type: "other", content: inspect(other)}
    end
  end
  
  defp format_step_result(result) do
    format_intermediate_result(result)
  end
  
  defp sanitize_context(context) do
    # Remove sensitive information from context
    context
    |> Map.drop([:credentials, :secrets, :tokens])
    |> Map.put(:sanitized, true)
  end
  
  defp sanitize_options(options) do
    # Remove sensitive information from options
    options
    |> Map.drop(["credentials", "secrets", "tokens"])
    |> Map.put("sanitized", true)
  end
  
  defp sanitize_result(result) do
    case result do
      %{credentials: _, secrets: _, tokens: _} = map ->
        map
        |> Map.drop([:credentials, :secrets, :tokens])
        |> Map.put(:sanitized, true)
        
      map when is_map(map) ->
        map
        |> Enum.reject(fn {k, _v} -> k in [:credentials, :secrets, :tokens] end)
        |> Map.new()
        
      other ->
        other
    end
  end
  
  defp sanitize_error(error) do
    case error do
      binary when is_binary(binary) ->
        binary
        |> String.replace(~r/password[=:]\s*\S+/i, "password=***")
        |> String.replace(~r/token[=:]\s*\S+/i, "token=***")
        |> String.replace(~r/secret[=:]\s*\S+/i, "secret=***")
        
      other ->
        inspect(other)
    end
  end
  
  defp generate_workflow_id do
    "workflow_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
  
  defp generate_stream_id do
    "stream_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end