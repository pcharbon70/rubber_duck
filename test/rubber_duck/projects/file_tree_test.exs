defmodule RubberDuck.Projects.FileTreeTest do
  use ExUnit.Case, async: true
  alias RubberDuck.Projects.FileTree
  
  setup do
    # Create a temporary directory structure for testing
    test_dir = System.tmp_dir!() |> Path.join("file_tree_test_#{System.unique_integer([:positive])}")
    
    File.mkdir_p!(test_dir)
    File.mkdir_p!(Path.join(test_dir, "lib"))
    File.mkdir_p!(Path.join(test_dir, "test"))
    File.mkdir_p!(Path.join(test_dir, ".hidden"))
    
    File.write!(Path.join(test_dir, "README.md"), "# Test")
    File.write!(Path.join(test_dir, "mix.exs"), "defmodule Test do end")
    File.write!(Path.join(test_dir, "lib/module.ex"), "defmodule Module do end")
    File.write!(Path.join(test_dir, "test/test.exs"), "defmodule Test do end")
    File.write!(Path.join(test_dir, ".hidden/secret.txt"), "secret")
    
    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)
    
    {:ok, test_dir: test_dir}
  end
  
  describe "list_tree/2" do
    test "lists directory tree structure", %{test_dir: test_dir} do
      assert {:ok, tree} = FileTree.list_tree(test_dir)
      
      assert tree.type == :directory
      assert tree.name == Path.basename(test_dir)
      assert is_list(tree.children)
      
      # Check that expected files are present
      file_names = Enum.map(tree.children, & &1.name)
      assert "README.md" in file_names
      assert "mix.exs" in file_names
      assert "lib" in file_names
      assert "test" in file_names
      
      # Hidden files should not be included by default
      refute ".hidden" in file_names
    end
    
    test "includes hidden files when requested", %{test_dir: test_dir} do
      assert {:ok, tree} = FileTree.list_tree(test_dir, show_hidden: true)
      
      file_names = Enum.map(tree.children, & &1.name)
      assert ".hidden" in file_names
    end
    
    test "respects max depth", %{test_dir: test_dir} do
      assert {:ok, tree} = FileTree.list_tree(test_dir, max_depth: 1)
      
      # Find lib directory
      lib_dir = Enum.find(tree.children, &(&1.name == "lib"))
      assert lib_dir
      
      # Children should be nil due to max depth
      assert lib_dir.children == nil
    end
    
    test "returns error for non-existent path" do
      assert {:error, :enoent} = FileTree.list_tree("/non/existent/path")
    end
    
    test "returns error for file instead of directory" do
      temp_file = Path.join(System.tmp_dir!(), "test_file_#{System.unique_integer([:positive])}")
      File.write!(temp_file, "content")
      
      assert {:error, :not_a_directory} = FileTree.list_tree(temp_file)
      
      File.rm!(temp_file)
    end
  end
  
  describe "build_tree/1" do
    test "builds tree structure", %{test_dir: test_dir} do
      tree = FileTree.build_tree(test_dir)
      
      assert tree.type == :directory
      assert is_list(tree.children)
    end
    
    test "returns default tree on error" do
      tree = FileTree.build_tree("/non/existent/path")
      
      assert tree == %{name: "/", type: :directory, children: []}
    end
  end
  
  describe "add_path/3 and remove_path/2" do
    test "adds a file to the tree", %{test_dir: test_dir} do
      tree = FileTree.build_tree(test_dir)
      
      # Add a new file
      new_tree = FileTree.add_path(tree, "new_file.txt", test_dir)
      
      # Check that the file was added
      file_names = Enum.map(new_tree.children, & &1.name)
      assert "new_file.txt" in file_names
    end
    
    test "adds a nested file to the tree", %{test_dir: test_dir} do
      tree = FileTree.build_tree(test_dir)
      
      # Add a file in lib directory
      new_tree = FileTree.add_path(tree, "lib/new_module.ex", test_dir)
      
      # Find lib directory
      lib_dir = Enum.find(new_tree.children, &(&1.name == "lib"))
      assert lib_dir
      
      # Check that the file was added to lib
      lib_files = Enum.map(lib_dir.children, & &1.name)
      assert "new_module.ex" in lib_files
    end
    
    test "removes a file from the tree", %{test_dir: test_dir} do
      tree = FileTree.build_tree(test_dir)
      
      # Remove README.md
      new_tree = FileTree.remove_path(tree, "README.md")
      
      # Check that the file was removed
      file_names = Enum.map(new_tree.children, & &1.name)
      refute "README.md" in file_names
    end
    
    test "removes a nested file from the tree", %{test_dir: test_dir} do
      tree = FileTree.build_tree(test_dir)
      
      # Remove lib/module.ex
      new_tree = FileTree.remove_path(tree, "lib/module.ex")
      
      # Find lib directory
      lib_dir = Enum.find(new_tree.children, &(&1.name == "lib"))
      assert lib_dir
      
      # Check that the file was removed from lib
      lib_files = Enum.map(lib_dir.children, & &1.name)
      refute "module.ex" in lib_files
    end
  end
  
  describe "update_path/4" do
    test "updates a file path (rename)", %{test_dir: test_dir} do
      tree = FileTree.build_tree(test_dir)
      
      # Rename README.md to CHANGELOG.md
      new_tree = FileTree.update_path(tree, "README.md", "CHANGELOG.md", test_dir)
      
      file_names = Enum.map(new_tree.children, & &1.name)
      refute "README.md" in file_names
      assert "CHANGELOG.md" in file_names
    end
  end
  
  describe "search_files/3" do
    test "searches for files by name", %{test_dir: test_dir} do
      assert {:ok, results} = FileTree.search_files(test_dir, "module")
      
      # Should find module.ex
      assert length(results) == 1
      assert hd(results).name == "module.ex"
    end
    
    test "searches with extensions filter", %{test_dir: test_dir} do
      assert {:ok, results} = FileTree.search_files(test_dir, "", extensions: [".md"])
      
      # Should only find .md files
      assert length(results) == 1
      assert hd(results).name == "README.md"
    end
    
    test "case insensitive search", %{test_dir: test_dir} do
      assert {:ok, results} = FileTree.search_files(test_dir, "readme")
      
      # Should find README.md
      assert length(results) == 1
      assert hd(results).name == "README.md"
    end
    
    test "includes hidden files when requested", %{test_dir: test_dir} do
      assert {:ok, results} = FileTree.search_files(test_dir, "secret", show_hidden: true)
      
      # Should find secret.txt in hidden directory
      assert length(results) == 1
      assert hd(results).name == "secret.txt"
    end
  end
  
  describe "get_git_status/1" do
    test "returns git status for files", %{test_dir: test_dir} do
      # Initialize git repo
      {_output, 0} = System.cmd("git", ["init"], cd: test_dir)
      
      # Stage a file
      {_output, 0} = System.cmd("git", ["add", "README.md"], cd: test_dir)
      
      # Create a new untracked file
      File.write!(Path.join(test_dir, "new_file.txt"), "content")
      
      assert {:ok, status_map} = FileTree.get_git_status(test_dir)
      
      # README.md should be added (staged)
      assert status_map["README.md"] == :added
      
      # new_file.txt should be untracked
      assert status_map["new_file.txt"] == :untracked
    end
    
    test "returns empty map for non-git directory" do
      temp_dir = System.tmp_dir!() |> Path.join("non_git_#{System.unique_integer([:positive])}")
      File.mkdir_p!(temp_dir)
      
      assert {:ok, status_map} = FileTree.get_git_status(temp_dir)
      assert status_map == %{}
      
      File.rm_rf!(temp_dir)
    end
  end
  
  describe "file filtering" do
    test "filters out ignored patterns", %{test_dir: test_dir} do
      # Create some files that should be ignored
      File.mkdir_p!(Path.join(test_dir, "_build"))
      File.mkdir_p!(Path.join(test_dir, "deps"))
      File.mkdir_p!(Path.join(test_dir, "node_modules"))
      File.write!(Path.join(test_dir, ".DS_Store"), "")
      
      assert {:ok, tree} = FileTree.list_tree(test_dir)
      
      file_names = Enum.map(tree.children, & &1.name)
      
      # These should be filtered out
      refute "_build" in file_names
      refute "deps" in file_names
      refute "node_modules" in file_names
      refute ".DS_Store" in file_names
      
      # But these should be included
      assert "lib" in file_names
      assert "test" in file_names
    end
  end
  
  describe "sorting" do
    test "sorts directories before files", %{test_dir: test_dir} do
      assert {:ok, tree} = FileTree.list_tree(test_dir)
      
      # First items should be directories
      {dirs, _files} = Enum.split_with(tree.children, &(&1.type == :directory))
      
      # Verify directories come first
      dir_count = length(dirs)
      first_items = Enum.take(tree.children, dir_count)
      assert Enum.all?(first_items, &(&1.type == :directory))
    end
    
    test "sorts alphabetically within type", %{test_dir: test_dir} do
      # Create additional files
      File.write!(Path.join(test_dir, "aaa.txt"), "")
      File.write!(Path.join(test_dir, "zzz.txt"), "")
      
      assert {:ok, tree} = FileTree.list_tree(test_dir)
      
      files = Enum.filter(tree.children, &(&1.type == :file))
      file_names = Enum.map(files, & &1.name)
      
      # Should be sorted alphabetically
      assert file_names == Enum.sort(file_names, &(String.downcase(&1) <= String.downcase(&2)))
    end
  end
end