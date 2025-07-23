defmodule RubberDuck.WorkspaceFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `RubberDuck.Workspace` context.
  """

  alias RubberDuck.Workspace

  @doc """
  Generate a project.
  """
  def project_fixture(attrs \\ %{}) do
    owner = Map.get(attrs, :owner_id) || Map.get(attrs, :owner)
    attrs = Map.drop(attrs, [:owner_id, :owner])
    
    {:ok, project} =
      attrs
      |> Enum.into(%{
        name: "test-project-#{System.unique_integer([:positive])}",
        description: "A test project",
        root_path: "/tmp/test-project-#{System.unique_integer([:positive])}"
      })
      |> Workspace.create_project(actor: owner)

    project
  end

  @doc """
  Generate a code file.
  """
  def code_file_fixture(attrs \\ %{}) do
    project = Map.get(attrs, :project) || project_fixture()
    
    {:ok, code_file} =
      attrs
      |> Enum.into(%{
        project_id: project.id,
        path: "test_file_#{System.unique_integer([:positive])}.ex",
        content: "defmodule Test do\n  def hello, do: :world\nend",
        language: "elixir"
      })
      |> Workspace.create_code_file()

    code_file
  end

  @doc """
  Generate an analysis result.
  """
  def analysis_result_fixture(attrs \\ %{}) do
    code_file = Map.get(attrs, :code_file) || code_file_fixture()
    
    {:ok, analysis_result} =
      attrs
      |> Enum.into(%{
        code_file_id: code_file.id,
        type: "syntax",
        status: "completed",
        results: %{"errors" => [], "warnings" => []}
      })
      |> Workspace.create_analysis_result()

    analysis_result
  end
end