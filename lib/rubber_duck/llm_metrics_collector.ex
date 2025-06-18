defmodule RubberDuck.LLMMetricsCollector do
  @moduledoc """
  Specialized metrics collector for LLM operations and performance tracking.
  
  Integrates with the existing EventBroadcaster infrastructure to collect,
  aggregate, and analyze LLM-specific performance metrics including:
  - Provider performance comparisons
  - Token usage and cost tracking
  - Response latency and quality metrics
  - Cache hit rates for LLM responses
  - Error rates and failure patterns
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.EventBroadcasting.EventBroadcaster
  alias RubberDuck.MetricsCollector
  
  @default_window_size :timer.minutes(5)
  @retention_windows [:timer.minutes(1), :timer.minutes(5), :timer.minutes(15), :timer.hours(1), :timer.hours(24)]
  @metric_types [:counter, :gauge, :histogram, :summary]
  
  # LLM-specific metric definitions
  @llm_metrics %{
    # Request metrics
    "llm.requests.total" => %{type: :counter, description: "Total LLM requests"},
    "llm.requests.success" => %{type: :counter, description: "Successful LLM requests"},
    "llm.requests.failure" => %{type: :counter, description: "Failed LLM requests"},
    "llm.requests.timeout" => %{type: :counter, description: "Timed out LLM requests"},
    
    # Latency metrics
    "llm.latency.request" => %{type: :histogram, description: "Request latency distribution"},
    "llm.latency.first_token" => %{type: :histogram, description: "Time to first token"},
    "llm.latency.streaming" => %{type: :histogram, description: "Streaming response latency"},
    
    # Token usage metrics
    "llm.tokens.input" => %{type: :counter, description: "Input tokens consumed"},
    "llm.tokens.output" => %{type: :counter, description: "Output tokens generated"},
    "llm.tokens.total" => %{type: :counter, description: "Total tokens used"},
    "llm.tokens.rate" => %{type: :gauge, description: "Current token usage rate"},
    
    # Cost metrics
    "llm.cost.request" => %{type: :counter, description: "Per-request cost accumulator"},
    "llm.cost.total" => %{type: :gauge, description: "Total accumulated cost"},
    "llm.cost.rate" => %{type: :gauge, description: "Cost per minute"},
    
    # Provider metrics
    "llm.provider.availability" => %{type: :gauge, description: "Provider availability percentage"},
    "llm.provider.health_score" => %{type: :gauge, description: "Provider health score"},
    "llm.provider.rate_limit" => %{type: :gauge, description: "Rate limit utilization"},
    
    # Cache metrics
    "llm.cache.hits" => %{type: :counter, description: "LLM cache hits"},
    "llm.cache.misses" => %{type: :counter, description: "LLM cache misses"},
    "llm.cache.evictions" => %{type: :counter, description: "LLM cache evictions"},
    "llm.cache.hit_rate" => %{type: :gauge, description: "LLM cache hit rate"},
    
    # Quality metrics
    "llm.quality.response_length" => %{type: :histogram, description: "Response length distribution"},
    "llm.quality.context_usage" => %{type: :histogram, description: "Context window utilization"},
    "llm.quality.deduplication_rate" => %{type: :gauge, description: "Response deduplication rate"},
    
    # Error metrics
    "llm.errors.api" => %{type: :counter, description: "API-level errors"},
    "llm.errors.validation" => %{type: :counter, description: "Request validation errors"},
    "llm.errors.circuit_breaker" => %{type: :counter, description: "Circuit breaker activations"},
    "llm.errors.quota_exceeded" => %{type: :counter, description: "Quota exceeded errors"}
  }
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    window_size = Keyword.get(opts, :window_size, @default_window_size)
    
    # Subscribe to LLM-related events
    EventBroadcaster.subscribe("llm.*")
    EventBroadcaster.subscribe("cache.llm.*")
    EventBroadcaster.subscribe("provider.*")
    EventBroadcaster.subscribe("transaction.llm.*")
    
    # Initialize metric storage
    :ets.new(:llm_metrics, [:named_table, :public, :set])
    :ets.new(:llm_metric_windows, [:named_table, :public, :bag])
    
    # Initialize all metrics
    initialize_metrics()
    
    # Schedule periodic aggregation
    :timer.send_interval(window_size, self(), :aggregate_metrics)
    
    Logger.info("LLM Metrics Collector started with #{length(Map.keys(@llm_metrics))} metrics")
    
    {:ok, %{
      window_size: window_size,
      last_aggregation: :os.system_time(:millisecond),
      active_requests: %{},
      provider_status: %{}
    }}
  end
  
  @impl true
  def handle_info({:event, topic, event_data}, state) do
    process_llm_event(topic, event_data, state)
    {:noreply, state}
  end
  
  def handle_info(:aggregate_metrics, state) do
    aggregate_window_metrics()
    cleanup_old_windows()
    {:noreply, %{state | last_aggregation: :os.system_time(:millisecond)}}
  end
  
  # Public API
  
  @doc """
  Record an LLM request start
  """
  def record_request_start(request_id, provider, model, metadata \\ %{}) do
    timestamp = :os.system_time(:millisecond)
    
    # Increment request counter
    increment_metric("llm.requests.total", 1, %{provider: provider, model: model})
    
    # Store request start time for latency calculation
    :ets.insert(:llm_metrics, {
      {:request_start, request_id}, 
      timestamp, 
      %{provider: provider, model: model, metadata: metadata}
    })
  end
  
  @doc """
  Record an LLM request completion
  """
  def record_request_completion(request_id, result, response_data \\ %{}) do
    timestamp = :os.system_time(:millisecond)
    
    case :ets.lookup(:llm_metrics, {:request_start, request_id}) do
      [{_, start_time, request_metadata}] ->
        latency = timestamp - start_time
        provider = request_metadata.provider
        model = request_metadata.model
        
        # Record completion metrics
        record_completion_metrics(result, provider, model, latency, response_data)
        
        # Clean up request tracking
        :ets.delete(:llm_metrics, {:request_start, request_id})
      
      [] ->
        Logger.warning("Request completion recorded for unknown request: #{request_id}")
    end
  end
  
  @doc """
  Record token usage for a request
  """
  def record_token_usage(provider, model, input_tokens, output_tokens, cost \\ 0.0) do
    tags = %{provider: provider, model: model}
    
    increment_metric("llm.tokens.input", input_tokens, tags)
    increment_metric("llm.tokens.output", output_tokens, tags)
    increment_metric("llm.tokens.total", input_tokens + output_tokens, tags)
    increment_metric("llm.cost.request", cost, tags)
    
    # Update rate gauges
    update_token_rates(provider, model)
  end
  
  @doc """
  Record cache operation
  """
  def record_cache_operation(operation, result, metadata \\ %{}) do
    tags = Map.merge(%{operation: operation}, metadata)
    
    case {operation, result} do
      {:get, :hit} ->
        increment_metric("llm.cache.hits", 1, tags)
      {:get, :miss} ->
        increment_metric("llm.cache.misses", 1, tags)
      {:evict, _} ->
        increment_metric("llm.cache.evictions", 1, tags)
      _ ->
        :ok
    end
    
    # Update hit rate
    update_cache_hit_rate()
  end
  
  @doc """
  Record provider status update
  """
  def record_provider_status(provider, status_data) do
    tags = %{provider: provider}
    
    set_gauge("llm.provider.availability", status_data.availability || 0, tags)
    set_gauge("llm.provider.health_score", status_data.health_score || 0, tags)
    set_gauge("llm.provider.rate_limit", status_data.rate_limit_utilization || 0, tags)
  end
  
  @doc """
  Get current metrics summary
  """
  def get_metrics_summary(opts \\ []) do
    window = Keyword.get(opts, :window, @default_window_size)
    provider = Keyword.get(opts, :provider)
    
    current_time = :os.system_time(:millisecond)
    since = current_time - window
    
    metrics = get_metrics_in_window(since, current_time)
    
    metrics
    |> filter_by_provider(provider)
    |> aggregate_summary()
  end
  
  @doc """
  Get provider performance comparison
  """
  def get_provider_comparison(opts \\ []) do
    window = Keyword.get(opts, :window, @default_window_size)
    providers = get_active_providers()
    
    Enum.map(providers, fn provider ->
      metrics = get_metrics_summary(window: window, provider: provider)
      
      %{
        provider: provider,
        request_count: get_metric_value(metrics, "llm.requests.total", 0),
        success_rate: calculate_success_rate(metrics),
        average_latency: get_metric_value(metrics, "llm.latency.request.avg", 0),
        total_cost: get_metric_value(metrics, "llm.cost.total", 0.0),
        tokens_per_second: get_metric_value(metrics, "llm.tokens.rate", 0),
        health_score: get_metric_value(metrics, "llm.provider.health_score", 0)
      }
    end)
    |> Enum.sort_by(& &1.health_score, :desc)
  end
  
  @doc """
  Get cost analysis for a time period
  """
  def get_cost_analysis(opts \\ []) do
    window = Keyword.get(opts, :window, @default_window_size)
    breakdown_by = Keyword.get(opts, :breakdown_by, :provider)
    
    metrics = get_metrics_summary(window: window)
    
    %{
      total_cost: get_metric_value(metrics, "llm.cost.total", 0.0),
      cost_per_request: calculate_cost_per_request(metrics),
      cost_per_token: calculate_cost_per_token(metrics),
      cost_breakdown: get_cost_breakdown(breakdown_by, window),
      cost_trend: get_cost_trend(window)
    }
  end
  
  # Private Functions
  
  defp process_llm_event(topic, event_data, _state) do
    case topic do
      "llm.request.start" ->
        record_request_start(
          event_data.request_id,
          event_data.provider,
          event_data.model,
          event_data.metadata || %{}
        )
      
      "llm.request.complete" ->
        record_request_completion(
          event_data.request_id,
          event_data.result,
          event_data.response_data || %{}
        )
      
      "llm.tokens.usage" ->
        record_token_usage(
          event_data.provider,
          event_data.model,
          event_data.input_tokens,
          event_data.output_tokens,
          event_data.cost || 0.0
        )
      
      "cache.llm." <> operation ->
        record_cache_operation(
          String.to_atom(operation),
          event_data.result,
          event_data.metadata || %{}
        )
      
      "provider.status.update" ->
        record_provider_status(event_data.provider, event_data.status)
      
      _ ->
        :ok
    end
  end
  
  defp initialize_metrics do
    Enum.each(@llm_metrics, fn {metric_name, config} ->
      :ets.insert(:llm_metrics, {{:metric_config, metric_name}, config})
      :ets.insert(:llm_metrics, {{:metric_value, metric_name}, 0})
    end)
  end
  
  defp increment_metric(metric_name, value, tags \\ %{}) do
    key = {:metric_value, metric_name, tags}
    
    case :ets.lookup(:llm_metrics, key) do
      [{_, current_value}] ->
        :ets.insert(:llm_metrics, {key, current_value + value})
      [] ->
        :ets.insert(:llm_metrics, {key, value})
    end
    
    # Also record timestamped value for windowed aggregation
    timestamp = :os.system_time(:millisecond)
    :ets.insert(:llm_metric_windows, {{metric_name, tags}, timestamp, value})
  end
  
  defp set_gauge(metric_name, value, tags \\ %{}) do
    key = {:metric_value, metric_name, tags}
    :ets.insert(:llm_metrics, {key, value})
    
    # Record for windowed aggregation
    timestamp = :os.system_time(:millisecond)
    :ets.insert(:llm_metric_windows, {{metric_name, tags}, timestamp, value})
  end
  
  defp record_completion_metrics(result, provider, model, latency, response_data) do
    tags = %{provider: provider, model: model}
    
    case result do
      :success ->
        increment_metric("llm.requests.success", 1, tags)
      :failure ->
        increment_metric("llm.requests.failure", 1, tags)
      :timeout ->
        increment_metric("llm.requests.timeout", 1, tags)
    end
    
    # Record latency
    record_histogram("llm.latency.request", latency, tags)
    
    # Record response quality metrics
    if response_length = Map.get(response_data, :response_length) do
      record_histogram("llm.quality.response_length", response_length, tags)
    end
    
    if context_usage = Map.get(response_data, :context_usage) do
      record_histogram("llm.quality.context_usage", context_usage, tags)
    end
  end
  
  defp record_histogram(metric_name, value, tags) do
    # For simplicity, store histogram values as individual points
    # In production, you might want to use a proper histogram implementation
    increment_metric("#{metric_name}.count", 1, tags)
    increment_metric("#{metric_name}.sum", value, tags)
    
    # Update min/max
    update_min_max(metric_name, value, tags)
  end
  
  defp update_min_max(metric_name, value, tags) do
    min_key = {:metric_value, "#{metric_name}.min", tags}
    max_key = {:metric_value, "#{metric_name}.max", tags}
    
    case :ets.lookup(:llm_metrics, min_key) do
      [{_, current_min}] ->
        if value < current_min do
          :ets.insert(:llm_metrics, {min_key, value})
        end
      [] ->
        :ets.insert(:llm_metrics, {min_key, value})
    end
    
    case :ets.lookup(:llm_metrics, max_key) do
      [{_, current_max}] ->
        if value > current_max do
          :ets.insert(:llm_metrics, {max_key, value})
        end
      [] ->
        :ets.insert(:llm_metrics, {max_key, value})
    end
  end
  
  defp update_token_rates(provider, model) do
    # Calculate tokens per second for the last minute
    current_time = :os.system_time(:millisecond)
    since = current_time - :timer.minutes(1)
    
    tags = %{provider: provider, model: model}
    
    total_tokens = get_metric_sum_in_window("llm.tokens.total", tags, since, current_time)
    rate = total_tokens / 60  # tokens per second
    
    set_gauge("llm.tokens.rate", rate, tags)
  end
  
  defp update_cache_hit_rate do
    # Calculate hit rate for the last 5 minutes
    current_time = :os.system_time(:millisecond)
    since = current_time - :timer.minutes(5)
    
    hits = get_metric_sum_in_window("llm.cache.hits", %{}, since, current_time)
    misses = get_metric_sum_in_window("llm.cache.misses", %{}, since, current_time)
    
    total_requests = hits + misses
    hit_rate = if total_requests > 0, do: hits / total_requests * 100, else: 0
    
    set_gauge("llm.cache.hit_rate", hit_rate, %{})
  end
  
  defp aggregate_window_metrics do
    current_time = :os.system_time(:millisecond)
    
    Enum.each(@retention_windows, fn window_size ->
      since = current_time - window_size
      aggregate_metrics_for_window(since, current_time, window_size)
    end)
  end
  
  defp aggregate_metrics_for_window(_since, _until, _window_size) do
    # Implementation for aggregating metrics within a time window
    # This would calculate averages, percentiles, etc. for histogram metrics
    :ok
  end
  
  defp cleanup_old_windows do
    # Remove metric windows older than the maximum retention period
    max_retention = Enum.max(@retention_windows)
    cutoff = :os.system_time(:millisecond) - max_retention
    
    :ets.select_delete(:llm_metric_windows, [
      {{{:_, :_}, :"$1", :_}, [{:<, :"$1", cutoff}], [true]}
    ])
  end
  
  defp get_metrics_in_window(since, until) do
    :ets.select(:llm_metric_windows, [
      {{{:"$1", :"$2"}, :"$3", :"$4"}, 
       [{:>=, :"$3", since}, {:"=<", :"$3", until}], 
       [{{:"$1", :"$2"}, :"$3", :"$4"}]}
    ])
  end
  
  defp get_metric_sum_in_window(metric_name, tags, since, until) do
    pattern = {{metric_name, tags}, :"$1", :"$2"}
    guards = [{:>=, :"$1", since}, {:"=<", :"$1", until}]
    
    :ets.select(:llm_metric_windows, [{pattern, guards, [:"$2"]}])
    |> Enum.sum()
  end
  
  defp filter_by_provider(metrics, nil), do: metrics
  defp filter_by_provider(metrics, provider) do
    Enum.filter(metrics, fn {{_metric, tags}, _timestamp, _value} ->
      Map.get(tags, :provider) == provider
    end)
  end
  
  defp aggregate_summary(metrics) do
    # Group metrics by name and calculate aggregates
    metrics
    |> Enum.group_by(fn {{metric_name, _tags}, _timestamp, _value} -> metric_name end)
    |> Enum.map(fn {metric_name, values} ->
      {metric_name, calculate_metric_aggregate(values)}
    end)
    |> Map.new()
  end
  
  defp calculate_metric_aggregate(values) do
    numeric_values = Enum.map(values, fn {_, _, value} -> value end)
    
    %{
      count: length(numeric_values),
      sum: Enum.sum(numeric_values),
      avg: if(length(numeric_values) > 0, do: Enum.sum(numeric_values) / length(numeric_values), else: 0),
      min: if(length(numeric_values) > 0, do: Enum.min(numeric_values), else: 0),
      max: if(length(numeric_values) > 0, do: Enum.max(numeric_values), else: 0)
    }
  end
  
  defp get_active_providers do
    # Get list of providers that have recorded metrics recently
    current_time = :os.system_time(:millisecond)
    since = current_time - :timer.minutes(15)
    
    get_metrics_in_window(since, current_time)
    |> Enum.map(fn {{_metric, tags}, _timestamp, _value} -> Map.get(tags, :provider) end)
    |> Enum.filter(& &1)
    |> Enum.uniq()
  end
  
  defp calculate_success_rate(metrics) do
    success = get_metric_value(metrics, "llm.requests.success", 0)
    total = get_metric_value(metrics, "llm.requests.total", 0)
    
    if total > 0, do: success / total * 100, else: 0
  end
  
  defp calculate_cost_per_request(metrics) do
    cost = get_metric_value(metrics, "llm.cost.total", 0.0)
    requests = get_metric_value(metrics, "llm.requests.total", 0)
    
    if requests > 0, do: cost / requests, else: 0.0
  end
  
  defp calculate_cost_per_token(metrics) do
    cost = get_metric_value(metrics, "llm.cost.total", 0.0)
    tokens = get_metric_value(metrics, "llm.tokens.total", 0)
    
    if tokens > 0, do: cost / tokens, else: 0.0
  end
  
  defp get_cost_breakdown(_breakdown_by, _window) do
    # Implementation for cost breakdown analysis
    %{}
  end
  
  defp get_cost_trend(_window) do
    # Implementation for cost trend analysis
    []
  end
  
  defp get_metric_value(metrics, metric_name, default) do
    case Map.get(metrics, metric_name) do
      nil -> default
      %{sum: sum} -> sum
      %{avg: avg} -> avg
      value -> value
    end
  end
end