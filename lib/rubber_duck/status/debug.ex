defmodule RubberDuck.Status.Debug do
  @moduledoc """
  Debugging tools for the Status Broadcasting System.
  
  Provides utilities for inspecting, tracing, and troubleshooting
  the status system in development and production environments.
  
  ## Features
  
  - Message tracing and inspection
  - Channel state visualization
  - Queue state dumping
  - Performance profiling
  - Real-time debugging console
  """
  
  require Logger
  
  alias RubberDuck.Status.{Broadcaster, Channel, Monitor, Optimizer}
  
  @doc """
  Enables message tracing for a specific conversation.
  
  All messages for the conversation will be logged with detailed information.
  """
  def trace_conversation(conversation_id, opts \\ []) do
    duration = Keyword.get(opts, :duration, :infinity)
    categories = Keyword.get(opts, :categories, :all)
    
    tracer_pid = spawn_link(fn ->
      trace_loop(conversation_id, categories)
    end)
    
    # Register the tracer
    register_tracer(conversation_id, tracer_pid, categories)
    
    # Schedule cleanup if duration specified
    if duration != :infinity do
      Process.send_after(tracer_pid, :stop, duration)
    end
    
    {:ok, tracer_pid}
  end
  
  @doc """
  Stops tracing for a conversation.
  """
  def stop_trace(conversation_id) do
    case get_tracer(conversation_id) do
      nil ->
        {:error, :not_tracing}
      
      tracer_pid ->
        send(tracer_pid, :stop)
        unregister_tracer(conversation_id)
        :ok
    end
  end
  
  @doc """
  Lists all active traces.
  """
  def list_traces do
    :persistent_term.get({__MODULE__, :tracers}, %{})
    |> Enum.map(fn {conv_id, {pid, categories}} ->
      %{
        conversation_id: conv_id,
        tracer_pid: pid,
        categories: categories,
        alive: Process.alive?(pid)
      }
    end)
  end
  
  @doc """
  Inspects the current state of a channel.
  """
  def inspect_channel(conversation_id) do
    case get_channel_state(conversation_id) do
      {:error, reason} ->
        {:error, reason}
      
      {:ok, state} ->
        {:ok, %{
          conversation_id: conversation_id,
          subscribers: length(Map.get(state, :subscribers, [])),
          categories: Map.get(state, :categories, []),
          message_count: Map.get(state, :message_count, 0),
          created_at: Map.get(state, :created_at),
          last_activity: Map.get(state, :last_activity)
        }}
    end
  end
  
  @doc """
  Lists all active channels with their state.
  """
  def list_channels(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    sort_by = Keyword.get(opts, :sort_by, :last_activity)
    
    list_all_channels()
    |> Enum.map(&inspect_channel/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, info} -> info end)
    |> Enum.sort_by(&Map.get(&1, sort_by), :desc)
    |> Enum.take(limit)
  end
  
  @doc """
  Dumps the current state of the message queue.
  """
  def dump_queue do
    state = :sys.get_state(Broadcaster)
    
    %{
      queue_size: :queue.len(state.message_queue),
      messages: queue_to_list(state.message_queue, 20),
      current_batch_size: state.batch_size,
      flush_interval: state.flush_interval,
      processing: state.processing
    }
  end
  
  @doc """
  Gets detailed queue statistics.
  """
  def queue_stats do
    state = :sys.get_state(Broadcaster)
    messages = queue_to_list(state.message_queue, :all)
    
    %{
      total_messages: length(messages),
      by_conversation: group_by_conversation(messages),
      by_category: group_by_category(messages),
      oldest_message: List.first(messages),
      newest_message: List.last(messages),
      estimated_memory: estimate_queue_memory(messages)
    }
  end
  
  @doc """
  Profiles the performance of the status system.
  """
  def profile(duration \\ 10_000) do
    Logger.info("Starting status system profiling for #{duration}ms")
    
    # Start collecting metrics
    start_time = System.monotonic_time(:millisecond)
    initial_metrics = collect_metrics()
    
    # Wait for duration
    Process.sleep(duration)
    
    # Collect final metrics
    end_time = System.monotonic_time(:millisecond)
    final_metrics = collect_metrics()
    
    # Calculate deltas and rates
    analyze_metrics(initial_metrics, final_metrics, end_time - start_time)
  end
  
  @doc """
  Simulates high load to test system behavior.
  """
  def simulate_load(conversation_ids, opts \\ []) do
    rate = Keyword.get(opts, :rate, 100)  # messages per second
    duration = Keyword.get(opts, :duration, 10_000)  # milliseconds
    categories = Keyword.get(opts, :categories, ["thinking", "processing", "ready"])
    
    Logger.warning("Starting load simulation: #{rate} msg/s for #{duration}ms")
    
    # Start load generator
    Task.start(fn ->
      generate_load(conversation_ids, categories, rate, duration)
    end)
    
    {:ok, %{rate: rate, duration: duration, total_messages: rate * duration / 1000}}
  end
  
  @doc """
  Captures a snapshot of the entire system state.
  """
  def capture_snapshot do
    %{
      timestamp: DateTime.utc_now(),
      broadcaster: capture_broadcaster_state(),
      channels: capture_all_channels(),
      monitor: capture_monitor_state(),
      optimizer: capture_optimizer_state(),
      memory: capture_memory_stats()
    }
  end
  
  @doc """
  Analyzes message flow patterns.
  """
  def analyze_flow(conversation_id, time_window \\ 60_000) do
    # This would analyze message patterns, timing, etc.
    # For now, return a placeholder
    %{
      conversation_id: conversation_id,
      time_window: time_window,
      analysis: "Message flow analysis not yet implemented"
    }
  end
  
  @doc """
  Checks system health and returns diagnostics.
  """
  def health_check do
    checks = [
      check_broadcaster_health(),
      check_channel_health(),
      check_monitor_health(),
      check_optimizer_health(),
      check_memory_usage()
    ]
    
    %{
      healthy: Enum.all?(checks, & &1.healthy),
      checks: checks,
      recommendations: generate_recommendations(checks)
    }
  end
  
  # Private Functions
  
  defp trace_loop(conversation_id, categories) do
    receive do
      :stop ->
        Logger.info("Stopping trace for conversation #{conversation_id}")
        :ok
      
      {:trace_message, message} ->
        if should_trace?(message, categories) do
          log_traced_message(conversation_id, message)
        end
        trace_loop(conversation_id, categories)
      
      _ ->
        trace_loop(conversation_id, categories)
    end
  end
  
  defp should_trace?(_message, :all), do: true
  defp should_trace?(message, categories) do
    message.category in categories
  end
  
  defp log_traced_message(conversation_id, message) do
    Logger.debug("""
    [STATUS TRACE] Conversation: #{conversation_id}
    Category: #{message.category}
    Message: #{inspect(message.content)}
    Metadata: #{inspect(message.metadata)}
    Timestamp: #{message.timestamp}
    """)
  end
  
  defp register_tracer(conversation_id, pid, categories) do
    tracers = :persistent_term.get({__MODULE__, :tracers}, %{})
    :persistent_term.put({__MODULE__, :tracers}, Map.put(tracers, conversation_id, {pid, categories}))
  end
  
  defp unregister_tracer(conversation_id) do
    tracers = :persistent_term.get({__MODULE__, :tracers}, %{})
    :persistent_term.put({__MODULE__, :tracers}, Map.delete(tracers, conversation_id))
  end
  
  defp get_tracer(conversation_id) do
    :persistent_term.get({__MODULE__, :tracers}, %{})
    |> Map.get(conversation_id)
    |> case do
      {pid, _categories} -> pid
      nil -> nil
    end
  end
  
  defp queue_to_list(queue, limit) do
    list = :queue.to_list(queue)
    
    case limit do
      :all -> list
      n when is_integer(n) -> Enum.take(list, n)
    end
  end
  
  defp group_by_conversation(messages) do
    messages
    |> Enum.group_by(& &1.conversation_id)
    |> Enum.map(fn {conv_id, msgs} ->
      {conv_id, length(msgs)}
    end)
    |> Map.new()
  end
  
  defp group_by_category(messages) do
    messages
    |> Enum.group_by(& &1.category)
    |> Enum.map(fn {category, msgs} ->
      {category, length(msgs)}
    end)
    |> Map.new()
  end
  
  defp estimate_queue_memory(messages) do
    # Rough estimation of memory usage
    messages
    |> Enum.map(&:erlang.external_size/1)
    |> Enum.sum()
  end
  
  defp collect_metrics do
    %{
      queue_depth: get_queue_depth(),
      active_channels: length(list_all_channels()),
      memory_usage: :erlang.memory(:total),
      monitor_metrics: Monitor.metrics_summary(),
      optimizer_settings: Optimizer.get_optimizations()
    }
  end
  
  defp get_queue_depth do
    try do
      state = :sys.get_state(Broadcaster)
      :queue.len(state.message_queue)
    catch
      _, _ -> 0
    end
  end
  
  defp analyze_metrics(initial, final, duration_ms) do
    %{
      duration_ms: duration_ms,
      messages_processed: final.queue_depth - initial.queue_depth,
      throughput: calculate_throughput(initial, final, duration_ms),
      channel_churn: final.active_channels - initial.active_channels,
      memory_growth: final.memory_usage - initial.memory_usage,
      monitor_summary: final.monitor_metrics,
      optimizer_changes: compare_optimizer_settings(initial.optimizer_settings, final.optimizer_settings)
    }
  end
  
  defp calculate_throughput(_initial, _final, duration_ms) do
    # This would need actual message count tracking
    messages_per_second = 0  # Placeholder
    messages_per_second * 1000 / duration_ms
  end
  
  defp compare_optimizer_settings(initial, final) do
    changes = []
    
    for key <- [:batch_size, :flush_interval, :compression, :sharding] do
      if initial[key] != final[key] do
        changes ++ [{key, initial[key], final[key]}]
      else
        changes
      end
    end
  end
  
  defp generate_load(conversation_ids, categories, rate, duration) do
    message_interval = div(1000, rate)  # milliseconds between messages
    end_time = System.monotonic_time(:millisecond) + duration
    
    generate_messages(conversation_ids, categories, message_interval, end_time)
  end
  
  defp generate_messages(conversation_ids, categories, interval, end_time) do
    if System.monotonic_time(:millisecond) < end_time do
      # Send a random message
      conversation_id = Enum.random(conversation_ids)
      category = Enum.random(categories)
      
      RubberDuck.Status.broadcast(
        conversation_id,
        category,
        "Load test message at #{System.monotonic_time(:millisecond)}",
        %{load_test: true}
      )
      
      Process.sleep(interval)
      generate_messages(conversation_ids, categories, interval, end_time)
    end
  end
  
  defp capture_broadcaster_state do
    try do
      state = :sys.get_state(Broadcaster)
      %{
        queue_size: :queue.len(state.message_queue),
        batch_size: state.batch_size,
        flush_interval: state.flush_interval,
        processing: state.processing
      }
    catch
      _, _ -> %{error: "Unable to capture broadcaster state"}
    end
  end
  
  defp capture_all_channels do
    list_all_channels()
    |> Enum.map(&inspect_channel/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, info} -> info end)
  end
  
  defp capture_monitor_state do
    try do
      Monitor.health_status()
    catch
      _, _ -> %{error: "Unable to capture monitor state"}
    end
  end
  
  defp capture_optimizer_state do
    try do
      Optimizer.get_optimizations()
    catch
      _, _ -> %{error: "Unable to capture optimizer state"}
    end
  end
  
  defp capture_memory_stats do
    %{
      total: :erlang.memory(:total),
      processes: :erlang.memory(:processes),
      binary: :erlang.memory(:binary),
      ets: :erlang.memory(:ets),
      atom: :erlang.memory(:atom)
    }
  end
  
  defp check_broadcaster_health do
    try do
      state = :sys.get_state(Broadcaster)
      queue_size = :queue.len(state.message_queue)
      
      %{
        component: :broadcaster,
        healthy: queue_size < 10_000,
        details: %{queue_size: queue_size},
        message: if(queue_size > 10_000, do: "Queue size is very high", else: "OK")
      }
    catch
      _, _ ->
        %{component: :broadcaster, healthy: false, message: "Unable to check"}
    end
  end
  
  defp check_channel_health do
    channel_count = length(list_all_channels())
    
    %{
      component: :channels,
      healthy: channel_count < 10_000,
      details: %{count: channel_count},
      message: if(channel_count > 10_000, do: "Too many active channels", else: "OK")
    }
  end
  
  defp check_monitor_health do
    try do
      status = Monitor.health_status()
      
      %{
        component: :monitor,
        healthy: status.status == :healthy,
        details: status,
        message: "Status: #{status.status}"
      }
    catch
      _, _ ->
        %{component: :monitor, healthy: false, message: "Unable to check"}
    end
  end
  
  defp check_optimizer_health do
    try do
      _optimizations = Optimizer.get_optimizations()
      
      %{
        component: :optimizer,
        healthy: true,
        message: "OK"
      }
    catch
      _, _ ->
        %{component: :optimizer, healthy: false, message: "Unable to check"}
    end
  end
  
  defp check_memory_usage do
    memory_mb = :erlang.memory(:total) / 1_048_576
    threshold_mb = 1000  # 1GB threshold
    
    %{
      component: :memory,
      healthy: memory_mb < threshold_mb,
      details: %{usage_mb: round(memory_mb)},
      message: if(memory_mb > threshold_mb, do: "High memory usage", else: "OK")
    }
  end
  
  defp generate_recommendations(checks) do
    checks
    |> Enum.filter(& not &1.healthy)
    |> Enum.map(&generate_recommendation/1)
  end
  
  defp generate_recommendation(%{component: :broadcaster, details: %{queue_size: size}}) do
    "Consider increasing batch size or flush rate. Queue has #{size} messages."
  end
  
  defp generate_recommendation(%{component: :channels, details: %{count: count}}) do
    "High channel count (#{count}). Consider implementing channel cleanup."
  end
  
  defp generate_recommendation(%{component: :memory, details: %{usage_mb: usage}}) do
    "Memory usage is high (#{usage}MB). Check for memory leaks."
  end
  
  defp generate_recommendation(%{component: component}) do
    "Check #{component} component health"
  end
  
  # Helper functions to interact with channel registry
  
  defp get_channel_state(conversation_id) do
    case :global.whereis_name({:status_channel, conversation_id}) do
      :undefined ->
        {:error, :channel_not_found}
      
      pid ->
        try do
          {:ok, :sys.get_state(pid)}
        catch
          _, _ -> {:error, :unable_to_get_state}
        end
    end
  end
  
  defp list_all_channels do
    # Get all registered channel names from :global
    :global.registered_names()
    |> Enum.filter(fn
      {:status_channel, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:status_channel, conversation_id} -> conversation_id end)
  end
end