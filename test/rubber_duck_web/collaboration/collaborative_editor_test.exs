defmodule RubberDuckWeb.Collaboration.CollaborativeEditorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuckWeb.Collaboration.{CollaborativeEditor, EditorSupervisor}
  
  setup do
    # Start the supervisor
    {:ok, _} = start_supervised(EditorSupervisor)
    {:ok, _} = start_supervised({Registry, keys: :unique, name: RubberDuckWeb.Collaboration.EditorRegistry})
    
    project_id = "test-project-#{Ecto.UUID.generate()}"
    file_path = "test/file.ex"
    initial_content = "defmodule Test do\n  def hello, do: :world\nend"
    
    {:ok, project_id: project_id, file_path: file_path, initial_content: initial_content}
  end
  
  describe "start_session/3" do
    test "starts a collaborative editing session", %{project_id: project_id, file_path: file_path, initial_content: initial_content} do
      assert {:ok, _pid} = CollaborativeEditor.start_session(project_id, file_path, initial_content)
      
      # Verify we can get the document
      assert {:ok, doc} = CollaborativeEditor.get_document(project_id, file_path)
      assert doc.content == initial_content
      assert doc.version == 0
    end
  end
  
  describe "apply_operation/3" do
    setup %{project_id: project_id, file_path: file_path, initial_content: initial_content} do
      {:ok, _} = CollaborativeEditor.start_session(project_id, file_path, initial_content)
      :ok
    end
    
    test "applies insert operation", %{project_id: project_id, file_path: file_path} do
      operation = %CollaborativeEditor.Operation{
        id: Ecto.UUID.generate(),
        user_id: "user1",
        type: :insert,
        position: 0,
        content: "# Header\n",
        version: 0,
        timestamp: DateTime.utc_now()
      }
      
      assert {:ok, applied_op} = CollaborativeEditor.apply_operation(project_id, file_path, operation)
      assert applied_op.version == 1
      
      {:ok, doc} = CollaborativeEditor.get_document(project_id, file_path)
      assert String.starts_with?(doc.content, "# Header\n")
      assert doc.version == 1
    end
    
    test "applies delete operation", %{project_id: project_id, file_path: file_path} do
      operation = %CollaborativeEditor.Operation{
        id: Ecto.UUID.generate(),
        user_id: "user1",
        type: :delete,
        position: 0,
        length: 9, # "defmodule"
        version: 0,
        timestamp: DateTime.utc_now()
      }
      
      assert {:ok, _} = CollaborativeEditor.apply_operation(project_id, file_path, operation)
      
      {:ok, doc} = CollaborativeEditor.get_document(project_id, file_path)
      assert String.starts_with?(doc.content, " Test do")
    end
    
    test "validates operation position", %{project_id: project_id, file_path: file_path} do
      operation = %CollaborativeEditor.Operation{
        id: Ecto.UUID.generate(),
        user_id: "user1",
        type: :insert,
        position: 1000, # Beyond content length
        content: "test",
        version: 0,
        timestamp: DateTime.utc_now()
      }
      
      assert {:error, :invalid_position} = CollaborativeEditor.apply_operation(project_id, file_path, operation)
    end
    
    test "handles concurrent operations", %{project_id: project_id, file_path: file_path} do
      # Two users insert at the same position
      op1 = %CollaborativeEditor.Operation{
        id: Ecto.UUID.generate(),
        user_id: "user1",
        type: :insert,
        position: 0,
        content: "A",
        version: 0,
        timestamp: DateTime.utc_now()
      }
      
      op2 = %CollaborativeEditor.Operation{
        id: Ecto.UUID.generate(),
        user_id: "user2",
        type: :insert,
        position: 0,
        content: "B",
        version: 0,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, _} = CollaborativeEditor.apply_operation(project_id, file_path, op1)
      {:ok, transformed} = CollaborativeEditor.apply_operation(project_id, file_path, op2)
      
      # Second operation should be transformed
      assert transformed.position == 1
      
      {:ok, doc} = CollaborativeEditor.get_document(project_id, file_path)
      assert String.starts_with?(doc.content, "AB")
    end
  end
  
  describe "join_session/3" do
    setup %{project_id: project_id, file_path: file_path, initial_content: initial_content} do
      {:ok, _} = CollaborativeEditor.start_session(project_id, file_path, initial_content)
      :ok
    end
    
    test "allows users to join session", %{project_id: project_id, file_path: file_path, initial_content: initial_content} do
      assert {:ok, join_data} = CollaborativeEditor.join_session(project_id, file_path, "user1")
      
      assert join_data.content == initial_content
      assert join_data.version == 0
      assert "user1" in join_data.active_users
    end
  end
  
  describe "get_history/3" do
    setup %{project_id: project_id, file_path: file_path, initial_content: initial_content} do
      {:ok, _} = CollaborativeEditor.start_session(project_id, file_path, initial_content)
      
      # Apply some operations
      ops = for i <- 1..5 do
        op = %CollaborativeEditor.Operation{
          id: Ecto.UUID.generate(),
          user_id: "user#{i}",
          type: :insert,
          position: 0,
          content: "Line #{i}\n",
          version: i - 1,
          timestamp: DateTime.utc_now()
        }
        {:ok, _} = CollaborativeEditor.apply_operation(project_id, file_path, op)
      end
      
      :ok
    end
    
    test "returns operation history", %{project_id: project_id, file_path: file_path} do
      assert {:ok, history} = CollaborativeEditor.get_history(project_id, file_path, 3)
      
      assert length(history) == 3
      # Most recent first
      assert hd(history).version == 5
    end
  end
end