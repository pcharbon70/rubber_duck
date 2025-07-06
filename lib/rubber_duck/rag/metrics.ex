defmodule RubberDuck.RAG.Metrics do
  @moduledoc """
  Quality monitoring and metrics for the RAG pipeline.
  
  Tracks and analyzes:
  - Retrieval quality metrics
  - Response relevance
  - Latency and performance
  - User feedback integration
  - A/B testing support
  """
  
  use GenServer
  require Logger
  
  @type metric_event :: %{
    type: atom(),
    timestamp: DateTime.t(),
    value: any(),
    metadata: map()
  }
  
  @type metric_summary :: %{
    avg_retrieval_score: float(),
    avg_response_time: float(),
    success_rate: float(),
    feedback_score: float()
  }
  
  # Client API
  
  @doc """
  Starts the metrics server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Records a retrieval event with quality metrics.
  """
  @spec record_retrieval(String.t(), list(map()), keyword()) :: :ok
  def record_retrieval(query, results, opts \\ []) do
    event = %{
      type: :retrieval,
      timestamp: DateTime.utc_now(),
      value: %{
        query: query,
        result_count: length(results),
        avg_score: calculate_avg_score(results),
        top_score: get_top_score(results),
        strategy: Keyword.get(opts, :strategy, :unknown)
      },
      metadata: opts
    }
    
    GenServer.cast(__MODULE__, {:record, event})
  end
  
  @doc """
  Records a reranking event.
  """
  @spec record_reranking(list(map()), list(map()), keyword()) :: :ok
  def record_reranking(original_results, reranked_results, opts \\ []) do
    event = %{
      type: :reranking,
      timestamp: DateTime.utc_now(),
      value: %{
        original_order: Enum.map(original_results, & &1.content) |> Enum.take(5),
        reranked_order: Enum.map(reranked_results, & &1.content) |> Enum.take(5),
        rank_changes: calculate_rank_changes(original_results, reranked_results),
        strategy: Keyword.get(opts, :strategy, :unknown)
      },
      metadata: opts
    }
    
    GenServer.cast(__MODULE__, {:record, event})
  end
  
  @doc """
  Records context building metrics.
  """
  @spec record_context_building(map(), keyword()) :: :ok
  def record_context_building(context, opts \\ []) do
    event = %{
      type: :context_building,
      timestamp: DateTime.utc_now(),
      value: %{
        token_count: context.token_count,
        citation_count: length(Map.get(context, :citations, [])),
        compression_ratio: Keyword.get(opts, :compression_ratio, 1.0),
        build_time_ms: Keyword.get(opts, :build_time_ms, 0)
      },
      metadata: opts
    }
    
    GenServer.cast(__MODULE__, {:record, event})
  end
  
  @doc """
  Records end-to-end RAG pipeline metrics.
  """
  @spec record_pipeline_execution(String.t(), map(), keyword()) :: :ok
  def record_pipeline_execution(query, result, opts \\ []) do
    event = %{
      type: :pipeline_execution,
      timestamp: DateTime.utc_now(),
      value: %{
        query: query,
        total_time_ms: Keyword.get(opts, :total_time_ms, 0),
        stages: %{
          retrieval_ms: Keyword.get(opts, :retrieval_ms, 0),
          reranking_ms: Keyword.get(opts, :reranking_ms, 0),
          context_building_ms: Keyword.get(opts, :context_building_ms, 0)
        },
        success: Map.get(result, :success, true),
        error: Map.get(result, :error)
      },
      metadata: opts
    }
    
    GenServer.cast(__MODULE__, {:record, event})
    
    # Also send telemetry event
    :telemetry.execute(
      [:rubber_duck, :rag, :pipeline],
      %{duration: Keyword.get(opts, :total_time_ms, 0)},
      %{query: query, success: Map.get(result, :success, true)}
    )
  end
  
  @doc """
  Records user feedback on RAG results.
  """
  @spec record_feedback(String.t(), atom(), keyword()) :: :ok
  def record_feedback(query, feedback, opts \\ []) do
    event = %{
      type: :user_feedback,
      timestamp: DateTime.utc_now(),
      value: %{
        query: query,
        feedback: feedback,  # :positive, :negative, :neutral
        rating: Keyword.get(opts, :rating),
        comment: Keyword.get(opts, :comment)
      },
      metadata: opts
    }
    
    GenServer.cast(__MODULE__, {:record, event})
  end
  
  @doc """
  Gets metric summary for a time period.
  """
  @spec get_summary(DateTime.t(), DateTime.t()) :: {:ok, metric_summary()} | {:error, term()}
  def get_summary(start_time, end_time) do
    GenServer.call(__MODULE__, {:get_summary, start_time, end_time})
  end
  
  @doc """
  Gets detailed metrics for analysis.
  """
  @spec get_detailed_metrics(keyword()) :: {:ok, list(metric_event())} | {:error, term()}
  def get_detailed_metrics(opts \\ []) do
    GenServer.call(__MODULE__, {:get_detailed_metrics, opts})
  end
  
  @doc """
  Analyzes A/B test results between strategies.
  """
  @spec analyze_ab_test(atom(), atom(), DateTime.t(), DateTime.t()) :: {:ok, map()} | {:error, term()}
  def analyze_ab_test(strategy_a, strategy_b, start_time, end_time) do
    GenServer.call(__MODULE__, {:analyze_ab_test, strategy_a, strategy_b, start_time, end_time})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Initialize ETS table for metrics storage
    :ets.new(:rag_metrics, [:set, :public, :named_table])
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    state = %{
      events: [],
      max_events: 10_000,
      retention_days: 7
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:record, event}, state) do
    # Store in memory
    new_events = [event | state.events] |> Enum.take(state.max_events)
    
    # Update aggregated metrics in ETS
    update_aggregated_metrics(event)
    
    {:noreply, %{state | events: new_events}}
  end
  
  @impl true
  def handle_call({:get_summary, start_time, end_time}, _from, state) do
    summary = calculate_summary(state.events, start_time, end_time)
    {:reply, {:ok, summary}, state}
  end
  
  @impl true
  def handle_call({:get_detailed_metrics, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 100)
    type = Keyword.get(opts, :type)
    
    filtered_events = state.events
    |> filter_by_type(type)
    |> Enum.take(limit)
    
    {:reply, {:ok, filtered_events}, state}
  end
  
  @impl true
  def handle_call({:analyze_ab_test, strategy_a, strategy_b, start_time, end_time}, _from, state) do
    analysis = perform_ab_analysis(state.events, strategy_a, strategy_b, start_time, end_time)
    {:reply, {:ok, analysis}, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Remove old events
    cutoff_time = DateTime.add(DateTime.utc_now(), -state.retention_days * 24 * 3600, :second)
    
    filtered_events = Enum.filter(state.events, fn event ->
      DateTime.compare(event.timestamp, cutoff_time) == :gt
    end)
    
    # Schedule next cleanup
    schedule_cleanup()
    
    {:noreply, %{state | events: filtered_events}}
  end
  
  # Private functions
  
  defp calculate_avg_score(results) do
    if length(results) > 0 do
      total = Enum.sum(Enum.map(results, & &1.score))
      total / length(results)
    else
      0.0
    end
  end
  
  defp get_top_score(results) do
    case results do
      [] -> 0.0
      _ -> Enum.max_by(results, & &1.score).score
    end
  end
  
  defp calculate_rank_changes(original, reranked) do
    original_positions = original
    |> Enum.with_index()
    |> Enum.into(%{}, fn {item, idx} -> {item.content, idx} end)
    
    reranked
    |> Enum.with_index()
    |> Enum.map(fn {item, new_idx} ->
      old_idx = Map.get(original_positions, item.content, -1)
      old_idx - new_idx  # Positive means moved up
    end)
    |> Enum.take(10)  # Top 10 changes
  end
  
  defp update_aggregated_metrics(event) do
    # Update counters and aggregates in ETS
    key = {:aggregate, event.type, Date.utc_today()}
    
    case :ets.lookup(:rag_metrics, key) do
      [{^key, current}] ->
        updated = update_aggregate(current, event)
        :ets.insert(:rag_metrics, {key, updated})
      
      [] ->
        initial = initialize_aggregate(event)
        :ets.insert(:rag_metrics, {key, initial})
    end
  end
  
  defp update_aggregate(current, event) do
    case event.type do
      :retrieval ->
        %{current |
          count: current.count + 1,
          total_score: current.total_score + event.value.avg_score,
          total_results: current.total_results + event.value.result_count
        }
      
      :pipeline_execution ->
        %{current |
          count: current.count + 1,
          total_time: current.total_time + event.value.total_time_ms,
          success_count: current.success_count + (if event.value.success, do: 1, else: 0)
        }
      
      :user_feedback ->
        %{current |
          count: current.count + 1,
          positive_count: current.positive_count + (if event.value.feedback == :positive, do: 1, else: 0),
          negative_count: current.negative_count + (if event.value.feedback == :negative, do: 1, else: 0)
        }
      
      _ ->
        %{current | count: current.count + 1}
    end
  end
  
  defp initialize_aggregate(event) do
    base = %{count: 1, type: event.type, date: Date.utc_today()}
    
    case event.type do
      :retrieval ->
        Map.merge(base, %{
          total_score: event.value.avg_score,
          total_results: event.value.result_count
        })
      
      :pipeline_execution ->
        Map.merge(base, %{
          total_time: event.value.total_time_ms,
          success_count: (if event.value.success, do: 1, else: 0)
        })
      
      :user_feedback ->
        Map.merge(base, %{
          positive_count: (if event.value.feedback == :positive, do: 1, else: 0),
          negative_count: (if event.value.feedback == :negative, do: 1, else: 0)
        })
      
      _ ->
        base
    end
  end
  
  defp calculate_summary(events, start_time, end_time) do
    filtered = Enum.filter(events, fn event ->
      DateTime.compare(event.timestamp, start_time) in [:gt, :eq] &&
      DateTime.compare(event.timestamp, end_time) in [:lt, :eq]
    end)
    
    retrieval_events = filter_by_type(filtered, :retrieval)
    pipeline_events = filter_by_type(filtered, :pipeline_execution)
    feedback_events = filter_by_type(filtered, :user_feedback)
    
    %{
      avg_retrieval_score: calculate_avg_from_events(retrieval_events, [:value, :avg_score]),
      avg_response_time: calculate_avg_from_events(pipeline_events, [:value, :total_time_ms]),
      success_rate: calculate_success_rate(pipeline_events),
      feedback_score: calculate_feedback_score(feedback_events),
      total_queries: length(pipeline_events),
      retrieval_strategies: count_strategies(retrieval_events),
      time_period: %{start: start_time, end: end_time}
    }
  end
  
  defp filter_by_type(events, nil), do: events
  defp filter_by_type(events, type) do
    Enum.filter(events, fn event -> event.type == type end)
  end
  
  defp calculate_avg_from_events([], _path), do: 0.0
  defp calculate_avg_from_events(events, path) do
    sum = Enum.sum(Enum.map(events, fn event ->
      get_in(event, path) || 0
    end))
    
    sum / length(events)
  end
  
  defp calculate_success_rate([]), do: 1.0
  defp calculate_success_rate(events) do
    success_count = Enum.count(events, fn event ->
      get_in(event, [:value, :success]) == true
    end)
    
    success_count / length(events)
  end
  
  defp calculate_feedback_score([]), do: 0.0
  defp calculate_feedback_score(events) do
    positive = Enum.count(events, fn e -> e.value.feedback == :positive end)
    negative = Enum.count(events, fn e -> e.value.feedback == :negative end)
    
    if positive + negative > 0 do
      positive / (positive + negative)
    else
      0.0
    end
  end
  
  defp count_strategies(events) do
    events
    |> Enum.map(fn e -> get_in(e, [:value, :strategy]) || :unknown end)
    |> Enum.frequencies()
  end
  
  defp perform_ab_analysis(events, strategy_a, strategy_b, start_time, end_time) do
    filtered = Enum.filter(events, fn event ->
      DateTime.compare(event.timestamp, start_time) in [:gt, :eq] &&
      DateTime.compare(event.timestamp, end_time) in [:lt, :eq]
    end)
    
    a_events = Enum.filter(filtered, fn e ->
      get_in(e, [:value, :strategy]) == strategy_a ||
      get_in(e, [:metadata, :strategy]) == strategy_a
    end)
    
    b_events = Enum.filter(filtered, fn e ->
      get_in(e, [:value, :strategy]) == strategy_b ||
      get_in(e, [:metadata, :strategy]) == strategy_b
    end)
    
    %{
      strategy_a: %{
        name: strategy_a,
        count: length(a_events),
        avg_score: calculate_avg_from_events(a_events, [:value, :avg_score]),
        avg_time: calculate_avg_from_events(a_events, [:value, :total_time_ms]),
        success_rate: calculate_success_rate(filter_by_type(a_events, :pipeline_execution))
      },
      strategy_b: %{
        name: strategy_b,
        count: length(b_events),
        avg_score: calculate_avg_from_events(b_events, [:value, :avg_score]),
        avg_time: calculate_avg_from_events(b_events, [:value, :total_time_ms]),
        success_rate: calculate_success_rate(filter_by_type(b_events, :pipeline_execution))
      },
      recommendation: determine_ab_winner(a_events, b_events)
    }
  end
  
  defp determine_ab_winner(a_events, b_events) do
    # Simple winner determination - in production use statistical significance
    a_score = calculate_avg_from_events(a_events, [:value, :avg_score])
    b_score = calculate_avg_from_events(b_events, [:value, :avg_score])
    
    cond do
      length(a_events) < 10 || length(b_events) < 10 ->
        "Insufficient data for recommendation"
      
      a_score > b_score * 1.1 ->
        "Strategy A performs significantly better"
      
      b_score > a_score * 1.1 ->
        "Strategy B performs significantly better"
      
      true ->
        "No significant difference detected"
    end
  end
  
  defp schedule_cleanup() do
    # Cleanup every hour
    Process.send_after(self(), :cleanup, :timer.hours(1))
  end
end