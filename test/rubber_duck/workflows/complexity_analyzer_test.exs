defmodule RubberDuck.Workflows.ComplexityAnalyzerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.ComplexityAnalyzer

  describe "analyze/2" do
    test "analyzes simple code analysis task" do
      task = %{
        type: :analysis,
        target: "lib/example.ex",
        code: """
        defmodule Example do
          def hello, do: "world"
        end
        """,
        options: %{}
      }

      result = ComplexityAnalyzer.analyze(task)

      assert result.complexity_score >= 0 and result.complexity_score <= 3
      assert result.task_type == :analysis
      assert result.size_category == :small
      assert result.resource_requirements.agents == [:analysis]
      assert result.resource_requirements.memory == :low
      assert result.resource_requirements.estimated_time < 30_000
      assert result.parallelization_strategy == :sequential
      assert result.suggested_workflow_type == :simple_analysis
    end

    test "analyzes complex multi-file analysis task" do
      task = %{
        type: :analysis,
        targets: [
          "lib/app/module1.ex",
          "lib/app/module2.ex",
          "lib/app/module3.ex"
        ],
        options: %{
          deep_analysis: true,
          security_check: true,
          performance_analysis: true
        }
      }

      result = ComplexityAnalyzer.analyze(task)

      assert result.complexity_score >= 6
      assert result.task_type == :analysis
      assert result.size_category == :medium
      assert :research in result.resource_requirements.agents
      assert :analysis in result.resource_requirements.agents
      assert result.resource_requirements.memory == :medium
      assert result.resource_requirements.estimated_time >= 60_000
      assert result.parallelization_strategy == :parallel_analysis
      assert result.suggested_workflow_type == :deep_analysis
    end

    test "analyzes code generation task" do
      task = %{
        type: :generation,
        description: "Generate a GenServer that manages user sessions",
        context: %{
          existing_modules: ["User", "Session"],
          requirements: ["fault tolerance", "session timeout", "concurrent access"]
        }
      }

      result = ComplexityAnalyzer.analyze(task)

      assert result.complexity_score >= 5
      assert result.task_type == :generation
      assert result.size_category == :medium
      assert :research in result.resource_requirements.agents
      assert :generation in result.resource_requirements.agents
      assert :review in result.resource_requirements.agents
      assert result.resource_requirements.memory == :medium
      assert result.parallelization_strategy == :pipeline
      assert result.suggested_workflow_type == :generation_pipeline
    end

    test "analyzes refactoring task" do
      task = %{
        type: :refactoring,
        target: "lib/legacy/big_module.ex",
        goal: :performance,
        code_stats: %{
          loc: 1500,
          functions: 45,
          complexity: 85
        }
      }

      result = ComplexityAnalyzer.analyze(task)

      assert result.complexity_score >= 8
      assert result.task_type == :refactoring
      assert result.size_category == :large
      assert length(result.resource_requirements.agents) >= 4
      assert result.resource_requirements.memory == :high
      assert result.resource_requirements.estimated_time >= 180_000
      assert result.parallelization_strategy == :parallel_analysis
      assert result.suggested_workflow_type == :complex_refactoring
    end

    test "identifies task dependencies" do
      task = %{
        type: :analysis,
        targets: ["a.ex", "b.ex", "c.ex"],
        dependencies: %{
          "b.ex" => ["a.ex"],
          "c.ex" => ["a.ex", "b.ex"]
        }
      }

      result = ComplexityAnalyzer.analyze(task)

      assert result.dependency_graph == %{
               "a.ex" => [],
               "b.ex" => ["a.ex"],
               "c.ex" => ["a.ex", "b.ex"]
             }

      assert result.parallelization_strategy == :dependency_aware
    end

    test "estimates resources for unknown task type" do
      task = %{
        type: :custom,
        description: "Do something special"
      }

      result = ComplexityAnalyzer.analyze(task)

      # default medium
      assert result.complexity_score == 5
      assert result.task_type == :custom
      assert result.suggested_workflow_type == :adaptive
    end

    test "considers historical data when provided" do
      task = %{
        type: :analysis,
        target: "lib/example.ex",
        code: "defmodule Example, do: :ok"
      }

      historical_data = %{
        similar_tasks: [
          %{duration: 15_000, memory_peak: 100},
          %{duration: 18_000, memory_peak: 120}
        ]
      }

      result = ComplexityAnalyzer.analyze(task, historical_data)

      # Should use historical average
      assert_in_delta result.resource_requirements.estimated_time, 16_500, 1000
    end

    test "handles missing or incomplete task data" do
      task = %{type: :analysis}

      result = ComplexityAnalyzer.analyze(task)

      assert result.complexity_score >= 0
      assert result.warnings == [:missing_target]
    end
  end

  describe "calculate_complexity/1" do
    test "calculates complexity based on multiple factors" do
      task = %{
        type: :analysis,
        code_stats: %{loc: 500, cyclomatic_complexity: 25},
        options: %{deep_analysis: true}
      }

      score = ComplexityAnalyzer.calculate_complexity(task)

      assert score > 5
      assert score <= 10
    end
  end

  describe "estimate_resources/1" do
    test "estimates agent requirements based on task type" do
      analysis_task = %{type: :analysis, options: %{}}
      generation_task = %{type: :generation}
      review_task = %{type: :review}

      assert ComplexityAnalyzer.estimate_resources(analysis_task).agents == [:analysis]
      assert :generation in ComplexityAnalyzer.estimate_resources(generation_task).agents
      assert :review in ComplexityAnalyzer.estimate_resources(review_task).agents
    end

    test "scales resources with task size" do
      small_task = %{type: :analysis, code_stats: %{loc: 100}}
      large_task = %{type: :analysis, code_stats: %{loc: 5000}}

      small_resources = ComplexityAnalyzer.estimate_resources(small_task)
      large_resources = ComplexityAnalyzer.estimate_resources(large_task)

      assert small_resources.memory == :low
      assert large_resources.memory == :high
      assert large_resources.estimated_time > small_resources.estimated_time
    end
  end

  describe "analyze_dependencies/1" do
    test "identifies independent tasks" do
      task = %{
        subtasks: [
          %{id: "a", depends_on: []},
          %{id: "b", depends_on: []},
          %{id: "c", depends_on: []}
        ]
      }

      strategy = ComplexityAnalyzer.analyze_dependencies(task)

      assert strategy == :fully_parallel
    end

    test "identifies sequential dependencies" do
      task = %{
        subtasks: [
          %{id: "a", depends_on: []},
          %{id: "b", depends_on: ["a"]},
          %{id: "c", depends_on: ["b"]}
        ]
      }

      strategy = ComplexityAnalyzer.analyze_dependencies(task)

      assert strategy == :sequential
    end

    test "identifies mixed dependencies" do
      task = %{
        subtasks: [
          %{id: "a", depends_on: []},
          %{id: "b", depends_on: []},
          %{id: "c", depends_on: ["a", "b"]},
          %{id: "d", depends_on: ["c"]}
        ]
      }

      strategy = ComplexityAnalyzer.analyze_dependencies(task)

      assert strategy == :mixed_parallel
    end
  end
end
