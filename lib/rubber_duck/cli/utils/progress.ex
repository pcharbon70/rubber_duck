defmodule RubberDuck.CLI.Utils.Progress do
  @moduledoc """
  Progress indicators for CLI operations.

  Provides simple progress display for long-running operations.
  """

  @doc """
  Shows a progress indicator with the current item being processed.
  """
  def show(action, current, total, item_name) do
    percentage = round(current / total * 100)
    bar = progress_bar(percentage)

    # Use carriage return to overwrite the current line
    IO.write("\r#{action} [#{bar}] #{percentage}% (#{current}/#{total}) #{item_name}")
  end

  @doc """
  Clears the progress line.
  """
  def clear do
    # Clear the line and return to start
    IO.write("\r" <> String.duplicate(" ", 80) <> "\r")
  end

  @doc """
  Shows a simple spinner for indeterminate progress.
  """
  def spinner(message, index \\ 0) do
    frames = ["|", "/", "-", "\\"]
    frame = Enum.at(frames, rem(index, 4))
    IO.write("\r#{frame} #{message}")
  end

  defp progress_bar(percentage) do
    width = 20
    filled = round(percentage / 100 * width)
    empty = width - filled

    String.duplicate("=", filled) <> String.duplicate(" ", empty)
  end
end
