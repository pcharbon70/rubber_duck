defmodule RubberDuck.Projects.FileManagerTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.Projects.FileManager
  alias RubberDuck.Workspace
  alias RubberDuck.AccountsFixtures
  
  setup do
    # Create a test user
    user = AccountsFixtures.user_fixture()
    
    # Create a test project with temporary directory
    temp_dir = Path.join(System.tmp_dir!(), "file_manager_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(temp_dir)
    
    {:ok, project} = Workspace.create_project(%{
      name: "Test Project",
      root_path: temp_dir
    }, actor: user)
    
    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)
    
    %{user: user, project: project, temp_dir: temp_dir}
  end
  
  describe "new/3" do
    test "creates a FileManager instance with default options", %{project: project, user: user} do
      fm = FileManager.new(project, user)
      
      assert fm.project == project
      assert fm.user == user
      assert fm.options[:max_file_size] == 50 * 1024 * 1024
      assert fm.options[:allowed_extensions] == :all
      assert fm.options[:enable_audit] == true
    end
    
    test "creates a FileManager instance with custom options", %{project: project, user: user} do
      fm = FileManager.new(project, user, 
        max_file_size: 1024,
        allowed_extensions: [".txt", ".md"],
        enable_audit: false
      )
      
      assert fm.options[:max_file_size] == 1024
      assert fm.options[:allowed_extensions] == [".txt", ".md"]
      assert fm.options[:enable_audit] == false
    end
  end
  
  describe "read_file/3" do
    test "reads an existing file", %{project: project, user: user, temp_dir: temp_dir} do
      # Create a test file
      file_path = Path.join(temp_dir, "test.txt")
      File.write!(file_path, "Hello, World!")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, "Hello, World!"} = FileManager.read_file(fm, "test.txt")
    end
    
    test "returns error for non-existent file", %{project: project, user: user} do
      fm = FileManager.new(project, user)
      
      assert {:error, :file_not_found} = FileManager.read_file(fm, "non_existent.txt")
    end
    
    test "returns error for path traversal attempts", %{project: project, user: user} do
      fm = FileManager.new(project, user)
      
      assert {:error, :path_traversal} = FileManager.read_file(fm, "../../../etc/passwd")
    end
    
    test "reads file as stream when requested", %{project: project, user: user, temp_dir: temp_dir} do
      # Create a test file
      file_path = Path.join(temp_dir, "stream_test.txt")
      File.write!(file_path, "Stream content")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, stream} = FileManager.read_file(fm, "stream_test.txt", stream: true)
      assert %File.Stream{} = stream
      assert Enum.join(stream) == "Stream content"
    end
  end
  
  describe "write_file/4" do
    test "writes a file atomically", %{project: project, user: user, temp_dir: temp_dir} do
      fm = FileManager.new(project, user)
      
      assert {:ok, "new_file.txt"} = FileManager.write_file(fm, "new_file.txt", "Test content")
      
      # Verify file was written
      file_path = Path.join(temp_dir, "new_file.txt")
      assert File.exists?(file_path)
      assert File.read!(file_path) == "Test content"
    end
    
    test "overwrites existing file", %{project: project, user: user, temp_dir: temp_dir} do
      # Create initial file
      file_path = Path.join(temp_dir, "existing.txt")
      File.write!(file_path, "Old content")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, "existing.txt"} = FileManager.write_file(fm, "existing.txt", "New content")
      assert File.read!(file_path) == "New content"
    end
    
    test "returns error for file size limit", %{project: project, user: user} do
      fm = FileManager.new(project, user, max_file_size: 10)
      
      assert {:error, {:validation_error, msg}} = 
        FileManager.write_file(fm, "large.txt", String.duplicate("a", 20))
      
      assert msg =~ "exceeds maximum allowed"
    end
    
    test "validates file extensions when configured", %{project: project, user: user} do
      fm = FileManager.new(project, user, allowed_extensions: [".txt", ".md"])
      
      assert {:ok, _} = FileManager.write_file(fm, "allowed.txt", "content")
      assert {:error, {:validation_error, msg}} = 
        FileManager.write_file(fm, "forbidden.exe", "content")
      
      assert msg =~ "not allowed"
    end
  end
  
  describe "delete_file/3" do
    test "moves file to trash by default", %{project: project, user: user, temp_dir: temp_dir} do
      # Create a test file
      file_path = Path.join(temp_dir, "to_delete.txt")
      File.write!(file_path, "Delete me")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, "to_delete.txt"} = FileManager.delete_file(fm, "to_delete.txt")
      assert not File.exists?(file_path)
      
      # Check trash directory
      trash_dir = Path.join(System.tmp_dir!(), ".trash")
      assert File.exists?(trash_dir)
      trash_files = File.ls!(trash_dir) |> Enum.filter(&String.starts_with?(&1, "to_delete.txt"))
      assert length(trash_files) > 0
    end
    
    test "permanently deletes file when trash is disabled", %{project: project, user: user, temp_dir: temp_dir} do
      # Create a test file
      file_path = Path.join(temp_dir, "permanent_delete.txt")
      File.write!(file_path, "Delete permanently")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, "permanent_delete.txt"} = FileManager.delete_file(fm, "permanent_delete.txt", trash: false)
      assert not File.exists?(file_path)
    end
    
    test "deletes directory recursively", %{project: project, user: user, temp_dir: temp_dir} do
      # Create directory structure
      dir_path = Path.join(temp_dir, "dir_to_delete")
      File.mkdir_p!(Path.join(dir_path, "subdir"))
      File.write!(Path.join([dir_path, "file.txt"]), "content")
      File.write!(Path.join([dir_path, "subdir", "nested.txt"]), "nested")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, "dir_to_delete"} = FileManager.delete_file(fm, "dir_to_delete", trash: false, recursive: true)
      assert not File.exists?(dir_path)
    end
  end
  
  describe "create_directory/3" do
    test "creates a directory", %{project: project, user: user, temp_dir: temp_dir} do
      fm = FileManager.new(project, user)
      
      assert {:ok, "new_dir"} = FileManager.create_directory(fm, "new_dir")
      
      dir_path = Path.join(temp_dir, "new_dir")
      assert File.exists?(dir_path)
      assert File.dir?(dir_path)
    end
    
    test "creates nested directories recursively", %{project: project, user: user, temp_dir: temp_dir} do
      fm = FileManager.new(project, user)
      
      assert {:ok, "parent/child/grandchild"} = FileManager.create_directory(fm, "parent/child/grandchild")
      
      dir_path = Path.join(temp_dir, "parent/child/grandchild")
      assert File.exists?(dir_path)
      assert File.dir?(dir_path)
    end
    
    test "returns error if directory exists", %{project: project, user: user, temp_dir: temp_dir} do
      # Create existing directory
      dir_path = Path.join(temp_dir, "existing_dir")
      File.mkdir!(dir_path)
      
      fm = FileManager.new(project, user)
      
      assert {:error, :file_exists} = FileManager.create_directory(fm, "existing_dir")
    end
  end
  
  describe "list_directory/3" do
    test "lists directory contents", %{project: project, user: user, temp_dir: temp_dir} do
      # Create test files and directories
      File.write!(Path.join(temp_dir, "file1.txt"), "content1")
      File.write!(Path.join(temp_dir, "file2.md"), "content2")
      File.mkdir!(Path.join(temp_dir, "subdir"))
      File.write!(Path.join(temp_dir, ".hidden"), "hidden")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, entries} = FileManager.list_directory(fm, ".")
      
      # Should not include hidden files by default
      assert length(entries) == 3
      assert Enum.any?(entries, &(&1.name == "file1.txt"))
      assert Enum.any?(entries, &(&1.name == "file2.md"))
      assert Enum.any?(entries, &(&1.name == "subdir"))
      
      # Each entry should have required fields
      Enum.each(entries, fn entry ->
        assert Map.has_key?(entry, :name)
        assert Map.has_key?(entry, :type)
        assert Map.has_key?(entry, :size)
        assert Map.has_key?(entry, :modified)
      end)
    end
    
    test "lists hidden files when requested", %{project: project, user: user, temp_dir: temp_dir} do
      File.write!(Path.join(temp_dir, ".hidden"), "hidden")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, entries} = FileManager.list_directory(fm, ".", show_hidden: true)
      assert Enum.any?(entries, &(&1.name == ".hidden"))
    end
    
    test "supports pagination", %{project: project, user: user, temp_dir: temp_dir} do
      # Create many files
      for i <- 1..10 do
        File.write!(Path.join(temp_dir, "file#{i}.txt"), "content")
      end
      
      fm = FileManager.new(project, user)
      
      assert {:ok, page1} = FileManager.list_directory(fm, ".", page: 1, page_size: 5)
      assert length(page1) == 5
      
      assert {:ok, page2} = FileManager.list_directory(fm, ".", page: 2, page_size: 5)
      assert length(page2) == 5
      
      # Ensure different files on each page
      page1_names = Enum.map(page1, & &1.name)
      page2_names = Enum.map(page2, & &1.name)
      assert MapSet.disjoint?(MapSet.new(page1_names), MapSet.new(page2_names))
    end
  end
  
  describe "move_file/4" do
    test "moves a file", %{project: project, user: user, temp_dir: temp_dir} do
      # Create source file
      source_path = Path.join(temp_dir, "source.txt")
      File.write!(source_path, "Move me")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, "moved.txt"} = FileManager.move_file(fm, "source.txt", "moved.txt")
      
      assert not File.exists?(source_path)
      assert File.exists?(Path.join(temp_dir, "moved.txt"))
      assert File.read!(Path.join(temp_dir, "moved.txt")) == "Move me"
    end
    
    test "moves a directory", %{project: project, user: user, temp_dir: temp_dir} do
      # Create source directory with content
      source_dir = Path.join(temp_dir, "source_dir")
      File.mkdir!(source_dir)
      File.write!(Path.join(source_dir, "file.txt"), "content")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, "dest_dir"} = FileManager.move_file(fm, "source_dir", "dest_dir")
      
      assert not File.exists?(source_dir)
      assert File.exists?(Path.join(temp_dir, "dest_dir"))
      assert File.exists?(Path.join([temp_dir, "dest_dir", "file.txt"]))
    end
    
    test "returns error if destination exists", %{project: project, user: user, temp_dir: temp_dir} do
      File.write!(Path.join(temp_dir, "source.txt"), "source")
      File.write!(Path.join(temp_dir, "dest.txt"), "dest")
      
      fm = FileManager.new(project, user)
      
      assert {:error, :file_exists} = FileManager.move_file(fm, "source.txt", "dest.txt")
    end
  end
  
  describe "copy_file/4" do
    test "copies a file", %{project: project, user: user, temp_dir: temp_dir} do
      # Create source file
      source_path = Path.join(temp_dir, "source.txt")
      File.write!(source_path, "Copy me")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, "copy.txt"} = FileManager.copy_file(fm, "source.txt", "copy.txt")
      
      assert File.exists?(source_path)
      assert File.exists?(Path.join(temp_dir, "copy.txt"))
      assert File.read!(Path.join(temp_dir, "copy.txt")) == "Copy me"
    end
    
    test "copies a directory recursively", %{project: project, user: user, temp_dir: temp_dir} do
      # Create source directory structure
      source_dir = Path.join(temp_dir, "source_dir")
      File.mkdir_p!(Path.join(source_dir, "subdir"))
      File.write!(Path.join(source_dir, "file1.txt"), "content1")
      File.write!(Path.join([source_dir, "subdir", "file2.txt"]), "content2")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, "copy_dir"} = FileManager.copy_file(fm, "source_dir", "copy_dir")
      
      # Verify structure was copied
      assert File.exists?(Path.join(temp_dir, "copy_dir"))
      assert File.exists?(Path.join([temp_dir, "copy_dir", "file1.txt"]))
      assert File.exists?(Path.join([temp_dir, "copy_dir", "subdir", "file2.txt"]))
      assert File.read!(Path.join([temp_dir, "copy_dir", "file1.txt"])) == "content1"
    end
    
    test "overwrites when configured", %{project: project, user: user, temp_dir: temp_dir} do
      File.write!(Path.join(temp_dir, "source.txt"), "source content")
      File.write!(Path.join(temp_dir, "dest.txt"), "old content")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, "dest.txt"} = FileManager.copy_file(fm, "source.txt", "dest.txt", overwrite: true)
      assert File.read!(Path.join(temp_dir, "dest.txt")) == "source content"
    end
    
    test "calls progress callback", %{project: project, user: user, temp_dir: temp_dir} do
      # Create a larger file
      File.write!(Path.join(temp_dir, "large.txt"), String.duplicate("a", 10_000))
      
      _progress_updates = []
      callback = fn update -> 
        send(self(), update)
      end
      
      fm = FileManager.new(project, user)
      
      assert {:ok, "copy.txt"} = FileManager.copy_file(fm, "large.txt", "copy.txt", 
        progress_callback: callback)
      
      # Should have received at least one progress update
      assert_received {:progress, _}
    end
  end
  
  describe "authorization" do
    test "allows owner to perform all operations", %{project: project, user: user, temp_dir: temp_dir} do
      File.write!(Path.join(temp_dir, "test.txt"), "content")
      
      fm = FileManager.new(project, user)
      
      assert {:ok, _} = FileManager.read_file(fm, "test.txt")
      assert {:ok, _} = FileManager.write_file(fm, "new.txt", "content")
      assert {:ok, _} = FileManager.create_directory(fm, "newdir")
    end
    
    test "denies operations for non-collaborator", %{project: project, temp_dir: temp_dir} do
      # Create another user
      other_user = AccountsFixtures.user_fixture()
      
      File.write!(Path.join(temp_dir, "test.txt"), "content")
      
      fm = FileManager.new(project, other_user)
      
      assert {:error, :unauthorized} = FileManager.read_file(fm, "test.txt")
      assert {:error, :unauthorized} = FileManager.write_file(fm, "new.txt", "content")
      assert {:error, :unauthorized} = FileManager.delete_file(fm, "test.txt")
    end
    
    test "respects collaborator permissions", %{project: project, user: owner, temp_dir: temp_dir} do
      # Create a collaborator with read permission
      reader = AccountsFixtures.user_fixture()
      
      {:ok, _} = Workspace.add_project_collaborator(project, reader, :read, actor: owner)
      
      File.write!(Path.join(temp_dir, "test.txt"), "content")
      
      fm = FileManager.new(project, reader)
      
      # Reader can read and list
      assert {:ok, _} = FileManager.read_file(fm, "test.txt")
      assert {:ok, _} = FileManager.list_directory(fm, ".")
      
      # But cannot write or delete
      assert {:error, :unauthorized} = FileManager.write_file(fm, "new.txt", "content")
      assert {:error, :unauthorized} = FileManager.delete_file(fm, "test.txt")
    end
  end
end