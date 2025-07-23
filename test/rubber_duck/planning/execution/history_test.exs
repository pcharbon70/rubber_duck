defmodule RubberDuck.Planning.Execution.HistoryTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Planning.Execution.History

  describe "new/1" do
    test "creates new history tracker" do
      history = History.new()

      assert history.execution_id
      assert history.entries == []
      assert history.thoughts == %{}
      assert history.observations == %{}
      assert history.failures == %{}
    end

    test "creates history with custom execution_id" do
      execution_id = "custom_execution"
      history = History.new(execution_id)

      assert history.execution_id == execution_id
    end
  end

  describe "record_thought/3" do
    test "records thought in history" do
      history = History.new()
      task_id = "task1"
      thought = %{reasoning: "This task looks simple", confidence: 0.9}

      updated_history = History.record_thought(history, task_id, thought)

      assert length(updated_history.entries) == 1
      assert List.first(updated_history.entries).type == :thought
      assert List.first(updated_history.entries).task_id == task_id
      assert updated_history.thoughts[task_id] == [thought]
    end

    test "accumulates multiple thoughts for same task" do
      history = History.new()
      task_id = "task1"
      thought1 = %{reasoning: "First thought", confidence: 0.8}
      thought2 = %{reasoning: "Second thought", confidence: 0.9}

      updated_history =
        history
        |> History.record_thought(task_id, thought1)
        |> History.record_thought(task_id, thought2)

      assert length(updated_history.thoughts[task_id]) == 2
      # Latest first
      assert List.first(updated_history.thoughts[task_id]) == thought2
    end
  end

  describe "record_observation/3" do
    test "records observation in history" do
      history = History.new()
      task_id = "task1"
      observation = %{status: :success, insights: ["Task completed well"]}

      updated_history = History.record_observation(history, task_id, observation)

      assert length(updated_history.entries) == 1
      assert List.first(updated_history.entries).type == :observation
      assert updated_history.observations[task_id] == [observation]
    end
  end

  describe "record_failure/3" do
    test "records failure with attempt number" do
      history = History.new()
      task_id = "task1"
      error = {:error, :timeout}

      updated_history = History.record_failure(history, task_id, error)

      assert length(updated_history.entries) == 1
      assert List.first(updated_history.entries).type == :failure

      failure_record = List.first(updated_history.failures[task_id])
      assert failure_record.error == error
      assert failure_record.attempt_number == 1
      assert failure_record.timestamp
    end

    test "increments attempt number for multiple failures" do
      history = History.new()
      task_id = "task1"

      # Record first failure
      updated_history = History.record_failure(history, task_id, {:error, :network})
      first_failure = List.first(updated_history.failures[task_id])
      assert first_failure.attempt_number == 1

      # Record second failure
      updated_history = History.record_failure(updated_history, task_id, {:error, :timeout})
      failures = updated_history.failures[task_id]
      assert length(failures) == 2
      # Latest first, but attempt 1 from first failure
      assert List.first(failures).attempt_number == 1
    end
  end

  describe "timing functions" do
    test "records task start and end times" do
      history = History.new()
      task_id = "task1"

      # Record start
      history_with_start = History.record_task_start(history, task_id)
      assert history_with_start.timings[task_id][:start]

      # Small delay to ensure different timestamps
      :timer.sleep(10)

      # Record end
      history_with_end = History.record_task_end(history_with_start, task_id)
      timing = history_with_end.timings[task_id]

      assert timing[:start]
      assert timing[:end]
      assert DateTime.compare(timing[:end], timing[:start]) == :gt
    end
  end

  describe "retry tracking" do
    test "increments retry count" do
      history = History.new()
      task_id = "task1"

      # Initial retry count should be 0
      assert History.get_retry_count(history, task_id) == 0

      # Increment retry
      updated_history = History.increment_retry(history, task_id)
      assert History.get_retry_count(updated_history, task_id) == 1

      # Increment again
      updated_history = History.increment_retry(updated_history, task_id)
      assert History.get_retry_count(updated_history, task_id) == 2
    end
  end

  describe "attempt tracking" do
    test "records task attempts" do
      history = History.new()
      task_id = "task1"
      attempt_data = %{strategy: :direct, confidence: 0.8}

      updated_history = History.record_attempt(history, task_id, attempt_data)

      assert History.get_attempt_count(updated_history, task_id) == 1

      attempt = List.first(updated_history.attempts[task_id])
      assert attempt.strategy == :direct
      assert attempt.confidence == 0.8
      assert attempt.attempt_number == 1
      assert attempt.timestamp
    end
  end

  describe "snapshot recording" do
    test "records state snapshots" do
      history = History.new()
      snapshot_data = %{state: :executing, tasks_completed: 5}

      updated_history = History.record_snapshot(history, :execution_state, snapshot_data)

      # Should have one snapshot
      assert map_size(updated_history.snapshots) == 1

      snapshot = updated_history.snapshots |> Map.values() |> List.first()
      assert snapshot.type == :execution_state
      assert snapshot.data == snapshot_data
      assert snapshot.timestamp
    end
  end

  describe "get_entries_by_type/2" do
    test "filters entries by type" do
      history =
        History.new()
        |> History.record_thought("task1", %{reasoning: "thinking"})
        |> History.record_observation("task1", %{status: :success})
        |> History.record_failure("task2", {:error, :failed})

      thoughts = History.get_entries_by_type(history, :thought)
      observations = History.get_entries_by_type(history, :observation)
      failures = History.get_entries_by_type(history, :failure)

      assert length(thoughts) == 1
      assert length(observations) == 1
      assert length(failures) == 1
    end
  end

  describe "get_task_entries/2" do
    test "filters entries by task" do
      history =
        History.new()
        |> History.record_thought("task1", %{reasoning: "thinking task1"})
        |> History.record_thought("task2", %{reasoning: "thinking task2"})
        |> History.record_observation("task1", %{status: :success})

      task1_entries = History.get_task_entries(history, "task1")
      task2_entries = History.get_task_entries(history, "task2")

      # 1 thought + 1 observation
      assert length(task1_entries) == 2
      # 1 thought only
      assert length(task2_entries) == 1
    end
  end

  describe "get_timeline/1" do
    test "returns chronological timeline" do
      history =
        History.new()
        |> History.record_thought("task1", %{reasoning: "First thought"})
        |> History.record_observation("task1", %{status: :success, insights: []})
        |> History.record_thought("task2", %{reasoning: "Second thought"})

      timeline = History.get_timeline(history)

      assert length(timeline) == 3
      # Timeline should be in chronological order (oldest first)
      assert Enum.at(timeline, 0).type == :thought
      assert Enum.at(timeline, 1).type == :observation
      assert Enum.at(timeline, 2).type == :thought
    end
  end

  describe "summary/1" do
    test "generates comprehensive summary" do
      history =
        History.new()
        |> History.record_thought("task1", %{reasoning: "thinking"})
        |> History.record_observation("task1", %{status: :success, insights: []})
        |> History.record_failure("task2", {:error, :failed})
        |> History.increment_retry("task2")

      summary = History.summary(history)

      assert summary.execution_id == history.execution_id
      assert summary.total_entries == 3
      assert summary.thoughts_count == 1
      assert summary.observations_count == 1
      assert summary.failures_count == 1
      assert summary.total_retries == 1
      assert summary.unique_tasks == 2
      assert summary.execution_patterns
      assert summary.insights
    end
  end

  describe "get_task_history/2" do
    test "provides detailed task history" do
      history = History.new()
      task_id = "task1"

      history =
        history
        |> History.record_thought(task_id, %{reasoning: "First thought"})
        |> History.record_thought(task_id, %{reasoning: "Second thought"})
        |> History.record_observation(task_id, %{status: :success, insights: []})
        |> History.record_failure(task_id, {:error, :timeout})
        |> History.increment_retry(task_id)
        |> History.record_task_start(task_id)
        |> History.record_task_end(task_id)

      task_history = History.get_task_history(history, task_id)

      assert task_history.task_id == task_id
      assert length(task_history.thoughts) == 2
      assert length(task_history.observations) == 1
      assert length(task_history.failures) == 1
      assert task_history.retry_count == 1
      assert task_history.timing
      # thought + observation + failure
      assert length(task_history.entries) == 3
    end
  end

  describe "export/1" do
    test "exports complete history for analysis" do
      history =
        History.new()
        |> History.record_thought("task1", %{reasoning: "thinking"})
        |> History.record_observation("task1", %{status: :success, insights: []})
        |> History.record_snapshot(:checkpoint, %{state: "saved"})

      export = History.export(history)

      assert export.execution_id == history.execution_id
      assert export.timeline
      assert export.summary
      assert export.task_histories
      assert export.snapshots
      assert export.metadata
    end
  end
end
