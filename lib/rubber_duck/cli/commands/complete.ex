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

    # Validate inputs
    cond do
      !file ->
        {:error, "File path is required"}
      
      !line || !is_integer(line) || line <= 0 ->
        {:error, "Valid line number is required"}
      
      !column || !is_integer(column) || column < 0 ->
        {:error, "Valid column number is required"}
      
      true ->
        validate_and_complete(file, line, column, max_suggestions)
    end
  end
  
  defp validate_and_complete(file, line, column, max_suggestions) do

    with {:ok, content} <- File.read(file),
         :ok <- validate_position(content, line, column),
         {:ok, completions} <- get_completions(content, file, line, column, max_suggestions) do
      {:ok,
       %{
         type: :completion,
         completions: completions
       }}
    else
      {:error, :enoent} ->
        {:error, "File not found: #{file}"}

      {:error, reason} ->
        {:error, "Completion failed: #{inspect(reason)}"}
    end
  end
  
  defp validate_position(content, line, column) do
    lines = String.split(content, "\n")
    
    if line > length(lines) do
      {:error, "Line #{line} is out of range (file has #{length(lines)} lines)"}
    else
      line_content = Enum.at(lines, line - 1, "")
      if column > String.length(line_content) do
        {:error, "Column #{column} is out of range for line #{line}"}
      else
        :ok
      end
    end
  end

  defp get_completions(content, file, line, column, max_suggestions) do
    # Get the line of code at the cursor
    lines = String.split(content, "\n")
    current_line = Enum.at(lines, line - 1, "")
    prefix = String.slice(current_line, 0, column)
    
    # Detect language from file extension
    language = detect_language(file)
    
    # Build prompt for completion
    prompt = """
    Complete the following #{language} code at the cursor position (marked with |):
    
    ```#{language}
    #{prefix}|
    ```
    
    Context (surrounding code):
    ```#{language}
    #{content}
    ```
    
    Provide #{max_suggestions} completion suggestions. Return only the code to insert at the cursor.
    """
    
    input = %{
      prompt: prompt,
      language: language,
      context: %{
        current_file: file,
        partial_code: prefix
      }
    }
    
    case Manager.execute(:generation, input, 30_000) do
      {:ok, %{code: completion_text}} ->
        # Parse the completion text into suggestions
        suggestions = parse_completion_suggestions(completion_text, max_suggestions)
        {:ok, suggestions}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp detect_language(file_path) do
    case Path.extname(file_path) do
      ".ex" -> :elixir
      ".exs" -> :elixir
      ".py" -> :python
      ".js" -> :javascript
      ".ts" -> :typescript
      _ -> :unknown
    end
  end
  
  defp parse_completion_suggestions(text, max_suggestions) do
    # Simple parsing - split by newlines and take first N non-empty lines
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(max_suggestions)
    |> Enum.map(fn suggestion ->
      %{
        text: suggestion,
        type: :completion,
        detail: "Generated completion",
        score: 1.0
      }
    end)
  end

  defp format_suggestion(%{text: text} = completion) do
    %{
      text: text,
      score: completion[:score],
      type: completion[:type] || :unknown
    }
  end
end
