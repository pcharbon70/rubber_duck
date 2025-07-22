defmodule RubberDuck.Projects.SymlinkSecurity do
  @moduledoc """
  Security module for detecting and preventing symbolic link attacks.
  
  Provides comprehensive symlink validation to prevent escaping project
  sandboxes through symbolic links.
  """

  require Logger

  @doc """
  Checks if a path contains or resolves through symbolic links.
  
  Returns {:ok, :safe} if no symlinks detected, {:error, reason} otherwise.
  """
  @spec check_symlinks(String.t(), String.t()) :: {:ok, :safe} | {:error, atom()}
  def check_symlinks(path, project_root) do
    with :ok <- validate_inputs(path, project_root),
         {:ok, normalized_path} <- normalize_within_root(path, project_root),
         :ok <- check_path_components(normalized_path, project_root),
         :ok <- verify_final_destination(normalized_path, project_root) do
      {:ok, :safe}
    end
  end

  @doc """
  Resolves all symbolic links in a path and verifies the final destination
  is within the project root.
  """
  @spec resolve_symlinks(String.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def resolve_symlinks(path, project_root) do
    with :ok <- validate_inputs(path, project_root),
         {:ok, normalized_path} <- normalize_within_root(path, project_root),
         {:ok, resolved} <- resolve_all_symlinks(normalized_path),
         :ok <- verify_resolved_within_root(resolved, project_root) do
      {:ok, resolved}
    end
  end

  @doc """
  Checks if symlinks are allowed based on project configuration.
  """
  @spec symlinks_allowed?(map()) :: boolean()
  def symlinks_allowed?(%{"allow_symlinks" => true}), do: true
  def symlinks_allowed?(_), do: false

  @doc """
  Validates a symlink target to ensure it doesn't escape the project sandbox.
  """
  @spec validate_symlink_target(String.t(), String.t(), String.t()) :: :ok | {:error, atom()}
  def validate_symlink_target(link_path, target_path, project_root) do
    with {:ok, link_dir} <- get_link_directory(link_path),
         {:ok, resolved_target} <- resolve_target(target_path, link_dir),
         :ok <- verify_target_within_root(resolved_target, project_root) do
      :ok
    end
  end

  @doc """
  Scans a directory recursively for symbolic links.
  Returns a list of all symlinks found.
  """
  @spec scan_for_symlinks(String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def scan_for_symlinks(directory) do
    case File.ls(directory) do
      {:ok, entries} ->
        symlinks = scan_directory_recursive(directory, entries, [])
        {:ok, symlinks}
      
      error ->
        error
    end
  end

  # Private functions

  defp validate_inputs(path, project_root) do
    cond do
      not is_binary(path) -> {:error, :invalid_path}
      not is_binary(project_root) -> {:error, :invalid_project_root}
      String.trim(path) == "" -> {:error, :empty_path}
      String.trim(project_root) == "" -> {:error, :empty_project_root}
      true -> :ok
    end
  end

  defp normalize_within_root(path, project_root) do
    normalized_root = Path.expand(project_root)
    
    normalized_path = 
      if Path.absname(path) == path do
        path
      else
        Path.join(normalized_root, path)
      end
      |> Path.expand()
    
    {:ok, normalized_path}
  end

  defp check_path_components(path, project_root) do
    # Check each component of the path for symlinks
    components = Path.split(path)
    root_components = Path.split(project_root)
    
    # Start checking from the first component after project root
    check_components_recursive(components, length(root_components), project_root)
  end

  defp check_components_recursive(components, start_index, project_root) do
    components
    |> Enum.take(start_index + 1)
    |> Path.join()
    |> check_remaining_components(components, start_index + 1, project_root)
  end

  defp check_remaining_components(_current_path, components, index, _project_root) 
       when index >= length(components) do
    :ok
  end

  defp check_remaining_components(current_path, components, index, project_root) do
    next_component = Enum.at(components, index)
    next_path = Path.join(current_path, next_component)
    
    case File.lstat(next_path) do
      {:ok, %File.Stat{type: :symlink}} ->
        # Found a symlink in the path
        case validate_symlink_in_path(next_path, project_root) do
          :ok -> check_remaining_components(next_path, components, index + 1, project_root)
          error -> error
        end
      
      {:ok, _} ->
        # Regular file or directory, continue checking
        check_remaining_components(next_path, components, index + 1, project_root)
      
      {:error, :enoent} ->
        # Path doesn't exist yet, that's okay for new files
        :ok
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_symlink_in_path(symlink_path, project_root) do
    case File.read_link(symlink_path) do
      {:ok, target} ->
        # Check if the symlink target escapes the project root
        resolved = resolve_symlink_target(symlink_path, target)
        verify_resolved_within_root(resolved, project_root)
      
      {:error, reason} ->
        Logger.error("Failed to read symlink #{symlink_path}: #{inspect(reason)}")
        {:error, :symlink_read_failed}
    end
  end

  defp resolve_symlink_target(symlink_path, target) do
    link_dir = Path.dirname(symlink_path)
    
    if Path.absname(target) == target do
      # Absolute target
      target
    else
      # Relative target - resolve relative to symlink location
      Path.join(link_dir, target) |> Path.expand()
    end
  end

  defp verify_final_destination(path, project_root) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :symlink}} ->
        # The final component is a symlink
        validate_symlink_in_path(path, project_root)
      
      {:ok, _} ->
        # Not a symlink, verify it's within root
        verify_resolved_within_root(path, project_root)
      
      {:error, :enoent} ->
        # File doesn't exist, check parent directory
        parent = Path.dirname(path)
        if parent == path do
          :ok
        else
          verify_final_destination(parent, project_root)
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_all_symlinks(path) do
    # Resolve symlinks up to a maximum depth to prevent infinite loops
    resolve_with_limit(path, 0, 10)
  end

  defp resolve_with_limit(_path, depth, max_depth) when depth > max_depth do
    {:error, :symlink_loop_detected}
  end

  defp resolve_with_limit(path, depth, max_depth) do
    case File.read_link(path) do
      {:ok, target} ->
        resolved = resolve_symlink_target(path, target)
        resolve_with_limit(resolved, depth + 1, max_depth)
      
      {:error, :einval} ->
        # Not a symlink, we're done
        {:ok, path}
      
      {:error, :enoent} ->
        # Path doesn't exist, check parent
        parent = Path.dirname(path)
        if parent == path do
          {:ok, path}
        else
          case resolve_with_limit(parent, depth, max_depth) do
            {:ok, resolved_parent} ->
              {:ok, Path.join(resolved_parent, Path.basename(path))}
            error ->
              error
          end
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_resolved_within_root(resolved_path, project_root) do
    normalized_root = Path.expand(project_root)
    normalized_resolved = Path.expand(resolved_path)
    
    if String.starts_with?(normalized_resolved, normalized_root <> "/") or
       normalized_resolved == normalized_root do
      :ok
    else
      Logger.warning("Symlink escape attempt: #{resolved_path} resolves outside #{project_root}")
      {:error, :symlink_escape_attempt}
    end
  end

  defp verify_target_within_root(target_path, project_root) do
    verify_resolved_within_root(target_path, project_root)
  end

  defp get_link_directory(link_path) do
    {:ok, Path.dirname(link_path)}
  end

  defp resolve_target(target_path, link_dir) do
    resolved = resolve_symlink_target(Path.join(link_dir, "dummy"), target_path)
    {:ok, resolved}
  end

  defp scan_directory_recursive(directory, entries, symlinks) do
    Enum.reduce(entries, symlinks, fn entry, acc ->
      full_path = Path.join(directory, entry)
      
      case File.lstat(full_path) do
        {:ok, %File.Stat{type: :symlink}} ->
          [full_path | acc]
        
        {:ok, %File.Stat{type: :directory}} ->
          # Recursively scan subdirectories
          case File.ls(full_path) do
            {:ok, subentries} ->
              scan_directory_recursive(full_path, subentries, acc)
            _ ->
              acc
          end
        
        _ ->
          acc
      end
    end)
  end
end