defmodule RubberDuck.Analysis.SourcerorIntegrationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analysis.{Analyzer, AST}

  describe "SourcerorParser integration" do
    test "analyzer uses SourcerorParser for Elixir code" do
      code = """
      defmodule TestModule do
        def unused_variable_example do
          x = 42  # This should be detected as unused
          y = 10
          y * 2
        end
        
        def unsafe_atom_creation(input) do
          String.to_atom(input)  # This should be detected as unsafe
        end
      end
      """

      # Test that AST.parse uses SourcerorParser
      assert {:ok, ast_info} = AST.parse(code, :elixir)
      assert ast_info.type == :module
      assert ast_info.name == TestModule
      assert length(ast_info.functions) == 2

      # Test full analysis pipeline
      assert {:ok, results} = Analyzer.analyze_source(code, :elixir, 
        engines: [:semantic, :security]
      )

      # Check that issues were detected
      assert length(results.all_issues) > 0
      
      # Find specific issues
      unused_var_issue = Enum.find(results.all_issues, &(&1.type == :unused_variable))
      unsafe_atom_issue = Enum.find(results.all_issues, &(&1.type == :dynamic_atom_creation))
      
      assert unused_var_issue != nil
      assert unsafe_atom_issue != nil
    end
  end
end