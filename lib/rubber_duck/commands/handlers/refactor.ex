defmodule RubberDuck.Commands.Handlers.Refactor do
  @moduledoc """
  Handler for code refactoring commands.
  
  Provides AI-assisted refactoring of code files based on natural language
  instructions using the generation engine.
  """

  @behaviour RubberDuck.Commands.Handler

  alias RubberDuck.Commands.{Command, Handler}
  alias RubberDuck.Engine.Manager

  @impl true
  def execute(%Command{name: :refactor, args: args, options: options} = command) do
    with :ok <- validate(command),
         {:ok, original_content} <- File.read(args.file),
         {:ok, refactored_content} <- refactor_code(original_content, args.instruction, args.file, options) do
      handle_refactor_output(original_content, refactored_content, args.file, options)
    end
  end

  def execute(_command) do
    {:error, "Invalid command for refactor handler"}
  end

  @impl true
  def validate(%Command{name: :refactor, args: args}) do
    with :ok <- Handler.validate_required_args(%{args: args}, [:file, :instruction]),
         :ok <- Handler.validate_file_exists(args.file),
         :ok <- validate_instruction(args.instruction) do
      :ok
    end
  end
  
  def validate(_), do: {:error, "Invalid command for refactor handler"}

  # Private functions

  defp validate_instruction(instruction) do
    if is_binary(instruction) and String.trim(instruction) != "" do
      :ok
    else
      {:error, "Refactoring instruction is required"}
    end
  end

  defp refactor_code(content, instruction, file_path, options) do
    # Detect language from file extension
    language = detect_language(file_path)
    
    # Build prompt for generation engine
    prompt = """
    Refactor the following #{language} code according to this instruction: #{instruction}

    Code:
    ```#{language}
    #{content}
    ```
    
    Please provide the refactored code without any explanations or markdown formatting.
    """
    
    input = %{
      prompt: prompt,
      language: language,
      context: %{
        current_file: file_path,
        partial_code: content
      }
    }

    timeout = Map.get(options, :timeout, 300_000)

    case Manager.execute(:generation, input, timeout) do
      {:ok, %{code: refactored_code}} ->
        {:ok, refactored_code}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp detect_language(file_path) do
    # Handle files with multiple extensions (e.g., test.ex.refactor)
    extensions = file_path |> Path.basename() |> String.split(".") |> Enum.drop(1)
    
    # Check if any extension matches a known language
    cond do
      Enum.member?(extensions, "ex") -> "elixir"
      Enum.member?(extensions, "exs") -> "elixir"
      Enum.member?(extensions, "py") -> "python"
      Enum.member?(extensions, "js") -> "javascript"
      Enum.member?(extensions, "ts") -> "typescript"
      true -> "unknown"
    end
  end

  defp handle_refactor_output(_original, refactored, file, options) do
    dry_run = Map.get(options, :dry_run, false)
    
    if dry_run do
      {:ok, %{
        type: "refactor",
        original_file: file,
        refactored_code: refactored,
        dry_run: true,
        message: "Dry run - no files modified",
        timestamp: DateTime.utc_now()
      }}
    else
      case File.write(file, refactored) do
        :ok ->
          {:ok, %{
            type: "refactor",
            original_file: file,
            refactored_code: refactored,
            dry_run: false,
            message: "Refactoring applied to #{file}",
            timestamp: DateTime.utc_now()
          }}

        {:error, reason} ->
          {:error, "Failed to write file: #{reason}"}
      end
    end
  end
end