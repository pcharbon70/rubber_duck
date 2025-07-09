defmodule RubberDuck.CLI.Formatter.Table do
  @moduledoc """
  Table formatter for CLI output.

  Formats results in a tabular format for better readability in terminals.
  """

  @doc """
  Formats the result as a table.
  """
  def format(%{type: :analysis, results: results}) do
    headers = ["File", "Line", "Column", "Severity", "Issue"]

    rows =
      results
      |> Enum.flat_map(fn result ->
        Enum.map(result.issues, fn issue ->
          [
            truncate(result.file, 30),
            to_string(issue.line),
            to_string(issue.column),
            to_string(issue.severity),
            truncate(issue.message, 50)
          ]
        end)
      end)

    {:ok, format_table(headers, rows)}
  end

  def format(%{type: :completion, suggestions: suggestions}) do
    headers = ["#", "Completion", "Score"]

    rows =
      suggestions
      |> Enum.with_index(1)
      |> Enum.map(fn {suggestion, idx} ->
        [
          to_string(idx),
          truncate(suggestion.text, 60),
          format_score(suggestion[:score])
        ]
      end)

    {:ok, format_table(headers, rows)}
  end

  def format(result) do
    # Fallback to plain format for unsupported types
    RubberDuck.CLI.Formatter.Plain.format(result)
  end

  defp format_table(headers, rows) do
    # Calculate column widths
    widths = calculate_widths(headers, rows)

    # Format header
    header_line = format_row(headers, widths)
    separator = format_separator(widths)

    # Format rows
    formatted_rows = Enum.map(rows, &format_row(&1, widths))

    # Combine all parts
    [header_line, separator | formatted_rows]
    |> Enum.join("\n")
  end

  defp calculate_widths(headers, rows) do
    all_rows = [headers | rows]

    all_rows
    |> Enum.zip()
    |> Enum.map(fn column ->
      column
      |> Tuple.to_list()
      |> Enum.map(&String.length/1)
      |> Enum.max()
    end)
  end

  defp format_row(row, widths) do
    row
    |> Enum.zip(widths)
    |> Enum.map(fn {cell, width} ->
      String.pad_trailing(cell, width)
    end)
    |> Enum.join(" | ")
    |> (fn line -> "| #{line} |" end).()
  end

  defp format_separator(widths) do
    widths
    |> Enum.map(&String.duplicate("-", &1))
    |> Enum.join("-+-")
    |> (fn line -> "+-#{line}-+" end).()
  end

  defp truncate(string, max_length) do
    if String.length(string) > max_length do
      String.slice(string, 0, max_length - 3) <> "..."
    else
      string
    end
  end

  defp format_score(nil), do: "N/A"

  defp format_score(score) when is_float(score) do
    :io_lib.format("~.2f", [score]) |> to_string()
  end

  defp format_score(score), do: to_string(score)
end
