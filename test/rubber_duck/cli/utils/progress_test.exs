defmodule RubberDuck.CLI.Utils.ProgressTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias RubberDuck.CLI.Utils.Progress

  describe "show/4" do
    test "displays progress bar with percentage" do
      output =
        capture_io(fn ->
          Progress.show("Processing", 5, 10, "file.ex")
        end)

      assert output =~ "Processing"
      assert output =~ "50%"
      assert output =~ "(5/10)"
      assert output =~ "file.ex"
      # 50% of progress bar filled
      assert output =~ "=========="
    end

    test "shows full progress bar at 100%" do
      output =
        capture_io(fn ->
          Progress.show("Complete", 10, 10, "done.ex")
        end)

      assert output =~ "100%"
      # Full progress bar
      assert output =~ "===================="
    end

    test "shows empty progress bar at 0%" do
      output =
        capture_io(fn ->
          Progress.show("Starting", 0, 10, "begin.ex")
        end)

      assert output =~ "0%"
      # Empty progress bar
      assert output =~ "                    "
    end
  end

  describe "clear/0" do
    test "clears the progress line" do
      output =
        capture_io(fn ->
          Progress.clear()
        end)

      # Should output carriage return, spaces, and another carriage return
      assert output =~ "\r"
      assert String.contains?(output, String.duplicate(" ", 80))
    end
  end

  describe "spinner/2" do
    test "shows spinner animation frames" do
      # Test each frame
      output1 = capture_io(fn -> Progress.spinner("Loading", 0) end)
      assert output1 =~ "| Loading"

      output2 = capture_io(fn -> Progress.spinner("Loading", 1) end)
      assert output2 =~ "/ Loading"

      output3 = capture_io(fn -> Progress.spinner("Loading", 2) end)
      assert output3 =~ "- Loading"

      output4 = capture_io(fn -> Progress.spinner("Loading", 3) end)
      assert output4 =~ "\\ Loading"

      # Test wraparound
      output5 = capture_io(fn -> Progress.spinner("Loading", 4) end)
      assert output5 =~ "| Loading"
    end
  end
end
