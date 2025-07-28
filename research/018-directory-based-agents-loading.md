# Directory-Based Agent Loading System with Sandbox Integration

Based on the existing RubberDuck instruction system, this directory-based loading system loads instructions based on file location while fully integrating with the project sandboxing system for secure file access.

## Overview

The directory-based instruction system will:
- Allow placing instruction files (`.agents.md`, `AGENTS.md`, etc.) in any project subdirectory
- Automatically load relevant instructions when working with files in those directories
- Apply instructions hierarchically from the file's directory up to the project root
- Integrate with the existing keyword filtering system
- Provide caching for performance
- **Fully respect project sandboxing and security boundaries**
- **Use FileManager for all file operations**
- **Validate all paths and check symlink safety**

## 1. Extended Metadata Structure

Add directory scope configuration to the YAML frontmatter:

```yaml
---
# Existing metadata fields...
priority: high
type: auto
tags: [elixir, phoenix]

# Directory-based configuration
directory_config:
  scope: "subtree"          # Options: "current", "subtree", "children"
  recursive: true           # Apply to subdirectories
  exclude_patterns:         # Directories to exclude
    - "node_modules"
    - "_build"
    - ".git"
  include_patterns:         # Specific patterns to include
    - "lib/**"
    - "test/**"
  
# Can be combined with keyword filtering
keyword_filter:
  keywords: ["genserver", "otp"]
  match_type: "any"
---
```

## 2. Implementation

### 2.1 Create DirectoryInstructionLoader Module

Create `lib/rubber_duck/instructions/directory_loader.ex`:

```elixir
defmodule RubberDuck.Instructions.DirectoryLoader do
  @moduledoc """
  Loads instructions based on the current file's directory location with full sandbox integration.
  Discovers and loads instruction files from the file's directory and parent directories
  while respecting project security boundaries.
  """
  
  alias RubberDuck.Projects.{FileAccess, FileManager, SymlinkSecurity}
  alias RubberDuck.Instructions.{Cache, KeywordMatcher}
  alias RubberDuck.Instructions.TemplateProcessor
  require Logger
  
  @instruction_filenames [".agents.md", "AGENTS.md", ".rules.md", "INSTRUCTIONS.md"]
  @cache_namespace :directory_instructions
  
  @doc """
  Loads instructions relevant to a specific file path within the project.
  
  Options:
    - :project - The Project resource (required for sandboxing)
    - :user - The User resource (required for authorization)
    - :context_text - Text for keyword filtering
    - :cache_enabled - Whether to use caching (default: true)
    - :include_parent_dirs - Load from parent directories (default: true)
  """
  @spec load_for_file(String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def load_for_file(file_path, opts \\ []) do
    project = Keyword.fetch!(opts, :project)
    user = Keyword.fetch!(opts, :user)
    
    with :ok <- validate_project_access(project, user),
         {:ok, normalized_path} <- FileAccess.validate_and_normalize(file_path, project.root_path),
         :ok <- check_file_access_enabled(project),
         {:ok, directories} <- get_relevant_directories(normalized_path, project, opts),
         {:ok, instruction_files} <- discover_instruction_files(directories, project, user, opts),
         {:ok, loaded_instructions} <- load_and_filter_instructions(instruction_files, project, user, opts) do
      {:ok, loaded_instructions}
    end
  end
  
  @doc """
  Discovers instruction files in a directory and its parents up to the project root.
  Uses sandboxed file operations.
  """
  def discover_directory_instructions(directory_path, project, user, opts \\ []) do
    cache_enabled = Keyword.get(opts, :cache_enabled, true)
    cache_key = generate_cache_key(directory_path, project.id, user.id)
    
    if cache_enabled do
      case Cache.get(@cache_namespace, cache_key) do
        {:ok, cached} -> {:ok, cached}
        :miss -> discover_and_cache(directory_path, project, user, cache_key, opts)
      end
    else
      discover_instructions_uncached(directory_path, project, user, opts)
    end
  end
  
  # Private functions
  
  defp validate_project_access(project, user) do
    # Check if user has access to the project
    # This would integrate with your authorization system
    if authorized?(user, project, :read) do
      :ok
    else
      {:error, :unauthorized}
    end
  end
  
  defp check_file_access_enabled(project) do
    if project.file_access_enabled do
      :ok
    else
      {:error, :file_access_disabled}
    end
  end
  
  defp get_relevant_directories(file_path, project, opts) do
    include_parents = Keyword.get(opts, :include_parent_dirs, true)
    
    dir_path = if File.dir?(file_path), do: file_path, else: Path.dirname(file_path)
    
    case get_directory_chain(dir_path, project.root_path, include_parents) do
      {:ok, directories} ->
        # Validate each directory is within sandbox
        validated_dirs = 
          directories
          |> Enum.filter(fn dir ->
            case FileAccess.validate_and_normalize(dir, project.root_path) do
              {:ok, _} -> true
              _ -> false
            end
          end)
        
        {:ok, validated_dirs}
        
      error -> error
    end
  end
  
  defp get_directory_chain(dir_path, project_root, true) do
    directories = 
      dir_path
      |> Path.split()
      |> build_directory_chain(project_root)
      |> Enum.filter(&String.starts_with?(&1, project_root))
    
    {:ok, directories}
  end
  
  defp get_directory_chain(dir_path, _project_root, false) do
    {:ok, [dir_path]}
  end
  
  defp build_directory_chain(path_parts, project_root) do
    project_parts = Path.split(project_root)
    
    path_parts
    |> Enum.scan([], &(&2 ++ [&1]))
    |> Enum.map(&Path.join/1)
    |> Enum.filter(fn path -> 
      path_parts_count = length(Path.split(path))
      project_parts_count = length(project_parts)
      path_parts_count >= project_parts_count
    end)
    |> Enum.reverse()
  end
  
  defp discover_instruction_files(directories, project, user, _opts) do
    file_manager = %FileManager{project: project, user: user}
    
    instruction_files = 
      directories
      |> Enum.flat_map(&discover_in_directory(&1, file_manager))
      |> Enum.uniq()
    
    {:ok, instruction_files}
  end
  
  defp discover_in_directory(directory, file_manager) do
    case FileManager.list_directory(file_manager, directory) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&instruction_file?/1)
        |> Enum.map(fn entry -> 
          path = Path.join(directory, entry)
          
          # Check symlink safety
          case SymlinkSecurity.check_symlink_safety(path, file_manager.project.root_path) do
            :ok ->
              %{
                path: path,
                directory: directory,
                priority: calculate_directory_priority(directory)
              }
              
            {:error, _reason} ->
              Logger.warning("Skipping unsafe symlink: #{path}")
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        
      {:error, reason} ->
        Logger.warning("Failed to list directory #{directory}: #{inspect(reason)}")
        []
    end
  end
  
  defp instruction_file?(filename) do
    filename in @instruction_filenames or
    String.ends_with?(filename, ".cursorrules")
  end
  
  defp calculate_directory_priority(directory) do
    # Deeper directories get higher priority
    depth = length(Path.split(directory))
    1000 + (depth * 10)
  end
  
  defp load_and_filter_instructions(instruction_files, project, user, opts) do
    context_text = Keyword.get(opts, :context_text)
    file_manager = %FileManager{project: project, user: user}
    
    loaded = 
      instruction_files
      |> Enum.map(&load_instruction_file(&1, file_manager, context_text))
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, instruction} -> instruction end)
      |> apply_directory_scope_filtering()
      |> Enum.sort_by(& &1.priority, :desc)
    
    {:ok, loaded}
  end
  
  defp load_instruction_file(file_info, file_manager, context_text) do
    # Check file size limit from sandbox config
    max_size = file_manager.project.max_file_size || 1_000_000  # 1MB default
    
    with {:ok, stats} <- FileManager.file_stats(file_manager, file_info.path),
         :ok <- validate_file_size(stats.size, max_size),
         {:ok, content} <- FileManager.read_file(file_manager, file_info.path),
         {:ok, parsed} <- parse_instruction_content(content, file_info) do
      
      # Apply keyword filtering if context is provided
      if should_include_file?(parsed, context_text) do
        instruction = Map.merge(parsed, %{
          directory: file_info.directory,
          directory_priority: file_info.priority,
          path: file_info.path
        })
        {:ok, instruction}
      else
        {:skip, :filtered_out}
      end
    else
      {:error, reason} ->
        Logger.warning("Failed to load instruction file #{file_info.path}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp validate_file_size(size, max_size) when size <= max_size, do: :ok
  defp validate_file_size(size, max_size) do
    {:error, {:file_too_large, size, max_size}}
  end
  
  defp parse_instruction_content(content, file_info) do
    case TemplateProcessor.extract_metadata(content) do
      {:ok, metadata, body} ->
        {:ok, %{
          content: body,
          metadata: validate_metadata(metadata),
          type: determine_type(metadata),
          priority: determine_priority(metadata, file_info.priority)
        }}
        
      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end
  
  defp validate_metadata(metadata) do
    # Reuse existing metadata validation logic
    metadata
    |> Map.put_new("priority", "normal")
    |> Map.put_new("type", "auto")
    |> Map.update("keyword_filter", nil, &KeywordMatcher.validate_keyword_filter/1)
  end
  
  defp determine_type(metadata) do
    case metadata["type"] do
      type when type in ["always", "auto", "agent", "manual"] -> String.to_atom(type)
      _ -> :auto
    end
  end
  
  defp determine_priority(metadata, base_priority) do
    priority_boost = case metadata["priority"] do
      "critical" -> 200
      "high" -> 100
      "normal" -> 0
      "low" -> -100
      _ -> 0
    end
    
    base_priority + priority_boost
  end
  
  defp should_include_file?(file_data, nil), do: true
  defp should_include_file?(file_data, context_text) do
    KeywordMatcher.matches?(file_data.metadata, context_text)
  end
  
  defp apply_directory_scope_filtering(instructions) do
    # Apply directory scope rules
    instructions
    |> Enum.filter(fn instruction ->
      directory_config = instruction.metadata["directory_config"]
      
      case directory_config do
        nil -> true  # No config means always include
        config -> evaluate_directory_scope(instruction, config)
      end
    end)
  end
  
  defp evaluate_directory_scope(instruction, config) do
    # This is simplified - in practice, you'd check against the current working file
    # For now, we'll include all instructions and let the consumer filter
    true
  end
  
  defp discover_and_cache(directory_path, project, user, cache_key, opts) do
    case discover_instructions_uncached(directory_path, project, user, opts) do
      {:ok, instructions} = result ->
        Cache.put(@cache_namespace, cache_key, instructions)
        result
        
      error ->
        error
    end
  end
  
  defp discover_instructions_uncached(directory_path, project, user, opts) do
    with {:ok, directories} <- get_relevant_directories(directory_path, project, opts),
         {:ok, files} <- discover_instruction_files(directories, project, user, opts) do
      {:ok, files}
    end
  end
  
  defp generate_cache_key(directory_path, project_id, user_id) do
    key_string = "#{project_id}:#{user_id}:#{directory_path}"
    :crypto.hash(:sha256, key_string) |> Base.encode16()
  end
  
  # Helper function - would be part of your authorization system
  defp authorized?(_user, _project, _action) do
    # Placeholder - integrate with your actual authorization system
    true
  end
end
```

### 2.2 Create Directory Scope Evaluator

Create `lib/rubber_duck/instructions/directory_scope.ex`:

```elixir
defmodule RubberDuck.Instructions.DirectoryScope do
  @moduledoc """
  Evaluates directory scope rules for instruction files.
  """
  
  @doc """
  Checks if an instruction should be applied based on its directory configuration
  and the current working file path.
  """
  @spec applies_to_file?(map(), String.t(), String.t()) :: boolean()
  def applies_to_file?(instruction, file_path, instruction_dir) do
    directory_config = instruction.metadata["directory_config"]
    
    case directory_config do
      nil -> 
        # No config means it applies to files in the same directory and subdirectories
        String.starts_with?(file_path, instruction_dir)
        
      %{"scope" => scope} = config ->
        evaluate_scope(scope, file_path, instruction_dir, config)
        
      _ ->
        true
    end
  end
  
  defp evaluate_scope("current", file_path, instruction_dir, _config) do
    # Only applies to files in the exact same directory
    Path.dirname(file_path) == instruction_dir
  end
  
  defp evaluate_scope("subtree", file_path, instruction_dir, config) do
    # Applies to files in this directory and all subdirectories
    base_applies = String.starts_with?(file_path, instruction_dir)
    
    if base_applies and config["exclude_patterns"] do
      not excluded_by_patterns?(file_path, instruction_dir, config["exclude_patterns"])
    else
      base_applies
    end
  end
  
  defp evaluate_scope("children", file_path, instruction_dir, config) do
    # Only applies to immediate child directories
    file_dir = Path.dirname(file_path)
    parent_dir = Path.dirname(file_dir)
    
    parent_dir == instruction_dir
  end
  
  defp evaluate_scope(_, _file_path, _instruction_dir, _config) do
    # Unknown scope - default to true
    true
  end
  
  defp excluded_by_patterns?(file_path, base_dir, patterns) do
    relative_path = Path.relative_to(file_path, base_dir)
    
    Enum.any?(patterns, fn pattern ->
      PathGlob.match?(relative_path, pattern)
    end)
  end
end
```

### 2.3 Update HierarchicalLoader for Directory Support

Modify `lib/rubber_duck/instructions/hierarchical_loader.ex`:

```elixir
defmodule RubberDuck.Instructions.HierarchicalLoader do
  # Add to existing module
  
  alias RubberDuck.Instructions.{DirectoryLoader, DirectoryScope}
  
  @doc """
  Loads instructions with optional directory-based filtering.
  
  New Options:
    - :current_file - Path to the file being worked on
    - :project - The Project resource (required for directory loading)
    - :user - The User resource (required for authorization)
    - :enable_directory_loading - Enable directory-based loading (default: true)
    - All existing options...
  """
  def load_instructions(root_path \\ ".", opts \\ []) do
    current_file = Keyword.get(opts, :current_file)
    enable_directory = Keyword.get(opts, :enable_directory_loading, true)
    project = Keyword.get(opts, :project)
    user = Keyword.get(opts, :user)
    
    # Validate required resources for directory loading
    if enable_directory and current_file and (is_nil(project) or is_nil(user)) do
      Logger.warning("Directory loading requires :project and :user options")
    end
    
    with {:ok, discovered_files} <- discover_all_files(root_path, opts),
         {:ok, directory_files} <- maybe_load_directory_instructions(
           current_file, project, user, enable_directory, opts
         ),
         all_files = merge_instruction_files(discovered_files, directory_files),
         {:ok, parsed_files} <- parse_all_files(all_files),
         {:ok, filtered_files} <- apply_all_filtering(parsed_files, opts),
         {:ok, resolved_files, conflicts} <- resolve_conflicts(filtered_files),
         {:ok, loading_result} <- load_into_registry(resolved_files) do
      
      {:ok, format_loading_result(loading_result, conflicts)}
    end
  end
  
  defp maybe_load_directory_instructions(nil, _project, _user, _enabled, _opts), do: {:ok, []}
  defp maybe_load_directory_instructions(_file, nil, _user, true, _opts), do: {:ok, []}
  defp maybe_load_directory_instructions(_file, _project, nil, true, _opts), do: {:ok, []}
  defp maybe_load_directory_instructions(_file, _project, _user, false, _opts), do: {:ok, []}
  
  defp maybe_load_directory_instructions(file_path, project, user, true, opts) do
    loading_opts = [
      project: project,
      user: user,
      context_text: opts[:context_text]
    ]
    
    case DirectoryLoader.load_for_file(file_path, loading_opts) do
      {:ok, instructions} -> {:ok, instructions}
      {:error, reason} -> 
        Logger.warning("Failed to load directory instructions: #{inspect(reason)}")
        {:ok, []}  # Continue without directory instructions
    end
  end
  
  defp merge_instruction_files(discovered, directory_instructions) do
    # Directory instructions get higher priority by default
    # but still respect the priority field in metadata
    (directory_instructions ++ discovered)
    |> Enum.uniq_by(& &1.path)
  end
  
  defp apply_all_filtering(files, opts) do
    current_file = Keyword.get(opts, :current_file)
    context_text = Keyword.get(opts, :context_text)
    skip_keyword_filtering = Keyword.get(opts, :skip_keyword_filtering, false)
    
    files
    |> apply_directory_scope_filtering(current_file)
    |> then(fn files ->
      if skip_keyword_filtering do
        {:ok, files}
      else
        apply_keyword_filtering(files, context_text, false)
      end
    end)
  end
  
  defp apply_directory_scope_filtering(files, nil), do: files
  defp apply_directory_scope_filtering(files, current_file) do
    Enum.filter(files, fn file ->
      if Map.has_key?(file, :directory) do
        DirectoryScope.applies_to_file?(file, current_file, file.directory)
      else
        # Non-directory instructions are always included
        true
      end
    end)
  end
end
```

### 2.4 Integration with Context Building

Update the context builder to include directory-based instructions:

```elixir
defmodule RubberDuck.Context.InstructionIntegration do
  @moduledoc """
  Integrates directory-based instructions into context building with sandboxing support.
  """
  
  alias RubberDuck.Instructions.HierarchicalLoader
  alias RubberDuck.Workspace
  
  @doc """
  Builds context with instructions based on the current file and conversation.
  Respects project sandboxing boundaries.
  """
  def build_context_with_instructions(params) do
    %{
      project_id: project_id,
      user: user,
      current_file: current_file,
      conversation_text: conversation_text,
      options: options
    } = params
    
    # Load the project resource to ensure sandboxing
    with {:ok, project} <- Workspace.get_project(project_id, user: user) do
      # Load instructions with both directory and keyword filtering
      loading_opts = [
        current_file: current_file,
        context_text: conversation_text,
        enable_directory_loading: true,
        include_global: Keyword.get(options, :include_global, false),
        project: project,
        user: user
      ]
      
      case HierarchicalLoader.load_instructions(project.root_path, loading_opts) do
        {:ok, result} ->
          instructions = format_instructions_for_context(result.loaded)
          {:ok, instructions}
          
        {:error, reason} ->
          Logger.error("Failed to load instructions: #{inspect(reason)}")
          {:ok, []}  # Return empty instructions on error
      end
    end
  end
  
  defp format_instructions_for_context(instructions) do
    instructions
    |> Enum.map(fn instruction ->
      %{
        content: instruction.content,
        source: instruction.path,
        priority: instruction.priority,
        type: instruction.type,
        directory: Map.get(instruction, :directory)
      }
    end)
    |> Enum.sort_by(& &1.priority, :desc)
  end
  
  @doc """
  Preloads instructions for a file change event.
  Ensures the user has access to the project before loading.
  """
  def preload_for_file_change(file_path, project_id, user) do
    with {:ok, project} <- Workspace.get_project(project_id, user: user),
         :ok <- validate_file_in_project(file_path, project) do
      
      Task.start(fn ->
        HierarchicalLoader.load_instructions(project.root_path, [
          current_file: file_path,
          enable_directory_loading: true,
          project: project,
          user: user
        ])
      end)
    end
  end
  
  defp validate_file_in_project(file_path, project) do
    case RubberDuck.Projects.FileAccess.validate_and_normalize(file_path, project.root_path) do
      {:ok, _} -> :ok
      error -> error
    end
  end
end
```

## 3. Usage Examples

### 3.1 Directory Structure with Instructions

```
project/
├── AGENTS.md                     # Project-wide instructions
├── lib/
│   ├── .agents.md               # Instructions for all lib/ files
│   ├── rubber_duck/
│   │   ├── .agents.md           # Instructions for rubber_duck module
│   │   └── engines/
│   │       ├── .agents.md       # Instructions for engines
│   │       └── completion.ex
│   └── rubber_duck_web/
│       ├── .agents.md           # Instructions for web files
│       └── controllers/
│           └── .agents.md       # Controller-specific instructions
└── test/
    └── .agents.md               # Test-specific instructions
```

### 3.2 Example Instruction Files

#### `lib/rubber_duck/engines/.agents.md`

```markdown
---
priority: high
type: auto
tags: [engines, genserver]
directory_config:
  scope: "subtree"
  recursive: true
keyword_filter:
  keywords: ["engine", "genserver", "behavior"]
  match_type: "any"
---

# Engine Development Instructions

## GenServer Implementation
- All engines must implement the Engine behavior
- Use GenServer for state management
- Implement proper supervision

## Error Handling
- Use {:error, reason} tuples for failures
- Log errors with appropriate levels
- Implement circuit breakers for external services
```

#### `lib/rubber_duck_web/controllers/.agents.md`

```markdown
---
priority: normal
type: auto
directory_config:
  scope: "current"  # Only for files in controllers/
---

# Phoenix Controller Guidelines

## Action Functions
- Keep controllers thin
- Delegate business logic to contexts
- Use action fallback for error handling

## Response Format
- Use proper HTTP status codes
- Return consistent JSON structures
- Include pagination metadata
```

### 3.3 Loading Instructions for a File with Sandboxing

```elixir
# First, ensure we have the project and user resources
{:ok, project} = Workspace.get_project(project_id, user: current_user)

# When working on a specific file
{:ok, result} = HierarchicalLoader.load_instructions(project.root_path,
  current_file: "/project/lib/rubber_duck/engines/completion.ex",
  context_text: "implementing new engine behavior",
  project: project,
  user: current_user
)

# This will load (with sandbox validation):
# 1. Project-wide AGENTS.md
# 2. lib/.agents.md
# 3. lib/rubber_duck/.agents.md
# 4. lib/rubber_duck/engines/.agents.md
# All filtered by the context text and validated through FileManager

# The sandboxing ensures:
# - All file paths are within project boundaries
# - Symlinks are validated for safety
# - File sizes respect project limits
# - User has proper authorization
```

## 4. Caching Strategy with Sandboxing

```elixir
defmodule RubberDuck.Instructions.DirectoryCache do
  @moduledoc """
  Caches directory-based instruction discovery to improve performance.
  Cache keys include project and user IDs for proper isolation.
  """
  
  use GenServer
  
  @table :directory_instruction_cache
  @ttl :timer.minutes(5)
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, {:read_concurrency, true}])
    schedule_cleanup()
    {:ok, %{}}
  end
  
  def get_or_compute(project_id, user_id, path, fun) do
    key = generate_key(project_id, user_id, path)
    
    case :ets.lookup(@table, key) do
      [{^key, value, expiry}] when expiry > System.monotonic_time() ->
        {:ok, value}
        
      _ ->
        value = fun.()
        put(key, value)
        {:ok, value}
    end
  end
  
  def put(key, value) do
    expiry = System.monotonic_time() + @ttl
    :ets.insert(@table, {key, value, expiry})
    :ok
  end
  
  def invalidate_for_project(project_id) do
    # Invalidate all cache entries for a project
    :ets.foldl(fn
      {{proj_id, _user_id, _path} = key, _value, _expiry}, acc when proj_id == project_id ->
        :ets.delete(@table, key)
        acc
      _, acc -> acc
    end, :ok, @table)
  end
  
  def invalidate_for_user(project_id, user_id) do
    # Invalidate all cache entries for a specific user in a project
    :ets.foldl(fn
      {{proj_id, usr_id, _path} = key, _value, _expiry}, acc 
        when proj_id == project_id and usr_id == user_id ->
        :ets.delete(@table, key)
        acc
      _, acc -> acc
    end, :ok, @table)
  end
  
  def invalidate_path(project_id, path) do
    # Invalidate all cache entries that include this path for all users
    :ets.foldl(fn
      {{proj_id, _user_id, cache_path} = key, _value, _expiry}, acc 
        when proj_id == project_id ->
        if String.contains?(cache_path, path) do
          :ets.delete(@table, key)
        end
        acc
      _, acc -> acc
    end, :ok, @table)
  end
  
  defp generate_key(project_id, user_id, path) do
    {project_id, user_id, path}
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, :timer.minutes(10))
  end
  
  def handle_info(:cleanup, state) do
    now = System.monotonic_time()
    
    :ets.foldl(fn
      {key, _value, expiry}, acc when expiry < now ->
        :ets.delete(@table, key)
        acc
      _, acc -> acc
    end, :ok, @table)
    
    schedule_cleanup()
    {:noreply, state}
  end
end
```

## 5. File Watcher Integration with Sandboxing

```elixir
defmodule RubberDuck.Instructions.DirectoryWatcher do
  @moduledoc """
  Watches for changes to instruction files and invalidates caches.
  Integrates with the project file watcher system for sandboxed monitoring.
  """
  
  use GenServer
  alias RubberDuck.Instructions.DirectoryCache
  alias RubberDuck.Projects.FileWatcher
  require Logger
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    # Subscribe to file watcher events
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "file_changes")
    
    {:ok, %{}}
  end
  
  @doc """
  Handle file change events from the sandboxed file watcher
  """
  def handle_info({:file_changed, project_id, file_path, _event}, state) do
    if instruction_file?(file_path) do
      # Invalidate caches for this file and its parent directories
      DirectoryCache.invalidate_path(project_id, Path.dirname(file_path))
      
      Logger.info("Instruction file changed in project #{project_id}: #{file_path}")
    end
    
    {:noreply, state}
  end
  
  def handle_info({:file_created, project_id, file_path, _event}, state) do
    if instruction_file?(file_path) do
      DirectoryCache.invalidate_path(project_id, Path.dirname(file_path))
      Logger.info("Instruction file created in project #{project_id}: #{file_path}")
    end
    
    {:noreply, state}
  end
  
  def handle_info({:file_deleted, project_id, file_path, _event}, state) do
    if instruction_file?(file_path) do
      DirectoryCache.invalidate_path(project_id, Path.dirname(file_path))
      Logger.info("Instruction file deleted in project #{project_id}: #{file_path}")
    end
    
    {:noreply, state}
  end
  
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  defp instruction_file?(path) do
    basename = Path.basename(path)
    basename in [".agents.md", "AGENTS.md", ".rules.md", "INSTRUCTIONS.md"] or
    String.ends_with?(basename, ".cursorrules")
  end
  
  @doc """
  Register a project for instruction file watching.
  This ensures the project's file watcher includes instruction files.
  """
  def watch_project(project_id) do
    # The project's file watcher will automatically pick up changes
    # We just need to ensure we're subscribed to its events
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "file_changes:#{project_id}")
    :ok
  end
  
  @doc """
  Stop watching a project for instruction file changes.
  """
  def unwatch_project(project_id) do
    Phoenix.PubSub.unsubscribe(RubberDuck.PubSub, "file_changes:#{project_id}")
    DirectoryCache.invalidate_for_project(project_id)
    :ok
  end
end
```

## 6. Configuration

Add to your configuration:

```elixir
# config/config.exs
config :rubber_duck, :instructions,
  # Existing configuration...
  directory_loading: [
    enabled: true,
    cache_ttl: :timer.minutes(5),
    instruction_filenames: [".agents.md", "AGENTS.md", ".rules.md"],
    max_parent_depth: 10,  # Maximum parent directories to check
    exclude_directories: ["node_modules", "_build", ".git", "deps"]
  ]
```

## 7. Testing

```elixir
defmodule RubberDuck.Instructions.DirectoryLoaderTest do
  use ExUnit.Case
  alias RubberDuck.Instructions.DirectoryLoader
  
  setup do
    # Create test directory structure
    test_root = Path.join(System.tmp_dir!(), "dir_loader_test_#{:rand.uniform(10000)}")
    
    # Create directories
    File.mkdir_p!(Path.join(test_root, "lib/contexts"))
    File.mkdir_p!(Path.join(test_root, "lib/engines"))
    File.mkdir_p!(Path.join(test_root, "test"))
    
    # Create instruction files
    File.write!(Path.join(test_root, "AGENTS.md"), """
    ---
    priority: normal
    ---
    # Root instructions
    """)
    
    File.write!(Path.join(test_root, "lib/.agents.md"), """
    ---
    priority: high
    directory_config:
      scope: "subtree"
    ---
    # Lib instructions
    """)
    
    File.write!(Path.join(test_root, "lib/engines/.agents.md"), """
    ---
    priority: critical
    keyword_filter:
      keywords: ["engine", "genserver"]
      match_type: "any"
    ---
    # Engine instructions
    """)
    
    on_exit(fn -> File.rm_rf!(test_root) end)
    
    {:ok, test_root: test_root}
  end
  
  test "loads instructions from file directory and parents", %{test_root: root} do
    file_path = Path.join(root, "lib/engines/my_engine.ex")
    File.touch!(file_path)
    
    {:ok, instructions} = DirectoryLoader.load_for_file(file_path,
      project_root: root,
      context_text: "working on engine"
    )
    
    # Should load all three instruction files
    assert length(instructions) == 3
    
    # Check priority ordering
    priorities = Enum.map(instructions, & &1.priority)
    assert priorities == [:critical, :high, :normal]
  end
  
  test "excludes instructions filtered by keywords", %{test_root: root} do
    file_path = Path.join(root, "lib/engines/my_engine.ex")
    File.touch!(file_path)
    
    {:ok, instructions} = DirectoryLoader.load_for_file(file_path,
      project_root: root,
      context_text: "working on documentation"  # Won't match engine keywords
    )
    
    # Should only load root and lib instructions
    assert length(instructions) == 2
  end
  
  test "respects directory scope configuration", %{test_root: root} do
    # Add a file with "current" scope
    File.write!(Path.join(root, "test/.agents.md"), """
    ---
    priority: high
    directory_config:
      scope: "current"
    ---
    # Test only instructions
    """)
    
    # File in a subdirectory of test/
    file_path = Path.join(root, "test/support/helper.ex")
    File.mkdir_p!(Path.dirname(file_path))
    File.touch!(file_path)
    
    {:ok, instructions} = DirectoryLoader.load_for_file(file_path,
      project_root: root
    )
    
    # Should not include test/.agents.md due to "current" scope
    paths = Enum.map(instructions, & &1.path)
    refute Enum.any?(paths, &String.contains?(&1, "test/.agents.md"))
  end
end
```

## 8. Performance Considerations

1. **Caching**: The directory cache significantly improves performance by avoiding repeated file system operations

2. **Lazy Loading**: Instructions are only loaded when needed for a specific file

3. **Path Optimization**: Use efficient path operations and minimize file system calls

4. **Memory Usage**: Monitor cache size and implement eviction policies if needed

## 9. Integration with Editor Plugins

The directory-based loading system can be integrated with editor plugins:

```elixir
defmodule RubberDuck.EditorIntegration do
  @doc """
  Called by editor plugins when switching files or opening new files.
  """
  def on_file_change(file_path, project_root) do
    # Preload instructions for the new file
    Task.start(fn ->
      HierarchicalLoader.load_instructions(project_root,
        current_file: file_path,
        enable_directory_loading: true
      )
    end)
  end
end
```

This directory-based instruction loading system provides fine-grained control over which instructions apply to which parts of your codebase, while maintaining compatibility with the existing keyword filtering system.
