defmodule RubberDuck.SelfCorrection.History do
  @moduledoc """
  Tracks correction history and patterns for learning purposes.

  Maintains a history of corrections applied, their effectiveness,
  and patterns that can be used to improve future corrections.
  """

  use GenServer
  require Logger

  @table_name :self_correction_history
  @max_history_size 1000
  @cleanup_interval :timer.hours(1)

  # Client API

  @doc """
  Starts the history tracker.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a correction attempt and its outcome.
  """
  @spec record_correction(map()) :: :ok
  def record_correction(correction_data) do
    GenServer.cast(__MODULE__, {:record_correction, correction_data})
  end

  @doc """
  Retrieves correction history for a specific pattern or type.
  """
  @spec get_history(atom(), keyword()) :: [map()]
  def get_history(pattern_type, opts \\ []) do
    GenServer.call(__MODULE__, {:get_history, pattern_type, opts})
  end

  @doc """
  Analyzes correction patterns to identify trends.
  """
  @spec analyze_patterns(keyword()) :: map()
  def analyze_patterns(opts \\ []) do
    GenServer.call(__MODULE__, {:analyze_patterns, opts})
  end

  @doc """
  Retrieves success metrics for different correction strategies.
  """
  @spec get_success_metrics() :: map()
  def get_success_metrics() do
    GenServer.call(__MODULE__, :get_success_metrics)
  end

  @doc """
  Clears old history entries based on age or count.
  """
  @spec cleanup_history(keyword()) :: {:ok, integer()}
  def cleanup_history(opts \\ []) do
    GenServer.call(__MODULE__, {:cleanup_history, opts})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for efficient history storage
    :ets.new(@table_name, [:set, :public, :named_table])

    # Schedule periodic cleanup
    schedule_cleanup()

    state = %{
      entry_count: 0,
      success_counts: %{},
      failure_counts: %{},
      pattern_cache: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:record_correction, data}, state) do
    entry = create_history_entry(data)

    # Store in ETS
    :ets.insert(@table_name, {entry.id, entry})

    # Update state metrics
    updated_state = update_metrics(state, entry)

    # Check if cleanup is needed
    new_state =
      if updated_state.entry_count > @max_history_size do
        perform_cleanup(updated_state, max_entries: @max_history_size)
      else
        updated_state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_history, pattern_type, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 100)
    since = Keyword.get(opts, :since)

    entries = get_matching_entries(pattern_type, since, limit)

    {:reply, entries, state}
  end

  @impl true
  def handle_call({:analyze_patterns, opts}, _from, state) do
    # Check cache first
    cache_key = :erlang.phash2(opts)

    analysis =
      case Map.get(state.pattern_cache, cache_key) do
        nil ->
          # Perform analysis
          result = perform_pattern_analysis(opts)

          # Update cache with TTL
          updated_cache = Map.put(state.pattern_cache, cache_key, {result, :os.system_time(:second)})

          # Clean old cache entries
          cleaned_cache = clean_pattern_cache(updated_cache)

          {:ok, result, %{state | pattern_cache: cleaned_cache}}

        {cached_result, timestamp} ->
          # Check if cache is still valid (5 minutes)
          if :os.system_time(:second) - timestamp < 300 do
            {:ok, cached_result, state}
          else
            # Recalculate
            result = perform_pattern_analysis(opts)
            updated_cache = Map.put(state.pattern_cache, cache_key, {result, :os.system_time(:second)})
            {:ok, result, %{state | pattern_cache: updated_cache}}
          end
      end

    case analysis do
      {:ok, result, new_state} -> {:reply, result, new_state}
    end
  end

  @impl true
  def handle_call(:get_success_metrics, _from, state) do
    metrics = calculate_success_metrics(state)
    {:reply, metrics, state}
  end

  @impl true
  def handle_call({:cleanup_history, opts}, _from, state) do
    new_state = perform_cleanup(state, opts)
    removed_count = state.entry_count - new_state.entry_count

    {:reply, {:ok, removed_count}, new_state}
  end

  @impl true
  def handle_info(:scheduled_cleanup, state) do
    Logger.debug("Running scheduled history cleanup")

    # Clean entries older than 7 days
    cutoff_time = DateTime.utc_now() |> DateTime.add(-7, :day)
    new_state = perform_cleanup(state, before: cutoff_time)

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, new_state}
  end

  # Private functions

  defp create_history_entry(data) do
    %{
      id: generate_id(),
      timestamp: DateTime.utc_now(),
      correction_type: data.correction_type,
      strategy: data.strategy,
      content_type: data.content_type,
      issues_found: data.issues_found,
      corrections_applied: data.corrections_applied,
      success: data.success,
      improvement_score: data.improvement_score,
      iterations: data.iterations,
      convergence_time: data.convergence_time,
      metadata: data.metadata || %{}
    }
  end

  defp generate_id() do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end

  defp update_metrics(state, entry) do
    # Update counts
    new_count = state.entry_count + 1

    # Update success/failure counts by strategy
    {success_counts, failure_counts} =
      if entry.success do
        {
          Map.update(state.success_counts, entry.strategy, 1, &(&1 + 1)),
          state.failure_counts
        }
      else
        {
          state.success_counts,
          Map.update(state.failure_counts, entry.strategy, 1, &(&1 + 1))
        }
      end

    %{state | entry_count: new_count, success_counts: success_counts, failure_counts: failure_counts}
  end

  defp get_matching_entries(pattern_type, since, limit) do
    # Build match spec
    match_spec = build_match_spec(pattern_type, since)

    # Query ETS
    case :ets.select(@table_name, match_spec, limit) do
      :"$end_of_table" ->
        []

      {results, _continuation} ->
        results
        |> Enum.map(fn {_id, entry} -> entry end)
        |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
        |> Enum.take(limit)
    end
  end

  defp build_match_spec(pattern_type, since) do
    base_pattern = {:"$1", :"$2"}

    guards = []

    # Add pattern type guard if specified
    guards =
      if pattern_type != :all do
        [{:==, {:map_get, :correction_type, :"$2"}, pattern_type} | guards]
      else
        guards
      end

    # Add time guard if specified
    guards =
      if since do
        [{:>, {:map_get, :timestamp, :"$2"}, since} | guards]
      else
        guards
      end

    if length(guards) > 0 do
      [{base_pattern, guards, [:"$_"]}]
    else
      [{base_pattern, [], [:"$_"]}]
    end
  end

  defp perform_pattern_analysis(opts) do
    # Get all entries for analysis
    entries =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {_id, entry} -> entry end)

    # Filter by options
    filtered_entries = filter_entries_for_analysis(entries, opts)

    # Analyze patterns
    %{
      total_corrections: length(filtered_entries),
      success_rate: calculate_success_rate(filtered_entries),
      average_iterations: calculate_average_iterations(filtered_entries),
      common_issues: identify_common_issues(filtered_entries),
      effective_strategies: analyze_strategy_effectiveness(filtered_entries),
      improvement_trends: analyze_improvement_trends(filtered_entries),
      convergence_patterns: analyze_convergence_patterns(filtered_entries)
    }
  end

  defp filter_entries_for_analysis(entries, opts) do
    since = Keyword.get(opts, :since)
    content_type = Keyword.get(opts, :content_type)
    strategy = Keyword.get(opts, :strategy)

    entries
    |> Enum.filter(fn entry ->
      (is_nil(since) || DateTime.compare(entry.timestamp, since) == :gt) &&
        (is_nil(content_type) || entry.content_type == content_type) &&
        (is_nil(strategy) || entry.strategy == strategy)
    end)
  end

  defp calculate_success_rate([]), do: 0.0

  defp calculate_success_rate(entries) do
    success_count = Enum.count(entries, & &1.success)
    success_count / length(entries)
  end

  defp calculate_average_iterations([]), do: 0.0

  defp calculate_average_iterations(entries) do
    total_iterations = Enum.sum(Enum.map(entries, & &1.iterations))
    total_iterations / length(entries)
  end

  defp identify_common_issues(entries) do
    entries
    |> Enum.flat_map(& &1.issues_found)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(10)
    |> Enum.map(fn {issue, count} -> %{issue: issue, count: count} end)
  end

  defp analyze_strategy_effectiveness(entries) do
    entries
    |> Enum.group_by(& &1.strategy)
    |> Enum.map(fn {strategy, strategy_entries} ->
      success_rate = calculate_success_rate(strategy_entries)
      avg_improvement = calculate_average_improvement(strategy_entries)
      avg_iterations = calculate_average_iterations(strategy_entries)

      {strategy,
       %{
         success_rate: success_rate,
         average_improvement: avg_improvement,
         average_iterations: avg_iterations,
         sample_size: length(strategy_entries)
       }}
    end)
    |> Enum.into(%{})
  end

  defp calculate_average_improvement(entries) do
    improvements =
      entries
      |> Enum.map(& &1.improvement_score)
      |> Enum.filter(&is_number/1)

    if length(improvements) > 0 do
      Enum.sum(improvements) / length(improvements)
    else
      0.0
    end
  end

  defp analyze_improvement_trends(entries) do
    # Group by day and calculate average improvement
    entries
    |> Enum.group_by(fn entry ->
      Date.to_iso8601(DateTime.to_date(entry.timestamp))
    end)
    |> Enum.map(fn {date, day_entries} ->
      %{
        date: date,
        average_improvement: calculate_average_improvement(day_entries),
        correction_count: length(day_entries)
      }
    end)
    |> Enum.sort_by(& &1.date)
  end

  defp analyze_convergence_patterns(entries) do
    convergence_times =
      entries
      |> Enum.map(& &1.convergence_time)
      |> Enum.filter(&is_number/1)
      |> Enum.sort()

    if length(convergence_times) > 0 do
      %{
        min: List.first(convergence_times),
        max: List.last(convergence_times),
        median: calculate_median(convergence_times),
        average: Enum.sum(convergence_times) / length(convergence_times)
      }
    else
      %{min: 0, max: 0, median: 0, average: 0}
    end
  end

  defp calculate_median([]), do: 0

  defp calculate_median(sorted_list) do
    len = length(sorted_list)
    mid = div(len, 2)

    if rem(len, 2) == 0 do
      (Enum.at(sorted_list, mid - 1) + Enum.at(sorted_list, mid)) / 2
    else
      Enum.at(sorted_list, mid)
    end
  end

  defp calculate_success_metrics(state) do
    total_successes = state.success_counts |> Map.values() |> Enum.sum()
    total_failures = state.failure_counts |> Map.values() |> Enum.sum()
    total_attempts = total_successes + total_failures

    overall_success_rate =
      if total_attempts > 0 do
        total_successes / total_attempts
      else
        0.0
      end

    strategy_metrics =
      Map.merge(state.success_counts, state.failure_counts, fn _k, s, f ->
        total = s + f

        %{
          successes: s,
          failures: f,
          total: total,
          success_rate: if(total > 0, do: s / total, else: 0.0)
        }
      end)

    %{
      overall_success_rate: overall_success_rate,
      total_corrections: total_attempts,
      strategy_metrics: strategy_metrics
    }
  end

  defp perform_cleanup(_state, opts) do
    before = Keyword.get(opts, :before)
    max_entries = Keyword.get(opts, :max_entries)

    # Get all entries
    all_entries =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {id, entry} -> {id, entry} end)
      |> Enum.sort_by(fn {_id, entry} -> entry.timestamp end, {:desc, DateTime})

    # Determine which entries to keep
    entries_to_keep =
      cond do
        before ->
          Enum.filter(all_entries, fn {_id, entry} ->
            DateTime.compare(entry.timestamp, before) == :gt
          end)

        max_entries ->
          Enum.take(all_entries, max_entries)

        true ->
          all_entries
      end

    # Clear table and reinsert
    :ets.delete_all_objects(@table_name)

    Enum.each(entries_to_keep, fn {id, entry} ->
      :ets.insert(@table_name, {id, entry})
    end)

    # Recalculate metrics
    recalculate_state_metrics(entries_to_keep)
  end

  defp recalculate_state_metrics(entries) do
    {success_counts, failure_counts} =
      Enum.reduce(entries, {%{}, %{}}, fn {_id, entry}, {succ, fail} ->
        if entry.success do
          {Map.update(succ, entry.strategy, 1, &(&1 + 1)), fail}
        else
          {succ, Map.update(fail, entry.strategy, 1, &(&1 + 1))}
        end
      end)

    %{
      entry_count: length(entries),
      success_counts: success_counts,
      failure_counts: failure_counts,
      pattern_cache: %{}
    }
  end

  defp clean_pattern_cache(cache) do
    current_time = :os.system_time(:second)

    # Remove entries older than 5 minutes
    Map.filter(cache, fn {_key, {_result, timestamp}} ->
      current_time - timestamp < 300
    end)
  end

  defp schedule_cleanup() do
    Process.send_after(self(), :scheduled_cleanup, @cleanup_interval)
  end
end
