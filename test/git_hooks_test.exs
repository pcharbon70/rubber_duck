defmodule GitHooksTest do
  use ExUnit.Case, async: false

  @hooks_dir ".git/hooks"
  @pre_commit_hook Path.join(@hooks_dir, "pre-commit")

  describe "pre-commit hook" do
    test "pre-commit hook should exist after installation" do
      # This will fail initially since we haven't created the hook yet
      assert File.exists?(@pre_commit_hook), "Pre-commit hook should exist at #{@pre_commit_hook}"
    end

    test "hooks.install mix task should be available" do
      # This will fail initially since we haven't created the task yet
      # We'll check if the task file exists instead of running it
      task_path = "lib/mix/tasks/hooks.ex"
      assert File.exists?(task_path), "Mix task file should exist at #{task_path}"
    end
  end
end
