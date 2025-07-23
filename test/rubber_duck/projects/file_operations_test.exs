defmodule RubberDuck.Projects.FileOperationsTest do
  use RubberDuck.DataCase
  alias RubberDuck.Projects.FileOperations
  alias RubberDuck.Workspace
  
  import RubberDuck.AccountsFixtures
  
  setup do
    # Create a test user
    user = user_fixture()
    
    # Create a test project with file access enabled
    {:ok, project} = Workspace.create_project(%{
      name: "Test Project",
      description: "Test project for file operations",
      file_access_enabled: true,
      root_path: System.tmp_dir!() |> Path.join("test_project_#{System.unique_integer([:positive])}"),
      max_file_size: 1_048_576,  # 1MB
      allowed_extensions: [".ex", ".exs", ".txt", ".md"]
    }, actor: user)
    
    # Create the project directory
    File.mkdir_p!(project.root_path)
    
    on_exit(fn ->
      # Cleanup
      File.rm_rf(project.root_path)
    end)
    
    {:ok, project: project, user: user}
  end
  
  describe "create/4" do
    test "creates a file successfully", %{project: project} do
      assert {:ok, result} = FileOperations.create(project, "/", "test.ex", :file)
      assert result.path == "test.ex"
      assert result.type == :file
      assert File.exists?(Path.join(project.root_path, "test.ex"))
    end
    
    test "creates a directory successfully", %{project: project} do
      assert {:ok, result} = FileOperations.create(project, "/", "test_dir", :directory)
      assert result.path == "test_dir"
      assert result.type == :directory
      assert File.dir?(Path.join(project.root_path, "test_dir"))
    end
    
    test "creates a file in a subdirectory", %{project: project} do
      # First create the directory
      assert {:ok, _} = FileOperations.create(project, "/", "lib", :directory)
      
      # Then create file in the directory
      assert {:ok, result} = FileOperations.create(project, "lib", "module.ex", :file)
      assert result.path == "lib/module.ex"
      assert File.exists?(Path.join(project.root_path, "lib/module.ex"))
    end
    
    test "fails when file access is disabled", %{project: project, user: user} do
      # Disable file access
      {:ok, project} = Workspace.update_project(project, %{file_access_enabled: false}, actor: user)
      
      assert {:error, "File access is not enabled for this project"} = 
        FileOperations.create(project, "/", "test.ex", :file)
    end
    
    test "fails with disallowed extension", %{project: project} do
      assert {:error, "File extension .py is not allowed"} = 
        FileOperations.create(project, "/", "test.py", :file)
    end
    
    test "prevents path traversal", %{project: project} do
      assert {:error, "Path is outside project root"} = 
        FileOperations.create(project, "../", "evil.txt", :file)
    end
  end
  
  describe "rename/3" do
    test "renames a file successfully", %{project: project} do
      # Create a file first
      assert {:ok, _} = FileOperations.create(project, "/", "old.txt", :file)
      
      # Rename it
      assert {:ok, result} = FileOperations.rename(project, "old.txt", "new.txt")
      assert result.old_path == "old.txt"
      assert result.new_path == "new.txt"
      assert File.exists?(Path.join(project.root_path, "new.txt"))
      refute File.exists?(Path.join(project.root_path, "old.txt"))
    end
    
    test "renames a directory successfully", %{project: project} do
      # Create a directory first
      assert {:ok, _} = FileOperations.create(project, "/", "old_dir", :directory)
      
      # Rename it
      assert {:ok, result} = FileOperations.rename(project, "old_dir", "new_dir")
      assert result.old_path == "old_dir"
      assert result.new_path == "new_dir"
      assert File.dir?(Path.join(project.root_path, "new_dir"))
      refute File.dir?(Path.join(project.root_path, "old_dir"))
    end
    
    test "fails with disallowed extension", %{project: project} do
      # Create a file first
      assert {:ok, _} = FileOperations.create(project, "/", "test.txt", :file)
      
      # Try to rename with disallowed extension
      assert {:error, "File extension .py is not allowed"} = 
        FileOperations.rename(project, "test.txt", "test.py")
    end
  end
  
  describe "delete/2" do
    test "deletes a file successfully", %{project: project} do
      # Create a file first
      assert {:ok, _} = FileOperations.create(project, "/", "test.txt", :file)
      
      # Delete it
      assert {:ok, result} = FileOperations.delete(project, "test.txt")
      assert result.path == "test.txt"
      refute File.exists?(Path.join(project.root_path, "test.txt"))
    end
    
    test "deletes a directory and its contents", %{project: project} do
      # Create directory structure
      assert {:ok, _} = FileOperations.create(project, "/", "dir", :directory)
      assert {:ok, _} = FileOperations.create(project, "dir", "file.txt", :file)
      
      # Delete the directory
      assert {:ok, result} = FileOperations.delete(project, "dir")
      assert result.path == "dir"
      refute File.dir?(Path.join(project.root_path, "dir"))
    end
  end
  
  describe "read_file/2" do
    test "reads file content successfully", %{project: project} do
      # Create and write a file
      file_path = Path.join(project.root_path, "test.txt")
      content = "Hello, World!"
      File.write!(file_path, content)
      
      # Read it through FileOperations
      assert {:ok, read_content} = FileOperations.read_file(project, "test.txt")
      assert read_content == content
    end
    
    test "fails when file is too large", %{project: project} do
      # Create a large file
      file_path = Path.join(project.root_path, "large.txt")
      large_content = String.duplicate("x", project.max_file_size + 1)
      File.write!(file_path, large_content)
      
      # Try to read it
      assert {:error, "File size exceeds limit of " <> _} = 
        FileOperations.read_file(project, "large.txt")
    end
  end
  
  describe "write_file/3" do
    test "writes file content successfully", %{project: project} do
      content = "Hello, Elixir!"
      
      assert :ok = FileOperations.write_file(project, "test.ex", content)
      
      # Verify the file was written
      assert File.read!(Path.join(project.root_path, "test.ex")) == content
    end
    
    test "creates parent directories if needed", %{project: project} do
      content = "defmodule Test do\\nend"
      
      assert :ok = FileOperations.write_file(project, "lib/test.ex", content)
      
      # Verify the file and directory were created
      assert File.exists?(Path.join(project.root_path, "lib/test.ex"))
    end
    
    test "fails when content is too large", %{project: project} do
      large_content = String.duplicate("x", project.max_file_size + 1)
      
      assert {:error, "File size exceeds limit of " <> _} = 
        FileOperations.write_file(project, "large.txt", large_content)
    end
  end
  
end