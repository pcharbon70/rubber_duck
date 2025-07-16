defmodule RubberDuck.Instructions.FileManager do
  @moduledoc """
  Hierarchical instruction file discovery and management system.
  
  Handles discovery, loading, and management of instruction files across
  multiple hierarchical levels with support for various file formats and
  priority-based loading.
  
  ## Supported File Formats
  
  - `.md` - Standard markdown instruction files
  - `.mdc` - Markdown with metadata files  
  - `AGENTS.md` - RubberDuck-specific instruction format
  - `.cursorrules` - Cursor IDE rules format
  
  ## Hierarchy Levels
  
  1. **Project Root** - Instructions specific to the current project
  2. **Workspace** - Instructions for the current workspace
  3. **Global** - System-wide default instructions
  4. **Directory-specific** - Instructions for specific directories
  
  ## File Discovery Algorithm
  
  Files are discovered using a hierarchical search pattern that respects
  priority ordering and handles conflicts through a deterministic resolution system.
  """

  require Logger
  alias RubberDuck.Instructions.{TemplateProcessor, Security}

  @type instruction_file :: %{
    path: String.t(),
    type: instruction_type(),
    priority: integer(),
    scope: scope_level(),
    metadata: map(),
    content: String.t(),
    size: integer(),
    modified_at: DateTime.t()
  }

  @type instruction_type :: :always | :auto | :agent | :manual
  @type scope_level :: :project | :workspace | :global | :directory
  @type discovery_opts :: [
    root_path: String.t(),
    include_global: boolean(),
    max_file_size: integer(),
    follow_symlinks: boolean()
  ]

  # Supported file patterns for instruction discovery
  @instruction_patterns [
    "AGENTS.md",
    "agents.md", 
    ".agents.md",
    "*.cursorrules",
    "instructions.md",
    "rules.md",
    "*.mdc",
    ".rules/*.md",
    "instructions/*.md"
  ]

  # Maximum file size (500 lines ≈ 25KB)
  @max_file_size 25_000
  
  # Directory traversal limits
  @max_depth 10
  @max_files_per_directory 50

  @doc """
  Discovers instruction files in the given directory and its hierarchy.
  
  Returns a list of instruction files ordered by priority and scope.
  
  ## Options
  
  - `:root_path` - Starting directory for discovery (defaults to current directory)
  - `:include_global` - Whether to include global instructions (defaults to true)
  - `:max_file_size` - Maximum file size in bytes (defaults to 25KB)
  - `:follow_symlinks` - Whether to follow symbolic links (defaults to false)
  
  ## Examples
  
      iex> FileManager.discover_files("/path/to/project")
      {:ok, [%{path: "/path/to/project/AGENTS.md", type: :auto, ...}, ...]}
      
      iex> FileManager.discover_files("/path", include_global: false)
      {:ok, [...]}
  """
  @spec discover_files(String.t(), discovery_opts()) :: {:ok, [instruction_file()]} | {:error, term()}
  def discover_files(path \\ ".", opts \\ []) do
    root_path = Keyword.get(opts, :root_path, path)
    include_global = Keyword.get(opts, :include_global, true)
    max_file_size = Keyword.get(opts, :max_file_size, @max_file_size)
    follow_symlinks = Keyword.get(opts, :follow_symlinks, false)

    try do
      with {:ok, project_files} <- discover_project_files(root_path, max_file_size, follow_symlinks),
           {:ok, workspace_files} <- discover_workspace_files(root_path, max_file_size),
           {:ok, global_files} <- maybe_discover_global_files(include_global, max_file_size) do
        
        all_files = project_files ++ workspace_files ++ global_files
        sorted_files = sort_by_priority(all_files)
        
        Logger.debug("Discovered #{length(sorted_files)} instruction files")
        {:ok, sorted_files}
      end
    rescue
      error -> {:error, {:discovery_failed, Exception.message(error)}}
    end
  end

  @doc """
  Loads and processes an instruction file with template processing.
  
  Returns the processed content along with extracted metadata.
  """
  @spec load_file(String.t(), map()) :: {:ok, instruction_file()} | {:error, term()}
  def load_file(file_path, variables \\ %{}) do
    with {:ok, content} <- read_file_safely(file_path),
         {:ok, metadata, template_content} <- TemplateProcessor.extract_metadata(content),
         {:ok, processed_content} <- TemplateProcessor.process_template(template_content, variables),
         {:ok, file_info} <- get_file_info(file_path) do
      
      instruction = %{
        path: file_path,
        type: determine_instruction_type(metadata, file_path),
        priority: determine_priority(metadata, file_path),
        scope: determine_scope(file_path),
        metadata: metadata,
        content: processed_content,
        size: file_info.size,
        modified_at: file_info.modified_at
      }
      
      {:ok, instruction}
    end
  end

  @doc """
  Validates an instruction file for format compliance and security.
  """
  @spec validate_file(String.t()) :: {:ok, map()} | {:error, term()}
  def validate_file(file_path) do
    with {:ok, content} <- read_file_safely(file_path),
         :ok <- validate_file_size(content),
         :ok <- Security.validate_template(content),
         {:ok, metadata, _} <- TemplateProcessor.extract_metadata(content),
         :ok <- validate_metadata(metadata) do
      
      {:ok, %{
        valid: true,
        size: String.length(content),
        metadata: metadata,
        warnings: []
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns file statistics for monitoring and optimization.
  """
  @spec get_file_stats(String.t()) :: {:ok, map()} | {:error, term()}
  def get_file_stats(root_path) do
    case discover_files(root_path) do
      {:ok, files} ->
        stats = %{
          total_files: length(files),
          total_size: Enum.sum(Enum.map(files, & &1.size)),
          by_type: group_by_type(files),
          by_scope: group_by_scope(files),
          largest_file: find_largest_file(files),
          oldest_file: find_oldest_file(files)
        }
        {:ok, stats}
        
      error -> error
    end
  end

  # Private functions

  defp discover_project_files(root_path, max_file_size, follow_symlinks) do
    patterns = @instruction_patterns
    files = []
    
    # Search in project root
    files = files ++ find_files_by_patterns(root_path, patterns, max_file_size, follow_symlinks)
    
    # Search in subdirectories up to max depth
    files = files ++ discover_in_subdirectories(root_path, patterns, max_file_size, follow_symlinks, 1)
    
    processed_files = 
      files
      |> Enum.map(&build_instruction_info(&1, :project))
      |> Enum.filter(&is_valid_instruction_file?/1)
    
    {:ok, processed_files}
  end

  defp discover_workspace_files(root_path, max_file_size) do
    # Look for workspace-level instruction files
    workspace_patterns = [
      ".vscode/*.md",
      ".idea/*.md", 
      "workspace.md",
      ".workspace/*.md"
    ]
    
    files = find_files_by_patterns(root_path, workspace_patterns, max_file_size, false)
    processed_files = 
      files
      |> Enum.map(&build_instruction_info(&1, :workspace))
      |> Enum.filter(&is_valid_instruction_file?/1)
    
    {:ok, processed_files}
  end

  defp maybe_discover_global_files(false, _), do: {:ok, []}
  defp maybe_discover_global_files(true, max_file_size) do
    global_paths = [
      Path.expand("~/.config/claude/instructions.md"),
      Path.expand("~/.agents.md"),
      Path.expand("~/.cursorrules"),
      "/etc/claude/instructions.md"
    ]
    
    files = 
      global_paths
      |> Enum.filter(&File.exists?/1)
      |> Enum.filter(&(get_file_size(&1) <= max_file_size))
      |> Enum.map(&build_instruction_info(&1, :global))
      |> Enum.filter(&is_valid_instruction_file?/1)
    
    {:ok, files}
  end

  defp discover_in_subdirectories(_root, _patterns, _max_size, _follow_symlinks, depth) when depth > @max_depth do
    []
  end
  
  defp discover_in_subdirectories(root_path, patterns, max_file_size, follow_symlinks, depth) do
    case File.ls(root_path) do
      {:ok, entries} ->
        entries
        |> Enum.take(@max_files_per_directory)
        |> Enum.flat_map(fn entry ->
          full_path = Path.join(root_path, entry)
          
          if File.dir?(full_path) and (follow_symlinks or File.lstat!(full_path).type != :symlink) do
            sub_files = find_files_by_patterns(full_path, patterns, max_file_size, follow_symlinks)
            deeper_files = discover_in_subdirectories(full_path, patterns, max_file_size, follow_symlinks, depth + 1)
            sub_files ++ deeper_files
          else
            []
          end
        end)
        
      {:error, _} -> []
    end
  end

  defp find_files_by_patterns(directory, patterns, max_file_size, follow_symlinks) do
    patterns
    |> Enum.flat_map(fn pattern ->
      full_pattern = Path.join(directory, pattern)
      
      case Path.wildcard(full_pattern) do
        [] -> []
        matches ->
          matches
          |> Enum.filter(&File.regular?/1)
          |> Enum.filter(&(get_file_size(&1) <= max_file_size))
          |> Enum.filter(fn path ->
            follow_symlinks or File.lstat!(path).type != :symlink
          end)
      end
    end)
    |> Enum.uniq()
  end

  defp build_instruction_info(file_path, scope) do
    case get_file_info(file_path) do
      {:ok, file_info} ->
        %{
          path: file_path,
          type: :auto,  # Will be determined when loading
          priority: calculate_base_priority(file_path, scope),
          scope: scope,
          metadata: %{},
          content: "",
          size: file_info.size,
          modified_at: file_info.modified_at
        }
        
      {:error, _} -> nil
    end
  end

  defp is_valid_instruction_file?(nil), do: false
  defp is_valid_instruction_file?(%{path: path}) do
    File.exists?(path) and File.regular?(path)
  end

  defp sort_by_priority(files) do
    files
    |> Enum.sort_by(fn file ->
      # Sort by priority (higher first), then by scope precedence, then by path
      {-file.priority, scope_order(file.scope), file.path}
    end)
  end

  defp scope_order(:project), do: 1
  defp scope_order(:workspace), do: 2
  defp scope_order(:directory), do: 3
  defp scope_order(:global), do: 4

  defp calculate_base_priority(file_path, scope) do
    base = case scope do
      :project -> 1000
      :workspace -> 800
      :directory -> 600
      :global -> 400
    end
    
    # Boost priority for well-known files
    filename = Path.basename(file_path)
    boost = case filename do
      "AGENTS.md" -> 100
      "agents.md" -> 100
      ".agents.md" -> 90
      "instructions.md" -> 80
      _ -> 
        if String.ends_with?(filename, ".cursorrules") do
          70
        else
          0
        end
    end
    
    base + boost
  end

  defp determine_instruction_type(metadata, _file_path) do
    case Map.get(metadata, "type", "auto") do
      type when type in ["always", "auto", "agent", "manual"] ->
        String.to_atom(type)
      _ -> 
        :auto
    end
  end

  defp determine_priority(metadata, file_path) do
    base_priority = calculate_base_priority(file_path, determine_scope(file_path))
    
    metadata_priority = case Map.get(metadata, "priority", "normal") do
      "critical" -> 200
      "high" -> 100
      "normal" -> 0
      "low" -> -100
      _ -> 0
    end
    
    base_priority + metadata_priority
  end

  defp determine_scope(file_path) do
    cond do
      String.contains?(file_path, ".vscode") or String.contains?(file_path, ".idea") ->
        :workspace
      String.starts_with?(Path.expand(file_path), Path.expand("~")) ->
        :global
      String.starts_with?(file_path, "/etc") ->
        :global
      true ->
        :project
    end
  end

  defp read_file_safely(file_path) do
    case File.read(file_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:file_read_error, reason}}
    end
  end

  defp get_file_info(file_path) do
    case File.stat(file_path) do
      {:ok, stat} ->
        {:ok, %{
          size: stat.size,
          modified_at: DateTime.from_naive!(stat.mtime, "Etc/UTC")
        }}
      {:error, reason} ->
        {:error, {:file_stat_error, reason}}
    end
  end

  defp get_file_size(file_path) do
    case File.stat(file_path) do
      {:ok, %{size: size}} -> size
      {:error, _} -> 0
    end
  end

  defp validate_file_size(content) do
    if String.length(content) > @max_file_size do
      {:error, :file_too_large}
    else
      :ok
    end
  end

  defp validate_metadata(metadata) when is_map(metadata) do
    # Validate required and optional metadata fields
    with :ok <- validate_instruction_type(Map.get(metadata, "type")),
         :ok <- validate_priority(Map.get(metadata, "priority")),
         :ok <- validate_tags(Map.get(metadata, "tags")) do
      :ok
    end
  end
  defp validate_metadata(_), do: {:error, :invalid_metadata}

  defp validate_instruction_type(nil), do: :ok
  defp validate_instruction_type(type) when type in ["always", "auto", "agent", "manual"], do: :ok
  defp validate_instruction_type(_), do: {:error, :invalid_instruction_type}

  defp validate_priority(nil), do: :ok
  defp validate_priority(priority) when priority in ["critical", "high", "normal", "low"], do: :ok
  defp validate_priority(_), do: {:error, :invalid_priority}

  defp validate_tags(nil), do: :ok
  defp validate_tags(tags) when is_list(tags) do
    if Enum.all?(tags, &is_binary/1) and length(tags) <= 20 do
      :ok
    else
      {:error, :invalid_tags}
    end
  end
  defp validate_tags(_), do: {:error, :invalid_tags}

  defp group_by_type(files) do
    files
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, files} -> {type, length(files)} end)
    |> Enum.into(%{})
  end

  defp group_by_scope(files) do
    files
    |> Enum.group_by(& &1.scope)
    |> Enum.map(fn {scope, files} -> {scope, length(files)} end)
    |> Enum.into(%{})
  end

  defp find_largest_file([]), do: nil
  defp find_largest_file(files) do
    Enum.max_by(files, & &1.size)
  end

  defp find_oldest_file([]), do: nil
  defp find_oldest_file(files) do
    Enum.min_by(files, & &1.modified_at)
  end
end