defmodule RubberDuck.Workspace.ProjectTest do
  use RubberDuck.DataCase

  alias RubberDuck.Workspace

  describe "projects" do
    test "can create a project with valid attributes" do
      assert {:ok, project} = 
        Workspace.create_project(%{
          name: "Test Project",
          description: "A test project for RubberDuck"
        })

      assert project.name == "Test Project"
      assert project.description == "A test project for RubberDuck"
      assert project.id
      assert project.inserted_at
      assert project.updated_at
    end

    test "name attribute is required" do
      assert {:error, error} = 
        Workspace.create_project(%{
          description: "Missing name"
        })

      assert %Ash.Error.Invalid{} = error
    end
  end
end