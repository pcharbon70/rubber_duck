defmodule RubberDuck.Workspace.CodeFileTest do
  use RubberDuck.DataCase

  alias RubberDuck.Workspace

  describe "code_files" do
    setup do
      # Create a project first
      {:ok, project} = 
        Workspace.create_project(%{
          name: "Test Project",
          description: "Project for testing code files"
        })

      {:ok, project: project}
    end

    test "can create a code file with project association", %{project: project} do
      assert {:ok, code_file} = 
        Workspace.create_code_file(%{
          file_path: "lib/example.ex",
          content: "defmodule Example do\nend",
          language: "elixir",
          project_id: project.id
        })

      assert code_file.file_path == "lib/example.ex"
      assert code_file.content == "defmodule Example do\nend"
      assert code_file.language == "elixir"
      assert code_file.project_id == project.id
      assert code_file.ast_cache == %{}
      assert code_file.embeddings == nil
    end

    test "file path is required", %{project: project} do
      assert {:error, error} = 
        Workspace.create_code_file(%{
          content: "some content",
          project_id: project.id
        })

      assert %Ash.Error.Invalid{} = error
    end

    test "project association is required" do
      assert {:error, error} = 
        Workspace.create_code_file(%{
          file_path: "lib/example.ex",
          content: "some content"
        })

      assert %Ash.Error.Invalid{} = error
    end

    test "can store embeddings array", %{project: project} do
      embeddings = [0.1, 0.2, 0.3, 0.4, 0.5]
      
      assert {:ok, code_file} = 
        Workspace.create_code_file(%{
          file_path: "lib/example.ex",
          content: "defmodule Example do\nend",
          language: "elixir",
          project_id: project.id,
          embeddings: embeddings
        })

      assert code_file.embeddings == embeddings
    end

    test "can store AST cache as JSON", %{project: project} do
      ast_cache = %{
        "type" => "module",
        "name" => "Example",
        "functions" => []
      }
      
      assert {:ok, code_file} = 
        Workspace.create_code_file(%{
          file_path: "lib/example.ex",
          content: "defmodule Example do\nend",
          language: "elixir",
          project_id: project.id,
          ast_cache: ast_cache
        })

      assert code_file.ast_cache == ast_cache
    end

    # TODO: Test semantic search once pgvector is properly integrated
    @tag :skip
    test "semantic search finds relevant files", %{project: _project} do
      # This will be implemented when we have proper pgvector support
    end
  end
end