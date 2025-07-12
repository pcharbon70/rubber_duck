defmodule RubberDuck.Commands.Handler do
  @moduledoc """
  Behavior for command handlers.
  
  All command handlers must implement this behavior to ensure consistent
  execution interface across the unified command system.
  """

  alias RubberDuck.Commands.Command

  @doc """
  Executes a command and returns a result.
  
  ## Parameters
  - `command` - The Command struct containing all necessary information
  
  ## Returns
  - `{:ok, result}` - On successful execution
  - `{:error, reason}` - On failure
  """
  @callback execute(command :: Command.t()) :: {:ok, any()} | {:error, any()}

  @doc """
  Optional callback for validating command arguments before execution.
  
  ## Parameters
  - `command` - The Command struct to validate
  
  ## Returns
  - `:ok` - If validation passes
  - `{:error, reason}` - If validation fails
  """
  @callback validate(command :: Command.t()) :: :ok | {:error, any()}

  @optional_callbacks validate: 1

  @doc """
  Helper function to validate required arguments are present.
  """
  def validate_required_args(command, required_keys) do
    missing = Enum.filter(required_keys, fn key ->
      is_nil(Map.get(command.args, key)) or Map.get(command.args, key) == ""
    end)

    case missing do
      [] -> :ok
      _ -> {:error, "Missing required arguments: #{Enum.join(missing, ", ")}"}
    end
  end

  @doc """
  Helper function to validate file paths exist.
  """
  def validate_file_exists(path) when is_binary(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, "File not found: #{path}"}
    end
  end
  def validate_file_exists(_), do: {:error, "Invalid file path"}

  @doc """
  Helper function to check if a path is within allowed directories.
  """
  def validate_path_safety(path) when is_binary(path) do
    # Allow absolute paths that exist and don't contain traversal patterns
    cond do
      # Check for obvious path traversal attempts
      String.contains?(path, "..") ->
        {:error, "Path traversal detected: #{path}"}
      
      # If it's an absolute path, verify it exists
      Path.type(path) == :absolute ->
        if File.exists?(path) do
          :ok
        else
          {:error, "Path not found: #{path}"}
        end
      
      # For relative paths, use safe_relative check
      true ->
        case Path.safe_relative(path) do
          {:ok, _} -> :ok
          :error -> {:error, "Unsafe path: #{path}"}
        end
    end
  end
  def validate_path_safety(_), do: {:error, "Invalid path"}
end