defmodule RubberDuck.Analysis.SemanticTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analysis.{Semantic, AST}

  setup do
    # Create a sample AST info for testing
    ast_info = %{
      type: :module,
      name: TestModule,
      functions: [
        %{name: :public_func, arity: 2, line: 5, private: false},
        %{name: :private_func, arity: 0, line: 10, private: true},
        %{name: :unused_private, arity: 1, line: 15, private: true},
        %{name: :long_params, arity: 6, line: 20, private: false}
      ],
      aliases: [Foo.Bar, Baz.Qux],
      imports: [Enum, String],
      requires: [Logger],
      calls: [
        %{from: {TestModule, :public_func, 2}, to: {TestModule, :private_func, 0}, line: 6},
        %{from: {TestModule, :private_func, 0}, to: {Enum, :map, 2}, line: 11}
      ],
      metadata: %{}
    }

    {:ok, ast_info: ast_info}
  end

  describe "analyze/2" do
    test "returns analysis results with all components", %{ast_info: ast_info} do
      {:ok, result} = Semantic.analyze(ast_info)

      assert result.engine == :semantic
      assert is_list(result.issues)
      assert is_map(result.metrics)
      assert is_map(result.suggestions)
      assert result.metadata.module_name == TestModule
    end

    test "detects dead code", %{ast_info: ast_info} do
      {:ok, result} = Semantic.analyze(ast_info)

      dead_code_issues = Enum.filter(result.issues, &(&1.type == :dead_code))
      assert length(dead_code_issues) == 1

      issue = hd(dead_code_issues)
      assert issue.severity == :low
      assert issue.message =~ "unused_private/1"
      assert issue.category == :maintainability
    end

    test "detects long parameter lists", %{ast_info: ast_info} do
      {:ok, result} = Semantic.analyze(ast_info)

      param_issues = Enum.filter(result.issues, &(&1.type == :long_parameter_list))
      assert length(param_issues) == 1

      issue = hd(param_issues)
      assert issue.severity == :low
      assert issue.message =~ "long_params/6"
      assert issue.message =~ "too many parameters"
    end

    test "respects configuration options", %{ast_info: ast_info} do
      config = %{detect_dead_code: false}
      {:ok, result} = Semantic.analyze(ast_info, config: config)

      dead_code_issues = Enum.filter(result.issues, &(&1.type == :dead_code))
      assert Enum.empty?(dead_code_issues)
    end

    test "calculates metrics correctly", %{ast_info: ast_info} do
      {:ok, result} = Semantic.analyze(ast_info)

      assert result.metrics.total_functions == 4
      assert result.metrics.public_functions == 2
      assert result.metrics.private_functions == 2
      assert result.metrics.total_dependencies == 5
      assert result.metrics.average_function_arity == 2.25
    end
  end

  describe "analyze_source/3" do
    test "performs basic source analysis when AST is not available" do
      source = """
      defmodule Example do
        def very_long_function_name_that_exceeds_reasonable_length do
          # This line is way too long and should be flagged by the analyzer because it exceeds the maximum line length configured
          :ok
        end
      end
      """

      {:ok, result} = Semantic.analyze_source(source, :elixir, [])

      assert result.engine == :semantic
      assert is_list(result.issues)
      assert result.metadata.source_analysis == true

      # Should detect long lines
      long_line_issues = Enum.filter(result.issues, &(&1.type == :long_line))
      assert length(long_line_issues) > 0
    end

    test "detects trailing whitespace" do
      source = "def example do  \n  :ok\nend  "

      {:ok, result} = Semantic.analyze_source(source, :elixir, [])

      trailing_issues = Enum.filter(result.issues, &(&1.type == :trailing_whitespace))
      assert length(trailing_issues) == 2
    end
  end

  describe "default_config/0" do
    test "returns expected default configuration" do
      config = Semantic.default_config()

      assert config.max_function_length == 10
      assert config.max_module_length == 100
      assert config.max_cyclomatic_complexity == 7
      assert config.detect_dead_code == true
    end
  end

  describe "large module detection" do
    test "detects modules with too many functions" do
      # Create AST with many functions
      functions =
        for i <- 1..150 do
          %{name: :"func_#{i}", arity: 0, line: i * 5, private: false}
        end

      ast_info = %{
        type: :module,
        name: LargeModule,
        functions: functions,
        aliases: [],
        imports: [],
        requires: [],
        calls: [],
        metadata: %{}
      }

      {:ok, result} = Semantic.analyze(ast_info)

      large_module_issues = Enum.filter(result.issues, &(&1.type == :large_module))
      assert length(large_module_issues) == 1
      assert hd(large_module_issues).severity == :medium
    end
  end
end
