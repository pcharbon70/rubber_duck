defmodule RubberDuck.Planning.Execution.History do
  @moduledoc """
  Tracks execution history for the ReAct framework.

  Maintains a record of thoughts, actions, observations, and outcomes
  for analysis, debugging, and learning.
  """

  defstruct [
    :execution_id,
    :entries,
    :thoughts,
    :observations,
    :failures,
    :retries,
    :attempts,
    :timings,
    :snapshots,
    :metadata
  ]

  @type entry :: %{
          id: String.t(),
          type: atom(),
          task_id: String.t() | nil,
          timestamp: DateTime.t(),
          data: map()
        }

  @type t :: %__MODULE__{
          execution_id: String.t(),
          entries: [entry()],
          thoughts: map(),
          observations: map(),
          failures: map(),
          retries: map(),
          attempts: map(),
          timings: map(),
          snapshots: map(),
          metadata: map()
        }

  @doc """
  Creates a new history tracker.
  """
  def new(execution_id \\ nil) do
    %__MODULE__{
      execution_id: execution_id || generate_id(),
      entries: [],
      thoughts: %{},
      observations: %{},
      failures: %{},
      retries: %{},
      attempts: %{},
      timings: %{},
      snapshots: %{},
      metadata: %{}
    }
  end

  @doc """
  Records a thought in the history.
  """
  def record_thought(history, task_id, thought) do
    entry = create_entry(:thought, task_id, thought)

    %{
      history
      | entries: [entry | history.entries],
        thoughts: Map.update(history.thoughts, task_id, [thought], &[thought | &1])
    }
  end

  @doc """
  Records an observation in the history.
  """
  def record_observation(history, task_id, observation) do
    entry = create_entry(:observation, task_id, observation)

    %{
      history
      | entries: [entry | history.entries],
        observations: Map.update(history.observations, task_id, [observation], &[observation | &1])
    }
  end

  @doc """
  Records a task failure.
  """
  def record_failure(history, task_id, error) do
    entry = create_entry(:failure, task_id, %{error: error})

    failure_record = %{
      error: error,
      timestamp: DateTime.utc_now(),
      attempt_number: get_attempt_count(history, task_id) + 1
    }

    %{
      history
      | entries: [entry | history.entries],
        failures: Map.update(history.failures, task_id, [failure_record], &[failure_record | &1])
    }
  end

  @doc """
  Records a task start time.
  """
  def record_task_start(history, task_id) do
    timing = Map.get(history.timings, task_id, %{})
    updated_timing = Map.put(timing, :start, DateTime.utc_now())

    %{history | timings: Map.put(history.timings, task_id, updated_timing)}
  end

  @doc """
  Records a task end time.
  """
  def record_task_end(history, task_id) do
    timing = Map.get(history.timings, task_id, %{})
    updated_timing = Map.put(timing, :end, DateTime.utc_now())

    %{history | timings: Map.put(history.timings, task_id, updated_timing)}
  end

  @doc """
  Increments the retry count for a task.
  """
  def increment_retry(history, task_id) do
    current_count = Map.get(history.retries, task_id, 0)

    %{history | retries: Map.put(history.retries, task_id, current_count + 1)}
  end

  @doc """
  Records a task attempt.
  """
  def record_attempt(history, task_id, attempt_data) do
    attempt =
      Map.merge(attempt_data, %{
        timestamp: DateTime.utc_now(),
        attempt_number: get_attempt_count(history, task_id) + 1
      })

    %{history | attempts: Map.update(history.attempts, task_id, [attempt], &[attempt | &1])}
  end

  @doc """
  Records a state snapshot.
  """
  def record_snapshot(history, snapshot_type, data) do
    snapshot_id = generate_snapshot_id()

    snapshot = %{
      id: snapshot_id,
      type: snapshot_type,
      data: data,
      timestamp: DateTime.utc_now()
    }

    %{history | snapshots: Map.put(history.snapshots, snapshot_id, snapshot)}
  end

  @doc """
  Gets the retry count for a task.
  """
  def get_retry_count(history, task_id) do
    Map.get(history.retries, task_id, 0)
  end

  @doc """
  Gets the attempt count for a task.
  """
  def get_attempt_count(history, task_id) do
    history.attempts
    |> Map.get(task_id, [])
    |> length()
  end

  @doc """
  Gets all entries of a specific type.
  """
  def get_entries_by_type(history, type) do
    Enum.filter(history.entries, &(&1.type == type))
  end

  @doc """
  Gets all entries for a specific task.
  """
  def get_task_entries(history, task_id) do
    Enum.filter(history.entries, &(&1.task_id == task_id))
  end

  @doc """
  Gets the execution timeline.
  """
  def get_timeline(history) do
    history.entries
    |> Enum.reverse()
    |> Enum.map(&format_timeline_entry/1)
  end

  @doc """
  Generates a summary of the execution history.
  """
  def summary(history) do
    %{
      execution_id: history.execution_id,
      total_entries: length(history.entries),
      thoughts_count: count_by_type(history.thoughts),
      observations_count: count_by_type(history.observations),
      failures_count: count_by_type(history.failures),
      total_retries: sum_retries(history.retries),
      unique_tasks: count_unique_tasks(history),
      execution_patterns: analyze_patterns(history),
      insights: generate_insights(history)
    }
  end

  @doc """
  Gets detailed task history.
  """
  def get_task_history(history, task_id) do
    %{
      task_id: task_id,
      thoughts: Map.get(history.thoughts, task_id, []) |> Enum.reverse(),
      observations: Map.get(history.observations, task_id, []) |> Enum.reverse(),
      failures: Map.get(history.failures, task_id, []) |> Enum.reverse(),
      attempts: Map.get(history.attempts, task_id, []) |> Enum.reverse(),
      retry_count: get_retry_count(history, task_id),
      timing: Map.get(history.timings, task_id),
      entries: get_task_entries(history, task_id) |> Enum.reverse()
    }
  end

  @doc """
  Exports history to a format suitable for analysis.
  """
  def export(history) do
    %{
      execution_id: history.execution_id,
      timeline: get_timeline(history),
      summary: summary(history),
      task_histories: export_task_histories(history),
      snapshots: history.snapshots,
      metadata: history.metadata
    }
  end

  # Private functions

  defp create_entry(type, task_id, data) do
    %{
      id: generate_entry_id(),
      type: type,
      task_id: task_id,
      timestamp: DateTime.utc_now(),
      data: data
    }
  end

  defp generate_id do
    "hist_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp generate_entry_id do
    "entry_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  defp generate_snapshot_id do
    "snap_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  defp format_timeline_entry(entry) do
    %{
      timestamp: entry.timestamp,
      type: entry.type,
      task_id: entry.task_id,
      summary: summarize_entry_data(entry.type, entry.data)
    }
  end

  defp summarize_entry_data(:thought, %{reasoning: reasoning}) do
    String.slice(reasoning, 0, 100) <> "..."
  end

  defp summarize_entry_data(:observation, %{status: status, insights: insights}) do
    "Status: #{status}, Insights: #{length(insights)}"
  end

  defp summarize_entry_data(:failure, %{error: error}) do
    "Error: #{inspect(error)}"
  end

  defp summarize_entry_data(_, data) do
    inspect(data)
  end

  defp count_by_type(map) do
    map
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end

  defp sum_retries(retries_map) do
    retries_map
    |> Map.values()
    |> Enum.sum()
  end

  defp count_unique_tasks(history) do
    history.entries
    |> Enum.map(& &1.task_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length()
  end

  defp analyze_patterns(history) do
    %{
      retry_patterns: analyze_retry_patterns(history),
      failure_patterns: analyze_failure_patterns(history),
      timing_patterns: analyze_timing_patterns(history)
    }
  end

  defp analyze_retry_patterns(history) do
    history.retries
    |> Enum.map(fn {task_id, count} ->
      %{task_id: task_id, retry_count: count}
    end)
    |> Enum.sort_by(& &1.retry_count, :desc)
    |> Enum.take(5)
  end

  defp analyze_failure_patterns(history) do
    history.failures
    |> Enum.map(fn {task_id, failures} ->
      %{
        task_id: task_id,
        failure_count: length(failures),
        failure_types: extract_failure_types(failures)
      }
    end)
    |> Enum.sort_by(& &1.failure_count, :desc)
    |> Enum.take(5)
  end

  defp extract_failure_types(failures) do
    failures
    |> Enum.map(fn %{error: error} ->
      case error do
        {:error, type} when is_atom(type) -> type
        %{type: type} -> type
        _ -> :unknown
      end
    end)
    |> Enum.frequencies()
  end

  defp analyze_timing_patterns(history) do
    history.timings
    |> Enum.map(fn {task_id, %{start: start, end: end_time}} ->
      duration = DateTime.diff(end_time, start, :millisecond)
      %{task_id: task_id, duration_ms: duration}
    end)
    |> Enum.sort_by(& &1.duration_ms, :desc)
    |> Enum.take(5)
  rescue
    _ -> []
  end

  defp generate_insights(history) do
    insights = []

    # High retry tasks
    high_retry_tasks = Enum.filter(history.retries, fn {_, count} -> count >= 3 end)

    insights =
      if length(high_retry_tasks) > 0 do
        insights ++ ["#{length(high_retry_tasks)} tasks required 3+ retries"]
      else
        insights
      end

    # Failure rate
    total_attempts = count_by_type(history.attempts)
    total_failures = count_by_type(history.failures)

    insights =
      if total_attempts > 0 do
        failure_rate = Float.round(total_failures / total_attempts * 100, 1)
        insights ++ ["Overall failure rate: #{failure_rate}%"]
      else
        insights
      end

    # Long-running tasks
    long_tasks =
      history.timings
      |> Enum.filter(fn {_, timing} ->
        case timing do
          %{start: start, end: end_time} ->
            DateTime.diff(end_time, start, :second) > 60

          _ ->
            false
        end
      end)

    insights =
      if length(long_tasks) > 0 do
        insights ++ ["#{length(long_tasks)} tasks took over 1 minute"]
      else
        insights
      end

    insights
  end

  defp export_task_histories(history) do
    history.entries
    |> Enum.map(& &1.task_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(&{&1, get_task_history(history, &1)})
    |> Map.new()
  end
end
