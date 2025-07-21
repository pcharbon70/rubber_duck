defmodule RubberDuck.Projects.FileTree do
  @moduledoc """
  Handles file tree operations for projects.
  
  Provides functionality to:
  - List files and directories
  - Watch for file system changes
  - Filter and search files
  - Track git status
  """
  
  require Logger
  alias Phoenix.PubSub
  
  @ignored_patterns [
    ~r/^\.git/,
    ~r/^\.elixir_ls/,
    ~r/^_build/,
    ~r/^deps/,
    ~r/^node_modules/,
    ~r/^\.DS_Store$/,
    ~r/^Thumbs\.db$/,
    ~r/\.beam$/,
    ~r/\.ez$/
  ]
  
  @doc """
  Lists all files and directories in the given project path.
  
  Returns a nested structure representing the file tree.
  """
  def list_tree(project_path, opts \\ []) do
    show_hidden = Keyword.get(opts, :show_hidden, false)
    max_depth = Keyword.get(opts, :max_depth, 10)
    
    case File.stat(project_path) do
      {:ok, %File.Stat{type: :directory}} ->
        {:ok, build_tree(project_path, project_path, 0, max_depth, show_hidden)}
        
      {:ok, %File.Stat{}} ->
        {:error, :not_a_directory}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Searches for files matching the given query.
  
  Returns a flat list of matching file paths.
  """
  def search_files(project_path, query, opts \\ []) do
    show_hidden = Keyword.get(opts, :show_hidden, false)
    extensions = Keyword.get(opts, :extensions, [])
    
    with {:ok, tree} <- list_tree(project_path, show_hidden: show_hidden) do
      results = 
        tree
        |> flatten_tree()
        |> Enum.filter(&matches_search?(&1, query, extensions))
        |> Enum.take(100) # Limit results
        
      {:ok, results}
    end
  end
  
  @doc """
  Gets git status for files in the project.
  
  Returns a map of file paths to their git status.
  """
  def get_git_status(project_path) do
    case System.cmd("git", ["status", "--porcelain"], cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        status_map = 
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_git_status_line/1)
          |> Enum.reject(&is_nil/1)
          |> Map.new()
          
        {:ok, status_map}
        
      {_output, _} ->
        # Not a git repository or git not available
        {:ok, %{}}
    end
  end
  
  @doc """
  Watches a directory for changes and broadcasts updates.
  """
  def watch_directory(project_id, project_path) do
    case FileSystem.start_link(dirs: [project_path], name: :"file_watcher_#{project_id}") do
      {:ok, pid} ->
        FileSystem.subscribe(pid)
        {:ok, pid}
        
      error ->
        Logger.error("Failed to start file watcher: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Handles file system events from the watcher.
  """
  def handle_fs_event(project_id, {path, events}) do
    # Determine the type of change
    change_type = 
      cond do
        :created in events -> :created
        :removed in events -> :deleted
        :modified in events -> :modified
        :renamed in events -> :renamed
        true -> :unknown
      end
    
    # Broadcast the file system change
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:files",
      {:file_changed, %{
        path: path,
        change_type: change_type,
        timestamp: DateTime.utc_now()
      }}
    )
  end
  
  # Private Functions
  
  defp build_tree(root_path, current_path, depth, max_depth, show_hidden) do
    relative_path = Path.relative_to(current_path, root_path)
    name = Path.basename(current_path)
    
    # Don't traverse too deep
    if depth >= max_depth do
      %{
        path: relative_path,
        name: name,
        type: :directory,
        children: nil # Indicate that children weren't loaded
      }
    else
      case File.ls(current_path) do
        {:ok, entries} ->
          children = 
            entries
            |> Enum.filter(&should_include?(&1, show_hidden))
            |> Enum.map(fn entry ->
              full_path = Path.join(current_path, entry)
              
              case File.stat(full_path) do
                {:ok, %File.Stat{type: :directory}} ->
                  build_tree(root_path, full_path, depth + 1, max_depth, show_hidden)
                  
                {:ok, stat} ->
                  %{
                    path: Path.relative_to(full_path, root_path),
                    name: entry,
                    type: :file,
                    size: stat.size,
                    modified: stat.mtime |> elem(0) |> DateTime.from_unix!()
                  }
                  
                {:error, _} ->
                  nil
              end
            end)
            |> Enum.reject(&is_nil/1)
            |> Enum.sort_by(fn node ->
              # Sort directories first, then by name
              {node.type != :directory, String.downcase(node.name)}
            end)
          
          %{
            path: relative_path,
            name: name,
            type: :directory,
            children: children
          }
          
        {:error, _reason} ->
          # Can't read directory
          %{
            path: relative_path,
            name: name,
            type: :directory,
            children: []
          }
      end
    end
  end
  
  defp should_include?(name, show_hidden) do
    # Check if hidden file
    if !show_hidden && String.starts_with?(name, ".") do
      false
    else
      # Check against ignored patterns
      !Enum.any?(@ignored_patterns, &Regex.match?(&1, name))
    end
  end
  
  defp flatten_tree(node, acc \\ []) do
    acc = [node | acc]
    
    if node.type == :directory && node[:children] do
      Enum.reduce(node.children, acc, &flatten_tree/2)
    else
      acc
    end
  end
  
  defp matches_search?(node, query, extensions) do
    # Skip directories in search results
    if node.type == :directory do
      false
    else
      name_match = String.contains?(String.downcase(node.name), String.downcase(query))
      
      extension_match = 
        if extensions == [] do
          true
        else
          extension = Path.extname(node.name)
          Enum.member?(extensions, extension)
        end
      
      name_match && extension_match
    end
  end
  
  defp parse_git_status_line(line) do
    case String.split(line, " ", parts: 2, trim: true) do
      [status_code, file_path] ->
        status = 
          case status_code do
            "M" -> :modified
            "MM" -> :modified
            "A" -> :added
            "AM" -> :added
            "D" -> :deleted
            "R" -> :renamed
            "RM" -> :renamed
            "??" -> :untracked
            _ -> :unknown
          end
          
        {file_path, status}
        
      _ ->
        nil
    end
  end
end