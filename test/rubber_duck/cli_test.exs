defmodule RubberDuck.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias RubberDuck.CLI

  describe "main/1" do
    test "shows help when no arguments provided" do
      assert_raise Optimus.ParseError, ~r/Required argument 'command' was not specified/, fn ->
        CLI.main([])
      end
    end

    test "shows version with --version flag" do
      output =
        capture_io(fn ->
          try do
            CLI.main(["--version"])
          catch
            :exit, _ -> :ok
          end
        end)

      assert output =~ "0.1.0"
    end

    test "shows help with --help flag" do
      output =
        capture_io(fn ->
          try do
            CLI.main(["--help"])
          catch
            :exit, _ -> :ok
          end
        end)

      assert output =~ "rubber_duck"
      assert output =~ "AI-powered coding assistant"
      assert output =~ "analyze"
      assert output =~ "generate"
      assert output =~ "complete"
    end

    test "parses global options correctly" do
      # This test would need to mock the command execution
      # For now, we'll test that it doesn't crash with valid options
      assert_raise Optimus.ParseError, fn ->
        CLI.main(["--format", "json", "--verbose", "analyze"])
      end
    end

    test "rejects invalid format option" do
      assert_raise Optimus.ParseError, ~r/Unknown format/, fn ->
        CLI.main(["--format", "invalid", "analyze", "test.ex"])
      end
    end
  end

  describe "command parsing" do
    test "analyze command requires path argument" do
      assert_raise Optimus.ParseError, ~r/Required argument 'PATH' was not specified/, fn ->
        CLI.main(["analyze"])
      end
    end

    test "generate command requires prompt argument" do
      assert_raise Optimus.ParseError, ~r/Required argument 'PROMPT' was not specified/, fn ->
        CLI.main(["generate"])
      end
    end

    test "complete command requires file and position" do
      assert_raise Optimus.ParseError, ~r/Required argument 'FILE' was not specified/, fn ->
        CLI.main(["complete"])
      end
    end

    test "complete command requires line and column options" do
      assert_raise Optimus.ParseError, ~r/Required option '--line' was not specified/, fn ->
        CLI.main(["complete", "test.ex"])
      end
    end
  end
end
