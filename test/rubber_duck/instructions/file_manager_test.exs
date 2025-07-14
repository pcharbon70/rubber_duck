defmodule RubberDuck.Instructions.FileManagerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Instructions.FileManager
  
  # Setup temporary directory for tests
  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("instruction_test_#{System.unique_integer()}")
    File.mkdir_p!(tmp_dir)
    
    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)
    
    {:ok, tmp_dir: tmp_dir}
  end
  
  describe "discover_files/2" do
    test "discovers instruction files in project root", %{tmp_dir: tmp_dir} do
      # Create test files
      claude_md = Path.join(tmp_dir, "claude.md")
      instructions_md = Path.join(tmp_dir, "instructions.md")
      
      File.write!(claude_md, "# Claude Instructions\nTest content")
      File.write!(instructions_md, "# Instructions\nOther content")
      
      {:ok, files} = FileManager.discover_files(tmp_dir, include_global: false)
      
      file_paths = Enum.map(files, & &1.path)
      assert claude_md in file_paths
      assert instructions_md in file_paths
      assert length(files) == 2
    end
    
    test "respects priority ordering", %{tmp_dir: tmp_dir} do
      # Create files with different priorities
      claude_md = Path.join(tmp_dir, "claude.md")
      other_md = Path.join(tmp_dir, "other.md")
      
      File.write!(claude_md, "# Claude")
      File.write!(other_md, "# Other")
      
      {:ok, files} = FileManager.discover_files(tmp_dir, include_global: false)
      
      # claude.md should have higher priority
      claude_file = Enum.find(files, &(&1.path == claude_md))
      other_file = Enum.find(files, &(&1.path == other_md))
      
      assert claude_file.priority > other_file.priority
    end
    
    test "discovers files in subdirectories", %{tmp_dir: tmp_dir} do
      # Create subdirectory with instructions
      sub_dir = Path.join(tmp_dir, "instructions")
      File.mkdir_p!(sub_dir)
      
      sub_file = Path.join(sub_dir, "rules.md")
      File.write!(sub_file, "# Rules\nSubdirectory rules")
      
      {:ok, files} = FileManager.discover_files(tmp_dir, include_global: false)
      
      file_paths = Enum.map(files, & &1.path)
      assert sub_file in file_paths
    end
    
    test "handles non-existent directories gracefully", %{tmp_dir: tmp_dir} do
      non_existent = Path.join(tmp_dir, "does_not_exist")
      
      {:ok, files} = FileManager.discover_files(non_existent, include_global: false)
      
      assert files == []
    end
    
    test "respects file size limits", %{tmp_dir: tmp_dir} do
      large_file = Path.join(tmp_dir, "large.md")
      large_content = String.duplicate("x", 30_000)  # Exceeds default limit
      File.write!(large_file, large_content)
      
      {:ok, files} = FileManager.discover_files(tmp_dir, 
        include_global: false, 
        max_file_size: 25_000
      )
      
      file_paths = Enum.map(files, & &1.path)
      refute large_file in file_paths
    end
    
    test "includes global files when requested" do
      # This test checks that global discovery is attempted
      # We don't create actual global files since that would affect the system
      {:ok, files} = FileManager.discover_files(".", include_global: true)
      
      # Just verify the function runs without error
      assert is_list(files)
    end
    
    test "excludes global files when not requested", %{tmp_dir: tmp_dir} do
      {:ok, files} = FileManager.discover_files(tmp_dir, include_global: false)
      
      # Verify no global scope files
      global_files = Enum.filter(files, &(&1.scope == :global))
      assert global_files == []
    end
  end
  
  describe "load_file/2" do
    test "loads and processes a simple markdown file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "test.md")
      content = """
      ---
      title: Test Instructions
      priority: high
      ---
      # Test
      
      Hello {{ name }}!
      """
      File.write!(file_path, content)
      
      {:ok, instruction} = FileManager.load_file(file_path, %{"name" => "World"})
      
      assert instruction.path == file_path
      assert instruction.metadata["title"] == "Test Instructions"
      assert instruction.metadata["priority"] == "high"
      assert instruction.content =~ "Hello World!"
      assert instruction.type == :auto
      assert instruction.scope == :project
    end
    
    test "handles files without frontmatter", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "simple.md")
      content = "# Simple Instructions\n\nJust basic content."
      File.write!(file_path, content)
      
      {:ok, instruction} = FileManager.load_file(file_path)
      
      assert instruction.metadata == %{}
      assert instruction.content =~ "Simple Instructions"
      assert instruction.type == :auto  # Default type
    end
    
    test "determines instruction type from metadata", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "always.md")
      content = """
      ---
      type: always
      ---
      # Always Active
      """
      File.write!(file_path, content)
      
      {:ok, instruction} = FileManager.load_file(file_path)
      
      assert instruction.type == :always
    end
    
    test "calculates priority from metadata and file path", %{tmp_dir: tmp_dir} do
      # Test high priority from metadata
      high_file = Path.join(tmp_dir, "high.md")
      high_content = """
      ---
      priority: critical
      ---
      # High Priority
      """
      File.write!(high_file, high_content)
      
      # Test claude.md boost
      claude_file = Path.join(tmp_dir, "claude.md")
      claude_content = "# Claude Instructions"
      File.write!(claude_file, claude_content)
      
      {:ok, high_instruction} = FileManager.load_file(high_file)
      {:ok, claude_instruction} = FileManager.load_file(claude_file)
      
      # Both should have elevated priority
      assert high_instruction.priority > 1000  # Base + metadata boost
      assert claude_instruction.priority > 1000  # Base + filename boost
    end
    
    test "handles file read errors gracefully", %{tmp_dir: tmp_dir} do
      non_existent = Path.join(tmp_dir, "missing.md")
      
      {:error, {:file_read_error, :enoent}} = FileManager.load_file(non_existent)
    end
  end
  
  describe "validate_file/1" do
    test "validates a correct instruction file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "valid.md")
      content = """
      ---
      title: Valid Instructions
      type: auto
      priority: normal
      tags: [testing, validation]
      ---
      # Valid Instructions
      
      This is a valid instruction file.
      """
      File.write!(file_path, content)
      
      {:ok, validation} = FileManager.validate_file(file_path)
      
      assert validation.valid == true
      assert validation.metadata["title"] == "Valid Instructions"
      assert validation.warnings == []
    end
    
    test "rejects files that are too large", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "large.md")
      large_content = String.duplicate("x", 30_000)
      File.write!(file_path, large_content)
      
      {:error, :file_too_large} = FileManager.validate_file(file_path)
    end
    
    test "rejects files with invalid metadata", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "invalid_meta.md")
      content = """
      ---
      type: invalid_type
      priority: wrong_priority
      ---
      # Invalid Metadata
      """
      File.write!(file_path, content)
      
      {:error, _reason} = FileManager.validate_file(file_path)
    end
    
    test "rejects files with dangerous content", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "dangerous.md")
      content = """
      # Dangerous Instructions
      
      {{ System.cmd('rm', ['-rf', '/']) }}
      """
      File.write!(file_path, content)
      
      {:error, _reason} = FileManager.validate_file(file_path)
    end
  end
  
  describe "get_file_stats/1" do
    test "returns statistics for discovered files", %{tmp_dir: tmp_dir} do
      # Create multiple files
      files = [
        {"claude.md", "# Claude\nContent 1"},
        {"instructions.md", "# Instructions\nContent 2"},
        {"rules.md", "# Rules\nContent 3"}
      ]
      
      Enum.each(files, fn {name, content} ->
        File.write!(Path.join(tmp_dir, name), content)
      end)
      
      {:ok, stats} = FileManager.get_file_stats(tmp_dir)
      
      assert stats.total_files == 3
      assert stats.total_size > 0
      assert is_map(stats.by_type)
      assert is_map(stats.by_scope)
      assert stats.largest_file != nil
      assert stats.oldest_file != nil
    end
    
    test "handles empty directories", %{tmp_dir: tmp_dir} do
      {:ok, stats} = FileManager.get_file_stats(tmp_dir)
      
      assert stats.total_files == 0
      assert stats.total_size == 0
      assert stats.largest_file == nil
      assert stats.oldest_file == nil
    end
  end
  
  describe "scope determination" do
    test "correctly identifies project scope", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "project.md")
      File.write!(file_path, "# Project")
      
      {:ok, instruction} = FileManager.load_file(file_path)
      
      assert instruction.scope == :project
    end
    
    test "correctly identifies workspace scope" do
      # Create a temporary .vscode directory
      tmp_dir = System.tmp_dir!() |> Path.join("vscode_test_#{System.unique_integer()}")
      vscode_dir = Path.join(tmp_dir, ".vscode")
      File.mkdir_p!(vscode_dir)
      
      file_path = Path.join(vscode_dir, "settings.md")
      File.write!(file_path, "# Workspace Settings")
      
      {:ok, instruction} = FileManager.load_file(file_path)
      
      assert instruction.scope == :workspace
      
      # Cleanup
      File.rm_rf!(tmp_dir)
    end
  end
  
  describe "file format support" do
    test "supports .md files", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "test.md")
      File.write!(file_path, "# Markdown File")
      
      {:ok, files} = FileManager.discover_files(tmp_dir, include_global: false)
      
      assert Enum.any?(files, &(&1.path == file_path))
    end
    
    test "supports .cursorrules files", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "project.cursorrules")
      File.write!(file_path, "# Cursor Rules\n- Rule 1\n- Rule 2")
      
      {:ok, files} = FileManager.discover_files(tmp_dir, include_global: false)
      
      assert Enum.any?(files, &(&1.path == file_path))
    end
    
    test "supports claude.md specifically", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "claude.md")
      File.write!(file_path, "# Claude Instructions")
      
      {:ok, files} = FileManager.discover_files(tmp_dir, include_global: false)
      
      claude_file = Enum.find(files, &(&1.path == file_path))
      assert claude_file != nil
      # claude.md should have higher priority than generic .md files
      assert claude_file.priority > 1000
    end
  end
  
  describe "error handling" do
    test "handles permission errors gracefully" do
      # Test with a path that likely doesn't exist or isn't readable
      {:ok, files} = FileManager.discover_files("/root/nonexistent", include_global: false)
      
      # Should return empty list rather than error
      assert files == []
    end
    
    test "handles malformed YAML frontmatter", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "malformed.md")
      content = """
      ---
      title: Unclosed quote "
      invalid: [unclosed
      ---
      # Content
      """
      File.write!(file_path, content)
      
      # Should handle the error gracefully
      case FileManager.load_file(file_path) do
        {:ok, _instruction} -> :ok  # If parser is resilient
        {:error, _reason} -> :ok    # If parser rejects malformed YAML
      end
    end
  end
  
  describe "priority calculation" do
    test "assigns higher priority to critical files", %{tmp_dir: tmp_dir} do
      normal_file = Path.join(tmp_dir, "normal.md")
      critical_file = Path.join(tmp_dir, "critical.md")
      
      File.write!(normal_file, """
      ---
      priority: normal
      ---
      # Normal
      """)
      
      File.write!(critical_file, """
      ---
      priority: critical
      ---
      # Critical
      """)
      
      {:ok, normal} = FileManager.load_file(normal_file)
      {:ok, critical} = FileManager.load_file(critical_file)
      
      assert critical.priority > normal.priority
    end
    
    test "gives filename-based priority boosts", %{tmp_dir: tmp_dir} do
      claude_file = Path.join(tmp_dir, "claude.md")
      generic_file = Path.join(tmp_dir, "generic.md")
      
      File.write!(claude_file, "# Claude")
      File.write!(generic_file, "# Generic")
      
      {:ok, claude} = FileManager.load_file(claude_file)
      {:ok, generic} = FileManager.load_file(generic_file)
      
      assert claude.priority > generic.priority
    end
  end
end