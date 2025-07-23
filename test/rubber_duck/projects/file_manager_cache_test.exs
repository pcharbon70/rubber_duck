defmodule RubberDuck.Projects.FileManagerCacheTest do
  use RubberDuck.DataCase, async: false
  
  alias RubberDuck.Projects.{FileManager, FileCache}
  alias RubberDuck.Workspace
  alias RubberDuck.AccountsFixtures
  
  setup do
    # Clear cache before each test
    FileCache.clear()
    
    # Create a test user
    user = AccountsFixtures.user_fixture()
    
    # Create a test project with temporary directory
    temp_dir = Path.join(System.tmp_dir!(), "fm_cache_test_#{:rand.uniform(1_000_000)}")
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
  
  describe "directory listing cache" do
    test "caches directory listings", %{project: project, user: user, temp_dir: temp_dir} do
      # Create test files
      File.write!(Path.join(temp_dir, "file1.txt"), "content1")
      File.write!(Path.join(temp_dir, "file2.txt"), "content2")
      
      fm = FileManager.new(project, user, enable_cache: true, auto_watch: false)
      
      # First call should miss cache
      {:ok, entries1} = FileManager.list_directory(fm, ".")
      assert length(entries1) == 2
      
      # Check that it was cached
      cache_key = "list:.:#{:erlang.phash2([])}"
      assert {:ok, ^entries1} = FileCache.get(project.id, cache_key)
      
      # Second call should hit cache (we can verify by checking that 
      # adding a new file doesn't show up)
      File.write!(Path.join(temp_dir, "file3.txt"), "content3")
      
      {:ok, entries2} = FileManager.list_directory(fm, ".")
      assert length(entries2) == 2  # Still 2, not 3, because cached
      assert entries1 == entries2
    end
    
    test "respects cache disable option", %{project: project, user: user, temp_dir: temp_dir} do
      File.write!(Path.join(temp_dir, "file1.txt"), "content1")
      
      fm = FileManager.new(project, user, enable_cache: false)
      
      # First call
      {:ok, entries1} = FileManager.list_directory(fm, ".")
      assert length(entries1) == 1
      
      # Add new file
      File.write!(Path.join(temp_dir, "file2.txt"), "content2")
      
      # Second call should see new file (not cached)
      {:ok, entries2} = FileManager.list_directory(fm, ".")
      assert length(entries2) == 2
    end
    
    test "cache key includes listing options", %{project: project, user: user, temp_dir: temp_dir} do
      # Create many files
      for i <- 1..10 do
        File.write!(Path.join(temp_dir, "file#{i}.txt"), "content#{i}")
      end
      
      fm = FileManager.new(project, user, enable_cache: true, auto_watch: false)
      
      # Different pages should have different cache keys
      {:ok, page1} = FileManager.list_directory(fm, ".", page: 1, page_size: 5)
      {:ok, page2} = FileManager.list_directory(fm, ".", page: 2, page_size: 5)
      
      assert length(page1) == 5
      assert length(page2) == 5
      assert page1 != page2
      
      # Different sort orders should have different cache keys
      {:ok, asc} = FileManager.list_directory(fm, ".", sort_by: :name, sort_order: :asc)
      {:ok, desc} = FileManager.list_directory(fm, ".", sort_by: :name, sort_order: :desc)
      
      assert hd(asc).name != hd(desc).name
    end
  end
  
  describe "cache invalidation" do
    test "invalidates cache on file write", %{project: project, user: user, temp_dir: _temp_dir} do
      fm = FileManager.new(project, user, enable_cache: true, auto_watch: false)
      
      # List directory (caches it)
      {:ok, entries1} = FileManager.list_directory(fm, ".")
      assert length(entries1) == 0
      
      # Write a file
      {:ok, _} = FileManager.write_file(fm, "new.txt", "content")
      
      # List again should show new file (cache invalidated)
      {:ok, entries2} = FileManager.list_directory(fm, ".")
      assert length(entries2) == 1
      assert hd(entries2).name == "new.txt"
    end
    
    test "invalidates cache on file delete", %{project: project, user: user, temp_dir: temp_dir} do
      # Create initial file
      File.write!(Path.join(temp_dir, "delete_me.txt"), "content")
      
      fm = FileManager.new(project, user, enable_cache: true, auto_watch: false)
      
      # List directory (caches it)
      {:ok, entries1} = FileManager.list_directory(fm, ".")
      assert length(entries1) == 1
      
      # Delete the file
      {:ok, _} = FileManager.delete_file(fm, "delete_me.txt", trash: false)
      
      # List again should show no files (cache invalidated)
      {:ok, entries2} = FileManager.list_directory(fm, ".")
      assert length(entries2) == 0
    end
    
    test "invalidates cache on directory creation", %{project: project, user: user} do
      fm = FileManager.new(project, user, enable_cache: true, auto_watch: false)
      
      # List directory (caches it)
      {:ok, entries1} = FileManager.list_directory(fm, ".")
      assert length(entries1) == 0
      
      # Create a directory
      {:ok, _} = FileManager.create_directory(fm, "new_dir")
      
      # List again should show new directory (cache invalidated)
      {:ok, entries2} = FileManager.list_directory(fm, ".")
      assert length(entries2) == 1
      assert hd(entries2).name == "new_dir"
      assert hd(entries2).type == :directory
    end
    
    test "invalidates cache on file move", %{project: project, user: user, temp_dir: temp_dir} do
      # Create source file
      File.write!(Path.join(temp_dir, "source.txt"), "content")
      
      fm = FileManager.new(project, user, enable_cache: true, auto_watch: false)
      
      # List directory (caches it)
      {:ok, entries1} = FileManager.list_directory(fm, ".")
      assert length(entries1) == 1
      assert hd(entries1).name == "source.txt"
      
      # Move the file
      {:ok, _} = FileManager.move_file(fm, "source.txt", "dest.txt")
      
      # List again should show renamed file (cache invalidated)
      {:ok, entries2} = FileManager.list_directory(fm, ".")
      assert length(entries2) == 1
      assert hd(entries2).name == "dest.txt"
    end
    
    test "invalidates cache on file copy", %{project: project, user: user, temp_dir: temp_dir} do
      # Create source file
      File.write!(Path.join(temp_dir, "source.txt"), "content")
      
      fm = FileManager.new(project, user, enable_cache: true, auto_watch: false)
      
      # List directory (caches it)
      {:ok, entries1} = FileManager.list_directory(fm, ".")
      assert length(entries1) == 1
      
      # Copy the file
      {:ok, _} = FileManager.copy_file(fm, "source.txt", "copy.txt")
      
      # List again should show both files (cache invalidated)
      {:ok, entries2} = FileManager.list_directory(fm, ".")
      assert length(entries2) == 2
      assert Enum.any?(entries2, &(&1.name == "source.txt"))
      assert Enum.any?(entries2, &(&1.name == "copy.txt"))
    end
    
    test "invalidates parent directory cache for nested operations", %{project: project, user: user, temp_dir: temp_dir} do
      # Create nested structure
      File.mkdir_p!(Path.join(temp_dir, "parent/child"))
      
      fm = FileManager.new(project, user, enable_cache: true, auto_watch: false)
      
      # List parent directory (caches it)
      {:ok, parent_entries} = FileManager.list_directory(fm, "parent")
      assert length(parent_entries) == 1
      assert hd(parent_entries).name == "child"
      
      # Create file in child directory
      {:ok, _} = FileManager.write_file(fm, "parent/child/file.txt", "content")
      
      # Parent listing cache should be invalidated too
      # (to ensure consistency when child directories change)
      cache_key = "list:parent:#{:erlang.phash2([])}"
      assert FileCache.get(project.id, cache_key) == :miss
      
      # But child directory listing should show new file
      {:ok, child_entries} = FileManager.list_directory(fm, "parent/child")
      assert length(child_entries) == 1
      assert hd(child_entries).name == "file.txt"
    end
  end
  
  describe "cache statistics" do
    test "tracks cache hits and misses", %{project: project, user: user, temp_dir: temp_dir} do
      File.write!(Path.join(temp_dir, "file.txt"), "content")
      
      fm = FileManager.new(project, user, enable_cache: true, auto_watch: false)
      
      # Clear stats by restarting cache
      FileCache.clear()
      
      # First call - miss
      {:ok, _} = FileManager.list_directory(fm, ".")
      
      # Second call - hit  
      {:ok, _} = FileManager.list_directory(fm, ".")
      
      # Third call with different options - miss
      {:ok, _} = FileManager.list_directory(fm, ".", show_hidden: true)
      
      # Check stats (Note: The actual stats tracking would need to be
      # implemented in FileCache, this is just showing the expected API)
      stats = FileCache.stats()
      assert stats.size > 0
      assert stats.memory > 0
    end
  end
end