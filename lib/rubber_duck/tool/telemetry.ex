defmodule RubberDuck.Tool.Telemetry do
  @moduledoc """
  Telemetry integration for tool execution monitoring.
  
  Provides standardized telemetry events and measurements for the tool
  execution system, enabling integration with various monitoring solutions.
  """
  
  require Logger
  
  @doc """
  Emits a tool execution start event.
  """
  def execute_start(tool_name, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :tool, :execution, :start],
      %{system_time: System.system_time()},
      Map.merge(metadata, %{tool: tool_name})
    )
  end
  
  @doc """
  Emits a tool execution stop event.
  """
  def execute_stop(tool_name, duration, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :tool, :execution, :stop],
      %{duration: duration},
      Map.merge(metadata, %{tool: tool_name})
    )
  end
  
  @doc """
  Emits a tool execution exception event.
  """
  def execute_exception(tool_name, duration, kind, reason, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :tool, :execution, :exception],
      %{duration: duration},
      Map.merge(metadata, %{
        tool: tool_name,
        kind: kind,
        reason: inspect(reason)
      })
    )
  end
  
  @doc """
  Emits a validation event.
  """
  def validation(tool_name, duration, valid?, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :tool, :validation, :stop],
      %{duration: duration},
      Map.merge(metadata, %{
        tool: tool_name,
        valid: valid?
      })
    )
  end
  
  @doc """
  Emits an authorization event.
  """
  def authorization(tool_name, duration, authorized?, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :tool, :authorization, :stop],
      %{duration: duration},
      Map.merge(metadata, %{
        tool: tool_name,
        authorized: authorized?
      })
    )
  end
  
  @doc """
  Emits a sandbox execution event.
  """
  def sandbox_execution(tool_name, duration, sandbox_level, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :tool, :sandbox, :execution],
      %{duration: duration},
      Map.merge(metadata, %{
        tool: tool_name,
        sandbox_level: sandbox_level
      })
    )
  end
  
  @doc """
  Emits a sandbox violation event.
  """
  def sandbox_violation(tool_name, violation_type, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :tool, :sandbox, :violation],
      %{count: 1},
      Map.merge(metadata, %{
        tool: tool_name,
        violation_type: violation_type
      })
    )
  end
  
  @doc """
  Emits a result processing event.
  """
  def result_processed(tool_name, processing_time, output_size, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :tool, :result, :processed],
      %{
        processing_time: processing_time,
        output_size: output_size
      },
      Map.merge(metadata, %{tool: tool_name})
    )
  end
  
  @doc """
  Emits a cache operation event.
  """
  def cache_operation(tool_name, operation, status, metadata \\ %{}) do
    :telemetry.execute(
      [:rubber_duck, :tool, :result, :cached],
      %{count: 1},
      Map.merge(metadata, %{
        tool: tool_name,
        operation: operation,
        status: status
      })
    )
  end
  
  @doc """
  Sets up default telemetry reporters.
  """
  def setup_default_reporters do
    # Console reporter for development
    if Application.get_env(:rubber_duck, :env) == :dev do
      attach_console_reporter()
    end
    
    # Metrics reporter
    attach_metrics_reporter()
    
    # Log reporter for errors
    attach_error_reporter()
  end
  
  @doc """
  Attaches a custom telemetry handler.
  """
  def attach_handler(handler_id, events, handler_fun, config \\ nil) do
    :telemetry.attach_many(handler_id, events, handler_fun, config)
  end
  
  @doc """
  Detaches a telemetry handler.
  """
  def detach_handler(handler_id) do
    :telemetry.detach(handler_id)
  end
  
  @doc """
  Lists all tool telemetry events.
  """
  def list_events do
    [
      # Execution events
      [:rubber_duck, :tool, :execution, :start],
      [:rubber_duck, :tool, :execution, :stop],
      [:rubber_duck, :tool, :execution, :exception],
      
      # Validation events
      [:rubber_duck, :tool, :validation, :start],
      [:rubber_duck, :tool, :validation, :stop],
      
      # Authorization events
      [:rubber_duck, :tool, :authorization, :start],
      [:rubber_duck, :tool, :authorization, :stop],
      
      # Sandbox events
      [:rubber_duck, :tool, :sandbox, :execution],
      [:rubber_duck, :tool, :sandbox, :violation],
      
      # Result processing events
      [:rubber_duck, :tool, :result, :processed],
      [:rubber_duck, :tool, :result, :cached],
      
      # Resource events
      [:rubber_duck, :tool, :resource, :limit_exceeded],
      [:rubber_duck, :tool, :resource, :usage],
      
      # Error events
      [:rubber_duck, :tool, :error, :validation_failed],
      [:rubber_duck, :tool, :error, :authorization_failed],
      [:rubber_duck, :tool, :error, :execution_failed]
    ]
  end
  
  # Private functions
  
  defp attach_console_reporter do
    events = [
      [:rubber_duck, :tool, :execution, :stop],
      [:rubber_duck, :tool, :execution, :exception]
    ]
    
    :telemetry.attach_many(
      "rubber-duck-console-reporter",
      events,
      &handle_console_event/4,
      nil
    )
  end
  
  defp attach_metrics_reporter do
    events = list_events()
    
    :telemetry.attach_many(
      "rubber-duck-metrics-reporter",
      events,
      &handle_metrics_event/4,
      nil
    )
  end
  
  defp attach_error_reporter do
    events = [
      [:rubber_duck, :tool, :execution, :exception],
      [:rubber_duck, :tool, :error, :validation_failed],
      [:rubber_duck, :tool, :error, :authorization_failed],
      [:rubber_duck, :tool, :error, :execution_failed]
    ]
    
    :telemetry.attach_many(
      "rubber-duck-error-reporter",
      events,
      &handle_error_event/4,
      nil
    )
  end
  
  defp handle_console_event(event_name, measurements, metadata, _config) do
    case event_name do
      [:rubber_duck, :tool, :execution, :stop] ->
        IO.puts("[TELEMETRY] Tool #{metadata.tool} executed in #{measurements.duration}ms")
      
      [:rubber_duck, :tool, :execution, :exception] ->
        IO.puts("[TELEMETRY] Tool #{metadata.tool} failed: #{metadata.kind} - #{metadata.reason}")
      
      _ ->
        :ok
    end
  end
  
  defp handle_metrics_event(event_name, measurements, metadata, _config) do
    # Forward to monitoring system
    case event_name do
      [:rubber_duck, :tool | _rest] ->
        RubberDuck.Tool.Monitoring.record_metric(
          format_metric_name(event_name),
          :counter,
          1,
          metadata
        )
        
        # Record measurements as gauges
        Enum.each(measurements, fn {key, value} ->
          RubberDuck.Tool.Monitoring.record_metric(
            "#{format_metric_name(event_name)}.#{key}",
            :gauge,
            value,
            metadata
          )
        end)
      
      _ ->
        :ok
    end
  rescue
    error ->
      Logger.error("Failed to record metric: #{inspect(error)}")
  end
  
  defp handle_error_event(event_name, measurements, metadata, _config) do
    Logger.error("Tool error event: #{inspect(event_name)}", 
      measurements: measurements,
      metadata: metadata
    )
  end
  
  defp format_metric_name(event_name) do
    event_name
    |> Enum.join(".")
    |> String.replace("rubber_duck.", "")
  end
end

defmodule RubberDuck.Tool.Telemetry.Poller do
  @moduledoc """
  Periodic telemetry measurements for tool execution system.
  """
  
  use GenServer
  
  @polling_interval 10_000 # 10 seconds
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    schedule_poll()
    {:ok, %{}}
  end
  
  @impl true
  def handle_info(:poll, state) do
    emit_measurements()
    schedule_poll()
    {:noreply, state}
  end
  
  defp emit_measurements do
    # Memory measurements
    memory = :erlang.memory()
    :telemetry.execute(
      [:rubber_duck, :tool, :system, :memory],
      %{
        total: memory[:total],
        processes: memory[:processes],
        ets: memory[:ets],
        binary: memory[:binary]
      },
      %{}
    )
    
    # Process measurements
    :telemetry.execute(
      [:rubber_duck, :tool, :system, :processes],
      %{
        count: length(:erlang.processes()),
        limit: :erlang.system_info(:process_limit)
      },
      %{}
    )
    
    # IO measurements
    {{:input, input}, {:output, output}} = :erlang.statistics(:io)
    :telemetry.execute(
      [:rubber_duck, :tool, :system, :io],
      %{
        input_bytes: input,
        output_bytes: output
      },
      %{}
    )
    
    # Cache measurements
    cache_stats = RubberDuck.Cache.ETS.stats()
    if not Map.has_key?(cache_stats, :error) do
      :telemetry.execute(
        [:rubber_duck, :tool, :cache, :stats],
        %{
          entries: cache_stats.total_entries,
          memory_words: cache_stats.memory_usage_words
        },
        %{}
      )
    end
    
    # Storage measurements
    storage_stats = RubberDuck.Storage.FileSystem.stats()
    if not Map.has_key?(storage_stats, :error) do
      :telemetry.execute(
        [:rubber_duck, :tool, :storage, :stats],
        %{
          files: storage_stats.total_files,
          size_bytes: storage_stats.total_size_bytes
        },
        %{}
      )
    end
  rescue
    error ->
      Logger.error("Failed to emit telemetry measurements: #{inspect(error)}")
  end
  
  defp schedule_poll do
    Process.send_after(self(), :poll, @polling_interval)
  end
end