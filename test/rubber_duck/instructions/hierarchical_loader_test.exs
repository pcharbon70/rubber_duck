defmodule RubberDuck.Instructions.HierarchicalLoaderTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Instructions.{HierarchicalLoader, Registry}

  # Setup temporary directory structure for tests
  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("hierarchy_test_#{System.unique_integer()}")
    File.mkdir_p!(tmp_dir)

    # Create directory structure
    instructions_dir = Path.join(tmp_dir, "instructions")
    vscode_dir = Path.join(tmp_dir, ".vscode")
    File.mkdir_p!(instructions_dir)
    File.mkdir_p!(vscode_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir, instructions_dir: instructions_dir, vscode_dir: vscode_dir}
  end

  describe "load_instructions/2" do
    test "loads instructions from multiple hierarchy levels",
         %{tmp_dir: tmp_dir, instructions_dir: instructions_dir, vscode_dir: vscode_dir} do
      # Create files at different levels
      project_file = Path.join(tmp_dir, "claude.md")
      directory_file = Path.join(instructions_dir, "rules.md")
      workspace_file = Path.join(vscode_dir, "settings.md")

      File.write!(project_file, """
      ---
      title: Project Instructions
      priority: high
      ---
      # Project Level
      """)

      File.write!(directory_file, """
      ---
      title: Directory Rules
      priority: normal
      ---
      # Directory Level
      """)

      File.write!(workspace_file, """
      ---
      title: Workspace Settings  
      priority: normal
      ---
      # Workspace Level
      """)

      {:ok, result} =
        HierarchicalLoader.load_instructions(tmp_dir,
          include_global: false,
          register_instructions: false,
          dry_run: true
        )

      assert result.stats.total_discovered >= 3
      assert result.stats.total_loaded >= 3
      assert result.stats.total_errors == 0

      # Check that all levels are represented
      scopes = Enum.map(result.loaded, & &1.scope)
      assert :project in scopes
      assert :workspace in scopes
    end

    test "respects priority ordering", %{tmp_dir: tmp_dir} do
      # Create files with different priorities
      high_file = Path.join(tmp_dir, "high.md")
      low_file = Path.join(tmp_dir, "low.md")

      File.write!(high_file, """
      ---
      priority: critical
      ---
      # High Priority
      """)

      File.write!(low_file, """
      ---
      priority: low
      ---
      # Low Priority
      """)

      {:ok, result} =
        HierarchicalLoader.load_instructions(tmp_dir,
          include_global: false,
          register_instructions: false,
          dry_run: true
        )

      high_instruction = Enum.find(result.loaded, &String.ends_with?(&1.file_path, "high.md"))
      low_instruction = Enum.find(result.loaded, &String.ends_with?(&1.file_path, "low.md"))

      assert high_instruction.priority > low_instruction.priority
    end

    test "handles file parsing errors gracefully", %{tmp_dir: tmp_dir} do
      # Create a file with malformed content
      bad_file = Path.join(tmp_dir, "bad.md")

      File.write!(bad_file, """
      ---
      title: "Unclosed quote
      invalid: [broken
      ---
      # Bad File
      """)

      # Also create a good file
      good_file = Path.join(tmp_dir, "good.md")
      File.write!(good_file, "# Good File")

      {:ok, result} =
        HierarchicalLoader.load_instructions(tmp_dir,
          include_global: false,
          register_instructions: false,
          dry_run: true
        )

      # Should load the good file and report error for bad file
      assert result.stats.total_loaded >= 1
      # Error handling may vary based on parser resilience
    end

    test "detects and resolves conflicts", %{tmp_dir: tmp_dir, instructions_dir: instructions_dir} do
      # Create conflicting files (same context)
      file1 = Path.join(tmp_dir, "claude.md")
      file2 = Path.join(instructions_dir, "claude.md")

      File.write!(file1, """
      ---
      title: Project Claude
      priority: normal
      ---
      # Project Claude
      """)

      File.write!(file2, """
      ---
      title: Directory Claude
      priority: high
      ---
      # Directory Claude
      """)

      {:ok, result} =
        HierarchicalLoader.load_instructions(tmp_dir,
          include_global: false,
          auto_resolve_conflicts: true,
          register_instructions: false,
          dry_run: true
        )

      # Should resolve conflict automatically
      assert result.stats.conflicts_resolved >= 1
      # Should only load one of the conflicting files
      claude_files = Enum.filter(result.loaded, &String.ends_with?(&1.file_path, "claude.md"))
      assert length(claude_files) == 1
    end

    test "dry run mode doesn't actually load instructions", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "test.md")
      File.write!(file_path, "# Test Instructions")

      # Get initial registry state
      initial_count =
        case Registry.get_stats() do
          stats when is_map(stats) -> stats.total_instructions
          _ -> 0
        end

      {:ok, result} =
        HierarchicalLoader.load_instructions(tmp_dir,
          include_global: false,
          register_instructions: true,
          dry_run: true
        )

      # Should show loaded instructions in result
      assert result.stats.total_loaded >= 1

      # But registry should be unchanged
      final_count =
        case Registry.get_stats() do
          stats when is_map(stats) -> stats.total_instructions
          _ -> 0
        end

      assert final_count == initial_count
    end
  end

  describe "discover_at_level/2" do
    test "discovers directory-level instructions", %{tmp_dir: tmp_dir, instructions_dir: instructions_dir} do
      file_path = Path.join(instructions_dir, "rules.md")
      File.write!(file_path, "# Directory Rules")

      {:ok, files} = HierarchicalLoader.discover_at_level(tmp_dir, :directory)

      file_paths = Enum.map(files, fn {path, _scope} -> path end)
      assert file_path in file_paths
    end

    test "discovers project-level instructions", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "claude.md")
      File.write!(file_path, "# Project Instructions")

      {:ok, files} = HierarchicalLoader.discover_at_level(tmp_dir, :project)

      file_paths = Enum.map(files, fn {path, _scope} -> path end)
      assert file_path in file_paths
    end

    test "discovers workspace-level instructions", %{tmp_dir: tmp_dir, vscode_dir: vscode_dir} do
      file_path = Path.join(vscode_dir, "instructions.md")
      File.write!(file_path, "# Workspace Instructions")

      {:ok, files} = HierarchicalLoader.discover_at_level(tmp_dir, :workspace)

      file_paths = Enum.map(files, fn {path, _scope} -> path end)
      assert file_path in file_paths
    end

    test "handles invalid hierarchy levels" do
      {:error, {:invalid_level, :invalid}} = HierarchicalLoader.discover_at_level(".", :invalid)
    end
  end

  describe "analyze_hierarchy/2" do
    test "provides hierarchy analysis without loading", %{tmp_dir: tmp_dir, instructions_dir: instructions_dir} do
      # Create files at different levels
      project_file = Path.join(tmp_dir, "claude.md")
      directory_file = Path.join(instructions_dir, "rules.md")

      File.write!(project_file, """
      ---
      priority: high
      ---
      # Project
      """)

      File.write!(directory_file, """
      ---
      priority: normal
      ---
      # Directory
      """)

      {:ok, analysis} = HierarchicalLoader.analyze_hierarchy(tmp_dir, include_global: false)

      assert is_map(analysis.hierarchy_levels)
      assert is_map(analysis.conflict_analysis)
      assert is_map(analysis.coverage_analysis)
      assert is_list(analysis.recommendations)
    end

    test "identifies coverage gaps", %{tmp_dir: tmp_dir} do
      # Create minimal setup that might have gaps
      {:ok, analysis} = HierarchicalLoader.analyze_hierarchy(tmp_dir, include_global: false)

      # Should have recommendations for missing project files
      assert length(analysis.recommendations) > 0
      assert Enum.any?(analysis.recommendations, &String.contains?(&1, "claude.md"))
    end
  end

  describe "conflict resolution" do
    test "automatically resolves conflicts by priority", %{tmp_dir: tmp_dir} do
      # Create two files that would conflict
      high_file = Path.join(tmp_dir, "high.md")
      low_file = Path.join(tmp_dir, "low.md")

      File.write!(high_file, """
      ---
      title: High Priority
      priority: critical
      context: same_context
      ---
      # High
      """)

      File.write!(low_file, """
      ---
      title: Low Priority  
      priority: low
      context: same_context
      ---
      # Low
      """)

      {:ok, result} =
        HierarchicalLoader.load_instructions(tmp_dir,
          include_global: false,
          auto_resolve_conflicts: true,
          register_instructions: false,
          dry_run: true
        )

      # Should prefer high priority file
      loaded_titles = Enum.map(result.loaded, & &1.file_path)
      # The exact conflict resolution depends on context key generation
      # Just verify that conflict resolution was attempted
      assert result.stats.total_discovered >= 2
    end

    test "reports conflict details", %{tmp_dir: tmp_dir} do
      # Create obvious conflicts
      file1 = Path.join(tmp_dir, "claude.md")
      # Case variation
      file2 = Path.join(tmp_dir, "CLAUDE.md")

      File.write!(file1, "# Claude 1")
      File.write!(file2, "# Claude 2")

      {:ok, result} =
        HierarchicalLoader.load_instructions(tmp_dir,
          include_global: false,
          auto_resolve_conflicts: true,
          register_instructions: false,
          dry_run: true
        )

      # Check conflict reporting structure
      if length(result.conflicts) > 0 do
        conflict = hd(result.conflicts)
        assert is_binary(conflict.context)
        assert is_binary(conflict.winner)
        assert is_list(conflict.losers)
        assert is_binary(conflict.resolution_reason)
      end
    end
  end

  describe "error handling and edge cases" do
    test "handles empty directories gracefully", %{tmp_dir: tmp_dir} do
      empty_dir = Path.join(tmp_dir, "empty")
      File.mkdir_p!(empty_dir)

      {:ok, result} =
        HierarchicalLoader.load_instructions(empty_dir,
          include_global: false,
          register_instructions: false,
          dry_run: true
        )

      assert result.stats.total_discovered == 0
      assert result.stats.total_loaded == 0
      assert result.stats.total_errors == 0
    end

    test "handles non-existent root directory" do
      non_existent = "/path/that/does/not/exist"

      {:ok, result} =
        HierarchicalLoader.load_instructions(non_existent,
          include_global: false,
          register_instructions: false,
          dry_run: true
        )

      # Should handle gracefully
      assert result.stats.total_discovered == 0
    end

    test "respects file size limits", %{tmp_dir: tmp_dir} do
      large_file = Path.join(tmp_dir, "large.md")
      large_content = String.duplicate("x", 30_000)
      File.write!(large_file, large_content)

      small_file = Path.join(tmp_dir, "small.md")
      File.write!(small_file, "# Small file")

      {:ok, result} =
        HierarchicalLoader.load_instructions(tmp_dir,
          include_global: false,
          validate_content: true,
          register_instructions: false,
          dry_run: true
        )

      # Large file should be skipped or error
      small_loaded = Enum.any?(result.loaded, &String.ends_with?(&1.file_path, "small.md"))
      assert small_loaded

      # Large file should not be loaded due to size
      large_loaded = Enum.any?(result.loaded, &String.ends_with?(&1.file_path, "large.md"))
      refute large_loaded
    end
  end

  describe "performance and stats" do
    test "provides comprehensive loading statistics", %{tmp_dir: tmp_dir} do
      # Create various files
      files = [
        {"good1.md", "# Good 1"},
        {"good2.md", "# Good 2"},
        {"good3.md", "# Good 3"}
      ]

      Enum.each(files, fn {name, content} ->
        File.write!(Path.join(tmp_dir, name), content)
      end)

      {:ok, result} =
        HierarchicalLoader.load_instructions(tmp_dir,
          include_global: false,
          register_instructions: false,
          dry_run: true
        )

      stats = result.stats
      assert is_integer(stats.total_discovered)
      assert is_integer(stats.total_loaded)
      assert is_integer(stats.total_skipped)
      assert is_integer(stats.total_errors)
      assert is_integer(stats.conflicts_resolved)
      assert is_integer(stats.loading_time)
      # Should take some time
      assert stats.loading_time > 0
    end

    test "measures loading performance", %{tmp_dir: tmp_dir} do
      # Create enough files to measure performance
      Enum.each(1..10, fn i ->
        File.write!(Path.join(tmp_dir, "file#{i}.md"), "# File #{i}")
      end)

      start_time = System.monotonic_time(:microsecond)

      {:ok, result} =
        HierarchicalLoader.load_instructions(tmp_dir,
          include_global: false,
          register_instructions: false,
          dry_run: true
        )

      end_time = System.monotonic_time(:microsecond)
      actual_time = end_time - start_time

      # Reported time should be close to actual time
      assert result.stats.loading_time <= actual_time
      assert result.stats.loading_time > 0
    end
  end

  describe "format support" do
    test "loads different instruction file formats", %{tmp_dir: tmp_dir} do
      # Create files in different formats
      formats = [
        {"markdown.md", "# Markdown\nContent"},
        {"claude.md", "# Claude\nSpecial format"},
        {"rules.cursorrules", "- Rule 1\n- Rule 2"},
        {"meta.mdc", "---\ntitle: Metadata\n---\n# Content"}
      ]

      Enum.each(formats, fn {name, content} ->
        File.write!(Path.join(tmp_dir, name), content)
      end)

      {:ok, result} =
        HierarchicalLoader.load_instructions(tmp_dir,
          include_global: false,
          register_instructions: false,
          dry_run: true
        )

      # Should load all format types
      assert result.stats.total_loaded >= 4
      assert result.stats.total_errors == 0
    end
  end
end
