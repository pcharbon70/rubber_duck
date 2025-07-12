defmodule RubberDuck.Commands.Handlers.Complete do
  @moduledoc """
  Handler for code completion commands.
  
  Provides intelligent code completions at specified cursor positions
  using the generation engine and language-specific context.
  """

  @behaviour RubberDuck.Commands.Handler

  alias RubberDuck.Commands.{Command, Handler}
  alias RubberDuck.Engine.Manager

  @impl true
  def execute(%Command{name: :complete, args: args, options: options} = command) do
    with :ok <- validate(command),
         {:ok, content} <- File.read(args.file),
         :ok <- validate_position(content, args.line, args.column),
         {:ok, completions} <- get_completions(content, args.file, args.line, args.column, options) do
      {:ok, %{
        completions: completions,
        file: args.file,
        line: args.line,
        column: args.column,
        timestamp: DateTime.utc_now()
      }}
    end
  end

  def execute(_command) do
    {:error, "Invalid command for complete handler"}
  end

  @impl true
  def validate(%Command{name: :complete, args: args}) do
    with :ok <- Handler.validate_required_args(%{args: args}, [:file, :line, :column]),
         :ok <- Handler.validate_file_exists(args.file),
         :ok <- validate_line_column(args.line, args.column) do
      :ok
    end
  end
  
  def validate(_), do: {:error, "Invalid command for complete handler"}

  # Private functions

  defp validate_line_column(line, column) do
    cond do
      !is_integer(line) or line <= 0 ->
        {:error, "Valid line number is required"}
        
      !is_integer(column) or column < 0 ->
        {:error, "Valid column number is required"}
        
      true ->
        :ok
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

  defp get_completions(content, file, line, column, options) do
    max_suggestions = Map.get(options, :max_suggestions, 5)
    
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
        suggestions = parse_completion_suggestions(completion_text, max_suggestions)
        {:ok, suggestions}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp detect_language(file_path) do
    case Path.extname(file_path) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".py" -> "python"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      _ -> "unknown"
    end
  end
  
  defp parse_completion_suggestions(text, max_suggestions) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(max_suggestions)
    |> Enum.with_index()
    |> Enum.map(fn {suggestion, index} ->
      %{
        text: suggestion,
        type: "completion",
        detail: "Generated completion",
        score: 1.0 - (index * 0.1),
        rank: index + 1
      }
    end)
  end
end