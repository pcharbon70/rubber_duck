defmodule RubberDuck.Tool.Composition.Middleware.Monitoring do
  @moduledoc """
  Monitoring middleware for tool composition workflows.
  
  This middleware provides comprehensive monitoring capabilities for Reactor-based workflows:
  - Real-time workflow execution tracking
  - Performance metrics and resource monitoring
  - Error tracking and alerting
  - Integration with RubberDuck's monitoring dashboard
  - Security event monitoring
  
  ## Features
  
  - Workflow lifecycle tracking (start, progress, completion)
  - Step-level execution monitoring
  - Resource usage tracking (memory, CPU, duration)
  - Error pattern detection and alerting
  - Real-time dashboard updates via Phoenix PubSub
  - Integration with existing telemetry infrastructure
  
  ## Usage
  
  The middleware is automatically integrated with composition workflows and
  leverages the existing RubberDuck monitoring infrastructure.
  """
  
  use Reactor.Middleware
  
  alias Phoenix.PubSub
  
  require Logger
  
  # Telemetry events for workflow monitoring
  @workflow_start_event [:rubber_duck, :tool, :composition, :workflow_start]
  @workflow_complete_event [:rubber_duck, :tool, :composition, :workflow_complete]
  @workflow_error_event [:rubber_duck, :tool, :composition, :workflow_error]
  @workflow_step_start_event [:rubber_duck, :tool, :composition, :workflow_step_start]
  @workflow_step_complete_event [:rubber_duck, :tool, :composition, :workflow_step_complete]
  @workflow_step_error_event [:rubber_duck, :tool, :composition, :workflow_step_error]
  
  # PubSub topic for real-time updates
  @pubsub_topic "composition_workflows"
  
  @doc """
  Initializes the monitoring middleware.
  
  Sets up telemetry handlers, initializes metrics storage, and prepares
  the middleware for workflow monitoring.
  """
  @impl Reactor.Middleware
  def init(opts) do
    # Initialize workflow tracking
    workflow_id = generate_workflow_id()
    
    # Create monitoring context
    context = %{
      workflow_id: workflow_id,
      start_time: System.monotonic_time(:millisecond),
      step_count: 0,
      completed_steps: 0,
      failed_steps: 0,
      metrics: %{},
      options: opts
    }
    
    Logger.info("Monitoring middleware initialized for workflow: #{workflow_id}")
    
    # Emit workflow start telemetry
    :telemetry.execute(
      @workflow_start_event,
      %{count: 1, timestamp: context.start_time},
      %{
        workflow_id: workflow_id,
        workflow_name: "composition_workflow"
      }
    )
    
    # Broadcast to dashboard
    broadcast_workflow_event(:start, workflow_id, %{
      name: "composition_workflow",
      start_time: context.start_time
    })
    
    {:ok, context}
  end
  
  @doc """
  Handles reactor events including step execution events.
  
  This is the main event handler that processes step-level events
  and emits appropriate telemetry.
  """
  @impl Reactor.Middleware
  def event(step_event, step, context) do
    workflow_id = context.workflow_id
    step_name = step.name
    
    case step_event do
      {:run_start, arguments} ->
        handle_step_start(workflow_id, step_name, step, arguments, context)
        
      {:run_complete, result} ->
        handle_step_complete(workflow_id, step_name, step, result, context)
        
      {:run_error, errors} ->
        handle_step_error(workflow_id, step_name, step, errors, context)
        
      {:process_start, _pid} ->
        # Handle async process start if needed
        {:ok, context}
        
      {:process_terminate, _pid} ->
        # Handle async process termination if needed
        {:ok, context}
        
      _ ->
        # Ignore other events
        {:ok, context}
    end
  end
  
  @doc """
  Called when the reactor completes successfully.
  
  Records completion metrics, calculates overall performance, and updates monitoring.
  """
  @impl Reactor.Middleware
  def complete(_result, context) do
    workflow_id = context.workflow_id
    end_time = System.monotonic_time(:millisecond)
    total_duration = end_time - context.start_time
    
    # Emit workflow completion telemetry
    :telemetry.execute(
      @workflow_complete_event,
      %{count: 1, duration: total_duration, timestamp: end_time},
      %{
        workflow_id: workflow_id,
        total_steps: context.step_count,
        completed_steps: context.completed_steps,
        failed_steps: context.failed_steps,
        success_rate: calculate_success_rate(context)
      }
    )
    
    # Broadcast completion to dashboard
    broadcast_workflow_event(:complete, workflow_id, %{
      end_time: end_time,
      duration: total_duration,
      status: :completed,
      success_rate: calculate_success_rate(context)
    })
    
    Logger.info("Workflow #{workflow_id} completed successfully in #{total_duration}ms")
    
    {:ok, context}
  end
  
  @doc """
  Called when the reactor fails.
  
  Records failure metrics, analyzes error patterns, and triggers alerting.
  """
  @impl Reactor.Middleware
  def error(errors, context) do
    workflow_id = context.workflow_id
    end_time = System.monotonic_time(:millisecond)
    total_duration = end_time - context.start_time
    
    # Extract error information
    error_type = extract_error_type(errors)
    error_message = extract_error_message(errors)
    
    # Emit workflow error telemetry
    :telemetry.execute(
      @workflow_error_event,
      %{count: 1, duration: total_duration, timestamp: end_time},
      %{
        workflow_id: workflow_id,
        total_steps: context.step_count,
        completed_steps: context.completed_steps,
        failed_steps: context.failed_steps,
        error_type: error_type,
        error_message: error_message
      }
    )
    
    # Broadcast error to dashboard
    broadcast_workflow_event(:error, workflow_id, %{
      end_time: end_time,
      duration: total_duration,
      status: :failed,
      error: %{
        type: error_type,
        message: error_message
      }
    })
    
    Logger.error("Workflow #{workflow_id} failed after #{total_duration}ms: #{error_message}")
    
    {:ok, context}
  end
  
  @doc """
  Called when the reactor is halted.
  
  Cleans up monitoring resources and emits halt telemetry.
  """
  @impl Reactor.Middleware
  def halt(context) do
    workflow_id = context.workflow_id
    end_time = System.monotonic_time(:millisecond)
    total_duration = end_time - context.start_time
    
    # Broadcast halt to dashboard
    broadcast_workflow_event(:halt, workflow_id, %{
      end_time: end_time,
      duration: total_duration,
      status: :halted
    })
    
    Logger.info("Workflow #{workflow_id} halted after #{total_duration}ms")
    
    {:ok, context}
  end
  
  # Private helper functions
  
  defp handle_step_start(workflow_id, step_name, step, _arguments, context) do
    step_start_time = System.monotonic_time(:millisecond)
    
    # Emit step start telemetry
    :telemetry.execute(
      @workflow_step_start_event,
      %{count: 1, timestamp: step_start_time},
      %{
        workflow_id: workflow_id,
        step_name: step_name,
        step_impl: step.impl
      }
    )
    
    # Broadcast step start to dashboard
    broadcast_step_event(:start, workflow_id, step_name, %{
      start_time: step_start_time,
      status: :running
    })
    
    # Update context with step timing
    step_timings = Map.put(context.metrics, step_name, %{start_time: step_start_time})
    updated_context = %{context | metrics: step_timings}
    
    {:ok, updated_context}
  end
  
  defp handle_step_complete(workflow_id, step_name, step, result, context) do
    # Calculate step execution time
    step_start_time = get_in(context.metrics, [step_name, :start_time])
    step_end_time = System.monotonic_time(:millisecond)
    duration = if step_start_time, do: step_end_time - step_start_time, else: 0
    
    # Emit step completion telemetry
    :telemetry.execute(
      @workflow_step_complete_event,
      %{count: 1, duration: duration, timestamp: step_end_time},
      %{
        workflow_id: workflow_id,
        step_name: step_name,
        step_impl: step.impl,
        result_size: estimate_result_size(result)
      }
    )
    
    # Broadcast step completion to dashboard
    broadcast_step_event(:complete, workflow_id, step_name, %{
      end_time: step_end_time,
      duration: duration,
      status: :completed
    })
    
    # Update context
    updated_context = %{
      context | 
      completed_steps: context.completed_steps + 1,
      metrics: put_in(context.metrics, [step_name, :end_time], step_end_time)
    }
    
    {:ok, updated_context}
  end
  
  defp handle_step_error(workflow_id, step_name, step, errors, context) do
    # Calculate step execution time
    step_start_time = get_in(context.metrics, [step_name, :start_time])
    step_end_time = System.monotonic_time(:millisecond)
    duration = if step_start_time, do: step_end_time - step_start_time, else: 0
    
    # Extract error information
    error_type = extract_error_type(errors)
    error_message = extract_error_message(errors)
    
    # Emit step error telemetry
    :telemetry.execute(
      @workflow_step_error_event,
      %{count: 1, duration: duration, timestamp: step_end_time},
      %{
        workflow_id: workflow_id,
        step_name: step_name,
        step_impl: step.impl,
        error_type: error_type,
        error_message: error_message
      }
    )
    
    # Broadcast step error to dashboard
    broadcast_step_event(:error, workflow_id, step_name, %{
      end_time: step_end_time,
      duration: duration,
      status: :failed,
      error: %{
        type: error_type,
        message: error_message
      }
    })
    
    # Log error for debugging
    Logger.error("Step #{step_name} failed in workflow #{workflow_id}: #{error_message}")
    
    # Update context
    updated_context = %{
      context | 
      failed_steps: context.failed_steps + 1,
      metrics: put_in(context.metrics, [step_name, :error], errors)
    }
    
    {:ok, updated_context}
  end
  
  defp generate_workflow_id do
    "workflow_#{System.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end
  
  defp broadcast_workflow_event(event_type, workflow_id, data) do
    message = %{
      type: :workflow,
      event: event_type,
      workflow_id: workflow_id,
      data: data,
      timestamp: System.system_time(:millisecond)
    }
    
    case Process.whereis(RubberDuck.PubSub) do
      nil -> :ok  # PubSub not available
      _pid -> 
        PubSub.broadcast(RubberDuck.PubSub, @pubsub_topic, message)
    end
  end
  
  defp broadcast_step_event(event_type, workflow_id, step_name, data) do
    message = %{
      type: :step,
      event: event_type,
      workflow_id: workflow_id,
      step_name: step_name,
      data: data,
      timestamp: System.system_time(:millisecond)
    }
    
    case Process.whereis(RubberDuck.PubSub) do
      nil -> :ok  # PubSub not available
      _pid -> 
        PubSub.broadcast(RubberDuck.PubSub, @pubsub_topic, message)
    end
  end
  
  defp estimate_result_size(result) do
    try do
      result
      |> :erlang.term_to_binary()
      |> byte_size()
    rescue
      _ -> 0
    end
  end
  
  defp extract_error_type(errors) when is_list(errors) do
    case List.first(errors) do
      nil -> :unknown
      error -> extract_error_type(error)
    end
  end
  
  defp extract_error_type(error) do
    case error do
      {:error, type} when is_atom(type) -> type
      {:error, {type, _}} when is_atom(type) -> type
      %{__struct__: struct} -> struct
      _ -> :unknown
    end
  end
  
  defp extract_error_message(errors) when is_list(errors) do
    case List.first(errors) do
      nil -> "Unknown error"
      error -> extract_error_message(error)
    end
  end
  
  defp extract_error_message(error) do
    case error do
      {:error, message} when is_binary(message) -> message
      {:error, {_, message}} when is_binary(message) -> message
      %{message: message} when is_binary(message) -> message
      _ -> inspect(error)
    end
  end
  
  defp calculate_success_rate(context) do
    total_steps = context.step_count
    
    if total_steps > 0 do
      success_steps = context.completed_steps
      (success_steps / total_steps) * 100
    else
      100.0
    end
  end
end