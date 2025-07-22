defmodule RubberDuck.Projects.SymlinkSecurityTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Projects.SymlinkSecurity

  setup do
    # Create a temporary test environment
    tmp_dir = System.tmp_dir!()
    test_root = Path.join(tmp_dir, "symlink_test_#{System.unique_integer()}")
    project_root = Path.join(test_root, "project")
    outside_dir = Path.join(test_root, "outside")

    File.mkdir_p!(project_root)
    File.mkdir_p!(outside_dir)

    on_exit(fn -> File.rm_rf!(test_root) end)

    {:ok, project_root: project_root, outside_dir: outside_dir, test_root: test_root}
  end

  describe "check_symlinks/2" do
    test "accepts regular files and directories", %{project_root: project_root} do
      file_path = Path.join(project_root, "regular.txt")
      File.write!(file_path, "content")

      assert {:ok, :safe} = SymlinkSecurity.check_symlinks(file_path, project_root)
    end

    test "accepts paths that don't exist yet", %{project_root: project_root} do
      new_file = Path.join(project_root, "new_file.txt")
      assert {:ok, :safe} = SymlinkSecurity.check_symlinks(new_file, project_root)
    end

    test "detects symlinks pointing outside project", %{project_root: project_root, outside_dir: outside_dir} do
      # Create a file outside the project
      outside_file = Path.join(outside_dir, "secret.txt")
      File.write!(outside_file, "secret content")

      # Create a symlink inside project pointing outside
      link_path = Path.join(project_root, "link_to_secret.txt")
      File.ln_s!(outside_file, link_path)

      assert {:error, :symlink_escape_attempt} = SymlinkSecurity.check_symlinks(link_path, project_root)
    end

    test "accepts symlinks within project", %{project_root: project_root} do
      # Create a file inside the project
      target = Path.join(project_root, "target.txt")
      File.write!(target, "content")

      # Create a symlink to it
      link = Path.join(project_root, "link.txt")
      File.ln_s!(target, link)

      assert {:ok, :safe} = SymlinkSecurity.check_symlinks(link, project_root)
    end

    test "detects symlinks in path components", %{project_root: project_root, outside_dir: outside_dir} do
      # Create a symlink directory that points outside
      sub_dir = Path.join(project_root, "subdir")
      File.mkdir_p!(sub_dir)
      
      link_dir = Path.join(project_root, "linkdir")
      File.ln_s!(outside_dir, link_dir)

      # Try to access a file through the symlink directory
      file_through_link = Path.join(link_dir, "file.txt")
      
      assert {:error, :symlink_escape_attempt} = SymlinkSecurity.check_symlinks(file_through_link, project_root)
    end

    test "handles invalid inputs", %{project_root: project_root} do
      assert {:error, :invalid_path} = SymlinkSecurity.check_symlinks(nil, project_root)
      assert {:error, :invalid_project_root} = SymlinkSecurity.check_symlinks("file.txt", nil)
      assert {:error, :empty_path} = SymlinkSecurity.check_symlinks("", project_root)
    end
  end

  describe "resolve_symlinks/2" do
    test "resolves simple symlinks", %{project_root: project_root} do
      target = Path.join(project_root, "target.txt")
      File.write!(target, "content")

      link = Path.join(project_root, "link.txt")
      File.ln_s!(target, link)

      assert {:ok, resolved} = SymlinkSecurity.resolve_symlinks(link, project_root)
      assert resolved == target
    end

    test "resolves chain of symlinks", %{project_root: project_root} do
      # Create a chain: link1 -> link2 -> target
      target = Path.join(project_root, "target.txt")
      File.write!(target, "content")

      link2 = Path.join(project_root, "link2.txt")
      File.ln_s!(target, link2)

      link1 = Path.join(project_root, "link1.txt")
      File.ln_s!(link2, link1)

      assert {:ok, resolved} = SymlinkSecurity.resolve_symlinks(link1, project_root)
      assert resolved == target
    end

    test "detects symlink loops", %{project_root: project_root} do
      # Create a circular symlink: link1 -> link2 -> link1
      link1 = Path.join(project_root, "link1.txt")
      link2 = Path.join(project_root, "link2.txt")

      File.ln_s!(link2, link1)
      File.ln_s!(link1, link2)

      assert {:error, :symlink_loop_detected} = SymlinkSecurity.resolve_symlinks(link1, project_root)
    end

    test "rejects resolved paths outside project", %{project_root: project_root, outside_dir: outside_dir} do
      outside_file = Path.join(outside_dir, "outside.txt")
      File.write!(outside_file, "content")

      link = Path.join(project_root, "escape.txt")
      File.ln_s!(outside_file, link)

      assert {:error, :symlink_escape_attempt} = SymlinkSecurity.resolve_symlinks(link, project_root)
    end
  end

  describe "symlinks_allowed?/1" do
    test "correctly interprets sandbox config" do
      assert SymlinkSecurity.symlinks_allowed?(%{"allow_symlinks" => true})
      refute SymlinkSecurity.symlinks_allowed?(%{"allow_symlinks" => false})
      refute SymlinkSecurity.symlinks_allowed?(%{})
      refute SymlinkSecurity.symlinks_allowed?(nil)
    end
  end

  describe "scan_for_symlinks/1" do
    test "finds all symlinks in directory tree", %{project_root: project_root} do
      # Create directory structure with some symlinks
      sub_dir = Path.join(project_root, "subdir")
      File.mkdir_p!(sub_dir)

      # Regular files
      File.write!(Path.join(project_root, "file1.txt"), "content")
      File.write!(Path.join(sub_dir, "file2.txt"), "content")

      # Symlinks
      link1 = Path.join(project_root, "link1.txt")
      link2 = Path.join(sub_dir, "link2.txt")
      
      File.ln_s!("file1.txt", link1)
      File.ln_s!("file2.txt", link2)

      assert {:ok, symlinks} = SymlinkSecurity.scan_for_symlinks(project_root)
      assert length(symlinks) == 2
      assert link1 in symlinks
      assert link2 in symlinks
    end

    test "handles empty directories", %{project_root: project_root} do
      assert {:ok, []} = SymlinkSecurity.scan_for_symlinks(project_root)
    end
  end

  describe "validate_symlink_target/3" do
    test "validates relative symlink targets", %{project_root: project_root} do
      link_path = Path.join(project_root, "subdir/link.txt")
      
      # Target within project (relative to link location)
      assert :ok = SymlinkSecurity.validate_symlink_target(link_path, "../file.txt", project_root)
      
      # Target escaping project
      assert {:error, :symlink_escape_attempt} = 
        SymlinkSecurity.validate_symlink_target(link_path, "../../outside.txt", project_root)
    end

    test "validates absolute symlink targets", %{project_root: project_root} do
      link_path = Path.join(project_root, "link.txt")
      
      # Absolute path within project
      target_within = Path.join(project_root, "target.txt")
      assert :ok = SymlinkSecurity.validate_symlink_target(link_path, target_within, project_root)
      
      # Absolute path outside project
      assert {:error, :symlink_escape_attempt} = 
        SymlinkSecurity.validate_symlink_target(link_path, "/etc/passwd", project_root)
    end
  end
end