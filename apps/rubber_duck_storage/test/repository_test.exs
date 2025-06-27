defmodule RubberDuckStorage.RepositoryTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias RubberDuckStorage.{Repository, Repo}
  alias RubberDuckStorage.Schemas.{Project, Conversation, Message}

  setup do
    # Clear any existing data
    Repo.delete_all(Message)
    Repo.delete_all(Conversation)
    Repo.delete_all(Project)
    :ok
  end

  describe "project operations" do
    test "can create a new project" do
      project_attrs = %{
        name: "Test Project",
        description: "A test project for validation"
      }

      assert {:ok, %Project{} = project} = Repository.add_project(project_attrs)
      assert project.name == "Test Project"
      assert project.description == "A test project for validation"
      assert project.id != nil
    end

    test "can list projects" do
      # Create a test project first
      {:ok, _project} = Repository.add_project(%{name: "Test Project"})

      assert {:ok, projects} = Repository.list_projects()
      assert is_list(projects)
      assert length(projects) >= 1
    end

    test "project-scoped conversation operations work" do
      # Create a project first
      {:ok, project} = Repository.add_project(%{name: "Test Project"})

      # Create a conversation scoped to this project
      conversation_attrs = %{
        title: "Test Conversation",
        status: :active
      }

      assert {:ok, conversation} = Repository.add_conversation(project.id, conversation_attrs)
      assert conversation.project_id == project.id

      # List conversations for this project only
      assert {:ok, conversations} = Repository.list_conversations(project.id)
      assert length(conversations) == 1
      assert hd(conversations).project_id == project.id
    end

    test "data isolation between projects works" do
      # Create two projects
      {:ok, project1} = Repository.add_project(%{name: "Project 1"})
      {:ok, project2} = Repository.add_project(%{name: "Project 2"})

      # Create conversations in each project
      {:ok, _conv1} = Repository.add_conversation(project1.id, %{title: "Conv 1"})
      {:ok, _conv2} = Repository.add_conversation(project2.id, %{title: "Conv 2"})

      # Verify isolation - each project should only see its own conversations
      {:ok, project1_conversations} = Repository.list_conversations(project1.id)
      {:ok, project2_conversations} = Repository.list_conversations(project2.id)

      assert length(project1_conversations) == 1
      assert length(project2_conversations) == 1
      assert hd(project1_conversations).project_id == project1.id
      assert hd(project2_conversations).project_id == project2.id
    end

    test "message operations are project-scoped" do
      # Create project and conversation
      {:ok, project} = Repository.add_project(%{name: "Test Project"})
      {:ok, conversation} = Repository.add_conversation(project.id, %{title: "Test Conv"})

      # Add a message
      message_attrs = %{
        role: :user,
        content: "Hello world",
        content_type: :text
      }

      assert {:ok, message} = Repository.add_message(project.id, conversation.id, message_attrs)
      assert message.conversation_id == conversation.id

      # List messages for the conversation
      assert {:ok, messages} = Repository.list_messages(project.id, conversation.id)
      assert length(messages) == 1
      assert hd(messages).content == "Hello world"
    end

    test "cross-project access is prevented" do
      # Create two projects with conversations
      {:ok, project1} = Repository.add_project(%{name: "Project 1"})
      {:ok, project2} = Repository.add_project(%{name: "Project 2"})
      {:ok, conv1} = Repository.add_conversation(project1.id, %{title: "Conv 1"})

      # Try to access project1's conversation from project2 scope
      assert Repository.get_conversation(project2.id, conv1.id) == nil

      # Try to add message to project1's conversation from project2 scope
      message_attrs = %{role: :user, content: "Test", content_type: :text}

      assert {:error, :conversation_not_found} =
               Repository.add_message(project2.id, conv1.id, message_attrs)
    end
  end
end
