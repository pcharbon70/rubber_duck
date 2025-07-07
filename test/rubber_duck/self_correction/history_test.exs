defmodule RubberDuck.SelfCorrection.HistoryTest do
  use ExUnit.Case, async: false

  alias RubberDuck.SelfCorrection.History

  setup do
    # Start the history process if not already started
    case Process.whereis(History) do
      nil -> {:ok, _} = History.start_link()
      _ -> :ok
    end

    # Clean up any existing history
    History.cleanup_history(max_entries: 0)

    :ok
  end

  describe "record_correction/1" do
    test "records correction data" do
      correction_data = %{
        correction_type: :spelling,
        strategy: :semantic,
        content_type: :text,
        issues_found: [:typo, :grammar],
        corrections_applied: ["fix spelling", "fix grammar"],
        success: true,
        improvement_score: 0.15,
        iterations: 2,
        convergence_time: 1.5,
        metadata: %{language: "english"}
      }

      assert :ok = History.record_correction(correction_data)

      # Give it time to process
      Process.sleep(50)

      # Verify it was recorded
      history = History.get_history(:all, limit: 1)
      assert length(history) == 1

      [entry] = history
      assert entry.correction_type == :spelling
      assert entry.strategy == :semantic
      assert entry.success == true
    end

    test "handles multiple recordings" do
      for i <- 1..5 do
        History.record_correction(%{
          correction_type: :syntax,
          strategy: :syntax,
          content_type: :code,
          issues_found: [:unmatched_delimiter],
          corrections_applied: ["add end"],
          # First 2 fail, rest succeed
          success: i > 2,
          improvement_score: i * 0.1,
          iterations: i,
          convergence_time: i * 0.5,
          metadata: %{}
        })
      end

      Process.sleep(100)

      history = History.get_history(:all)
      assert length(history) == 5
    end
  end

  describe "get_history/2" do
    setup do
      # Add some test data
      for i <- 1..10 do
        History.record_correction(%{
          correction_type: if(rem(i, 2) == 0, do: :syntax, else: :semantic),
          strategy: if(rem(i, 2) == 0, do: :syntax, else: :semantic),
          content_type: :code,
          issues_found: [:test_issue],
          corrections_applied: ["test fix #{i}"],
          success: rem(i, 3) != 0,
          improvement_score: i * 0.05,
          iterations: i,
          convergence_time: i * 0.3,
          metadata: %{}
        })
      end

      Process.sleep(100)
      :ok
    end

    test "retrieves all history with limit" do
      history = History.get_history(:all, limit: 5)
      assert length(history) == 5
    end

    test "filters by pattern type" do
      syntax_history = History.get_history(:syntax)

      assert Enum.all?(syntax_history, fn entry ->
               entry.correction_type == :syntax
             end)
    end

    test "filters by time" do
      cutoff = DateTime.add(DateTime.utc_now(), -1, :hour)
      recent_history = History.get_history(:all, since: cutoff)

      assert length(recent_history) > 0

      assert Enum.all?(recent_history, fn entry ->
               DateTime.compare(entry.timestamp, cutoff) == :gt
             end)
    end
  end

  describe "analyze_patterns/1" do
    setup do
      # Add varied test data
      strategies = [:syntax, :semantic, :logic]

      for i <- 1..30 do
        strategy = Enum.at(strategies, rem(i, 3))

        History.record_correction(%{
          correction_type: strategy,
          strategy: strategy,
          content_type: if(i < 15, do: :code, else: :text),
          issues_found: [:issue1, :issue2] ++ if(rem(i, 5) == 0, do: [:issue3], else: []),
          corrections_applied: ["fix #{i}"],
          success: rem(i, 4) != 0,
          improvement_score: if(rem(i, 4) != 0, do: 0.1 + rem(i, 10) * 0.05, else: 0),
          iterations: 1 + rem(i, 5),
          convergence_time: 0.5 + rem(i, 5) * 0.3,
          metadata: %{}
        })
      end

      Process.sleep(200)
      :ok
    end

    test "analyzes overall patterns" do
      analysis = History.analyze_patterns()

      assert analysis.total_corrections == 30
      assert is_float(analysis.success_rate)
      assert analysis.success_rate > 0.5
      assert is_float(analysis.average_iterations)
      assert is_list(analysis.common_issues)
      assert is_map(analysis.effective_strategies)
      assert is_list(analysis.improvement_trends)
      assert is_map(analysis.convergence_patterns)
    end

    test "identifies common issues" do
      analysis = History.analyze_patterns()

      assert length(analysis.common_issues) > 0
      [most_common | _] = analysis.common_issues
      assert most_common.issue in [:issue1, :issue2]
      assert most_common.count > 0
    end

    test "analyzes strategy effectiveness" do
      analysis = History.analyze_patterns()

      assert Map.has_key?(analysis.effective_strategies, :syntax)
      assert Map.has_key?(analysis.effective_strategies, :semantic)

      syntax_stats = analysis.effective_strategies.syntax
      assert is_float(syntax_stats.success_rate)
      assert is_float(syntax_stats.average_improvement)
      assert is_integer(syntax_stats.sample_size)
    end

    test "filters analysis by options" do
      code_analysis = History.analyze_patterns(content_type: :code)
      text_analysis = History.analyze_patterns(content_type: :text)

      assert code_analysis.total_corrections < 30
      assert text_analysis.total_corrections < 30
      assert code_analysis.total_corrections + text_analysis.total_corrections == 30
    end
  end

  describe "get_success_metrics/0" do
    setup do
      # Add success/failure data
      for i <- 1..20 do
        History.record_correction(%{
          correction_type: :test,
          strategy: if(i <= 10, do: :strategy_a, else: :strategy_b),
          content_type: :test,
          issues_found: [:test],
          corrections_applied: ["test"],
          success: if(i <= 10, do: i > 3, else: i > 15),
          improvement_score: 0.1,
          iterations: 1,
          convergence_time: 0.5,
          metadata: %{}
        })
      end

      Process.sleep(100)
      :ok
    end

    test "calculates success metrics" do
      metrics = History.get_success_metrics()

      assert is_float(metrics.overall_success_rate)
      assert metrics.overall_success_rate > 0
      assert metrics.overall_success_rate < 1
      assert metrics.total_corrections == 20

      assert Map.has_key?(metrics.strategy_metrics, :strategy_a)
      assert Map.has_key?(metrics.strategy_metrics, :strategy_b)

      strategy_a = metrics.strategy_metrics.strategy_a
      assert strategy_a.total == 10
      assert strategy_a.successes == 7
      assert strategy_a.failures == 3
      assert_in_delta strategy_a.success_rate, 0.7, 0.01
    end
  end

  describe "cleanup_history/1" do
    setup do
      # Add old and new entries
      for i <- 1..20 do
        History.record_correction(%{
          correction_type: :test,
          strategy: :test,
          content_type: :test,
          issues_found: [:test],
          corrections_applied: ["test"],
          success: true,
          improvement_score: 0.1,
          iterations: 1,
          convergence_time: 0.5,
          metadata: %{index: i}
        })
      end

      Process.sleep(100)
      :ok
    end

    test "cleans up by max entries" do
      {:ok, removed} = History.cleanup_history(max_entries: 10)

      assert removed == 10
      remaining = History.get_history(:all)
      assert length(remaining) == 10
    end

    test "preserves most recent entries" do
      History.cleanup_history(max_entries: 5)

      remaining = History.get_history(:all)
      assert length(remaining) == 5

      # Should have kept the last 5 entries (16-20)
      indices = Enum.map(remaining, fn entry -> entry.metadata.index end)
      assert Enum.all?(indices, fn i -> i > 15 end)
    end
  end
end
