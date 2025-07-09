defmodule RubberDuck.CLI.Commands.Complete do
  @moduledoc """
  CLI command for getting code completions.
  """

  alias RubberDuck.Engine.Manager

  @doc """
  Runs the complete command with the given arguments and configuration.
  """
  def run(args, _config) do
    file = args[:file]
    line = args[:line]
    column = args[:column]
    max_suggestions = args[:max_suggestions] || 5

    with {:ok, content} <- File.read(file),
         {:ok, suggestions} <- get_completions(content, file, line, column, max_suggestions) do
      {:ok,
       %{
         type: :completion,
         suggestions: suggestions
       }}
    else
      {:error, :enoent} ->
        {:error, "File not found: #{file}"}

      {:error, reason} ->
        {:error, "Completion failed: #{inspect(reason)}"}
    end
  end

  defp get_completions(content, file, line, column, max_suggestions) do
    input = %{
      content: content,
      file_path: file,
      cursor_position: {line, column},
      max_suggestions: max_suggestions
    }

    case Manager.execute(:completion, input) do
      {:ok, %{completions: completions}} ->
        suggestions =
          completions
          |> Enum.take(max_suggestions)
          |> Enum.map(&format_suggestion/1)

        {:ok, suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_suggestion(%{text: text} = completion) do
    %{
      text: text,
      score: completion[:score],
      type: completion[:type] || :unknown
    }
  end
end
