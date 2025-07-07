defmodule RubberDuck.SelfCorrection.LearnerTest do
  use ExUnit.Case, async: false

  alias RubberDuck.SelfCorrection.{Learner, History}

  setup do
    # Ensure processes are started
    case Process.whereis(History) do
      nil -> {:ok, _} = History.start_link()
      _ -> :ok
    end

    case Process.whereis(Learner) do
      nil -> {:ok, _} = Learner.start_link()
      _ -> :ok
    end

    # Clean history for fresh start
    History.cleanup_history(max_entries: 0)

    # Seed with learning data
    seed_learning_data()

    # Give learner time to process
    Process.sleep(200)

    :ok
  end

  defp seed_learning_data() do
    # Add diverse correction history
    strategies = [:syntax, :semantic, :logic]
    content_types = [:code, :text]

    for i <- 1..50 do
      strategy = Enum.at(strategies, rem(i, 3))
      content_type = Enum.at(content_types, rem(i, 2))

      # Make some strategies more effective for certain content types
      success =
        case {strategy, content_type} do
          # 80% success
          {:syntax, :code} -> rem(i, 10) > 2
          # 70% success
          {:semantic, :text} -> rem(i, 10) > 3
          # 60% success
          {:logic, _} -> rem(i, 10) > 4
          # 50% success
          _ -> rem(i, 2) == 0
        end

      History.record_correction(%{
        correction_type: strategy,
        strategy: strategy,
        content_type: content_type,
        issues_found: generate_issues(strategy, i),
        corrections_applied: ["correction_#{i}"],
        success: success,
        improvement_score: if(success, do: 0.1 + rem(i, 5) * 0.05, else: 0),
        iterations: 1 + rem(i, 4),
        convergence_time: 0.5 + rem(i, 4) * 0.2,
        metadata: %{test_index: i}
      })
    end
  end

  defp generate_issues(strategy, seed) do
    base_issues =
      case strategy do
        :syntax -> [:unmatched_delimiter, :syntax_error, :missing_comma]
        :semantic -> [:poor_naming, :unclear_reference, :redundancy]
        :logic -> [:impossible_condition, :unhandled_error, :weak_argument]
      end

    # Pick 1-2 issues based on seed
    Enum.take(base_issues, 1 + rem(seed, 2))
  end

  describe "get_insights/3" do
    test "provides insights for known patterns" do
      insights = Learner.get_insights(:code, :syntax, %{})

      assert insights.has_historical_data == true
      assert is_list(insights.recommended_strategies)
      assert length(insights.recommended_strategies) > 0
      assert is_float(insights.expected_iterations)
      assert is_map(insights.expected_improvement)
      assert insights.confidence_level in [:low, :medium, :high]
      assert is_list(insights.tips)
    end

    test "provides default insights for unknown patterns" do
      insights = Learner.get_insights(:unknown_type, :unknown_issue, %{})

      assert insights.has_historical_data == false
      assert is_list(insights.recommended_strategies)
      assert insights.confidence_level == :low
    end

    test "recommends effective strategies" do
      # Syntax should be recommended for code
      code_insights = Learner.get_insights(:code, :syntax_error, %{})
      assert :syntax in code_insights.recommended_strategies

      # Semantic should be recommended for text
      text_insights = Learner.get_insights(:text, :unclear_reference, %{})
      assert :semantic in text_insights.recommended_strategies
    end
  end

  describe "get_strategy_rankings/0" do
    test "ranks strategies by effectiveness" do
      rankings = Learner.get_strategy_rankings()

      assert is_list(rankings)
      assert length(rankings) > 0

      [top_strategy | _] = rankings
      assert Map.has_key?(top_strategy, :strategy)
      assert Map.has_key?(top_strategy, :score)
      assert Map.has_key?(top_strategy, :success_rate)
      assert Map.has_key?(top_strategy, :average_improvement)
      assert Map.has_key?(top_strategy, :reliability)
      assert Map.has_key?(top_strategy, :sample_size)

      # Verify descending order by score
      scores = Enum.map(rankings, & &1.score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "syntax strategy ranks high for code" do
      # Force update to ensure fresh calculations
      Learner.update_recommendations()
      Process.sleep(100)

      rankings = Learner.get_strategy_rankings()

      # Find syntax strategy
      syntax_ranking = Enum.find(rankings, fn r -> r.strategy == :syntax end)
      assert syntax_ranking != nil
      # We seeded it with 80% success
      assert syntax_ranking.success_rate > 0.7
    end
  end

  describe "suggest_corrections/3" do
    test "suggests corrections based on patterns" do
      content = "def a(b, c) do\n  d = b + c\n  d\nend"

      suggestions = Learner.suggest_corrections(content, :code, %{})

      assert is_list(suggestions)

      if length(suggestions) > 0 do
        [suggestion | _] = suggestions
        assert Map.has_key?(suggestion, :issue_type)
        assert Map.has_key?(suggestion, :correction)
        assert Map.has_key?(suggestion, :confidence)
        assert Map.has_key?(suggestion, :based_on_samples)
        assert Map.has_key?(suggestion, :recommended_strategy)
      end
    end

    test "orders suggestions by confidence" do
      content = "This has issues"

      suggestions = Learner.suggest_corrections(content, :text, %{})

      if length(suggestions) > 1 do
        confidences = Enum.map(suggestions, & &1.confidence)
        assert confidences == Enum.sort(confidences, :desc)
      end
    end
  end

  describe "update_recommendations/0" do
    test "updates learning from recent history" do
      # Add new correction data
      History.record_correction(%{
        correction_type: :new_pattern,
        strategy: :syntax,
        content_type: :code,
        issues_found: [:new_issue],
        corrections_applied: ["new_fix"],
        success: true,
        improvement_score: 0.5,
        iterations: 1,
        convergence_time: 0.3,
        metadata: %{}
      })

      # Trigger update
      :ok = Learner.update_recommendations()
      Process.sleep(100)

      # Should now have insights for new pattern
      insights = Learner.get_insights(:code, :new_pattern, %{})
      assert insights.has_historical_data == true
    end
  end

  describe "learning patterns" do
    test "identifies correlated issues" do
      # Add corrections with correlated issues
      for i <- 1..20 do
        History.record_correction(%{
          correction_type: :correlation_test,
          strategy: :logic,
          content_type: :code,
          # Always appear together
          issues_found: [:issue_a, :issue_b],
          corrections_applied: ["fix"],
          success: true,
          improvement_score: 0.2,
          iterations: 2,
          convergence_time: 1.0,
          metadata: %{}
        })
      end

      # Force relearning
      Learner.update_recommendations()
      Process.sleep(100)

      insights = Learner.get_insights(:code, :issue_a, %{})

      # Should mention correlation in tips
      assert Enum.any?(insights.tips, fn tip ->
               String.contains?(tip, "often appears with")
             end)
    end

    test "models convergence patterns" do
      # Add consistent convergence data
      for i <- 1..15 do
        History.record_correction(%{
          correction_type: :convergence_test,
          strategy: :semantic,
          content_type: :text,
          issues_found: [:clarity],
          corrections_applied: ["improve clarity"],
          success: true,
          improvement_score: 0.3,
          # Consistent iterations
          iterations: 3,
          # Consistent time
          convergence_time: 1.5,
          metadata: %{}
        })
      end

      Learner.update_recommendations()
      Process.sleep(100)

      insights = Learner.get_insights(:text, :clarity, %{})

      # Should predict ~3 iterations based on history
      assert_in_delta insights.expected_iterations, 3.0, 0.5
    end

    test "adapts to changing patterns" do
      # First batch - low success
      for i <- 1..10 do
        History.record_correction(%{
          correction_type: :adaptive_test,
          strategy: :logic,
          content_type: :code,
          issues_found: [:complex_logic],
          corrections_applied: ["simplify"],
          success: false,
          improvement_score: 0,
          iterations: 5,
          convergence_time: 3.0,
          metadata: %{batch: 1}
        })
      end

      Learner.update_recommendations()
      Process.sleep(100)

      first_insights = Learner.get_insights(:code, :complex_logic, %{})
      first_success_rate = first_insights.success_rate

      # Second batch - high success (improved approach)
      for i <- 1..10 do
        History.record_correction(%{
          correction_type: :adaptive_test,
          strategy: :logic,
          content_type: :code,
          issues_found: [:complex_logic],
          corrections_applied: ["refactor"],
          success: true,
          improvement_score: 0.4,
          iterations: 2,
          convergence_time: 1.0,
          metadata: %{batch: 2}
        })
      end

      Learner.update_recommendations()
      Process.sleep(100)

      second_insights = Learner.get_insights(:code, :complex_logic, %{})

      # Success rate should improve
      assert second_insights.success_rate > first_success_rate
      assert second_insights.expected_iterations < first_insights.expected_iterations
    end
  end
end
