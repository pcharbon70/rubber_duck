defmodule RubberDuck.Projects.FileAccessTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Projects.FileAccess

  @project_root "/home/user/projects/test"

  describe "validate_path/2" do
    test "accepts valid relative paths" do
      assert {:ok, path} = FileAccess.validate_path("src/main.ex", @project_root)
      assert path == "/home/user/projects/test/src/main.ex"
    end

    test "accepts paths within project root" do
      assert {:ok, path} = FileAccess.validate_path("./lib/app.ex", @project_root)
      assert path == "/home/user/projects/test/lib/app.ex"
    end

    test "rejects parent directory traversal" do
      assert {:error, :path_traversal_attempt} = FileAccess.validate_path("../outside.ex", @project_root)
      assert {:error, :path_traversal_attempt} = FileAccess.validate_path("src/../../outside.ex", @project_root)
    end

    test "rejects absolute paths outside project" do
      assert {:error, :outside_project_root} = FileAccess.validate_path("/etc/passwd", @project_root)
      assert {:error, :outside_project_root} = FileAccess.validate_path("/tmp/file.txt", @project_root)
    end

    test "rejects home directory expansion" do
      assert {:error, :path_traversal_attempt} = FileAccess.validate_path("~/secrets.txt", @project_root)
    end

    test "rejects null bytes in paths" do
      assert {:error, :path_traversal_attempt} = FileAccess.validate_path("file.ex\0.txt", @project_root)
    end

    test "rejects invalid path characters" do
      assert {:error, :path_traversal_attempt} = FileAccess.validate_path("file<script>.ex", @project_root)
      assert {:error, :path_traversal_attempt} = FileAccess.validate_path("file|command.ex", @project_root)
    end

    test "handles empty inputs" do
      assert {:error, :invalid_arguments} = FileAccess.validate_path(nil, @project_root)
      assert {:error, :invalid_arguments} = FileAccess.validate_path("file.ex", nil)
    end
  end

  describe "check_extension/2" do
    test "allows any extension when list is empty" do
      assert :ok = FileAccess.check_extension("file.anything", [])
    end

    test "allows matching extensions" do
      allowed = [".ex", ".exs", ".md"]
      assert :ok = FileAccess.check_extension("main.ex", allowed)
      assert :ok = FileAccess.check_extension("test.exs", allowed)
      assert :ok = FileAccess.check_extension("README.md", allowed)
    end

    test "rejects non-matching extensions" do
      allowed = [".ex", ".exs"]
      assert {:error, :invalid_extension} = FileAccess.check_extension("script.py", allowed)
      assert {:error, :invalid_extension} = FileAccess.check_extension("binary.exe", allowed)
    end

    test "handles files without extensions" do
      allowed = [".ex", ".exs"]
      assert {:error, :invalid_extension} = FileAccess.check_extension("Makefile", allowed)
    end
  end

  describe "check_file_size/3" do
    setup do
      # Create a temporary directory for tests
      tmp_dir = System.tmp_dir!()
      project_root = Path.join(tmp_dir, "file_access_test_#{System.unique_integer()}")
      File.mkdir_p!(project_root)

      on_exit(fn -> File.rm_rf!(project_root) end)

      {:ok, project_root: project_root}
    end

    test "allows files under size limit", %{project_root: project_root} do
      file_path = Path.join(project_root, "small.txt")
      File.write!(file_path, "Small content")

      assert :ok = FileAccess.check_file_size("small.txt", project_root, 1024)
    end

    test "rejects files over size limit", %{project_root: project_root} do
      file_path = Path.join(project_root, "large.txt")
      File.write!(file_path, String.duplicate("x", 1000))

      assert {:error, :file_too_large} = FileAccess.check_file_size("large.txt", project_root, 100)
    end

    test "allows non-existent files", %{project_root: project_root} do
      assert :ok = FileAccess.check_file_size("new_file.txt", project_root, 1024)
    end
  end

  describe "get_file_info/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      project_root = Path.join(tmp_dir, "file_info_test_#{System.unique_integer()}")
      File.mkdir_p!(project_root)

      on_exit(fn -> File.rm_rf!(project_root) end)

      {:ok, project_root: project_root}
    end

    test "returns file metadata", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test do\nend")

      assert {:ok, info} = FileAccess.get_file_info("test.ex", project_root)
      assert info.path == file_path
      assert info.size > 0
      assert info.type == :regular
      assert info.is_symlink == false
      assert is_integer(info.permissions)
    end

    test "detects symbolic links", %{project_root: project_root} do
      target = Path.join(project_root, "target.txt")
      link = Path.join(project_root, "link.txt")

      File.write!(target, "content")
      File.ln_s!(target, link)

      assert {:ok, info} = FileAccess.get_file_info("link.txt", project_root)
      assert info.is_symlink == true
    end
  end
end
