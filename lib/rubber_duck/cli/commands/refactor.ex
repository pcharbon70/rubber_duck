defmodule RubberDuck.CLI.Commands.Refactor do
  @moduledoc """
  CLI command for refactoring code with AI assistance.
  """

  @doc """
  Runs the refactor command with the given arguments and configuration.
  """
  def run(args, _config) do
    file = args[:file]
    instruction = args[:instruction]
    dry_run = args[:dry_run] || false

    # Validate inputs
    cond do
      !file || !File.exists?(file) ->
        {:error, "File not found: #{file}"}
      
      !instruction || String.trim(to_string(instruction)) == "" ->
        {:error, "Refactoring instruction is required"}
      
      true ->
        refactor_file(file, instruction, dry_run)
    end
  end
  
  defp refactor_file(file, instruction, dry_run) do

    with {:ok, original_content} <- File.read(file),
         {:ok, refactored_content} <- refactor_code(original_content, instruction, file) do
      handle_refactor_output(original_content, refactored_content, file, dry_run)
    else
      {:error, :enoent} ->
        {:error, "File not found: #{file}"}

      {:error, reason} ->
        {:error, "Refactoring failed: #{inspect(reason)}"}
    end
  end

  defp refactor_code(content, instruction, file_path) do
    alias RubberDuck.Engine.Manager
    
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

    # Use generation engine with refactoring context
    case Manager.execute(:generation, input, 300_000) do
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
      Enum.member?(extensions, "ex") -> :elixir
      Enum.member?(extensions, "exs") -> :elixir
      Enum.member?(extensions, "py") -> :python
      Enum.member?(extensions, "js") -> :javascript
      Enum.member?(extensions, "ts") -> :typescript
      true -> :unknown
    end
  end

  defp handle_refactor_output(_original, refactored, file, dry_run) do
    if dry_run do
      # Don't modify file, just return the refactored code
      {:ok,
       %{
         type: :refactor,
         original_file: file,
         refactored_code: refactored,
         dry_run: true,
         message: "Dry run - no files modified"
       }}
    else
      # Apply the refactoring
      case File.write(file, refactored) do
        :ok ->
          {:ok,
           %{
             type: :refactor,
             original_file: file,
             refactored_code: refactored,
             dry_run: false,
             message: "Refactoring applied to #{file}"
           }}

        {:error, reason} ->
          {:error, "Failed to write file: #{reason}"}
      end
    end
  end

end
