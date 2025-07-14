defmodule RubberDuck.Instructions.HierarchicalLoader do
  @moduledoc """
  Hierarchical instruction loading system.
  
  Orchestrates the discovery, parsing, and loading of instruction files
  across multiple hierarchy levels with intelligent conflict resolution
  and priority-based merging.
  
  ## Loading Strategy
  
  1. **Discovery Phase**: Find all instruction files across hierarchy levels
  2. **Parsing Phase**: Parse files according to their format
  3. **Validation Phase**: Validate content and metadata
  4. **Resolution Phase**: Resolve conflicts and apply priority rules
  5. **Loading Phase**: Load resolved instructions into registry
  
  ## Hierarchy Levels (in priority order)
  
  1. **Directory-specific** - `./.instructions/`, `./instructions/`
  2. **Project root** - `./claude.md`, `./instructions.md`, etc.
  3. **Workspace** - `.vscode/`, `.idea/` instructions
  4. **Global** - `~/.claude.md`, `/etc/claude/`, etc.
  
  ## Conflict Resolution
  
  When multiple files provide instructions for the same context:
  - Higher priority level wins
  - Within same level, explicit priority metadata wins
  - File modification time used as tiebreaker
  """

  require Logger
  alias RubberDuck.Instructions.{FileManager, FormatParser, Registry}

  @type loading_result :: %{
    loaded: [loaded_instruction()],
    skipped: [skipped_instruction()],
    errors: [failed_instruction()],
    conflicts: [conflict_resolution()],
    stats: loading_stats()
  }

  @type loaded_instruction :: %{
    id: String.t(),
    file_path: String.t(),
    priority: integer(),
    scope: atom(),
    type: atom()
  }

  @type skipped_instruction :: %{
    file_path: String.t(),
    reason: atom(),
    details: String.t()
  }

  @type failed_instruction :: %{
    file_path: String.t(),
    error: term(),
    stage: atom()
  }

  @type conflict_resolution :: %{
    context: String.t(),
    winner: String.t(),
    losers: [String.t()],
    resolution_reason: String.t()
  }

  @type loading_stats :: %{
    total_discovered: integer(),
    total_loaded: integer(),
    total_skipped: integer(),
    total_errors: integer(),
    conflicts_resolved: integer(),
    loading_time: integer()
  }

  @type loading_opts :: [
    root_path: String.t(),
    include_global: boolean(),
    auto_resolve_conflicts: boolean(),
    validate_content: boolean(),
    register_instructions: boolean(),
    dry_run: boolean()
  ]

  @doc """
  Loads instructions hierarchically from the specified root path.
  
  ## Options
  
  - `:root_path` - Starting directory (defaults to current directory)
  - `:include_global` - Include global instructions (defaults to true)
  - `:auto_resolve_conflicts` - Automatically resolve conflicts (defaults to true)
  - `:validate_content` - Validate instruction content (defaults to true)
  - `:register_instructions` - Register in registry (defaults to true)
  - `:dry_run` - Don't actually load, just analyze (defaults to false)
  
  ## Examples
  
      iex> HierarchicalLoader.load_instructions("/path/to/project")
      {:ok, %{loaded: [...], skipped: [...], errors: [...], ...}}
      
      iex> HierarchicalLoader.load_instructions(".", dry_run: true)
      {:ok, %{...}}  # Analysis only, no actual loading
  """
  @spec load_instructions(String.t(), loading_opts()) :: {:ok, loading_result()} | {:error, term()}
  def load_instructions(root_path \\ ".", opts \\ []) do
    start_time = System.monotonic_time(:microsecond)
    
    include_global = Keyword.get(opts, :include_global, true)
    auto_resolve = Keyword.get(opts, :auto_resolve_conflicts, true)
    validate_content = Keyword.get(opts, :validate_content, true)
    register_instructions = Keyword.get(opts, :register_instructions, true)
    dry_run = Keyword.get(opts, :dry_run, false)

    Logger.info("Starting hierarchical instruction loading from: #{root_path}")

    with {:ok, discovered_files} <- discover_all_files(root_path, include_global),
         {:ok, parsed_files} <- parse_all_files(discovered_files, validate_content),
         {:ok, resolved_files, conflicts} <- resolve_conflicts(parsed_files, auto_resolve),
         {:ok, loading_result} <- maybe_load_instructions(resolved_files, register_instructions, dry_run) do
      
      end_time = System.monotonic_time(:microsecond)
      loading_time = end_time - start_time
      
      result = %{
        loaded: loading_result.loaded,
        skipped: loading_result.skipped,
        errors: loading_result.errors,
        conflicts: conflicts,
        stats: %{
          total_discovered: length(discovered_files),
          total_loaded: length(loading_result.loaded),
          total_skipped: length(loading_result.skipped),
          total_errors: length(loading_result.errors),
          conflicts_resolved: length(conflicts),
          loading_time: loading_time
        }
      }
      
      log_loading_summary(result)
      {:ok, result}
    end
  end

  @doc """
  Discovers instructions at a specific hierarchy level.
  """
  @spec discover_at_level(String.t(), atom()) :: {:ok, [String.t()]} | {:error, term()}
  def discover_at_level(root_path, level) do
    case level do
      :directory -> discover_directory_instructions(root_path)
      :project -> discover_project_instructions(root_path)
      :workspace -> discover_workspace_instructions(root_path)
      :global -> discover_global_instructions()
      _ -> {:error, {:invalid_level, level}}
    end
  end

  @doc """
  Analyzes instruction hierarchy without loading.
  
  Useful for understanding what would be loaded and potential conflicts.
  """
  @spec analyze_hierarchy(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def analyze_hierarchy(root_path, opts \\ []) do
    opts_with_dry_run = Keyword.put(opts, :dry_run, true)
    
    case load_instructions(root_path, opts_with_dry_run) do
      {:ok, result} ->
        analysis = %{
          hierarchy_levels: analyze_hierarchy_levels(result),
          conflict_analysis: analyze_conflicts(result.conflicts),
          coverage_analysis: analyze_coverage(result),
          recommendations: generate_recommendations(result)
        }
        
        {:ok, analysis}
        
      error -> error
    end
  end

  # Private functions

  defp discover_all_files(root_path, include_global) do
    Logger.debug("Discovering instruction files...")
    
    with {:ok, directory_files} <- discover_directory_instructions(root_path),
         {:ok, project_files} <- discover_project_instructions(root_path),
         {:ok, workspace_files} <- discover_workspace_instructions(root_path),
         {:ok, global_files} <- maybe_discover_global_instructions(include_global) do
      
      all_files = directory_files ++ project_files ++ workspace_files ++ global_files
      unique_files = Enum.uniq(all_files)
      
      Logger.debug("Discovered #{length(unique_files)} unique instruction files")
      {:ok, unique_files}
    end
  end

  defp discover_directory_instructions(root_path) do
    patterns = [
      ".instructions/*.md",
      ".instructions/*.mdc",
      "instructions/*.md",
      "instructions/*.mdc"
    ]
    
    discover_with_patterns(root_path, patterns, :directory)
  end

  defp discover_project_instructions(root_path) do
    patterns = [
      "claude.md",
      "CLAUDE.md",
      ".claude.md",
      "instructions.md",
      "rules.md",
      "*.cursorrules"
    ]
    
    discover_with_patterns(root_path, patterns, :project)
  end

  defp discover_workspace_instructions(root_path) do
    patterns = [
      ".vscode/*.md",
      ".vscode/instructions.md",
      ".idea/*.md",
      ".idea/instructions.md",
      "workspace.md",
      ".workspace/*.md"
    ]
    
    discover_with_patterns(root_path, patterns, :workspace)
  end

  defp maybe_discover_global_instructions(false), do: {:ok, []}
  defp maybe_discover_global_instructions(true), do: discover_global_instructions()

  defp discover_global_instructions do
    global_paths = [
      Path.expand("~/.config/claude/instructions.md"),
      Path.expand("~/.config/claude/claude.md"),
      Path.expand("~/.claude.md"),
      Path.expand("~/.cursorrules"),
      "/etc/claude/instructions.md",
      "/etc/claude/claude.md"
    ]
    
    existing_files = 
      global_paths
      |> Enum.filter(&File.exists?/1)
      |> Enum.map(&{&1, :global})
    
    {:ok, existing_files}
  end

  defp discover_with_patterns(root_path, patterns, scope) do
    files = 
      patterns
      |> Enum.flat_map(fn pattern ->
        full_pattern = Path.join(root_path, pattern)
        
        Path.wildcard(full_pattern)
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(&{&1, scope})
      end)
      |> Enum.uniq()
    
    {:ok, files}
  end

  defp parse_all_files(discovered_files, validate_content) do
    Logger.debug("Parsing #{length(discovered_files)} instruction files...")
    
    {parsed_files, errors} = 
      discovered_files
      |> Enum.reduce({[], []}, fn {file_path, scope}, {parsed_acc, error_acc} ->
        case parse_instruction_file(file_path, scope, validate_content) do
          {:ok, parsed} -> {[parsed | parsed_acc], error_acc}
          {:error, reason} -> 
            error = %{file_path: file_path, error: reason, stage: :parsing}
            {parsed_acc, [error | error_acc]}
        end
      end)
    
    result = %{
      parsed: Enum.reverse(parsed_files),
      errors: Enum.reverse(errors)
    }
    
    {:ok, result}
  end

  defp parse_instruction_file(file_path, scope, validate_content) do
    with {:ok, parsed_content} <- FormatParser.parse_file(file_path),
         {:ok, validated} <- maybe_validate_content(parsed_content, validate_content) do
      
      # Create enhanced instruction info
      instruction = %{
        file_path: file_path,
        scope: scope,
        parsed_content: validated,
        priority: calculate_effective_priority(validated, scope),
        context_key: generate_context_key(validated, scope),
        modified_at: get_file_modified_time(file_path)
      }
      
      {:ok, instruction}
    end
  end

  defp maybe_validate_content(parsed_content, false), do: {:ok, parsed_content}
  defp maybe_validate_content(parsed_content, true) do
    # Perform content validation
    with :ok <- validate_parsed_content(parsed_content) do
      {:ok, parsed_content}
    end
  end

  defp validate_parsed_content(parsed) do
    # Basic validation of parsed content
    cond do
      String.trim(parsed.content) == "" ->
        {:error, :empty_content}
        
      String.length(parsed.content) > 50_000 ->
        {:error, :content_too_large}
        
      true ->
        :ok
    end
  end

  defp resolve_conflicts(parse_result, auto_resolve) do
    parsed_files = parse_result.parsed
    
    # Group by context key to find conflicts
    grouped = Enum.group_by(parsed_files, & &1.context_key)
    
    {resolved_files, conflicts} = 
      grouped
      |> Enum.reduce({[], []}, fn {context_key, files}, {resolved_acc, conflict_acc} ->
        case length(files) do
          1 -> 
            # No conflict
            {[hd(files) | resolved_acc], conflict_acc}
            
          _ -> 
            # Conflict detected
            if auto_resolve do
              {winner, losers} = resolve_conflict_automatically(files)
              conflict = create_conflict_record(context_key, winner, losers, "automatic_priority")
              {[winner | resolved_acc], [conflict | conflict_acc]}
            else
              # Manual resolution required - for now, take highest priority
              {winner, losers} = resolve_conflict_automatically(files)
              conflict = create_conflict_record(context_key, winner, losers, "manual_required")
              {[winner | resolved_acc], [conflict | conflict_acc]}
            end
        end
      end)
    
    final_result = %{parse_result | parsed: resolved_files}
    {:ok, final_result, conflicts}
  end

  defp resolve_conflict_automatically(files) do
    # Sort by priority (highest first), then by modification time (newest first)
    sorted_files = 
      files
      |> Enum.sort_by(fn file ->
        {-file.priority, -DateTime.to_unix(file.modified_at)}
      end)
    
    [winner | losers] = sorted_files
    {winner, losers}
  end

  defp create_conflict_record(context_key, winner, losers, reason) do
    %{
      context: context_key,
      winner: winner.file_path,
      losers: Enum.map(losers, & &1.file_path),
      resolution_reason: reason
    }
  end

  defp maybe_load_instructions(parse_result, register_instructions, dry_run) do
    if dry_run or not register_instructions do
      # Dry run - simulate loading
      loaded = Enum.map(parse_result.parsed, &simulate_loading/1)
      result = %{loaded: loaded, skipped: [], errors: parse_result.errors}
      {:ok, result}
    else
      # Actually load into registry
      load_into_registry(parse_result)
    end
  end

  defp simulate_loading(instruction) do
    %{
      id: generate_instruction_id(instruction),
      file_path: instruction.file_path,
      priority: instruction.priority,
      scope: instruction.scope,
      type: instruction.parsed_content.metadata["type"] || "auto"
    }
  end

  defp load_into_registry(parse_result) do
    {loaded, skipped, errors} = 
      parse_result.parsed
      |> Enum.reduce({[], [], parse_result.errors}, fn instruction, {loaded_acc, skipped_acc, error_acc} ->
        case load_single_instruction(instruction) do
          {:ok, loaded_info} -> {[loaded_info | loaded_acc], skipped_acc, error_acc}
          {:skipped, reason} -> 
            skipped_info = %{
              file_path: instruction.file_path,
              reason: reason,
              details: "Instruction was skipped during loading"
            }
            {loaded_acc, [skipped_info | skipped_acc], error_acc}
          {:error, error} ->
            error_info = %{
              file_path: instruction.file_path,
              error: error,
              stage: :loading
            }
            {loaded_acc, skipped_acc, [error_info | error_acc]}
        end
      end)
    
    result = %{
      loaded: Enum.reverse(loaded),
      skipped: Enum.reverse(skipped),
      errors: Enum.reverse(errors)
    }
    
    {:ok, result}
  end

  defp load_single_instruction(instruction) do
    # Convert to FileManager format
    file_info = %{
      path: instruction.file_path,
      type: String.to_atom(instruction.parsed_content.metadata["type"] || "auto"),
      priority: instruction.priority,
      scope: instruction.scope,
      metadata: instruction.parsed_content.metadata,
      content: instruction.parsed_content.content,
      size: String.length(instruction.parsed_content.content),
      modified_at: instruction.modified_at
    }
    
    case Registry.register_instruction(file_info) do
      {:ok, instruction_id} ->
        loaded_info = %{
          id: instruction_id,
          file_path: instruction.file_path,
          priority: instruction.priority,
          scope: instruction.scope,
          type: file_info.type
        }
        {:ok, loaded_info}
        
      {:error, :duplicate_instruction} ->
        {:skipped, :duplicate}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_effective_priority(parsed_content, scope) do
    # Base priority by scope
    base_priority = case scope do
      :directory -> 1200
      :project -> 1000
      :workspace -> 800
      :global -> 400
    end
    
    # Metadata priority adjustment
    metadata_priority = case Map.get(parsed_content.metadata, "priority", "normal") do
      "critical" -> 300
      "high" -> 200
      "normal" -> 0
      "low" -> -100
    end
    
    # Format-specific adjustments
    format_priority = case parsed_content.format do
      :claude_md -> 50
      :cursorrules -> 30
      :mdc -> 20
      :markdown -> 0
    end
    
    base_priority + metadata_priority + format_priority
  end

  defp generate_context_key(parsed_content, scope) do
    # Generate context key for conflict detection
    context_factors = [
      to_string(scope),
      Map.get(parsed_content.metadata, "context", "general"),
      Path.basename(Path.dirname(parsed_content.format))
    ]
    
    Enum.join(context_factors, ":")
  end

  defp generate_instruction_id(instruction) do
    hash = :crypto.hash(:sha256, instruction.file_path) |> Base.encode16(case: :lower)
    "#{instruction.scope}:#{Path.basename(instruction.file_path)}:#{String.slice(hash, 0, 8)}"
  end

  defp get_file_modified_time(file_path) do
    case File.stat(file_path) do
      {:ok, %{mtime: mtime}} -> DateTime.from_naive!(mtime, "Etc/UTC")
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp log_loading_summary(result) do
    stats = result.stats
    
    Logger.info("""
    Instruction loading completed:
    - Discovered: #{stats.total_discovered} files
    - Loaded: #{stats.total_loaded} instructions
    - Skipped: #{stats.total_skipped} files
    - Errors: #{stats.total_errors} files
    - Conflicts resolved: #{stats.conflicts_resolved}
    - Loading time: #{div(stats.loading_time, 1000)}ms
    """)
    
    if stats.total_errors > 0 do
      Logger.warn("#{stats.total_errors} files failed to load")
    end
    
    if stats.conflicts_resolved > 0 do
      Logger.info("#{stats.conflicts_resolved} conflicts were automatically resolved")
    end
  end

  defp analyze_hierarchy_levels(result) do
    # Analyze distribution across hierarchy levels
    result.loaded
    |> Enum.group_by(& &1.scope)
    |> Enum.map(fn {scope, instructions} ->
      {scope, %{
        count: length(instructions),
        avg_priority: avg_priority(instructions),
        files: Enum.map(instructions, & &1.file_path)
      }}
    end)
    |> Enum.into(%{})
  end

  defp analyze_conflicts(conflicts) do
    %{
      total_conflicts: length(conflicts),
      conflict_contexts: Enum.map(conflicts, & &1.context),
      resolution_methods: Enum.group_by(conflicts, & &1.resolution_reason)
    }
  end

  defp analyze_coverage(result) do
    # Analyze instruction coverage
    types = Enum.group_by(result.loaded, & &1.type)
    scopes = Enum.group_by(result.loaded, & &1.scope)
    
    %{
      type_coverage: Enum.map(types, fn {type, instructions} -> {type, length(instructions)} end),
      scope_coverage: Enum.map(scopes, fn {scope, instructions} -> {scope, length(instructions)} end),
      coverage_gaps: identify_coverage_gaps(result)
    }
  end

  defp generate_recommendations(result) do
    recommendations = []
    
    # Check for missing critical files
    recommendations = if not has_project_instructions?(result) do
      ["Consider adding a claude.md or instructions.md file in the project root" | recommendations]
    else
      recommendations
    end
    
    # Check for conflicts
    recommendations = if length(result.conflicts) > 0 do
      ["Review and resolve #{length(result.conflicts)} instruction conflicts" | recommendations]
    else
      recommendations
    end
    
    # Check for errors
    recommendations = if result.stats.total_errors > 0 do
      ["Fix #{result.stats.total_errors} files that failed to load" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  defp avg_priority(instructions) do
    if length(instructions) > 0 do
      total = Enum.sum(Enum.map(instructions, & &1.priority))
      div(total, length(instructions))
    else
      0
    end
  end

  defp identify_coverage_gaps(_result) do
    # Identify potential gaps in instruction coverage
    ["This feature is not yet implemented"]
  end

  defp has_project_instructions?(result) do
    Enum.any?(result.loaded, &(&1.scope == :project))
  end
end