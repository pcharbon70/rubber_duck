defmodule RubberDuck.Workspace.AnalysisResultTest do
  use RubberDuck.DataCase

  alias RubberDuck.Workspace

  describe "analysis_results" do
    setup do
      # Create a project and code file first
      {:ok, project} = 
        Workspace.create_project(%{
          name: "Test Project",
          description: "Project for testing analysis results"
        })

      {:ok, code_file} = 
        Workspace.create_code_file(%{
          file_path: "lib/example.ex",
          content: "defmodule Example do\n  def hello, do: :world\nend",
          language: "elixir",
          project_id: project.id
        })

      {:ok, project: project, code_file: code_file}
    end

    test "can create an analysis result with code file association", %{code_file: code_file} do
      assert {:ok, analysis_result} = 
        Workspace.create_analysis_result(%{
          analysis_type: "complexity",
          results: %{
            "cyclomatic_complexity" => 1,
            "cognitive_complexity" => 0
          },
          severity: :low,
          code_file_id: code_file.id
        })

      assert analysis_result.analysis_type == "complexity"
      assert analysis_result.results["cyclomatic_complexity"] == 1
      assert analysis_result.results["cognitive_complexity"] == 0
      assert analysis_result.severity == :low
      assert analysis_result.code_file_id == code_file.id
    end

    test "analysis_type is required", %{code_file: code_file} do
      assert {:error, error} = 
        Workspace.create_analysis_result(%{
          results: %{"some" => "data"},
          code_file_id: code_file.id
        })

      assert %Ash.Error.Invalid{} = error
    end

    test "code_file association is required" do
      assert {:error, error} = 
        Workspace.create_analysis_result(%{
          analysis_type: "complexity",
          results: %{"some" => "data"}
        })

      assert %Ash.Error.Invalid{} = error
    end

    test "results defaults to empty map if not provided", %{code_file: code_file} do
      assert {:ok, analysis_result} = 
        Workspace.create_analysis_result(%{
          analysis_type: "linting",
          code_file_id: code_file.id
        })

      assert analysis_result.results == %{}
    end

    test "can store complex results as JSON", %{code_file: code_file} do
      complex_results = %{
        "errors" => [
          %{
            "line" => 10,
            "column" => 5,
            "message" => "Unused variable",
            "rule" => "no-unused-vars"
          }
        ],
        "warnings" => [],
        "info" => [
          %{
            "type" => "suggestion",
            "message" => "Consider using pattern matching"
          }
        ]
      }
      
      assert {:ok, analysis_result} = 
        Workspace.create_analysis_result(%{
          analysis_type: "linting",
          results: complex_results,
          severity: :medium,
          code_file_id: code_file.id
        })

      assert analysis_result.results == complex_results
      assert length(analysis_result.results["errors"]) == 1
    end

    test "severity field is optional", %{code_file: code_file} do
      assert {:ok, analysis_result} = 
        Workspace.create_analysis_result(%{
          analysis_type: "security",
          results: %{"vulnerabilities" => []},
          code_file_id: code_file.id
        })

      assert analysis_result.severity == nil
    end

    test "can list analysis results", %{code_file: code_file} do
      # Create multiple analysis results
      {:ok, _} = 
        Workspace.create_analysis_result(%{
          analysis_type: "complexity",
          results: %{},
          code_file_id: code_file.id
        })

      {:ok, _} = 
        Workspace.create_analysis_result(%{
          analysis_type: "security",
          results: %{},
          code_file_id: code_file.id
        })

      {:ok, results} = Workspace.list_analysis_results()
      assert length(results) >= 2
    end
  end
end