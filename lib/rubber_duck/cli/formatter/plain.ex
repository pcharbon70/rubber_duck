defmodule RubberDuck.CLI.Formatter.Plain do
  @moduledoc """
  Plain text formatter for CLI output.
  """

  @doc """
  Formats the result as plain text.
  """
  def format(%{type: :analysis, results: results}) do
    output =
      results
      |> Enum.map(&format_analysis_result/1)
      |> Enum.join("\n\n")

    {:ok, output}
  end

  def format(%{type: :completion, suggestions: suggestions}) do
    output =
      suggestions
      |> Enum.with_index(1)
      |> Enum.map(fn {suggestion, idx} ->
        "#{idx}. #{suggestion.text}"
      end)
      |> Enum.join("\n")

    {:ok, output}
  end

  def format(%{type: :generation, code: code, language: language}) do
    output = """
    Generated #{language} code:
    #{String.duplicate("-", 50)}
    #{code}
    #{String.duplicate("-", 50)}
    """

    {:ok, output}
  end

  def format(%{type: :refactor, diff: diff}) when is_binary(diff) do
    {:ok, diff}
  end

  def format(%{type: :refactor, code: code}) do
    {:ok, code}
  end

  def format(%{type: :test, tests: tests, framework: framework}) do
    output = """
    Generated #{framework} tests:
    #{String.duplicate("-", 50)}
    #{tests}
    #{String.duplicate("-", 50)}
    """

    {:ok, output}
  end

  def format(%{type: :error, message: message}) do
    {:ok, "Error: #{message}"}
  end

  def format(result) do
    {:ok, inspect(result, pretty: true)}
  end

  defp format_analysis_result(%{
         file: file,
         issues: issues,
         severity: severity
       }) do
    header = "File: #{file}"
    severity_text = "Severity: #{severity}"

    issue_list =
      issues
      |> Enum.map(fn issue ->
        "  - [#{issue.line}:#{issue.column}] #{issue.message}"
      end)
      |> Enum.join("\n")

    """
    #{header}
    #{severity_text}
    Issues:
    #{issue_list}
    """
  end

  defp format_analysis_result(result) do
    inspect(result, pretty: true)
  end
end
