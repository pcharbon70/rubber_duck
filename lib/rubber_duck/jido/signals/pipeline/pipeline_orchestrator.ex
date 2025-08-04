defmodule RubberDuck.Jido.Signals.Pipeline.PipelineOrchestrator do
  @moduledoc """
  Orchestrates the signal processing pipeline.
  
  This module coordinates the flow of signals through transformers
  and monitors, ensuring proper ordering, error handling, and
  CloudEvents compliance throughout the pipeline.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Jido.Signals.Pipeline.{
    SignalNormalizer,
    SignalEnricher,
    SchemaValidator,
    SecurityFilter,
    DeliveryTracker,
    MetricsCollector
  }
  
  @default_transformers [
    SignalNormalizer,
    SignalEnricher,
    SchemaValidator,
    SecurityFilter
  ]
  
  @default_monitors [
    DeliveryTracker,
    MetricsCollector
  ]
  
  # Client API
  
  @doc """
  Starts the pipeline orchestrator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Processes a signal through the pipeline.
  """
  @spec process(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def process(signal, opts \\ []) do
    GenServer.call(__MODULE__, {:process, signal, opts}, 10_000)
  end
  
  @doc """
  Processes multiple signals in batch.
  """
  @spec process_batch([map()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def process_batch(signals, opts \\ []) do
    GenServer.call(__MODULE__, {:process_batch, signals, opts}, 30_000)
  end
  
  @doc """
  Gets pipeline configuration.
  """
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end
  
  @doc """
  Updates pipeline configuration.
  """
  def update_config(config) do
    GenServer.call(__MODULE__, {:update_config, config})
  end
  
  @doc """
  Gets pipeline health status.
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end
  
  @doc """
  Gets pipeline metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Start monitors
    start_monitors(Keyword.get(opts, :monitors, @default_monitors))
    
    state = %{
      transformers: Keyword.get(opts, :transformers, @default_transformers),
      monitors: Keyword.get(opts, :monitors, @default_monitors),
      config: build_config(opts),
      stats: %{
        processed: 0,
        errors: 0,
        skipped: 0,
        total_time: 0
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:process, signal, opts}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Merge options with config
    pipeline_opts = Map.merge(state.config, Map.new(opts))
    
    # Process through transformers
    result = process_through_pipeline(signal, state.transformers, pipeline_opts, state.monitors)
    
    # Update stats
    duration = System.monotonic_time(:microsecond) - start_time
    new_state = update_stats(state, result, duration)
    
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:process_batch, signals, opts}, _from, state) do
    # Process signals in parallel with controlled concurrency
    max_concurrency = Map.get(state.config, :max_concurrency, 10)
    pipeline_opts = Map.merge(state.config, Map.new(opts))
    
    results = signals
      |> Enum.chunk_every(max_concurrency)
      |> Enum.flat_map(fn chunk ->
        chunk
        |> Enum.map(fn signal ->
          Task.async(fn ->
            process_through_pipeline(signal, state.transformers, pipeline_opts, state.monitors)
          end)
        end)
        |> Task.await_many(5_000)
      end)
    
    # Separate successes and failures
    {successes, failures} = Enum.split_with(results, fn
      {:ok, _} -> true
      _ -> false
    end)
    
    if Enum.empty?(failures) do
      processed_signals = Enum.map(successes, fn {:ok, sig} -> sig end)
      {:reply, {:ok, processed_signals}, state}
    else
      {:reply, {:error, {:batch_processing_failed, failures}}, state}
    end
  end
  
  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end
  
  @impl true
  def handle_call({:update_config, config}, _from, state) do
    new_config = Map.merge(state.config, config)
    {:reply, :ok, %{state | config: new_config}}
  end
  
  @impl true
  def handle_call(:health_check, _from, state) do
    # Check health of all monitors
    monitor_health = Enum.map(state.monitors, fn monitor ->
      try do
        {status, details} = monitor.check_health()
        {monitor, status, details}
      rescue
        _ -> {monitor, :unknown, %{}}
      end
    end)
    
    # Determine overall health
    overall_status = determine_overall_health(monitor_health, state.stats)
    
    health_info = %{
      status: overall_status,
      monitors: monitor_health,
      stats: state.stats,
      config: state.config
    }
    
    {:reply, health_info, state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    # Collect metrics from all monitors
    monitor_metrics = Enum.reduce(state.monitors, %{}, fn monitor, acc ->
      try do
        metrics = monitor.get_current_metrics()
        Map.put(acc, monitor, metrics)
      rescue
        _ -> acc
      end
    end)
    
    metrics = %{
      pipeline_stats: state.stats,
      monitors: monitor_metrics,
      average_processing_time: calculate_average_time(state.stats)
    }
    
    {:reply, metrics, state}
  end
  
  # Private functions
  
  defp start_monitors(monitors) do
    Enum.each(monitors, fn monitor ->
      case monitor.start_link() do
        {:ok, _pid} ->
          Logger.info("Started monitor: #{inspect(monitor)}")
        {:error, {:already_started, _}} ->
          Logger.debug("Monitor already running: #{inspect(monitor)}")
        error ->
          Logger.error("Failed to start monitor #{inspect(monitor)}: #{inspect(error)}")
      end
    end)
  end
  
  defp build_config(opts) do
    %{
      max_concurrency: Keyword.get(opts, :max_concurrency, 10),
      strict_validation: Keyword.get(opts, :strict_validation, false),
      security_enabled: Keyword.get(opts, :security_enabled, true),
      enrichment_ttl: Keyword.get(opts, :enrichment_ttl, :timer.minutes(5)),
      emit_telemetry: Keyword.get(opts, :emit_telemetry, true)
    }
  end
  
  defp process_through_pipeline(signal, transformers, opts, monitors) do
    # Validate signal is proper Jido signal
    with {:ok, validated_signal} <- ensure_jido_signal(signal),
         # Process through transformers
         {:ok, transformed} <- apply_transformers(validated_signal, transformers, opts),
         # Notify monitors
         :ok <- notify_monitors(transformed, monitors, :success) do
      
      # Emit telemetry
      if Map.get(opts, :emit_telemetry, true) do
        emit_pipeline_telemetry(transformed, :success)
      end
      
      {:ok, transformed}
    else
      {:error, reason} = error ->
        notify_monitors(signal, monitors, :error)
        
        if Map.get(opts, :emit_telemetry, true) do
          emit_pipeline_telemetry(signal, :error)
        end
        
        Logger.error("Pipeline processing failed: #{inspect(reason)}")
        error
    end
  end
  
  defp ensure_jido_signal(signal) do
    case Jido.Signal.new(signal) do
      {:ok, jido_signal} ->
        # Convert back to map for processing
        {:ok, Map.from_struct(jido_signal)}
      {:error, reason} ->
        {:error, {:invalid_jido_signal, reason}}
    end
  end
  
  defp apply_transformers(signal, [], _opts), do: {:ok, signal}
  defp apply_transformers(signal, [transformer | rest], opts) do
    case transformer.apply(signal, Keyword.new(opts)) do
      {:ok, transformed} ->
        apply_transformers(transformed, rest, opts)
      {:skip, _reason} ->
        # Skip this transformer, continue with next
        apply_transformers(signal, rest, opts)
      {:error, _reason} = error ->
        error
    end
  end
  
  defp notify_monitors(signal, monitors, status) do
    metadata = %{
      status: status,
      timestamp: DateTime.utc_now(),
      processing_time: Map.get(signal, :_processing_time)
    }
    
    Enum.each(monitors, fn monitor ->
      try do
        monitor.observe_signal(signal, metadata)
      rescue
        error ->
          Logger.error("Monitor notification failed: #{inspect(error)}")
      end
    end)
    
    :ok
  end
  
  defp emit_pipeline_telemetry(signal, status) do
    :telemetry.execute(
      [:rubber_duck, :signal, :pipeline],
      %{
        processing_time: Map.get(signal, :_processing_time, 0)
      },
      %{
        status: status,
        signal_type: Map.get(signal, :type),
        signal_category: Map.get(signal, :category)
      }
    )
  end
  
  defp update_stats(state, {:ok, _}, duration) do
    update_in(state, [:stats], fn stats ->
      stats
      |> Map.update!(:processed, &(&1 + 1))
      |> Map.update!(:total_time, &(&1 + duration))
    end)
  end
  
  defp update_stats(state, {:error, _}, duration) do
    update_in(state, [:stats], fn stats ->
      stats
      |> Map.update!(:errors, &(&1 + 1))
      |> Map.update!(:total_time, &(&1 + duration))
    end)
  end
  
  defp calculate_average_time(%{processed: 0}), do: 0
  defp calculate_average_time(%{processed: count, total_time: time}) do
    round(time / count)
  end
  
  defp determine_overall_health(monitor_health, stats) do
    unhealthy_count = Enum.count(monitor_health, fn {_, status, _} -> status == :unhealthy end)
    degraded_count = Enum.count(monitor_health, fn {_, status, _} -> status == :degraded end)
    
    error_rate = if stats.processed > 0 do
      stats.errors / (stats.processed + stats.errors) * 100
    else
      0
    end
    
    cond do
      unhealthy_count > 0 -> :unhealthy
      degraded_count > 1 -> :degraded
      error_rate > 10.0 -> :unhealthy
      error_rate > 5.0 -> :degraded
      true -> :healthy
    end
  end
end