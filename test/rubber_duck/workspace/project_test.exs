defmodule RubberDuck.Workspace.ProjectTest do
  use RubberDuck.DataCase

  alias RubberDuck.Workspace
  alias RubberDuck.AccountsFixtures

  describe "projects" do
    setup do
      user = AccountsFixtures.user_fixture()
      {:ok, user: user}
    end

    test "can create a project with valid attributes", %{user: user} do
      assert {:ok, project} =
               Workspace.create_project(
                 %{
                   name: "Test Project",
                   description: "A test project for RubberDuck"
                 },
                 actor: user
               )

      assert project.name == "Test Project"
      assert project.description == "A test project for RubberDuck"
      assert project.id
      assert project.inserted_at
      assert project.updated_at
      assert project.owner_id == user.id
    end

    test "name attribute is required", %{user: user} do
      assert {:error, error} =
               Workspace.create_project(
                 %{
                   description: "Missing name"
                 },
                 actor: user
               )

      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "project file sandbox attributes" do
    setup do
      user = AccountsFixtures.user_fixture()
      {:ok, user: user}
    end

    test "creates project with file sandbox configuration", %{user: user} do
      attrs = %{
        name: "Test Project",
        description: "A test project with file sandbox",
        root_path: "/home/user/projects/test",
        file_access_enabled: true,
        # 10MB
        max_file_size: 10_485_760,
        allowed_extensions: [".ex", ".exs", ".md", ".txt"],
        sandbox_config: %{
          "allow_symlinks" => false,
          "follow_hidden_files" => false
        }
      }

      assert {:ok, project} = Workspace.create_project(attrs, actor: user)
      assert project.name == "Test Project"
      assert project.root_path == "/home/user/projects/test"
      assert project.file_access_enabled == true
      assert project.max_file_size == 10_485_760
      assert project.allowed_extensions == [".ex", ".exs", ".md", ".txt"]
      assert project.sandbox_config["allow_symlinks"] == false
      assert project.owner_id == user.id
    end

    test "validates root_path is required when file_access_enabled", %{user: user} do
      attrs = %{
        name: "Test Project",
        file_access_enabled: true
      }

      assert {:error, _} = Workspace.create_project(attrs, actor: user)
    end

    test "creates project with non-existent root_path", %{user: user} do
      # Note: Current implementation doesn't validate path existence
      # This would be added in production with proper filesystem checks
      attrs = %{
        name: "Test Project",
        root_path: "/nonexistent/path",
        file_access_enabled: true
      }

      assert {:ok, project} = Workspace.create_project(attrs, actor: user)
      assert project.root_path == "/nonexistent/path"
    end
  end

  describe "project collaborators" do
    setup do
      owner = AccountsFixtures.user_fixture()
      collaborator = AccountsFixtures.user_fixture()

      {:ok, project} =
        Workspace.create_project(
          %{
            name: "Test Project #{System.unique_integer()}",
            description: "Test description"
          },
          actor: owner
        )

      {:ok, owner: owner, collaborator: collaborator, project: project}
    end

    test "adds collaborator to project", %{project: project, collaborator: collaborator, owner: owner} do
      assert {:ok, collab} = Workspace.add_project_collaborator(project, collaborator, :write, actor: owner)
      assert collab.user_id == collaborator.id
      assert collab.project_id == project.id
      assert collab.permission == :write
    end

    test "only owner can add collaborators", %{project: project, collaborator: collaborator} do
      non_owner = AccountsFixtures.user_fixture()

      assert {:error, _} = Workspace.add_project_collaborator(project, collaborator, :write, actor: non_owner)
    end

    test "lists project collaborators", %{project: project, collaborator: collaborator, owner: owner} do
      {:ok, _} = Workspace.add_project_collaborator(project, collaborator, :read, actor: owner)

      collaborators = Workspace.list_project_collaborators!(project, actor: owner)
      assert length(collaborators) == 1
      assert hd(collaborators).user_id == collaborator.id
    end
  end
end
