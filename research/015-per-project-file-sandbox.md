# Implementing project-based sandboxed filesystem access for Elixir/Phoenix web applications

Building a secure, real-time file management system in Elixir/Phoenix for multi-project environments requires orchestrating project isolation, collaborative access, and real-time updates. This guide explores production-ready patterns for project-based sandboxed filesystem access, supporting multiple users working on different or shared projects simultaneously.

## Architecture overview: Project-centric sandboxing

Unlike user-based sandboxing, this system centers around **projects as the primary isolation boundary**. Each project (an Ash resource) contains a path to its directory, which becomes a sandboxed environment. Multiple users can access the same project, enabling real-time collaboration while maintaining security.

```elixir
# Example Ash Project resource
defmodule MyApp.Workspace.Project do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :root_path, :string, allow_nil?: false  # The directory to sandbox
    attribute :owner_id, :uuid, allow_nil?: false
    timestamps()
  end
  
  relationships do
    has_many :collaborators, MyApp.Accounts.ProjectCollaborator
    belongs_to :owner, MyApp.Accounts.User
  end
end
```

## Core security: Project-based path validation

Path validation must ensure all file operations remain within a specific project's directory boundaries:

```elixir
defmodule MyApp.ProjectFileAccess do
  @max_path_length 4096
  @forbidden_chars ["<", ">", ":", "\"", "|", "?", "*", "\0"]
  
  def validate_and_normalize(project, user_path) do
    project_root = Path.expand(project.root_path)
    
    with :ok <- validate_project_directory_exists(project_root),
         :ok <- validate_length(user_path),
         :ok <- validate_characters(user_path),
         {:ok, safe_path} <- Path.safe_relative(user_path),
         full_path = Path.join(project_root, safe_path),
         expanded_path = Path.expand(full_path),
         true <- String.starts_with?(expanded_path, project_root) do
      {:ok, expanded_path}
    else
      false -> {:error, :path_traversal_attempt}
      error -> error
    end
  end
  
  defp validate_project_directory_exists(path) do
    if File.dir?(path) do
      :ok
    else
      {:error, :project_directory_not_found}
    end
  end
  
  defp validate_length(path) when byte_size(path) > @max_path_length do
    {:error, :path_too_long}
  end
  defp validate_length(_), do: :ok
  
  defp validate_characters(path) do
    if Enum.any?(@forbidden_chars, &String.contains?(path, &1)) do
      {:error, :forbidden_characters}
    else
      :ok
    end
  end
end
```

**Critical insight**: Each project maintains its own sandbox boundary. Validation must always use the project's specific root path, not a global sandbox directory.

## Symbolic link detection and prevention in project directories

Symbolic links pose security risks in project-based systems where links might point to sensitive areas outside the project boundary:

```elixir
defmodule MyApp.ProjectSymlinkSecurity do
  def check_symlink_safety(path, project) do
    project_root = Path.expand(project.root_path)
    
    with {:ok, stat} <- File.lstat(path),
         true <- stat.type != :symlink do
      {:ok, path}
    else
      {:ok, %{type: :symlink}} ->
        case File.read_link(path) do
          {:ok, target} ->
            resolved_target = Path.expand(target, Path.dirname(path))
            if String.starts_with?(resolved_target, project_root) do
              {:ok, path}
            else
              {:error, :symlink_outside_project}
            end
          {:error, reason} ->
            {:error, reason}
        end
      false ->
        {:ok, path}
    end
  end
  
  # Scan entire project for external symlinks
  def scan_project_for_unsafe_symlinks(project) do
    project_root = Path.expand(project.root_path)
    
    project_root
    |> File.ls!()
    |> Enum.flat_map(&find_symlinks(&1, project_root))
    |> Enum.filter(fn {_path, target} ->
      not String.starts_with?(target, project_root)
    end)
  end
  
  defp find_symlinks(path, root) do
    full_path = Path.join(root, path)
    
    case File.lstat(full_path) do
      {:ok, %{type: :symlink}} ->
        case File.read_link(full_path) do
          {:ok, target} -> [{full_path, Path.expand(target, root)}]
          _ -> []
        end
      {:ok, %{type: :directory}} ->
        full_path
        |> File.ls!()
        |> Enum.flat_map(&find_symlinks(Path.join(path, &1), root))
      _ ->
        []
    end
  end
end
```

## Multi-project file watching with FileSystem and LiveView

Managing file watchers for multiple projects requires a dynamic supervision tree and efficient PubSub channel design to support collaborative real-time updates:

```elixir
defmodule MyApp.ProjectFileWatcher.Supervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  
  def start_watcher(project) do
    spec = {MyApp.ProjectFileWatcher, project}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
  
  def stop_watcher(project_id) do
    case Registry.lookup(MyApp.ProjectRegistry, project_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      _ -> :ok
    end
  end
end

defmodule MyApp.ProjectFileWatcher do
  use GenServer
  require Logger

  def start_link(project) do
    GenServer.start_link(
      __MODULE__, 
      project,
      name: {:via, Registry, {MyApp.ProjectRegistry, project.id}}
    )
  end

  def init(project) do
    # Subscribe this watcher to the project's file events
    {:ok, watcher_pid} = FileSystem.start_link(
      dirs: [project.root_path],
      latency: 100,
      recursive: true
    )
    
    FileSystem.subscribe(watcher_pid)
    
    Logger.info("Started file watcher for project #{project.id} at #{project.root_path}")
    
    {:ok, %{
      project: project,
      watcher_pid: watcher_pid,
      event_buffer: %{},
      buffer_timer: nil
    }}
  end

  # Batch file events to prevent overwhelming clients
  def handle_info(
    {:file_event, watcher_pid, {path, events}}, 
    %{watcher_pid: watcher_pid} = state
  ) do
    # Validate the path is still within project bounds
    case MyApp.ProjectFileAccess.validate_and_normalize(state.project, path) do
      {:ok, safe_path} ->
        relative_path = Path.relative_to(safe_path, state.project.root_path)
        
        # Buffer events
        new_buffer = Map.update(
          state.event_buffer,
          relative_path,
          MapSet.new(events),
          &MapSet.union(&1, MapSet.new(events))
        )
        
        # Cancel existing timer and set new one
        if state.buffer_timer, do: Process.cancel_timer(state.buffer_timer)
        timer = Process.send_after(self(), :flush_events, 50)
        
        {:noreply, %{state | event_buffer: new_buffer, buffer_timer: timer}}
        
      {:error, reason} ->
        Logger.warn("Invalid file event path in project #{state.project.id}: #{reason}")
        {:noreply, state}
    end
  end
  
  def handle_info(:flush_events, state) do
    if map_size(state.event_buffer) > 0 do
      # Broadcast to all users watching this project
      Phoenix.PubSub.broadcast(
        MyApp.PubSub,
        "project:#{state.project.id}:files",
        {:file_changes, state.event_buffer}
      )
    end
    
    {:noreply, %{state | event_buffer: %{}, buffer_timer: nil}}
  end
  
  def terminate(_reason, state) do
    FileSystem.stop(state.watcher_pid)
    :ok
  end
end
```

### LiveView integration for multi-user project collaboration

```elixir
defmodule MyAppWeb.ProjectFilesLive do
  use MyAppWeb, :live_view
  alias MyApp.Workspace
  
  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    current_user = socket.assigns.current_user
    
    with {:ok, project} <- Workspace.get_project(project_id),
         :ok <- authorize_project_access(project, current_user) do
      
      if connected?(socket) do
        # Subscribe to file changes for this specific project
        Phoenix.PubSub.subscribe(MyApp.PubSub, "project:#{project.id}:files")
        
        # Ensure file watcher is running for this project
        ensure_project_watcher_started(project)
        
        # Track user presence for collaborative features
        {:ok, _} = Presence.track(
          self(),
          "project:#{project.id}:presence",
          current_user.id,
          %{
            name: current_user.name,
            joined_at: System.system_time(:second)
          }
        )
      end
      
      {:ok,
       socket
       |> assign(:project, project)
       |> assign(:current_path, "/")
       |> stream(:files, load_project_files(project, "/"))
       |> assign(:active_users, %{})}
    else
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found")
         |> redirect(to: ~p"/projects")}
         
      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have access to this project")
         |> redirect(to: ~p"/projects")}
    end
  end
  
  @impl true
  def handle_info({:file_changes, changes}, socket) do
    # Process batched file changes
    socket = Enum.reduce(changes, socket, fn {path, events}, acc ->
      handle_file_change(acc, path, events)
    end)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    # Update active users list
    users = Presence.list("project:#{socket.assigns.project.id}:presence")
    {:noreply, assign(socket, :active_users, users)}
  end
  
  defp handle_file_change(socket, path, events) do
    cond do
      MapSet.member?(events, :deleted) ->
        stream_delete_by_dom_id(socket, :files, file_dom_id(path))
        
      MapSet.member?(events, :created) ->
        case load_file_info(socket.assigns.project, path) do
          {:ok, file_info} ->
            stream_insert(socket, :files, file_info)
          _ ->
            socket
        end
        
      MapSet.member?(events, :modified) ->
        case load_file_info(socket.assigns.project, path) do
          {:ok, file_info} ->
            stream_insert(socket, :files, file_info, at: -1)
          _ ->
            socket
        end
        
      true ->
        socket
    end
  end
  
  defp ensure_project_watcher_started(project) do
    case Registry.lookup(MyApp.ProjectRegistry, project.id) do
      [] -> 
        MyApp.ProjectFileWatcher.Supervisor.start_watcher(project)
      _ -> 
        :ok
    end
  end
end
```

## Production deployment: Managing multiple project watchers

Running file watchers for multiple projects requires careful resource management and monitoring:

### Managing FileSystem processes at scale

```elixir
defmodule MyApp.ProjectWatcherManager do
  use GenServer
  require Logger

  @max_watchers 100  # Limit concurrent watchers
  @inactive_timeout :timer.minutes(30)  # Stop watchers after inactivity

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_inactive, @inactive_timeout)
    
    {:ok, %{
      active_watchers: %{},  # project_id => {pid, last_activity}
      watcher_count: 0
    }}
  end
  
  def ensure_watcher_started(project_id) do
    GenServer.call(__MODULE__, {:ensure_started, project_id})
  end
  
  def handle_call({:ensure_started, project_id}, _from, state) do
    case Map.get(state.active_watchers, project_id) do
      {pid, _} when is_pid(pid) and Process.alive?(pid) ->
        # Update last activity
        new_watchers = Map.put(
          state.active_watchers, 
          project_id, 
          {pid, System.system_time(:second)}
        )
        {:reply, {:ok, pid}, %{state | active_watchers: new_watchers}}
        
      _ ->
        if state.watcher_count >= @max_watchers do
          # Find and stop least recently used watcher
          stop_lru_watcher(state)
        end
        
        # Start new watcher
        case start_project_watcher(project_id) do
          {:ok, pid} ->
            new_watchers = Map.put(
              state.active_watchers,
              project_id,
              {pid, System.system_time(:second)}
            )
            {:reply, {:ok, pid}, %{state | 
              active_watchers: new_watchers,
              watcher_count: state.watcher_count + 1
            }}
            
          error ->
            {:reply, error, state}
        end
    end
  end
  
  def handle_info(:cleanup_inactive, state) do
    now = System.system_time(:second)
    cutoff = now - (@inactive_timeout / 1000)
    
    {active, inactive} = Enum.split_with(state.active_watchers, fn {_, {_, last_activity}} ->
      last_activity > cutoff
    end)
    
    # Stop inactive watchers
    Enum.each(inactive, fn {project_id, {pid, _}} ->
      Logger.info("Stopping inactive watcher for project #{project_id}")
      MyApp.ProjectFileWatcher.Supervisor.stop_watcher(project_id)
    end)
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup_inactive, @inactive_timeout)
    
    {:noreply, %{state | 
      active_watchers: Map.new(active),
      watcher_count: length(active)
    }}
  end
end
```

### System resource configuration for multiple projects

```elixir
# config/runtime.exs
if config_env() == :prod do
  # Increase limits for multiple file watchers
  System.put_env("ERL_MAX_PORTS", "131072")  # Increased for many projects
  System.put_env("RLIMIT_NOFILE", "65536")   # File descriptor limit
  
  config :my_app, MyApp.ProjectFileService,
    max_concurrent_projects: 100,
    max_files_per_project: 10_000,
    cache_ttl: :timer.minutes(5),
    # Use different cache strategies for different project sizes
    cache_strategy: :adaptive
end
```

### Project-aware caching system

```elixir
defmodule MyApp.ProjectFileCache do
  @cache_name :project_file_cache
  
  def start_link do
    # Create cache table with project-based partitioning
    :ets.new(@cache_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true},
      {:decentralized_counters, true}  # Better concurrent performance
    ])
  end
  
  def get_or_fetch(project_id, path, ttl \\ 300) do
    key = {project_id, path}
    
    case :ets.lookup(@cache_name, key) do
      [{^key, data, expire_time}] when expire_time > :os.system_time(:seconds) ->
        {:ok, data}
      _ ->
        # Clean up stale entry if exists
        :ets.delete(@cache_name, key)
        fetch_and_cache(project_id, path, ttl)
    end
  end
  
  def invalidate_project(project_id) do
    # Efficiently delete all cache entries for a project
    :ets.match_delete(@cache_name, {{project_id, :_}, :_, :_})
  end
  
  def get_cache_stats do
    projects = :ets.foldl(
      fn {{project_id, _}, _, _}, acc ->
        MapSet.put(acc, project_id)
      end,
      MapSet.new(),
      @cache_name
    )
    
    %{
      total_entries: :ets.info(@cache_name, :size),
      projects_cached: MapSet.size(projects),
      memory_bytes: :ets.info(@cache_name, :memory) * :erlang.system_info(:wordsize)
    }
  end
end
```

## Complete project-based file manager implementation

Here's a production-ready module that combines security, Ash integration, and collaborative features:

```elixir
defmodule MyApp.ProjectFileManager do
  @moduledoc """
  Manages sandboxed file operations for projects with Ash integration
  """
  
  alias MyApp.Workspace
  alias MyApp.ProjectFileAccess
  alias MyApp.ProjectSymlinkSecurity
  
  @max_file_size 50 * 1024 * 1024  # 50MB
  @text_file_extensions ~w(.txt .md .ex .exs .js .jsx .ts .tsx .json .yaml .yml .toml .css .html)
  
  defstruct [:project, :current_user]
  
  def new(project_id, current_user) when is_binary(project_id) do
    with {:ok, project} <- Workspace.get_project(project_id),
         :ok <- authorize_access(project, current_user) do
      {:ok, %__MODULE__{project: project, current_user: current_user}}
    end
  end
  
  def new(%Workspace.Project{} = project, current_user) do
    with :ok <- authorize_access(project, current_user) do
      {:ok, %__MODULE__{project: project, current_user: current_user}}
    end
  end
  
  def read_file(%__MODULE__{project: project} = manager, relative_path) do
    with {:ok, file_path} <- ProjectFileAccess.validate_and_normalize(project, relative_path),
         :ok <- check_file_exists(file_path),
         {:ok, _} <- ProjectSymlinkSecurity.check_symlink_safety(file_path, project),
         {:ok, content} <- read_file_with_size_check(file_path) do
      
      # Log file access for audit trail
      log_file_access(manager, relative_path, :read)
      
      {:ok, %{
        content: content,
        path: relative_path,
        encoding: detect_encoding(content),
        size: byte_size(content),
        mime_type: MIME.from_path(file_path)
      }}
    end
  end
  
  def write_file(%__MODULE__{project: project} = manager, relative_path, content) do
    with {:ok, file_path} <- ProjectFileAccess.validate_and_normalize(project, relative_path),
         :ok <- validate_content_size(content),
         :ok <- ensure_parent_directory_exists(file_path),
         :ok <- check_write_permissions(manager, relative_path) do
      
      # Write atomically
      temp_path = "#{file_path}.tmp.#{:rand.uniform(999999)}"
      
      try do
        File.write!(temp_path, content)
        File.rename!(temp_path, file_path)
        
        # Log write for audit
        log_file_access(manager, relative_path, :write)
        
        # Invalidate cache
        MyApp.ProjectFileCache.invalidate_file(project.id, relative_path)
        
        :ok
      rescue
        error ->
          File.rm(temp_path)
          {:error, error}
      end
    end
  end
  
  def list_directory(%__MODULE__{project: project}, relative_path \\ "") do
    with {:ok, dir_path} <- ProjectFileAccess.validate_and_normalize(project, relative_path),
         {:ok, entries} <- File.ls(dir_path) do
      
      # Check cache first
      cache_key = {project.id, relative_path, :listing}
      
      case MyApp.ProjectFileCache.get(cache_key) do
        {:ok, cached} -> {:ok, cached}
        
        :miss ->
          file_infos = entries
          |> Enum.reject(&String.starts_with?(&1, "."))  # Hide dot files
          |> Enum.map(fn name ->
            full_path = Path.join(dir_path, name)
            build_file_info(full_path, Path.join(relative_path, name), project)
          end)
          |> Enum.filter(&(&1 != nil))
          |> Enum.sort_by(&{&1.type != :directory, &1.name})
          
          # Cache the listing
          MyApp.ProjectFileCache.put(cache_key, file_infos, ttl: 60)
          
          {:ok, file_infos}
      end
    end
  end
  
  def create_directory(%__MODULE__{project: project} = manager, relative_path) do
    with {:ok, dir_path} <- ProjectFileAccess.validate_and_normalize(project, relative_path),
         :ok <- check_write_permissions(manager, relative_path),
         :ok <- File.mkdir_p(dir_path) do
      
      log_file_access(manager, relative_path, :create_directory)
      :ok
    end
  end
  
  def delete_file(%__MODULE__{project: project} = manager, relative_path) do
    with {:ok, file_path} <- ProjectFileAccess.validate_and_normalize(project, relative_path),
         :ok <- check_write_permissions(manager, relative_path),
         :ok <- ensure_not_project_root(relative_path) do
      
      # Move to trash instead of permanent deletion
      trash_path = Path.join([project.root_path, ".trash", timestamp_string(), relative_path])
      File.mkdir_p!(Path.dirname(trash_path))
      
      case File.rename(file_path, trash_path) do
        :ok ->
          log_file_access(manager, relative_path, :delete)
          MyApp.ProjectFileCache.invalidate_file(project.id, relative_path)
          :ok
          
        error -> error
      end
    end
  end
  
  def search_files(%__MODULE__{project: project}, pattern, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 100)
    file_types = Keyword.get(opts, :file_types, :all)
    
    project.root_path
    |> find_files_matching(pattern, file_types)
    |> Enum.take(max_results)
    |> Enum.map(fn path ->
      relative = Path.relative_to(path, project.root_path)
      build_file_info(path, relative, project)
    end)
  end
  
  # Private functions
  
  defp authorize_access(project, user) do
    # Check if user has access to project
    cond do
      project.owner_id == user.id -> :ok
      has_collaborator_access?(project, user) -> :ok
      true -> {:error, :unauthorized}
    end
  end
  
  defp has_collaborator_access?(project, user) do
    Enum.any?(project.collaborators, &(&1.user_id == user.id))
  end
  
  defp check_write_permissions(manager, _relative_path) do
    # Add more granular permission checks here
    if manager.project.owner_id == manager.current_user.id do
      :ok
    else
      # Check collaborator write permissions
      collaborator = Enum.find(
        manager.project.collaborators,
        &(&1.user_id == manager.current_user.id)
      )
      
      if collaborator && collaborator.can_write do
        :ok
      else
        {:error, :write_permission_denied}
      end
    end
  end
  
  defp build_file_info(full_path, relative_path, project) do
    case File.stat(full_path) do
      {:ok, stat} ->
        %{
          name: Path.basename(relative_path),
          path: relative_path,
          type: stat.type,
          size: stat.size,
          modified: stat.mtime,
          mime_type: get_mime_type(full_path, stat.type),
          readable: is_text_file?(full_path),
          project_id: project.id
        }
      _ ->
        nil
    end
  end
  
  defp is_text_file?(path) do
    ext = String.downcase(Path.extname(path))
    ext in @text_file_extensions
  end
  
  defp read_file_with_size_check(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_file_size ->
        {:error, :file_too_large}
      {:ok, _} ->
        # Use raw file operations for better performance
        read_file_raw(path)
      error ->
        error
    end
  end
  
  defp read_file_raw(path) do
    with {:ok, io} <- :file.open(path, [:raw, :binary, :read]),
         {:ok, content} <- :file.read(io, :all),
         :ok <- :file.close(io) do
      {:ok, content}
    end
  end
  
  defp log_file_access(manager, path, action) do
    :telemetry.execute(
      [:my_app, :file_access],
      %{count: 1},
      %{
        project_id: manager.project.id,
        user_id: manager.current_user.id,
        path: path,
        action: action
      }
    )
  end
end
```

## Monitoring and rate limiting strategies

Production systems require comprehensive monitoring and abuse prevention:

```elixir
defmodule MyApp.FileOperationMonitor do
  def instrument_operation(operation, path, func) do
    start_time = System.monotonic_time()
    
    result = func.()
    
    duration = System.monotonic_time() - start_time
    
    :telemetry.execute(
      [:my_app, :file, operation],
      %{duration: duration},
      %{path: path, result: elem(result, 0)}
    )
    
    result
  end
end

# Rate limiting with Hammer
defmodule MyAppWeb.FileAccessPlug do
  import Plug.Conn
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)
    key = "file_access:#{user_id}"
    
    case Hammer.check_rate(key, 60_000, 100) do  # 100 operations per minute
      {:allow, _count} ->
        conn
      {:deny, _limit} ->
        conn
        |> put_status(429)
        |> json(%{error: "Rate limit exceeded"})
        |> halt()
    end
  end
end
```

## Key architectural decisions for production

After extensive research and real-world testing, several critical patterns emerge for production deployments:

**Use raw file operations** whenever possible to bypass the BEAM's single file_server bottleneck. This dramatically improves concurrent file access performance.

**Implement multi-layer validation** combining Path.safe_relative/2, symlink detection, and final path verification. Security requires defense in depth.

**Cache aggressively but intelligently** using ETS for metadata and directory listings. File operations are expensive; minimize actual filesystem touches.

**Monitor everything** through Telemetry integration. File operations can be slow and resource-intensive - visibility is crucial for maintaining performance.

**Design for horizontal scaling** by keeping file operations stateless and using external storage (S3, NFS) for distributed deployments.

This architecture provides a robust foundation for building secure, performant file management features in Phoenix applications while leveraging Elixir's strengths in concurrency and fault tolerance.
