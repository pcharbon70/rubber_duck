defmodule RubberDuck.Analysis.StyleTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analysis.Style

  setup do
    ast_info = %{
      type: :module,
      # Invalid module name
      name: Test.BadNaming,
      functions: [
        # camelCase
        %{name: :goodFunction, arity: 2, line: 5, private: false},
        %{name: :good_function, arity: 3, line: 10, private: false},
        %{name: :extremely_long_function_name_that_should_be_shorter, arity: 0, line: 15, private: true}
      ],
      aliases: [GenServer, Task, Agent, Supervisor, Registry, Phoenix.Channel],
      imports: [Enum, String, Map, List],
      requires: [Logger],
      calls: [
        %{from: {Test.BadNaming, :good_function, 3}, to: {GenServer, :call, 3}, line: 11}
      ],
      metadata: %{}
    }

    {:ok, ast_info: ast_info}
  end

  describe "analyze/2" do
    test "detects invalid module naming", %{ast_info: ast_info} do
      {:ok, result} = Style.analyze(ast_info)

      naming_issues = Enum.filter(result.issues, &(&1.type == :invalid_module_name))
      assert length(naming_issues) == 1
      assert hd(naming_issues).severity == :medium
    end

    test "detects invalid function naming", %{ast_info: ast_info} do
      {:ok, result} = Style.analyze(ast_info)

      func_name_issues = Enum.filter(result.issues, &(&1.type == :invalid_function_name))
      assert length(func_name_issues) == 1

      issue = hd(func_name_issues)
      assert issue.message =~ "goodFunction"
      assert issue.message =~ "snake_case"
    end

    test "detects long function names", %{ast_info: ast_info} do
      {:ok, result} = Style.analyze(ast_info)

      long_name_issues = Enum.filter(result.issues, &(&1.type == :long_function_name))
      assert length(long_name_issues) == 1
      assert hd(long_name_issues).severity == :info
    end

    test "detects primitive obsession", %{ast_info: ast_info} do
      # Add a function with many parameters
      ast_with_many_params =
        Map.update!(ast_info, :functions, fn funcs ->
          [%{name: :many_params, arity: 5, line: 20, private: false} | funcs]
        end)

      {:ok, result} = Style.analyze(ast_with_many_params)

      primitive_issues = Enum.filter(result.issues, &(&1.type == :primitive_obsession))
      assert length(primitive_issues) >= 1
    end

    test "calculates style metrics", %{ast_info: ast_info} do
      {:ok, result} = Style.analyze(ast_info)

      # Due to bad naming
      assert result.metrics.naming_consistency_score < 100.0
      assert is_float(result.metrics.function_organization_score)
      assert is_float(result.metrics.coupling_score)
    end
  end

  describe "analyze_source/3" do
    test "detects line length violations" do
      source = """
      defmodule Example do
        def function do
          # This is an extremely long line that definitely exceeds the 120 character limit and should be flagged by the style analyzer
          :ok
        end
      end
      """

      {:ok, result} = Style.analyze_source(source, :elixir, [])

      line_length_issues = Enum.filter(result.issues, &(&1.type == :line_too_long))
      assert length(line_length_issues) > 0
    end

    test "detects TODO comments" do
      source = """
      defmodule Example do
        # TODO: Implement this function
        def incomplete do
          # FIXME: This is broken
          nil
        end
      end
      """

      {:ok, result} = Style.analyze_source(source, :elixir, [])

      todo_issues = Enum.filter(result.issues, &(&1.type == :todo_comment))
      assert length(todo_issues) == 2
    end

    test "detects commented code" do
      source = """
      defmodule Example do
        def active do
          :ok
        end
        
        # def old_implementation do
        #   :deprecated
        # end
      end
      """

      {:ok, result} = Style.analyze_source(source, :elixir, [])

      commented_code_issues = Enum.filter(result.issues, &(&1.type == :commented_code))
      assert length(commented_code_issues) >= 1
    end
  end

  describe "function organization" do
    test "detects mixed public/private functions" do
      ast_info = %{
        type: :module,
        name: MixedModule,
        functions: [
          %{name: :public1, arity: 0, line: 5, private: false},
          %{name: :private1, arity: 0, line: 10, private: true},
          # Public after private
          %{name: :public2, arity: 0, line: 15, private: false},
          %{name: :private2, arity: 0, line: 20, private: true}
        ],
        aliases: [],
        imports: [],
        requires: [],
        calls: [],
        metadata: %{}
      }

      {:ok, result} = Style.analyze(ast_info)

      org_issues = Enum.filter(result.issues, &(&1.type == :mixed_function_visibility))
      assert length(org_issues) == 1
      assert hd(org_issues).severity == :info
    end
  end

  describe "module coupling" do
    test "detects high coupling" do
      # Create AST with many external module calls
      calls =
        for i <- 1..20 do
          %{
            from: {TestModule, :func, 0},
            to: {:"External#{i}", :call, 1},
            line: i
          }
        end

      ast_info = %{
        type: :module,
        name: HighlyCoupled,
        functions: [%{name: :func, arity: 0, line: 1, private: false}],
        aliases: [],
        imports: [],
        requires: [],
        calls: calls,
        metadata: %{}
      }

      {:ok, result} = Style.analyze(ast_info)

      coupling_issues = Enum.filter(result.issues, &(&1.type == :high_coupling))
      assert length(coupling_issues) == 1
      assert hd(coupling_issues).severity == :medium
    end
  end
end
