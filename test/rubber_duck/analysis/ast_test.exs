defmodule RubberDuck.Analysis.ASTTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analysis.AST
  alias RubberDuck.Analysis.AST.ElixirParser

  describe "AST module" do
    test "parse/2 delegates to appropriate parser based on language" do
      elixir_code = """
      defmodule Example do
        def hello, do: :world
      end
      """

      assert {:ok, %{type: :module, name: Example}} = AST.parse(elixir_code, :elixir)
    end

    test "parse/2 returns error for unsupported language" do
      assert {:error, :unsupported_language} = AST.parse("code", :ruby)
    end
  end

  describe "ElixirParser" do
    test "parse/1 extracts module information" do
      code = """
      defmodule MyApp.User do
        @moduledoc "User module"
        
        def name(user), do: user.name
      end
      """

      assert {:ok, ast_info} = ElixirParser.parse(code)
      assert ast_info.type == :module
      assert ast_info.name == MyApp.User
      assert ast_info.functions == [%{name: :name, arity: 1, line: 5}]
    end

    test "parse/1 extracts function signatures with arity" do
      code = """
      defmodule Example do
        def zero_arity, do: :ok
        def one_arity(x), do: x
        def two_arity(x, y), do: {x, y}
        defp private_fun(x), do: x
      end
      """

      assert {:ok, ast_info} = ElixirParser.parse(code)

      assert Enum.find(ast_info.functions, &(&1.name == :zero_arity)).arity == 0
      assert Enum.find(ast_info.functions, &(&1.name == :one_arity)).arity == 1
      assert Enum.find(ast_info.functions, &(&1.name == :two_arity)).arity == 2
      assert Enum.find(ast_info.functions, &(&1.name == :private_fun)).private == true
    end

    test "parse/1 extracts dependencies" do
      code = """
      defmodule MyModule do
        alias MyApp.{User, Post}
        import Ecto.Query
        require Logger
        
        def process(user) do
          Logger.info("Processing")
          User.validate(user)
        end
      end
      """

      assert {:ok, ast_info} = ElixirParser.parse(code)

      assert MyApp.User in ast_info.aliases
      assert MyApp.Post in ast_info.aliases
      assert Ecto.Query in ast_info.imports
      assert Logger in ast_info.requires
    end

    test "parse/1 handles syntax errors gracefully" do
      code = """
      defmodule Broken do
        def incomplete(
      """

      assert {:error, {:syntax_error, _}} = ElixirParser.parse(code)
    end
  end
end

