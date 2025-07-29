defmodule RubberDuck.Jido.Agents.Telemetry do
  @moduledoc """
  Comprehensive telemetry and observability for the agent system.
  
  Provides:
  - Lifecycle event tracking
  - Performance metrics collection
  - Resource usage monitoring
  - Integration with telemetry libraries
  - Custom metric aggregation
  - Distributed tracing support
  
  ## Telemetry Events
  
  ### Lifecycle Events
  - `[:rubber_duck, :agent, :spawn]` - Agent spawned
  - `[:rubber_duck, :agent, :terminate]` - Agent terminated
  - `[:rubber_duck, :agent, :state_change]` - Agent state changed
  - `[:rubber_duck, :agent, :error]` - Agent error occurred
  - `[:rubber_duck, :agent, :recovery]` - Agent recovered from error
  
  ### Performance Events
  - `[:rubber_duck, :agent, :action, :start]` - Action execution started
  - `[:rubber_duck, :agent, :action, :stop]` - Action execution completed
  - `[:rubber_duck, :agent, :action, :exception]` - Action execution failed
  - `[:rubber_duck, :agent, :queue, :depth]` - Queue depth measurement
  
  ### Resource Events
  - `[:rubber_duck, :agent, :memory]` - Memory usage measurement
  - `[:rubber_duck, :agent, :cpu]` - CPU usage measurement
  - `[:rubber_duck, :agent, :message_queue]` - Message queue size
  
  ## Usage
  
      # Attach a handler
      Telemetry.attach_default_handlers()
      
      # Custom handler
      :telemetry.attach(
        "my-handler",
        [:rubber_duck, :agent, :spawn],
        &MyHandler.handle_event/4,
        %{}
      )
  """
  
  require Logger
  
  @type event_name :: [atom()]
  @type measurements :: map()
  @type metadata :: map()
  
  # Event name prefixes
  @agent_prefix [:rubber_duck, :agent]
  @lifecycle_events [:spawn, :terminate, :state_change, :error, :recovery]
  @resource_events [:memory, :cpu, :message_queue]
  
  @doc """
  Attaches default telemetry handlers for logging and basic metrics.
  """
  def attach_default_handlers do
    handlers = [
      # Lifecycle handlers
      {"agent-lifecycle-logger", lifecycle_events(), &handle_lifecycle_event/4},
      
      # Performance handlers
      {"agent-performance-logger", performance_events(), &handle_performance_event/4},
      
      # Resource handlers
      {"agent-resource-logger", resource_events(), &handle_resource_event/4},
      
      # Health monitoring handler
      {"agent-health-logger", health_events(), &handle_health_event/4}
    ]
    
    Enum.each(handlers, fn {handler_id, events, handler_fun} ->
      :telemetry.attach_many(
        handler_id,
        events,
        handler_fun,
        %{}
      )
    end)
    
    Logger.info("Attached default telemetry handlers for agent system")
    :ok
  end
  
  @doc """
  Detaches all default handlers.
  """
  def detach_default_handlers do
    handler_ids = [
      "agent-lifecycle-logger",
      "agent-performance-logger", 
      "agent-resource-logger",
      "agent-health-logger"
    ]
    
    Enum.each(handler_ids, &:telemetry.detach/1)
    :ok
  end
  
  @doc """
  Emits an agent spawn event.
  """
  def agent_spawned(agent_id, agent_module, metadata \\ %{}) do
    :telemetry.execute(
      @agent_prefix ++ [:spawn],
      %{count: 1},
      Map.merge(metadata, %{
        agent_id: agent_id,
        agent_module: agent_module,
        timestamp: System.system_time(:microsecond)
      })
    )
  end
  
  @doc """
  Emits an agent termination event.
  """
  def agent_terminated(agent_id, reason, metadata \\ %{}) do
    :telemetry.execute(
      @agent_prefix ++ [:terminate],
      %{count: 1},
      Map.merge(metadata, %{
        agent_id: agent_id,
        reason: reason,
        timestamp: System.system_time(:microsecond)
      })
    )
  end
  
  @doc """
  Emits an agent state change event.
  """
  def agent_state_changed(agent_id, old_state, new_state, metadata \\ %{}) do
    :telemetry.execute(
      @agent_prefix ++ [:state_change],
      %{count: 1},
      Map.merge(metadata, %{
        agent_id: agent_id,
        old_state: old_state,
        new_state: new_state,
        timestamp: System.system_time(:microsecond)
      })
    )
  end
  
  @doc """
  Emits an agent error event.
  """
  def agent_error(agent_id, error, metadata \\ %{}) do
    :telemetry.execute(
      @agent_prefix ++ [:error],
      %{count: 1, severity: error_severity(error)},
      Map.merge(metadata, %{
        agent_id: agent_id,
        error: error,
        timestamp: System.system_time(:microsecond)
      })
    )
  end
  
  @doc """
  Emits an agent recovery event.
  """
  def agent_recovered(agent_id, from_error, metadata \\ %{}) do
    :telemetry.execute(
      @agent_prefix ++ [:recovery],
      %{count: 1},
      Map.merge(metadata, %{
        agent_id: agent_id,
        from_error: from_error,
        timestamp: System.system_time(:microsecond)
      })
    )
  end
  
  @doc """
  Spans an action execution with start/stop/exception events.
  
  ## Example
  
      Telemetry.span_action(agent_id, MyAction, fn ->
        # Execute action
        {:ok, result}
      end)
  """
  def span_action(agent_id, action, metadata \\ %{}, fun) do
    span_metadata = Map.merge(metadata, %{agent_id: agent_id, action: action})
    
    # telemetry.span returns the result of the function directly
    try do
      :telemetry.span(
        @agent_prefix ++ [:action],
        span_metadata,
        fn ->
          result = fun.()
          # Return {result, metadata} as expected by telemetry.span
          {result, %{}}
        end
      )
    rescue
      e ->
        # The span will emit the exception event, but we need to add our metadata
        reraise e, __STACKTRACE__
    end
  end
  
  @doc """
  Emits a queue depth measurement.
  """
  def report_queue_depth(queue_name, depth, metadata \\ %{}) do
    :telemetry.execute(
      @agent_prefix ++ [:queue, :depth],
      %{depth: depth},
      Map.merge(metadata, %{
        queue_name: queue_name,
        timestamp: System.system_time(:microsecond)
      })
    )
  end
  
  @doc """
  Emits resource usage metrics for an agent.
  """
  def report_agent_resources(agent_id, pid) do
    case Process.info(pid, [:memory, :message_queue_len, :reductions]) do
      [{:memory, memory}, {:message_queue_len, queue_len}, {:reductions, reductions}] ->
        # Memory usage
        :telemetry.execute(
          @agent_prefix ++ [:memory],
          %{bytes: memory},
          %{agent_id: agent_id, pid: pid}
        )
        
        # Message queue
        :telemetry.execute(
          @agent_prefix ++ [:message_queue],
          %{length: queue_len},
          %{agent_id: agent_id, pid: pid}
        )
        
        # CPU approximation via reductions
        :telemetry.execute(
          @agent_prefix ++ [:cpu],
          %{reductions: reductions},
          %{agent_id: agent_id, pid: pid}
        )
        
        {:ok, %{memory: memory, queue_length: queue_len, reductions: reductions}}
        
      nil ->
        {:error, :process_not_found}
    end
  end
  
  @doc """
  Sets up periodic resource monitoring for all agents.
  """
  def start_resource_monitoring(interval_ms \\ 30_000) do
    Task.start_link(fn ->
      resource_monitoring_loop(interval_ms)
    end)
  end
  
  # Private functions
  
  defp lifecycle_events do
    Enum.map(@lifecycle_events, &(@agent_prefix ++ [&1]))
  end
  
  defp performance_events do
    [
      @agent_prefix ++ [:action, :start],
      @agent_prefix ++ [:action, :stop],
      @agent_prefix ++ [:action, :exception],
      @agent_prefix ++ [:queue, :depth]
    ]
  end
  
  defp resource_events do
    Enum.map(@resource_events, &(@agent_prefix ++ [&1]))
  end
  
  defp health_events do
    [
      @agent_prefix ++ [:health_check],
      @agent_prefix ++ [:circuit_breaker],
      @agent_prefix ++ [:health_alert]
    ]
  end
  
  defp handle_lifecycle_event(event_name, measurements, metadata, _config) do
    level = case List.last(event_name) do
      :error -> :error
      :terminate when metadata.reason != :normal -> :warning
      _ -> :info
    end
    
    Logger.log(level, "Agent lifecycle event: #{inspect(event_name)}", 
      event: event_name,
      measurements: measurements,
      metadata: metadata
    )
  end
  
  defp handle_performance_event(event_name, measurements, metadata, _config) do
    case List.last(event_name) do
      :exception ->
        Logger.error("Agent action failed", 
          event: event_name,
          measurements: measurements,
          metadata: metadata
        )
        
      :stop ->
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
        if duration_ms > 1000 do
          Logger.warning("Slow agent action: #{duration_ms}ms",
            event: event_name,
            measurements: measurements,
            metadata: metadata
          )
        end
        
      _ ->
        Logger.debug("Agent performance event",
          event: event_name,
          measurements: measurements,
          metadata: metadata
        )
    end
  end
  
  defp handle_resource_event(event_name, measurements, metadata, _config) do
    case List.last(event_name) do
      :memory when measurements.bytes > 100_000_000 ->  # 100MB
        Logger.warning("High agent memory usage: #{measurements.bytes} bytes",
          event: event_name,
          measurements: measurements,
          metadata: metadata
        )
        
      :message_queue when measurements.length > 1000 ->
        Logger.warning("Large agent message queue: #{measurements.length}",
          event: event_name,
          measurements: measurements,
          metadata: metadata
        )
        
      _ ->
        Logger.debug("Agent resource event",
          event: event_name,
          measurements: measurements,
          metadata: metadata
        )
    end
  end
  
  defp handle_health_event(event_name, measurements, metadata, _config) do
    case List.last(event_name) do
      :health_alert ->
        Logger.error("Agent health alert",
          event: event_name,
          measurements: measurements,
          metadata: metadata
        )
        
      :circuit_breaker when metadata.state == :open ->
        Logger.warning("Agent circuit breaker opened",
          event: event_name,
          measurements: measurements,
          metadata: metadata
        )
        
      _ ->
        Logger.debug("Agent health event",
          event: event_name,
          measurements: measurements,
          metadata: metadata
        )
    end
  end
  
  defp error_severity(error) do
    case error do
      {:exit, _} -> 3  # High
      {:error, _} -> 2  # Medium
      _ -> 1  # Low
    end
  end
  
  defp resource_monitoring_loop(interval_ms) do
    # Get all agents
    case RubberDuck.Jido.Agents.Supervisor.list_agents() do
      agents when is_list(agents) ->
        Enum.each(agents, fn agent ->
          report_agent_resources(agent.id, agent.pid)
        end)
        
      _ ->
        :ok
    end
    
    Process.sleep(interval_ms)
    resource_monitoring_loop(interval_ms)
  end
end