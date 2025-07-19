defmodule RubberDuck.Status.Optimizer do
  @moduledoc """
  Dynamic optimization engine for the Status Broadcasting System.
  
  Implements adaptive strategies to optimize performance based on
  current system load and metrics.
  
  ## Optimization Strategies
  
  - Dynamic batch sizing based on queue depth and throughput
  - Adaptive flush intervals based on message rate
  - Message compression for large payloads
  - Topic sharding for improved scalability
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Status.{Monitor, Broadcaster}
  
  @type optimization :: :batch_size | :flush_interval | :compression | :sharding
  
  @type state :: %{
    optimizations: %{optimization() => any()},
    metrics_history: list(map()),
    last_optimization: DateTime.t(),
    enabled: boolean()
  }
  
  # Default configuration
  @default_batch_size 10
  @default_flush_interval 100
  @min_batch_size 5
  @max_batch_size 100
  @min_flush_interval 50
  @max_flush_interval 500
  @compression_threshold 1024  # bytes
  
  # Optimization intervals
  @optimization_interval 60_000  # 1 minute
  
  # Client API
  
  @doc """
  Starts the optimizer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets current optimization settings.
  """
  def get_optimizations do
    GenServer.call(__MODULE__, :get_optimizations)
  end
  
  @doc """
  Enables or disables automatic optimization.
  """
  def set_enabled(enabled) do
    GenServer.cast(__MODULE__, {:set_enabled, enabled})
  end
  
  @doc """
  Manually triggers optimization.
  """
  def optimize_now do
    GenServer.cast(__MODULE__, :optimize_now)
  end
  
  @doc """
  Updates a specific optimization setting.
  """
  def set_optimization(type, value) do
    GenServer.call(__MODULE__, {:set_optimization, type, value})
  end
  
  @doc """
  Determines if a message should be compressed based on size.
  """
  def should_compress?(message) when is_binary(message) do
    byte_size(message) > @compression_threshold
  end
  def should_compress?(message) do
    message
    |> :erlang.term_to_binary()
    |> byte_size()
    |> Kernel.>(@compression_threshold)
  end
  
  @doc """
  Compresses a message for transmission.
  """
  def compress_message(message) do
    binary = :erlang.term_to_binary(message)
    compressed = :zlib.compress(binary)
    
    %{
      compressed: true,
      data: Base.encode64(compressed),
      original_size: byte_size(binary),
      compressed_size: byte_size(compressed)
    }
  end
  
  @doc """
  Decompresses a message.
  """
  def decompress_message(%{compressed: true, data: data}) do
    data
    |> Base.decode64!()
    |> :zlib.uncompress()
    |> :erlang.binary_to_term()
  end
  def decompress_message(message), do: message
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Schedule periodic optimization
    schedule_optimization()
    
    state = %{
      optimizations: %{
        batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
        flush_interval: Keyword.get(opts, :flush_interval, @default_flush_interval),
        compression: Keyword.get(opts, :compression, true),
        sharding: Keyword.get(opts, :sharding, false)
      },
      metrics_history: [],
      last_optimization: DateTime.utc_now(),
      enabled: Keyword.get(opts, :enabled, true)
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_optimizations, _from, state) do
    {:reply, state.optimizations, state}
  end
  
  @impl true
  def handle_call({:set_optimization, type, value}, _from, state) do
    new_optimizations = Map.put(state.optimizations, type, value)
    
    # Apply the optimization
    apply_optimization(type, value)
    
    {:reply, :ok, %{state | optimizations: new_optimizations}}
  end
  
  @impl true
  def handle_cast({:set_enabled, enabled}, state) do
    {:noreply, %{state | enabled: enabled}}
  end
  
  @impl true
  def handle_cast(:optimize_now, state) do
    new_state = perform_optimization(state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:optimize, state) do
    new_state = 
      if state.enabled do
        perform_optimization(state)
      else
        state
      end
    
    schedule_optimization()
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp perform_optimization(state) do
    # Get current metrics
    metrics = Monitor.metrics_summary()
    
    # Store metrics history
    metrics_entry = %{
      timestamp: DateTime.utc_now(),
      metrics: metrics
    }
    
    new_history = 
      [metrics_entry | state.metrics_history]
      |> Enum.take(10)  # Keep last 10 entries
    
    # Calculate new optimizations
    new_optimizations = 
      state.optimizations
      |> optimize_batch_size(metrics)
      |> optimize_flush_interval(metrics)
      |> optimize_compression(metrics)
      |> optimize_sharding(metrics)
    
    # Apply optimizations if changed
    apply_optimizations(state.optimizations, new_optimizations)
    
    # Log optimization results
    log_optimization_changes(state.optimizations, new_optimizations)
    
    %{state | 
      optimizations: new_optimizations,
      metrics_history: new_history,
      last_optimization: DateTime.utc_now()
    }
  end
  
  defp optimize_batch_size(optimizations, metrics) do
    queue_stats = Map.get(metrics, :queue_depth, %{})
    throughput_stats = Map.get(metrics, :throughput, %{})
    
    current_batch_size = optimizations.batch_size
    avg_queue_depth = Map.get(queue_stats, :average, 0)
    current_throughput = Map.get(throughput_stats, :current, 0)
    
    # Dynamic batch sizing logic
    new_batch_size = cond do
      # High queue depth - increase batch size
      avg_queue_depth > 1000 ->
        min(current_batch_size * 1.5, @max_batch_size)
      
      # Low queue depth but high throughput - slightly increase
      avg_queue_depth < 100 and current_throughput > 500 ->
        min(current_batch_size * 1.1, @max_batch_size)
      
      # Very low queue depth - decrease batch size for lower latency
      avg_queue_depth < 10 ->
        max(current_batch_size * 0.8, @min_batch_size)
      
      # Default - no change
      true ->
        current_batch_size
    end
    
    Map.put(optimizations, :batch_size, round(new_batch_size))
  end
  
  defp optimize_flush_interval(optimizations, metrics) do
    throughput_stats = Map.get(metrics, :throughput, %{})
    latency_stats = Map.get(metrics, :latency, %{})
    
    current_interval = optimizations.flush_interval
    avg_throughput = Map.get(throughput_stats, :average, 0)
    p95_latency = Map.get(latency_stats, :p95, 0)
    
    # Adaptive flush interval logic
    new_interval = cond do
      # High throughput - decrease interval for faster processing
      avg_throughput > 1000 ->
        max(current_interval * 0.8, @min_flush_interval)
      
      # High latency - decrease interval to reduce buffering
      p95_latency > 200 ->
        max(current_interval * 0.9, @min_flush_interval)
      
      # Low throughput - increase interval to batch more
      avg_throughput < 100 ->
        min(current_interval * 1.2, @max_flush_interval)
      
      # Default - no change
      true ->
        current_interval
    end
    
    Map.put(optimizations, :flush_interval, round(new_interval))
  end
  
  defp optimize_compression(optimizations, metrics) do
    # Enable compression if error rate is low and latency is acceptable
    error_stats = Map.get(metrics, :error_rate, %{})
    latency_stats = Map.get(metrics, :latency, %{})
    
    error_rate = Map.get(error_stats, :current, 0)
    avg_latency = Map.get(latency_stats, :average, 0)
    
    # Only enable compression if system is stable
    compression_enabled = error_rate < 0.01 and avg_latency < 100
    
    Map.put(optimizations, :compression, compression_enabled)
  end
  
  defp optimize_sharding(optimizations, metrics) do
    # Enable sharding for very high throughput scenarios
    throughput_stats = Map.get(metrics, :throughput, %{})
    avg_throughput = Map.get(throughput_stats, :average, 0)
    
    # Enable sharding if throughput exceeds threshold
    sharding_enabled = avg_throughput > 5000
    
    Map.put(optimizations, :sharding, sharding_enabled)
  end
  
  defp apply_optimizations(old_opts, new_opts) do
    # Apply batch size change
    if old_opts.batch_size != new_opts.batch_size do
      apply_optimization(:batch_size, new_opts.batch_size)
    end
    
    # Apply flush interval change
    if old_opts.flush_interval != new_opts.flush_interval do
      apply_optimization(:flush_interval, new_opts.flush_interval)
    end
    
    # Apply compression change
    if old_opts.compression != new_opts.compression do
      apply_optimization(:compression, new_opts.compression)
    end
    
    # Apply sharding change
    if old_opts.sharding != new_opts.sharding do
      apply_optimization(:sharding, new_opts.sharding)
    end
  end
  
  defp apply_optimization(:batch_size, value) do
    # Update broadcaster configuration
    GenServer.cast(Broadcaster, {:update_config, :batch_size, value})
  end
  
  defp apply_optimization(:flush_interval, value) do
    # Update broadcaster configuration
    GenServer.cast(Broadcaster, {:update_config, :flush_interval, value})
  end
  
  defp apply_optimization(:compression, value) do
    # Update global compression setting
    :persistent_term.put({__MODULE__, :compression_enabled}, value)
  end
  
  defp apply_optimization(:sharding, value) do
    # Update sharding configuration
    :persistent_term.put({__MODULE__, :sharding_enabled}, value)
  end
  
  defp log_optimization_changes(old_opts, new_opts) do
    changes = 
      [:batch_size, :flush_interval, :compression, :sharding]
      |> Enum.filter(fn key -> Map.get(old_opts, key) != Map.get(new_opts, key) end)
      |> Enum.map(fn key ->
        "#{key}: #{Map.get(old_opts, key)} -> #{Map.get(new_opts, key)}"
      end)
    
    if length(changes) > 0 do
      Logger.info("Status optimizer applied changes: #{Enum.join(changes, ", ")}")
      
      # Emit telemetry for optimization changes
      :telemetry.execute(
        [:rubber_duck, :status, :optimizer, :adjusted],
        %{change_count: length(changes)},
        %{changes: changes}
      )
    end
  end
  
  defp schedule_optimization do
    Process.send_after(self(), :optimize, @optimization_interval)
  end
  
  @doc """
  Gets the topic for a message based on sharding configuration.
  """
  def get_topic(conversation_id, category) do
    base_topic = "status:#{conversation_id}"
    
    if :persistent_term.get({__MODULE__, :sharding_enabled}, false) do
      # Simple sharding based on conversation_id hash
      shard = :erlang.phash2(conversation_id, 4)  # 4 shards
      "#{base_topic}:#{category}:shard#{shard}"
    else
      "#{base_topic}:#{category}"
    end
  end
end