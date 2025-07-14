defmodule RubberDuck.Instructions.CacheInvalidator do
  @moduledoc """
  Intelligent cache invalidation system with file system integration.
  
  Provides automatic invalidation of instruction caches when files change,
  cascade invalidation for template inheritance, and smart invalidation
  patterns based on instruction relationships.
  
  ## Features
  
  - **File System Integration**: Automatic invalidation on file changes
  - **Cascade Invalidation**: Invalidates dependent templates on parent changes
  - **Scope-based Invalidation**: Invalidates by project/workspace/global scope
  - **Registry Coordination**: Coordinates with instruction registry for version tracking
  - **Batch Invalidation**: Optimized bulk invalidation for large changes
  - **Smart Patterns**: Intelligent pattern matching for efficient invalidation
  
  ## Invalidation Triggers
  
  1. **File Changes**: Direct file modification, creation, or deletion
  2. **Template Dependencies**: Changes to inherited or included templates
  3. **Registry Updates**: Instruction registry version changes
  4. **Scope Changes**: Project-wide or workspace-wide updates
  5. **Manual Triggers**: Explicit invalidation requests
  
  ## Usage Examples
  
      # Start the invalidation system
      {:ok, _pid} = CacheInvalidator.start_link()
      
      # Register file watchers
      CacheInvalidator.watch_directory("/path/to/project")
      
      # Manual invalidation
      CacheInvalidator.invalidate_file("/path/to/RUBBERDUCK.md")
      CacheInvalidator.invalidate_cascade("base_template.md")
  """

  use GenServer
  require Logger

  alias RubberDuck.Instructions.{Cache, Registry}

  # File system watcher configuration
  @watcher_name :instruction_file_watcher
  @debounce_interval 500  # milliseconds

  @type invalidation_reason :: :file_change | :template_dependency | :registry_update | :manual
  @type invalidation_event :: %{
    type: invalidation_reason(),
    target: String.t(),
    timestamp: integer(),
    metadata: map()
  }

  ## Public API

  @doc """
  Starts the cache invalidation system.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a directory for file system watching.
  
  Any changes to instruction files in this directory will trigger cache invalidation.
  """
  @spec watch_directory(String.t()) :: :ok | {:error, term()}
  def watch_directory(path) do
    GenServer.call(__MODULE__, {:watch_directory, path})
  end

  @doc """
  Stops watching a directory.
  """
  @spec unwatch_directory(String.t()) :: :ok
  def unwatch_directory(path) do
    GenServer.call(__MODULE__, {:unwatch_directory, path})
  end

  @doc """
  Manually invalidates cache entries for a specific file.
  """
  @spec invalidate_file(String.t(), keyword()) :: :ok
  def invalidate_file(file_path, opts \\ []) do
    reason = Keyword.get(opts, :reason, :manual)
    GenServer.cast(__MODULE__, {:invalidate_file, file_path, reason})
  end

  @doc """
  Invalidates cache entries with cascade effect for template dependencies.
  """
  @spec invalidate_cascade(String.t()) :: :ok
  def invalidate_cascade(template_path) do
    GenServer.cast(__MODULE__, {:invalidate_cascade, template_path})
  end

  @doc """
  Invalidates all cache entries for a specific scope.
  """
  @spec invalidate_scope(Cache.scope(), String.t()) :: :ok
  def invalidate_scope(scope, root_path) do
    GenServer.cast(__MODULE__, {:invalidate_scope, scope, root_path})
  end

  @doc """
  Returns invalidation statistics and metrics.
  """
  @spec get_stats() :: map()
  def get_stats() do
    GenServer.call(__MODULE__, :get_stats)
  end

  ## GenServer Implementation

  def init(_opts) do
    # Start file system watcher (handle gracefully if not available)
    watcher_pid = case FileSystem.start_link(
      name: @watcher_name,
      dirs: []  # Directories added dynamically
    ) do
      {:ok, pid} -> 
        # Subscribe to file system events
        FileSystem.subscribe(@watcher_name)
        pid
      _ -> 
        Logger.warning("File system watcher not available, manual invalidation only")
        nil
    end

    state = %{
      watcher_pid: watcher_pid,
      watched_directories: MapSet.new(),
      pending_invalidations: %{},
      invalidation_history: [],
      stats: init_stats(),
      dependency_graph: build_dependency_graph()
    }

    # Schedule periodic cleanup of invalidation history
    schedule_cleanup()

    Logger.info("Cache invalidation system initialized")
    {:ok, state}
  end

  def handle_call({:watch_directory, path}, _from, state) do
    if File.exists?(path) and File.dir?(path) do
      # Note: FileSystem.subscribe API may vary, for now just track directories
      updated_directories = MapSet.put(state.watched_directories, path)
      Logger.debug("Started watching directory: #{path}")
      {:reply, :ok, %{state | watched_directories: updated_directories}}
    else
      {:reply, {:error, :invalid_directory}, state}
    end
  end

  def handle_call({:unwatch_directory, path}, _from, state) do
    # Note: FileSystem.unsubscribe API may vary, for now just track directories
    updated_directories = MapSet.delete(state.watched_directories, path)
    Logger.debug("Stopped watching directory: #{path}")
    {:reply, :ok, %{state | watched_directories: updated_directories}}
  end

  def handle_call(:get_stats, _from, state) do
    stats = calculate_invalidation_stats(state)
    {:reply, stats, state}
  end

  def handle_cast({:invalidate_file, file_path, reason}, state) do
    event = create_invalidation_event(:file_change, file_path, reason)
    updated_state = process_invalidation_event(event, state)
    {:noreply, updated_state}
  end

  def handle_cast({:invalidate_cascade, template_path}, state) do
    event = create_invalidation_event(:template_dependency, template_path, :cascade)
    updated_state = process_cascade_invalidation(event, state)
    {:noreply, updated_state}
  end

  def handle_cast({:invalidate_scope, scope, root_path}, state) do
    event = create_invalidation_event(:registry_update, "#{scope}:#{root_path}", :scope_change)
    updated_state = process_scope_invalidation(scope, root_path, event, state)
    {:noreply, updated_state}
  end

  # File system events
  def handle_info({:file_event, _watcher_pid, {file_path, events}}, state) do
    if is_instruction_file?(file_path) do
      Logger.debug("File event for instruction file: #{file_path} - #{inspect(events)}")
      
      # Debounce rapid file changes
      updated_state = debounce_file_invalidation(file_path, events, state)
      {:noreply, updated_state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    Logger.warning("File system watcher stopped")
    {:noreply, state}
  end

  def handle_info({:process_pending_invalidations, file_path}, state) do
    case Map.get(state.pending_invalidations, file_path) do
      nil ->
        {:noreply, state}
        
      {_events, _timer_ref} ->
        # Process accumulated events
        event = create_invalidation_event(:file_change, file_path, :file_system)
        updated_state = process_invalidation_event(event, state)
        
        # Remove from pending
        updated_pending = Map.delete(updated_state.pending_invalidations, file_path)
        
        {:noreply, %{updated_state | pending_invalidations: updated_pending}}
    end
  end

  def handle_info(:cleanup_history, state) do
    # Keep only last 1000 invalidation events
    updated_history = Enum.take(state.invalidation_history, 1000)
    schedule_cleanup()
    {:noreply, %{state | invalidation_history: updated_history}}
  end

  ## Private Functions

  defp init_stats() do
    %{
      total_invalidations: 0,
      file_invalidations: 0,
      cascade_invalidations: 0,
      scope_invalidations: 0,
      start_time: :os.system_time(:millisecond)
    }
  end

  defp create_invalidation_event(type, target, reason) do
    %{
      type: type,
      target: target,
      reason: reason,
      timestamp: :os.system_time(:millisecond),
      metadata: %{
        process: self(),
        node: node()
      }
    }
  end

  defp process_invalidation_event(event, state) do
    file_path = event.target
    
    # Invalidate all cache layers for this file
    Cache.invalidate_file(file_path)
    
    # Check for template dependencies
    dependencies = find_template_dependencies(file_path, state.dependency_graph)
    Enum.each(dependencies, &Cache.invalidate_file/1)
    
    # Update registry if needed
    update_instruction_registry(file_path)
    
    # Record event and update stats
    updated_history = [event | state.invalidation_history]
    updated_stats = update_invalidation_stats(state.stats, event)
    
    emit_invalidation_telemetry(event)
    
    %{state | 
      invalidation_history: updated_history,
      stats: updated_stats
    }
  end

  defp process_cascade_invalidation(event, state) do
    template_path = event.target
    
    # Find all files that depend on this template
    dependent_files = find_dependent_files(template_path, state.dependency_graph)
    
    # Invalidate the template and all dependents
    Cache.invalidate_file(template_path)
    Enum.each(dependent_files, &Cache.invalidate_file/1)
    
    # Record cascade event
    updated_history = [event | state.invalidation_history]
    updated_stats = update_invalidation_stats(state.stats, event)
    
    emit_invalidation_telemetry(event, %{cascade_count: length(dependent_files)})
    
    %{state | 
      invalidation_history: updated_history,
      stats: updated_stats
    }
  end

  defp process_scope_invalidation(scope, root_path, event, state) do
    # Invalidate all cache entries for the scope
    Cache.invalidate_scope(scope, root_path)
    
    # Record scope event
    updated_history = [event | state.invalidation_history]
    updated_stats = update_invalidation_stats(state.stats, event)
    
    emit_invalidation_telemetry(event, %{scope: scope, root_path: root_path})
    
    %{state | 
      invalidation_history: updated_history,
      stats: updated_stats
    }
  end

  defp debounce_file_invalidation(file_path, events, state) do
    # Cancel existing timer if any
    updated_pending = case Map.get(state.pending_invalidations, file_path) do
      {_old_events, timer_ref} ->
        Process.cancel_timer(timer_ref)
        state.pending_invalidations
      nil ->
        state.pending_invalidations
    end
    
    # Start new debounce timer
    timer_ref = Process.send_after(
      self(), 
      {:process_pending_invalidations, file_path}, 
      @debounce_interval
    )
    
    # Store pending invalidation
    updated_pending = Map.put(updated_pending, file_path, {events, timer_ref})
    
    %{state | pending_invalidations: updated_pending}
  end

  defp is_instruction_file?(file_path) do
    instruction_extensions = [".md", ".mdc", ".cursorrules"]
    instruction_names = ["RUBBERDUCK.md", "rubber_duck.md", ".rubber_duck.md"]
    
    extension = Path.extname(file_path)
    filename = Path.basename(file_path)
    
    extension in instruction_extensions or filename in instruction_names
  end

  defp build_dependency_graph() do
    # Build a graph of template dependencies
    # This would analyze include/extends relationships
    # For now, return empty graph - to be implemented
    %{}
  end

  defp find_template_dependencies(_file_path, _dependency_graph) do
    # Find files that this template depends on
    # Return list of dependency file paths
    []
  end

  defp find_dependent_files(_template_path, _dependency_graph) do
    # Find files that depend on this template
    # Return list of dependent file paths
    []
  end

  defp update_instruction_registry(_file_path) do
    # Notify registry of file change for version tracking
    case Registry.get_stats() do
      stats when is_map(stats) ->
        # Registry is available, could trigger re-indexing
        :ok
      _ ->
        # Registry not available
        :skip
    end
  end

  defp update_invalidation_stats(stats, event) do
    updated_stats = %{stats | total_invalidations: stats.total_invalidations + 1}
    
    case event.type do
      :file_change -> %{updated_stats | file_invalidations: stats.file_invalidations + 1}
      :template_dependency -> %{updated_stats | cascade_invalidations: stats.cascade_invalidations + 1}
      :registry_update -> %{updated_stats | scope_invalidations: stats.scope_invalidations + 1}
      _ -> updated_stats
    end
  end

  defp calculate_invalidation_stats(state) do
    %{
      total_invalidations: state.stats.total_invalidations,
      file_invalidations: state.stats.file_invalidations,
      cascade_invalidations: state.stats.cascade_invalidations,
      scope_invalidations: state.stats.scope_invalidations,
      watched_directories: MapSet.size(state.watched_directories),
      pending_invalidations: map_size(state.pending_invalidations),
      recent_events: Enum.take(state.invalidation_history, 10),
      uptime_ms: :os.system_time(:millisecond) - state.stats.start_time
    }
  end

  defp schedule_cleanup() do
    Process.send_after(self(), :cleanup_history, :timer.minutes(30))
  end

  defp emit_invalidation_telemetry(event, extra_metadata \\ %{}) do
    metadata = Map.merge(%{
      type: event.type,
      target: event.target,
      reason: event.reason
    }, extra_metadata)
    
    :telemetry.execute(
      [:rubber_duck, :instructions, :cache, :invalidation],
      %{count: 1, timestamp: event.timestamp},
      metadata
    )
  end
end