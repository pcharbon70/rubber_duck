defmodule RubberDuck.Enhancement.MetricsCollectorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Enhancement.MetricsCollector

  describe "collect/2" do
    test "collects base metrics from result" do
      result = %{
        original: "def add(a, b), do: a + b",
        enhanced: "def add(a, b) when is_number(a) and is_number(b), do: a + b",
        duration_ms: 1500,
        techniques_applied: [:cot, :self_correction]
      }

      metrics = MetricsCollector.collect(result, [:cot, :self_correction])

      assert metrics["execution_time_ms"] == 1500
      assert metrics["content_length_original"] == String.length(result.original)
      assert metrics["content_length_enhanced"] == String.length(result.enhanced)
      assert metrics["techniques_count"] == 2
      assert metrics["timestamp"] != nil
    end

    test "collects CoT-specific metrics" do
      result = %{
        original: "test",
        enhanced: "enhanced test",
        context: %{
          cot_chain: %{
            steps: [%{}, %{}, %{}],
            depth: 3,
            valid: true
          }
        }
      }

      metrics = MetricsCollector.collect(result, [:cot])

      assert metrics["cot_steps_count"] == 3
      assert metrics["cot_reasoning_depth"] == 3
      assert metrics["cot_validation_passed"] == true
    end

    test "collects RAG-specific metrics" do
      result = %{
        original: "query",
        enhanced: "enhanced with context",
        context: %{
          rag_sources: [
            %{relevance_score: 0.9},
            %{relevance_score: 0.8},
            %{relevance_score: 0.7}
          ],
          rag_retrieval_time: 500
        }
      }

      metrics = MetricsCollector.collect(result, [:rag])

      assert metrics["rag_sources_count"] == 3
      assert_in_delta metrics["rag_avg_relevance"], 0.8, 0.01
      assert metrics["rag_retrieval_time_ms"] == 500
    end

    test "collects self-correction metrics" do
      result = %{
        original: "buggy code",
        enhanced: "fixed code",
        iterations: 2,
        context: %{
          corrections_applied: [%{}, %{}],
          converged: true
        }
      }

      metrics = MetricsCollector.collect(result, [:self_correction])

      assert metrics["self_correction_iterations"] == 2
      assert metrics["self_correction_changes"] == 2
      assert metrics["self_correction_converged"] == true
    end

    test "calculates quality improvement metrics" do
      result = %{
        original: "def add(a, b), do: a + b",
        enhanced: """
        @doc "Adds two numbers"
        def add(a, b) when is_number(a) and is_number(b) do
          a + b
        end
        """,
        context: %{}
      }

      metrics = MetricsCollector.collect(result, [:cot])

      assert metrics["quality_improvement"] > 0
      assert metrics["readability_score"] > 0
      assert metrics["completeness_score"] > 0
      assert metrics["consistency_score"] > 0
    end

    test "handles missing data gracefully" do
      result = %{
        original: "",
        enhanced: "something"
      }

      metrics = MetricsCollector.collect(result, [])

      assert is_map(metrics)
      assert metrics["content_length_original"] == 0
      assert metrics["content_length_enhanced"] == 9
    end
  end

  describe "aggregate/1" do
    test "aggregates multiple metric sets" do
      metrics_list = [
        %{"quality_improvement" => 0.7, "execution_time_ms" => 1000},
        %{"quality_improvement" => 0.8, "execution_time_ms" => 1200},
        %{"quality_improvement" => 0.6, "execution_time_ms" => 900}
      ]

      aggregated = MetricsCollector.aggregate(metrics_list)

      assert aggregated.count == 3
      assert_in_delta aggregated.averages["quality_improvement"], 0.7, 0.01
      assert aggregated.averages["execution_time_ms"] == 1033.33 |> Float.round(2)
      assert aggregated.totals["execution_time_ms"] == 3100
    end

    test "calculates distributions" do
      metrics_list =
        Enum.map(1..10, fn i ->
          %{"quality_improvement" => i * 0.1}
        end)

      aggregated = MetricsCollector.aggregate(metrics_list)

      dist = aggregated.distributions["quality_improvement"]
      assert dist.min == 0.1
      assert dist.max == 1.0
      assert_in_delta dist.median, 0.55, 0.01
      assert dist.p95 >= 0.9
    end

    test "handles empty metrics list" do
      assert MetricsCollector.aggregate([]) == %{}
    end

    test "calculates success rate" do
      metrics_list = [
        %{"overall_success" => true},
        %{"overall_success" => true},
        %{"overall_success" => false}
      ]

      aggregated = MetricsCollector.aggregate(metrics_list)

      assert_in_delta aggregated.success_rate, 0.667, 0.01
    end
  end

  describe "format_metrics/1" do
    test "formats metrics for display" do
      metrics = %{
        "quality_improvement" => 0.75,
        "execution_time_ms" => 1234,
        "success" => true,
        "details" => %{nested: "value"}
      }

      formatted = MetricsCollector.format_metrics(metrics)

      assert formatted =~ "quality_improvement: 0.75"
      assert formatted =~ "execution_time_ms: 1234"
      assert formatted =~ "success: true"
      assert formatted =~ "details:"
    end

    test "sorts metrics alphabetically" do
      metrics = %{
        "z_metric" => 1,
        "a_metric" => 2,
        "m_metric" => 3
      }

      formatted = MetricsCollector.format_metrics(metrics)
      lines = String.split(formatted, "\n")

      assert Enum.at(lines, 0) =~ "a_metric"
      assert Enum.at(lines, 1) =~ "m_metric"
      assert Enum.at(lines, 2) =~ "z_metric"
    end
  end

  describe "export/2" do
    test "exports to JSON format" do
      metrics = %{
        "quality_improvement" => 0.8,
        "techniques_count" => 3
      }

      json = MetricsCollector.export(metrics, :json)
      parsed = Jason.decode!(json)

      assert parsed["quality_improvement"] == 0.8
      assert parsed["techniques_count"] == 3
    end

    test "exports to CSV format" do
      metrics = %{
        "metric_a" => "value1",
        "metric_b" => 42,
        "metric_c" => true
      }

      csv = MetricsCollector.export(metrics, :csv)
      lines = String.split(csv, "\n")

      assert length(lines) == 2
      assert lines |> Enum.at(0) |> String.contains?("metric_")
      assert lines |> Enum.at(1) |> String.contains?("42")
    end

    test "exports to Prometheus format" do
      metrics = %{
        "quality_improvement" => 0.85,
        "success" => true,
        "error" => false
      }

      prometheus = MetricsCollector.export(metrics, :prometheus)

      assert prometheus =~ "rubber_duck_enhancement_quality_improvement 0.85"
      assert prometheus =~ "rubber_duck_enhancement_success 1"
      assert prometheus =~ "rubber_duck_enhancement_error 0"
    end
  end

  describe "quality calculations" do
    test "detects documentation improvements" do
      original = "def add(a, b), do: a + b"

      enhanced = """
      @doc "Adds two numbers together"
      def add(a, b), do: a + b
      """

      result = %{original: original, enhanced: enhanced, context: %{}}
      metrics = MetricsCollector.collect(result, [])

      assert metrics["quality_improvement"] > 0.4
    end

    test "detects error reductions" do
      original = "def broken() do\n  # TODO: fix this\n  raise \"Not implemented\"\nend"
      enhanced = "def working() do\n  :ok\nend"

      result = %{original: original, enhanced: enhanced, context: %{}}
      metrics = MetricsCollector.collect(result, [])

      assert metrics["quality_improvement"] > 0.5
    end

    test "calculates readability scores" do
      simple = "Short sentence."

      complex =
        "This is an extraordinarily complicated and convoluted sentence that contains numerous subclauses and parenthetical expressions which make it exceedingly difficult to parse and comprehend."

      simple_result = %{original: "", enhanced: simple, context: %{}}
      complex_result = %{original: "", enhanced: complex, context: %{}}

      simple_metrics = MetricsCollector.collect(simple_result, [])
      complex_metrics = MetricsCollector.collect(complex_result, [])

      assert simple_metrics["readability_score"] > complex_metrics["readability_score"]
    end

    test "evaluates completeness" do
      incomplete = "The function should"
      complete = "The function should validate input and return the processed result."

      result_incomplete = %{
        original: "",
        enhanced: incomplete,
        context: %{required_elements: ["validate", "return"]}
      }

      result_complete = %{
        original: "",
        enhanced: complete,
        context: %{required_elements: ["validate", "return"]}
      }

      metrics_incomplete = MetricsCollector.collect(result_incomplete, [])
      metrics_complete = MetricsCollector.collect(result_complete, [])

      assert metrics_complete["completeness_score"] > metrics_incomplete["completeness_score"]
      assert metrics_complete["completeness_score"] == 1.0
    end
  end
end
