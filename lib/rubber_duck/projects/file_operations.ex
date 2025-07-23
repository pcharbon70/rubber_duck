defmodule RubberDuck.Projects.FileOperations do
  @moduledoc """
  Handles file operations for projects within sandboxed environments.
  
  All operations are performed with safety checks to ensure:
  - Operations stay within the project's root_path
  - File size limits are respected
  - Only allowed file extensions are permitted
  - Proper error handling and logging
  """
  
  require Logger
  alias Phoenix.PubSub
  
  @doc """
  Creates a new file or directory within the project.
  """
  def create(project, parent_path, name, type) when type in [:file, :directory] do
    with :ok <- validate_project_access(project),
         {:ok, full_path} <- build_safe_path(project.root_path, parent_path, name),
         :ok <- validate_path_within_project(full_path, project.root_path),
         :ok <- validate_file_extension(name, project.allowed_extensions, type) do
      
      result = case type do
        :file -> create_file(full_path)
        :directory -> create_directory(full_path)
      end
      
      case result do
        :ok ->
          broadcast_file_change(project.id, %{
            type: :created,
            path: Path.relative_to(full_path, project.root_path)
          })
          {:ok, %{path: Path.relative_to(full_path, project.root_path), type: type}}
          
        error -> error
      end
    end
  end
  
  @doc """
  Renames a file or directory within the project.
  """
  def rename(project, old_path, new_name) do
    with :ok <- validate_project_access(project),
         {:ok, old_full_path} <- build_safe_path(project.root_path, old_path),
         :ok <- validate_path_within_project(old_full_path, project.root_path),
         {:ok, new_full_path} <- build_safe_path(project.root_path, Path.dirname(old_path), new_name),
         :ok <- validate_path_within_project(new_full_path, project.root_path),
         :ok <- validate_file_extension(new_name, project.allowed_extensions, get_file_type(old_full_path)) do
      
      case File.rename(old_full_path, new_full_path) do
        :ok ->
          broadcast_file_change(project.id, %{
            type: :renamed,
            path: Path.relative_to(old_full_path, project.root_path),
            new_path: Path.relative_to(new_full_path, project.root_path)
          })
          {:ok, %{
            old_path: Path.relative_to(old_full_path, project.root_path),
            new_path: Path.relative_to(new_full_path, project.root_path)
          }}
          
        {:error, reason} ->
          {:error, "Failed to rename: #{inspect(reason)}"}
      end
    end
  end
  
  @doc """
  Deletes a file or directory within the project.
  """
  def delete(project, path) do
    with :ok <- validate_project_access(project),
         {:ok, full_path} <- build_safe_path(project.root_path, path),
         :ok <- validate_path_within_project(full_path, project.root_path) do
      
      result = if File.dir?(full_path) do
        delete_directory(full_path)
      else
        File.rm(full_path)
      end
      
      case result do
        :ok ->
          broadcast_file_change(project.id, %{
            type: :deleted,
            path: Path.relative_to(full_path, project.root_path)
          })
          {:ok, %{path: Path.relative_to(full_path, project.root_path)}}
          
        {:error, reason} ->
          {:error, "Failed to delete: #{inspect(reason)}"}
      end
    end
  end
  
  @doc """
  Reads file content with size validation.
  """
  def read_file(project, path) do
    with :ok <- validate_project_access(project),
         {:ok, full_path} <- build_safe_path(project.root_path, path),
         :ok <- validate_path_within_project(full_path, project.root_path),
         {:ok, stat} <- File.stat(full_path),
         :ok <- validate_file_size(stat.size, project.max_file_size) do
      File.read(full_path)
    end
  end
  
  @doc """
  Writes content to a file with size validation.
  """
  def write_file(project, path, content) do
    with :ok <- validate_project_access(project),
         {:ok, full_path} <- build_safe_path(project.root_path, path),
         :ok <- validate_path_within_project(full_path, project.root_path),
         :ok <- validate_file_extension(path, project.allowed_extensions, :file),
         :ok <- validate_content_size(content, project.max_file_size) do
      
      # Ensure parent directory exists
      :ok = File.mkdir_p(Path.dirname(full_path))
      
      case File.write(full_path, content) do
        :ok ->
          broadcast_file_change(project.id, %{
            type: :modified,
            path: Path.relative_to(full_path, project.root_path)
          })
          :ok
          
        error -> error
      end
    end
  end
  
  defp build_safe_path(root, path) do
    build_safe_path(root, path, "")
  end
  
  # Private functions
  
  defp validate_project_access(project) do
    if project.file_access_enabled do
      :ok
    else
      {:error, "File access is not enabled for this project"}
    end
  end
  
  defp build_safe_path(root, parent, name) do
    # Remove any leading slashes from parent and name
    parent = String.trim_leading(parent, "/")
    name = String.trim(name)
    
    # Build the full path
    parts = [root | Path.split(parent)]
    parts = if name != "", do: parts ++ [name], else: parts
    
    full_path = Path.join(parts) |> Path.expand()
    {:ok, full_path}
  end
  
  defp validate_path_within_project(path, root_path) do
    expanded_root = Path.expand(root_path)
    expanded_path = Path.expand(path)
    
    if String.starts_with?(expanded_path, expanded_root) do
      :ok
    else
      {:error, "Path is outside project root"}
    end
  end
  
  defp validate_file_extension(_name, [], _type), do: :ok
  defp validate_file_extension(_name, _allowed, :directory), do: :ok
  
  defp validate_file_extension(name, allowed_extensions, :file) do
    extension = Path.extname(name)
    
    if extension in allowed_extensions do
      :ok
    else
      {:error, "File extension #{extension} is not allowed"}
    end
  end
  
  defp validate_file_size(size, max_size) do
    if size <= max_size do
      :ok
    else
      {:error, "File size exceeds limit of #{max_size} bytes"}
    end
  end
  
  defp validate_content_size(content, max_size) do
    size = byte_size(content)
    validate_file_size(size, max_size)
  end
  
  defp create_file(path) do
    # Ensure parent directory exists
    :ok = File.mkdir_p(Path.dirname(path))
    File.touch(path)
  end
  
  defp create_directory(path) do
    File.mkdir_p(path)
  end
  
  defp delete_directory(path) do
    case File.rm_rf(path) do
      {:ok, _} -> :ok
      error -> error
    end
  end
  
  defp get_file_type(path) do
    if File.dir?(path), do: :directory, else: :file
  end
  
  defp broadcast_file_change(project_id, change) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "file_watcher:#{project_id}",
      %{
        event: :file_changed,
        changes: [change]
      }
    )
  end
end