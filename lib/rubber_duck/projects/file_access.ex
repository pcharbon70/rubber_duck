defmodule RubberDuck.Projects.FileAccess do
  @moduledoc """
  Secure file access management for project sandboxes.

  Provides path validation, normalization, and access control to ensure
  all file operations remain within project boundaries.
  """

  require Logger

  @doc """
  Validates that a path is safe and within the project's root directory.

  Returns {:ok, normalized_path} or {:error, reason}
  """
  @spec validate_path(String.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate_path(path, project_root) when is_binary(path) and is_binary(project_root) do
    with {:ok, safe_path} <- make_relative_path(path, project_root),
         :ok <- check_path_traversal(safe_path),
         {:ok, normalized} <- normalize_path(safe_path, project_root),
         :ok <- verify_within_root(normalized, project_root) do
      {:ok, normalized}
    end
  end

  def validate_path(_, _), do: {:error, :invalid_arguments}

  @doc """
  Checks if a file exists within the project sandbox.
  """
  @spec file_exists?(String.t(), String.t()) :: boolean()
  def file_exists?(path, project_root) do
    case validate_path(path, project_root) do
      {:ok, safe_path} -> File.exists?(safe_path)
      _ -> false
    end
  end

  @doc """
  Safely reads a file within the project sandbox.
  """
  @spec read_file(String.t(), String.t()) :: {:ok, binary()} | {:error, atom() | File.posix()}
  def read_file(path, project_root) do
    with {:ok, safe_path} <- validate_path(path, project_root) do
      File.read(safe_path)
    end
  end

  @doc """
  Lists files in a directory within the project sandbox.
  """
  @spec list_files(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def list_files(path, project_root) do
    with {:ok, safe_path} <- validate_path(path, project_root),
         {:ok, files} <- File.ls(safe_path) do
      {:ok, files}
    else
      {:error, :enoent} -> {:error, :directory_not_found}
      {:error, :enotdir} -> {:error, :not_a_directory}
      error -> error
    end
  end

  @doc """
  Checks if a path would exceed the maximum allowed file size.
  """
  @spec check_file_size(String.t(), String.t(), integer()) :: :ok | {:error, :file_too_large}
  def check_file_size(path, project_root, max_size) do
    with {:ok, safe_path} <- validate_path(path, project_root),
         {:ok, %File.Stat{size: size}} <- File.stat(safe_path) do
      if size <= max_size do
        :ok
      else
        {:error, :file_too_large}
      end
    else
      # File doesn't exist yet, size check passes
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  @doc """
  Validates file extension against allowed extensions list.
  Empty list means all extensions are allowed.
  """
  @spec check_extension(String.t(), [String.t()]) :: :ok | {:error, :invalid_extension}
  def check_extension(_path, []), do: :ok

  def check_extension(path, allowed_extensions) do
    ext = Path.extname(path)

    if ext in allowed_extensions do
      :ok
    else
      {:error, :invalid_extension}
    end
  end

  @doc """
  Gets file metadata safely within the project sandbox.
  """
  @spec get_file_info(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def get_file_info(path, project_root) do
    with {:ok, safe_path} <- validate_path(path, project_root),
         {:ok, stat} <- File.stat(safe_path),
         {:ok, lstat} <- File.lstat(safe_path) do
      {:ok,
       %{
         path: safe_path,
         size: stat.size,
         type: stat.type,
         modified: stat.mtime,
         is_symlink: lstat.type == :symlink,
         permissions: stat.mode
       }}
    end
  end

  # Private functions

  defp make_relative_path(path, project_root) do
    cond do
      # Already an absolute path within project
      String.starts_with?(path, project_root) ->
        relative = Path.relative_to(path, project_root)
        {:ok, relative}

      # Absolute path outside project
      Path.absname(path) == path ->
        {:error, :outside_project_root}

      # Relative path
      true ->
        {:ok, path}
    end
  end

  defp check_path_traversal(path) do
    dangerous_patterns = [
      # Parent directory traversal
      ~r/\.\./,
      # Absolute paths
      ~r/^\//,
      # Home directory expansion
      ~r/^~/,
      # Null bytes
      ~r/\0/,
      # Invalid path characters
      ~r/[<>:"|?*]/
    ]

    if Enum.any?(dangerous_patterns, &Regex.match?(&1, path)) do
      {:error, :path_traversal_attempt}
    else
      :ok
    end
  end

  defp normalize_path(relative_path, project_root) do
    # Use Path.safe_relative/1 if available (OTP 26+)
    # Otherwise fall back to manual normalization
    normalized =
      Path.join(project_root, relative_path)
      |> Path.expand()

    {:ok, normalized}
  end

  defp verify_within_root(normalized_path, project_root) do
    normalized_root = Path.expand(project_root)

    if String.starts_with?(normalized_path, normalized_root <> "/") or
         normalized_path == normalized_root do
      :ok
    else
      Logger.warning("Path escape attempt detected: #{normalized_path} not within #{normalized_root}")
      {:error, :outside_project_root}
    end
  end
end
