defmodule RubberDuck.Analysis.EnhancedCapabilitiesTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analysis.{Analyzer, AST}

  describe "Enhanced Semantic Analysis" do
    test "detects variable shadowing" do
      code = """
      defmodule ShadowExample do
        def outer_func do
          x = 10
          
          inner_func = fn ->
            x = 20  # This shadows the outer x
            x * 2
          end
          
          inner_func.() + x
        end
      end
      """

      assert {:ok, ast_info} = AST.parse(code, :elixir)
      assert {:ok, results} = Analyzer.analyze_ast(ast_info, :elixir, engines: [:semantic])

      issues = results.engine_results.semantic.issues
      shadowing_issue = Enum.find(issues, &(&1.type == :variable_shadowing))

      assert shadowing_issue != nil
      assert shadowing_issue.message =~ "shadows outer variable"
    end

    test "detects potentially dead private functions" do
      code = """
      defmodule DeadCodeExample do
        def public_func(x) do
          helper(x)
        end
        
        defp helper(x), do: x * 2
        
        defp unused_helper(x), do: x * 3  # Never called
      end
      """

      assert {:ok, ast_info} = AST.parse(code, :elixir)
      assert {:ok, results} = Analyzer.analyze_ast(ast_info, :elixir, engines: [:semantic])

      issues = results.engine_results.semantic.issues
      dead_code_issue = Enum.find(issues, &(&1.type == :potentially_dead_code))

      assert dead_code_issue != nil
      assert dead_code_issue.message =~ "never called"
    end

    test "detects circular dependencies" do
      code = """
      defmodule CircularExample do
        def recursive_func(n) when n > 0 do
          recursive_func(n - 1)  # Direct recursion
        end
        def recursive_func(0), do: :done
      end
      """

      assert {:ok, ast_info} = AST.parse(code, :elixir)
      assert {:ok, results} = Analyzer.analyze_ast(ast_info, :elixir, engines: [:semantic])

      issues = results.engine_results.semantic.issues
      circular_issue = Enum.find(issues, &(&1.type == :circular_dependency))

      assert circular_issue != nil
      assert circular_issue.message =~ "calls itself directly"
    end
  end

  describe "Enhanced Style Analysis" do
    test "detects excessive imports" do
      code = """
      defmodule ImportHeavy do
        import Enum
        import List
        import Map
        import String
        import Keyword
        import Process
        import GenServer
        import Supervisor
        import Registry
        import Task
        import Agent
        
        def some_func, do: :ok
      end
      """

      assert {:ok, ast_info} = AST.parse(code, :elixir)
      assert {:ok, results} = Analyzer.analyze_ast(ast_info, :elixir, engines: [:style])

      issues = results.engine_results.style.issues
      import_issue = Enum.find(issues, &(&1.type == :excessive_imports))

      assert import_issue != nil
      assert import_issue.message =~ "imports, consider reducing"
    end

    test "detects long function names" do
      code = """
      defmodule LongNames do
        def this_is_an_extremely_long_function_name_that_should_be_shortened do
          :ok
        end
      end
      """

      assert {:ok, ast_info} = AST.parse(code, :elixir)
      assert {:ok, results} = Analyzer.analyze_ast(ast_info, :elixir, engines: [:style])

      issues = results.engine_results.style.issues
      name_issue = Enum.find(issues, &(&1.type == :long_function_name))

      assert name_issue != nil
      assert name_issue.message =~ "characters long"
    end

    test "detects high function arity" do
      code = """
      defmodule HighArity do
        def too_many_params(a, b, c, d, e, f, g) do
          {a, b, c, d, e, f, g}
        end
      end
      """

      assert {:ok, ast_info} = AST.parse(code, :elixir)
      assert {:ok, results} = Analyzer.analyze_ast(ast_info, :elixir, engines: [:style])

      issues = results.engine_results.style.issues
      arity_issue = Enum.find(issues, &(&1.type == :high_arity))

      assert arity_issue != nil
      assert arity_issue.message =~ "too many parameters"
    end
  end

  describe "Enhanced Security Analysis" do
    test "detects dangerous call chains" do
      code = """
      defmodule DangerousChain do
        def execute_command(cmd) do
          System.cmd(cmd, [])  # Dangerous!
        end
      end
      """

      assert {:ok, ast_info} = AST.parse(code, :elixir)
      assert {:ok, results} = Analyzer.analyze_ast(ast_info, :elixir, engines: [:security])

      issues = results.engine_results.security.issues
      chain_issue = Enum.find(issues, &(&1.type == :dangerous_call_chain))

      assert chain_issue != nil
      assert chain_issue.message =~ "potentially dangerous"
    end

    test "detects potential input validation issues" do
      code = """
      defmodule InputValidation do
        def process_params(params) do
          # Using params directly without validation
          execute_query(params.query)
        end
        
        defp execute_query(query) do
          Repo.query(query)
        end
      end
      """

      assert {:ok, ast_info} = AST.parse(code, :elixir)
      assert {:ok, results} = Analyzer.analyze_ast(ast_info, :elixir, engines: [:security])

      issues = results.engine_results.security.issues

      # Should detect unvalidated input
      input_issue = Enum.find(issues, &(&1.type == :unvalidated_input))
      assert input_issue != nil

      # Should also detect potential injection
      injection_issue = Enum.find(issues, &(&1.type == :potential_injection))
      assert injection_issue != nil
    end
  end
end
