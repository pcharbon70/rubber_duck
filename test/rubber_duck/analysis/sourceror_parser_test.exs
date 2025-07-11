defmodule RubberDuck.Analysis.AST.SourcerorParserTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analysis.AST.SourcerorParser

  describe "parse/1" do
    test "parses a simple module" do
      code = """
      defmodule Example do
        def hello, do: :world
      end
      """

      assert {:ok, ast_info} = SourcerorParser.parse(code)
      assert ast_info.type == :module
      assert ast_info.name == Example
      assert length(ast_info.functions) == 1
      assert hd(ast_info.functions).name == :hello
    end

    test "returns map structure compatible with analysis engines" do
      code = """
      defmodule MyApp.User do
        @moduledoc "User module"
        
        alias MyApp.Repo
        import Ecto.Query
        
        def name(user), do: user.name
        
        def update_name(user, new_name) do
          user
          |> change_name(new_name)
          |> Repo.update()
        end
        
        defp change_name(user, name) do
          %{user | name: name}
        end
      end
      """

      assert {:ok, ast_info} = SourcerorParser.parse(code)
      
      # Check structure matches expected format
      assert is_map(ast_info)
      assert Map.has_key?(ast_info, :type)
      assert Map.has_key?(ast_info, :name)
      assert Map.has_key?(ast_info, :functions)
      assert Map.has_key?(ast_info, :aliases)
      assert Map.has_key?(ast_info, :imports)
      assert Map.has_key?(ast_info, :requires)
      assert Map.has_key?(ast_info, :calls)
      assert Map.has_key?(ast_info, :variables)
      
      # Check specific values
      assert ast_info.type == :module
      assert ast_info.name == MyApp.User
      assert length(ast_info.functions) == 3
      assert MyApp.Repo in ast_info.aliases
      assert Ecto.Query in ast_info.imports
      
      # Check function structure
      name_func = Enum.find(ast_info.functions, &(&1.name == :name))
      assert name_func.arity == 1
      assert name_func.private == false
      assert is_list(name_func.variables)
      assert is_list(name_func.body_calls)
    end

    test "handles syntax errors gracefully" do
      code = """
      defmodule Broken do
        def incomplete(
      """

      assert {:error, error} = SourcerorParser.parse(code)
      assert is_map(error)
    end
  end
end