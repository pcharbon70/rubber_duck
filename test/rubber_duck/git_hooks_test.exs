defmodule RubberDuck.GitHooksTest do
  use ExUnit.Case, async: true
  import Bitwise

  @hooks_dir ".githooks"
  @pre_commit_hook Path.join(@hooks_dir, "pre-commit")
  @install_script Path.join(@hooks_dir, "install.sh")

  describe "git hooks structure" do
    test "git hooks directory exists" do
      assert File.dir?(@hooks_dir), ".githooks directory should exist"
    end

    test "pre-commit hook exists and is executable" do
      assert File.exists?(@pre_commit_hook), "pre-commit hook should exist"

      # Check if file is executable (on Unix-like systems)
      case :os.type() do
        {:unix, _} ->
          stat = File.stat!(@pre_commit_hook)
          # Check if any execute bit is set (owner, group, or other)
          assert (stat.mode &&& 0o111) != 0, "pre-commit hook should be executable"

        _ ->
          :ok
      end
    end

    test "install script exists and is executable" do
      assert File.exists?(@install_script), "install.sh script should exist"

      case :os.type() do
        {:unix, _} ->
          stat = File.stat!(@install_script)
          assert (stat.mode &&& 0o111) != 0, "install.sh should be executable"

        _ ->
          :ok
      end
    end

    test "README exists in git hooks directory" do
      readme_path = Path.join(@hooks_dir, "README.md")
      assert File.exists?(readme_path), "README.md should exist in .githooks"
    end
  end

  describe "pre-commit hook content" do
    test "pre-commit hook has proper shebang" do
      content = File.read!(@pre_commit_hook)

      assert String.starts_with?(content, "#!/bin/bash"),
             "pre-commit hook should start with bash shebang"
    end

    test "pre-commit hook checks for mix format" do
      content = File.read!(@pre_commit_hook)

      assert content =~ "mix format",
             "pre-commit hook should run mix format"
    end

    test "pre-commit hook checks for compilation" do
      content = File.read!(@pre_commit_hook)

      assert content =~ "mix compile",
             "pre-commit hook should run mix compile"
    end

    test "pre-commit hook checks for credo" do
      content = File.read!(@pre_commit_hook)

      assert content =~ "mix credo",
             "pre-commit hook should run mix credo"
    end

    test "pre-commit hook only checks staged files" do
      content = File.read!(@pre_commit_hook)

      assert content =~ "git diff --cached",
             "pre-commit hook should check staged files"
    end
  end

  describe "install script" do
    test "install script configures git hooks path" do
      content = File.read!(@install_script)

      assert content =~ "git config core.hooksPath .githooks",
             "install script should configure git hooks path"

      assert content =~ "Making hooks executable",
             "install script should make hooks executable"
    end

    test "install script verifies installation" do
      content = File.read!(@install_script)

      assert content =~ "Verify installation",
             "install script should verify installation"

      assert content =~ "Available hooks:",
             "install script should list available hooks"
    end
  end

  describe "hook functionality" do
    @tag :skip
    test "pre-commit hook prevents commit with formatting issues" do
      # This test would require creating a temporary git repo
      # and testing the actual hook execution
      # Marked as skip to avoid complexity in unit tests
    end

    @tag :skip
    test "pre-commit hook prevents commit with compilation errors" do
      # This test would require creating a temporary git repo
      # and testing the actual hook execution
      # Marked as skip to avoid complexity in unit tests
    end

    @tag :skip
    test "pre-commit hook prevents commit with credo issues in strict mode" do
      # This test would require creating a temporary git repo
      # and testing the actual hook execution
      # Marked as skip to avoid complexity in unit tests
    end
  end
end
