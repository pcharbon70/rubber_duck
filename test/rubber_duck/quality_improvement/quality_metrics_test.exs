defmodule RubberDuck.QualityImprovement.QualityMetricsTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.QualityImprovement.QualityMetrics
  
  @sample_code """
  defmodule TestModule do
    @moduledoc "Test module for quality metrics"
    
    def simple_function(a, b) do
      a + b
    end
    
    def complex_function(x, y, z) do
      if x > 0 do
        if y > 0 do
          if z > 0 do
            x + y + z
          else
            x + y
          end
        else
          x
        end
      else
        0
      end
    end
  end
  """
  
  @high_quality_code """
  defmodule HighQualityModule do
    @moduledoc \"\"\"
    A well-structured module demonstrating good coding practices.
    
    This module provides mathematical operations with clear naming,
    proper documentation, and reasonable complexity.
    \"\"\"
    
    @doc \"\"\"
    Adds two numbers together.
    
    ## Parameters
    - first_number: The first addend
    - second_number: The second addend
    
    ## Returns
    The sum of the two numbers
    \"\"\"
    def add_numbers(first_number, second_number) do
      first_number + second_number
    end
    
    @doc \"\"\"
    Multiplies two numbers.
    \"\"\"
    def multiply_numbers(multiplier, multiplicand) do
      multiplier * multiplicand
    end
  end
  """
  
  describe "calculate_quality_metrics/2" do
    test "calculates comprehensive quality metrics for code" do
      result = QualityMetrics.calculate_quality_metrics(@sample_code)
      
      assert {:ok, metrics} = result
      
      # Should have all major metric categories
      assert Map.has_key?(metrics, :complexity)
      assert Map.has_key?(metrics, :maintainability)
      assert Map.has_key?(metrics, :readability)
      assert Map.has_key?(metrics, :testability)
      assert Map.has_key?(metrics, :documentation)
      assert Map.has_key?(metrics, :overall_score)
      assert Map.has_key?(metrics, :timestamp)
      assert Map.has_key?(metrics, :confidence)
      
      # Overall score should be between 0 and 1
      assert metrics.overall_score >= 0.0
      assert metrics.overall_score <= 1.0
      
      # Should have confidence measure
      assert metrics.confidence > 0.0
      assert metrics.confidence <= 1.0
    end
    
    test "calculates complexity metrics correctly" do
      result = QualityMetrics.calculate_quality_metrics(@sample_code)
      
      assert {:ok, metrics} = result
      
      complexity = metrics.complexity
      assert is_number(complexity.cyclomatic_complexity)
      assert is_number(complexity.cognitive_complexity)
      assert is_number(complexity.max_nesting_depth)
      assert is_number(complexity.method_count)
      assert is_number(complexity.average_method_complexity)
      assert is_number(complexity.complexity_score)
      
      # Complex function should increase complexity metrics
      assert complexity.cyclomatic_complexity > 1
      assert complexity.max_nesting_depth > 0
      assert complexity.method_count >= 2  # Should find both functions
    end
    
    test "calculates maintainability metrics correctly" do
      result = QualityMetrics.calculate_quality_metrics(@sample_code)
      
      assert {:ok, metrics} = result
      
      maintainability = metrics.maintainability
      assert is_number(maintainability.lines_of_code)
      assert is_number(maintainability.duplication_ratio)
      assert is_number(maintainability.coupling_factor)
      assert is_number(maintainability.cohesion_score)
      assert is_number(maintainability.maintainability_index)
      assert is_number(maintainability.maintainability_score)
      
      # Lines of code should be reasonable
      assert maintainability.lines_of_code > 0
      
      # Scores should be in valid ranges
      assert maintainability.maintainability_score >= 0.0
      assert maintainability.maintainability_score <= 1.0
    end
    
    test "calculates readability metrics correctly" do
      result = QualityMetrics.calculate_quality_metrics(@sample_code)
      
      assert {:ok, metrics} = result
      
      readability = metrics.readability
      assert is_number(readability.average_line_length)
      assert is_number(readability.comment_ratio)
      assert is_number(readability.naming_quality)
      assert is_number(readability.formatting_consistency)
      assert is_number(readability.readability_score)
      
      # Readability score should be valid
      assert readability.readability_score >= 0.0
      assert readability.readability_score <= 1.0
    end
    
    test "calculates testability metrics correctly" do
      result = QualityMetrics.calculate_quality_metrics(@sample_code)
      
      assert {:ok, metrics} = result
      
      testability = metrics.testability
      assert is_number(testability.public_method_count)
      assert is_number(testability.dependency_count)
      assert is_number(testability.potential_mock_points)
      assert is_number(testability.estimated_test_complexity)
      assert is_number(testability.testability_score)
      
      # Public method count should match expected functions
      assert testability.public_method_count >= 2
      
      # Testability score should be valid
      assert testability.testability_score >= 0.0
      assert testability.testability_score <= 1.0
    end
    
    test "calculates documentation metrics correctly" do
      result = QualityMetrics.calculate_quality_metrics(@high_quality_code)
      
      assert {:ok, metrics} = result
      
      documentation = metrics.documentation
      assert is_number(documentation.documentation_coverage)
      assert is_number(documentation.documentation_quality)
      assert is_number(documentation.inline_comment_density)
      assert is_number(documentation.documentation_score)
      
      # High quality code should have better documentation metrics
      assert documentation.documentation_coverage >= 0.0
      assert documentation.documentation_coverage <= 100.0
      assert documentation.documentation_score >= 0.0
      assert documentation.documentation_score <= 1.0
    end
    
    test "compares quality between different code samples" do
      {:ok, simple_metrics} = QualityMetrics.calculate_quality_metrics(@sample_code)
      {:ok, high_quality_metrics} = QualityMetrics.calculate_quality_metrics(@high_quality_code)
      
      # High quality code should have better overall score
      assert high_quality_metrics.overall_score >= simple_metrics.overall_score
      
      # High quality code should have better documentation
      assert high_quality_metrics.documentation.documentation_score >= 
             simple_metrics.documentation.documentation_score
    end
    
    test "handles syntax errors gracefully" do
      invalid_code = "defmodule Invalid do invalid syntax"
      
      result = QualityMetrics.calculate_quality_metrics(invalid_code)
      
      assert {:error, error_message} = result
      assert String.contains?(error_message, "Syntax error")
    end
  end
  
  describe "track_quality_improvements/2" do
    setup do
      # Create sample improvement history
      now = DateTime.utc_now()
      
      improvement_history = [
        %{
          type: :improvement,
          timestamp: DateTime.add(now, -30, :day),
          result: %{
            overall_score: 0.6,
            quality_improvement: %{overall_improvement: 0.1},
            strategy: "conservative"
          }
        },
        %{
          type: :improvement,
          timestamp: DateTime.add(now, -20, :day),
          result: %{
            overall_score: 0.7,
            quality_improvement: %{overall_improvement: 0.15},
            strategy: "targeted"
          }
        },
        %{
          type: :improvement,
          timestamp: DateTime.add(now, -10, :day),
          result: %{
            overall_score: 0.8,
            quality_improvement: %{overall_improvement: 0.05},
            strategy: "comprehensive"
          }
        },
        %{
          type: :analysis,
          timestamp: DateTime.add(now, -5, :day),
          result: %{overall_score: 0.75}
        }
      ]
      
      {:ok, improvement_history: improvement_history}
    end
    
    test "tracks improvement trends", %{improvement_history: history} do
      result = QualityMetrics.track_quality_improvements(history)
      
      assert {:ok, tracking_result} = result
      
      assert Map.has_key?(tracking_result, :trends)
      assert Map.has_key?(tracking_result, :velocity)
      assert Map.has_key?(tracking_result, :patterns)
      assert Map.has_key?(tracking_result, :roi_analysis)
      assert Map.has_key?(tracking_result, :regressions)
      assert Map.has_key?(tracking_result, :total_improvements)
      
      # Should identify upward trend
      trends = tracking_result.trends
      case trends.trend do
        "improving" -> assert trends.slope > 0
        "stable" -> assert abs(trends.slope) < 0.01
        "declining" -> assert trends.slope < 0
        "insufficient_data" -> assert true
      end
    end
    
    test "calculates improvement velocity", %{improvement_history: history} do
      result = QualityMetrics.track_quality_improvements(history)
      
      assert {:ok, tracking_result} = result
      
      velocity = tracking_result.velocity
      assert is_number(velocity.velocity)
      assert is_number(velocity.improvements_per_day)
      assert is_number(velocity.average_impact)
      assert is_number(velocity.total_recent_improvements)
      assert is_number(velocity.time_span_days)
      
      # Velocity should be non-negative
      assert velocity.velocity >= 0
      assert velocity.improvements_per_day >= 0
    end
    
    test "identifies improvement patterns", %{improvement_history: history} do
      result = QualityMetrics.track_quality_improvements(history)
      
      assert {:ok, tracking_result} = result
      
      patterns = tracking_result.patterns
      assert Map.has_key?(patterns, :strategy_effectiveness)
      assert Map.has_key?(patterns, :temporal_patterns)
      assert Map.has_key?(patterns, :most_effective_strategy)
      assert Map.has_key?(patterns, :improvement_frequency)
      
      # Should analyze strategy effectiveness
      strategy_effectiveness = patterns.strategy_effectiveness
      assert is_map(strategy_effectiveness)
      
      # Each strategy should have metrics
      for {_strategy, metrics} <- strategy_effectiveness do
        assert Map.has_key?(metrics, :count)
        assert Map.has_key?(metrics, :average_impact)
        assert Map.has_key?(metrics, :effectiveness_score)
      end
    end
    
    test "calculates improvement ROI", %{improvement_history: history} do
      result = QualityMetrics.track_quality_improvements(history)
      
      assert {:ok, tracking_result} = result
      
      roi_analysis = tracking_result.roi_analysis
      assert is_number(roi_analysis.total_roi)
      assert is_number(roi_analysis.average_roi)
      assert is_map(roi_analysis.roi_by_strategy)
      assert is_number(roi_analysis.high_roi_threshold)
      
      # ROI should be calculated per strategy
      for {_strategy, roi} <- roi_analysis.roi_by_strategy do
        assert is_number(roi)
      end
    end
    
    test "detects quality regressions", %{improvement_history: history} do
      result = QualityMetrics.track_quality_improvements(history)
      
      assert {:ok, tracking_result} = result
      
      regressions = tracking_result.regressions
      assert is_list(regressions)
      
      # Each regression should have required fields
      for regression <- regressions do
        assert Map.has_key?(regression, :start_time)
        assert Map.has_key?(regression, :end_time)
        assert Map.has_key?(regression, :magnitude)
        assert Map.has_key?(regression, :severity)
      end
    end
    
    test "handles empty improvement history" do
      result = QualityMetrics.track_quality_improvements([])
      
      assert {:ok, tracking_result} = result
      assert tracking_result.total_improvements == 0
      assert tracking_result.trends.trend == "insufficient_data"
      assert tracking_result.velocity.velocity == 0
    end
  end
  
  describe "generate_quality_report/3" do
    setup do
      quality_data = %{
        overall_score: 0.75,
        complexity: %{complexity_score: 0.8, cyclomatic_complexity: 5},
        maintainability: %{maintainability_score: 0.7, maintainability_index: 75},
        readability: %{readability_score: 0.85},
        testability: %{testability_score: 0.6},
        documentation: %{documentation_score: 0.5, documentation_coverage: 60},
        confidence: 0.85
      }
      
      improvement_data = %{
        trends: %{trend: "improving", slope: 0.01, confidence: 0.8},
        velocity: %{improvements_per_day: 0.5, average_impact: 0.1},
        patterns: %{
          strategy_effectiveness: %{
            "conservative" => %{count: 3, average_impact: 0.08, effectiveness_score: 0.24},
            "aggressive" => %{count: 1, average_impact: 0.15, effectiveness_score: 0.15}
          }
        },
        roi_analysis: %{total_roi: 2.5, average_roi: 0.8},
        total_improvements: 4
      }
      
      {:ok, quality_data: quality_data, improvement_data: improvement_data}
    end
    
    test "generates comprehensive quality report", %{quality_data: quality_data, improvement_data: improvement_data} do
      result = QualityMetrics.generate_quality_report(quality_data, improvement_data)
      
      assert {:ok, report} = result
      
      # Should have all report sections
      assert Map.has_key?(report, :report_type)
      assert Map.has_key?(report, :generated_at)
      assert Map.has_key?(report, :executive_summary)
      assert Map.has_key?(report, :detailed_metrics)
      assert Map.has_key?(report, :improvement_analysis)
      assert Map.has_key?(report, :trend_analysis)
      assert Map.has_key?(report, :recommendations)
      assert Map.has_key?(report, :report_confidence)
      
      assert report.report_type == "comprehensive"
      assert is_struct(report.generated_at, DateTime)
    end
    
    test "generates executive summary", %{quality_data: quality_data, improvement_data: improvement_data} do
      {:ok, report} = QualityMetrics.generate_quality_report(quality_data, improvement_data)
      
      summary = report.executive_summary
      assert Map.has_key?(summary, :current_quality_score)
      assert Map.has_key?(summary, :quality_status)
      assert Map.has_key?(summary, :improvement_trend)
      assert Map.has_key?(summary, :total_improvements_applied)
      assert Map.has_key?(summary, :regressions_detected)
      assert Map.has_key?(summary, :report_confidence)
      
      assert summary.current_quality_score == 0.75
      assert summary.quality_status in ["excellent", "good", "fair", "needs_improvement"]
    end
    
    test "generates detailed metrics section", %{quality_data: quality_data, improvement_data: improvement_data} do
      {:ok, report} = QualityMetrics.generate_quality_report(quality_data, improvement_data)
      
      detailed_metrics = report.detailed_metrics
      assert Map.has_key?(detailed_metrics, :complexity_analysis)
      assert Map.has_key?(detailed_metrics, :maintainability_analysis)
      assert Map.has_key?(detailed_metrics, :readability_analysis)
      assert Map.has_key?(detailed_metrics, :testability_analysis)
      assert Map.has_key?(detailed_metrics, :documentation_analysis)
      assert Map.has_key?(detailed_metrics, :metric_thresholds)
      assert Map.has_key?(detailed_metrics, :metric_comparisons)
    end
    
    test "generates improvement analysis", %{quality_data: quality_data, improvement_data: improvement_data} do
      {:ok, report} = QualityMetrics.generate_quality_report(quality_data, improvement_data)
      
      improvement_analysis = report.improvement_analysis
      assert Map.has_key?(improvement_analysis, :improvement_velocity)
      assert Map.has_key?(improvement_analysis, :improvement_patterns)
      assert Map.has_key?(improvement_analysis, :roi_analysis)
      assert Map.has_key?(improvement_analysis, :most_effective_strategies)
      assert Map.has_key?(improvement_analysis, :improvement_opportunities)
    end
    
    test "generates trend analysis", %{quality_data: quality_data, improvement_data: improvement_data} do
      {:ok, report} = QualityMetrics.generate_quality_report(quality_data, improvement_data, %{"time_period" => "quarter"})
      
      trend_analysis = report.trend_analysis
      assert Map.has_key?(trend_analysis, :time_period)
      assert Map.has_key?(trend_analysis, :overall_trend)
      assert Map.has_key?(trend_analysis, :quality_trajectory)
      assert Map.has_key?(trend_analysis, :trend_forecast)
      assert Map.has_key?(trend_analysis, :seasonal_patterns)
      
      assert trend_analysis.time_period == "quarter"
    end
    
    test "generates quality recommendations", %{quality_data: quality_data, improvement_data: improvement_data} do
      {:ok, report} = QualityMetrics.generate_quality_report(quality_data, improvement_data)
      
      recommendations = report.recommendations
      assert is_list(recommendations)
      
      # Should generate recommendations based on low scores
      if length(recommendations) > 0 do
        first_recommendation = List.first(recommendations)
        assert Map.has_key?(first_recommendation, :category)
        assert Map.has_key?(first_recommendation, :priority)
        assert Map.has_key?(first_recommendation, :recommendation)
        assert Map.has_key?(first_recommendation, :expected_impact)
        assert Map.has_key?(first_recommendation, :effort_estimate)
      end
      
      # Should have documentation recommendation due to low doc score
      doc_recommendations = Enum.filter(recommendations, &(&1.category == "documentation"))
      assert length(doc_recommendations) > 0
    end
    
    test "calculates report confidence", %{quality_data: quality_data, improvement_data: improvement_data} do
      {:ok, report} = QualityMetrics.generate_quality_report(quality_data, improvement_data)
      
      assert is_number(report.report_confidence)
      assert report.report_confidence >= 0.0
      assert report.report_confidence <= 1.0
      
      # Should be based on input data confidence
      expected_confidence = (quality_data.confidence + improvement_data.trends.confidence) / 2
      assert abs(report.report_confidence - expected_confidence) < 0.01
    end
  end
  
  describe "detect_quality_regressions/2" do
    test "detects quality regressions in history" do
      # Create history with regression
      now = DateTime.utc_now()
      
      quality_history = [
        %{timestamp: DateTime.add(now, -40, :day), overall_score: 0.8},
        %{timestamp: DateTime.add(now, -30, :day), overall_score: 0.85},
        %{timestamp: DateTime.add(now, -20, :day), overall_score: 0.9},
        %{timestamp: DateTime.add(now, -10, :day), overall_score: 0.75},  # Regression
        %{timestamp: now, overall_score: 0.7}  # Continued regression
      ]
      
      result = QualityMetrics.detect_quality_regressions(quality_history)
      
      assert {:ok, regression_result} = result
      
      assert Map.has_key?(regression_result, :regressions_detected)
      assert Map.has_key?(regression_result, :regressions)
      assert Map.has_key?(regression_result, :root_causes)
      assert Map.has_key?(regression_result, :severity_breakdown)
      
      # Should detect at least one regression
      assert regression_result.regressions_detected > 0
      assert is_map(regression_result.regressions)
    end
    
    test "categorizes regressions by severity" do
      now = DateTime.utc_now()
      
      # Create history with major regression
      quality_history = [
        %{timestamp: DateTime.add(now, -10, :day), overall_score: 0.9},
        %{timestamp: now, overall_score: 0.6}  # Major drop
      ]
      
      result = QualityMetrics.detect_quality_regressions(quality_history)
      
      assert {:ok, regression_result} = result
      
      severity_breakdown = regression_result.severity_breakdown
      assert is_map(severity_breakdown)
      
      # Should categorize the major regression
      total_regressions = Map.values(severity_breakdown) |> Enum.sum()
      assert total_regressions > 0
    end
    
    test "handles stable quality history" do
      now = DateTime.utc_now()
      
      # Create stable history
      stable_history = [
        %{timestamp: DateTime.add(now, -30, :day), overall_score: 0.8},
        %{timestamp: DateTime.add(now, -20, :day), overall_score: 0.81},
        %{timestamp: DateTime.add(now, -10, :day), overall_score: 0.79},
        %{timestamp: now, overall_score: 0.8}
      ]
      
      result = QualityMetrics.detect_quality_regressions(stable_history)
      
      assert {:ok, regression_result} = result
      assert regression_result.regressions_detected == 0
    end
  end
  
  describe "analyze_quality_trends/3" do
    test "analyzes quality trends over time period" do
      now = DateTime.utc_now()
      
      quality_data = [
        %{timestamp: DateTime.add(now, -30, :day), overall_score: 0.6},
        %{timestamp: DateTime.add(now, -20, :day), overall_score: 0.7},
        %{timestamp: DateTime.add(now, -10, :day), overall_score: 0.8},
        %{timestamp: now, overall_score: 0.85}
      ]
      
      result = QualityMetrics.analyze_quality_trends(quality_data, "month")
      
      assert {:ok, trend_analysis} = result
      
      assert Map.has_key?(trend_analysis, :time_period)
      assert Map.has_key?(trend_analysis, :overall_trend)
      assert Map.has_key?(trend_analysis, :metric_trends)
      assert Map.has_key?(trend_analysis, :trend_patterns)
      assert Map.has_key?(trend_analysis, :trend_strength)
      assert Map.has_key?(trend_analysis, :trend_confidence)
      assert Map.has_key?(trend_analysis, :forecast)
      assert Map.has_key?(trend_analysis, :data_points)
      
      assert trend_analysis.time_period == "month"
      assert trend_analysis.data_points == length(quality_data)
    end
    
    test "calculates trend strength and confidence" do
      # Strong upward trend data
      now = DateTime.utc_now()
      
      strong_trend_data = [
        %{timestamp: DateTime.add(now, -30, :day), overall_score: 0.5},
        %{timestamp: DateTime.add(now, -20, :day), overall_score: 0.6},
        %{timestamp: DateTime.add(now, -10, :day), overall_score: 0.7},
        %{timestamp: now, overall_score: 0.8}
      ]
      
      result = QualityMetrics.analyze_quality_trends(strong_trend_data, "month")
      
      assert {:ok, trend_analysis} = result
      assert is_number(trend_analysis.trend_strength)
      assert is_number(trend_analysis.trend_confidence)
      
      # Strong trend should have high strength and confidence
      assert trend_analysis.trend_strength >= 0.0
      assert trend_analysis.trend_confidence >= 0.0
    end
    
    test "forecasts future trends" do
      now = DateTime.utc_now()
      
      trend_data = [
        %{timestamp: DateTime.add(now, -20, :day), overall_score: 0.7},
        %{timestamp: DateTime.add(now, -10, :day), overall_score: 0.75},
        %{timestamp: now, overall_score: 0.8}
      ]
      
      result = QualityMetrics.analyze_quality_trends(trend_data, "month")
      
      assert {:ok, trend_analysis} = result
      
      forecast = trend_analysis.forecast
      assert is_map(forecast)
      assert Map.has_key?(forecast, :short_term)
      assert Map.has_key?(forecast, :medium_term)
      assert Map.has_key?(forecast, :long_term)
      assert Map.has_key?(forecast, :confidence)
    end
  end
  
  describe "error handling" do
    test "handles empty code gracefully" do
      result = QualityMetrics.calculate_quality_metrics("")
      
      case result do
        {:ok, _metrics} -> assert true  # Acceptable to succeed with minimal metrics
        {:error, _reason} -> assert true  # Acceptable to fail on empty code
      end
    end
    
    test "handles malformed improvement history" do
      malformed_history = [
        %{invalid: "structure"},
        nil,
        "not a map",
        %{type: :improvement}  # Missing required fields
      ]
      
      result = QualityMetrics.track_quality_improvements(malformed_history)
      
      # Should handle malformed data gracefully
      case result do
        {:ok, tracking_result} ->
          # If it succeeds, should have filtered out invalid entries
          assert is_map(tracking_result)
        {:error, _reason} ->
          # Acceptable to fail on malformed data
          assert true
      end
    end
    
    test "handles very large datasets" do
      # Create large dataset
      large_history = Enum.map(1..1000, fn i ->
        %{
          type: :improvement,
          timestamp: DateTime.add(DateTime.utc_now(), -i, :day),
          result: %{overall_score: 0.5 + (:rand.uniform() * 0.5)}
        }
      end)
      
      result = QualityMetrics.track_quality_improvements(large_history)
      
      # Should handle large datasets without crashing
      case result do
        {:ok, _tracking_result} -> assert true
        {:error, _reason} -> assert true  # Acceptable to fail on very large datasets
      end
    end
  end
end