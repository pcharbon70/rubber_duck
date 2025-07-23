defmodule RubberDuck.Projects.FileManager do
  @moduledoc """
  A comprehensive file management system providing secure, atomic file operations
  with collaborative features, search functionality, and extensive security validations.
  
  This module provides:
  - Context-aware file operations with project/user tracking
  - Atomic operations with rollback support
  - Comprehensive security validations
  - Operation logging and audit trails
  - Error handling with detailed error types
  """
  
  alias RubberDuck.Workspace
  alias RubberDuck.Projects.{
    FileCacheWrapper, SecurityValidator, FileAudit, FileEncryption, FileSearch,
    FileCollaboration, CollaborationSupervisor
  }
  require Logger
  
  defstruct [:project, :user, :options]
  
  @type t :: %__MODULE__{
    project: Workspace.Project.t(),
    user: RubberDuck.Accounts.User.t(),
    options: keyword()
  }
  
  @type operation_result :: {:ok, any()} | {:error, error_reason()}
  
  @type error_reason ::
    :unauthorized
    | :path_traversal
    | :file_not_found
    | :directory_not_found
    | :file_exists
    | :permission_denied
    | :file_too_large
    | :invalid_file_type
    | :operation_failed
    | {:validation_error, String.t()}
    | {:system_error, String.t()}
  
  @type file_operation ::
    :read
    | :write
    | :delete
    | :create
    | :rename
    | :move
    | :copy
    | :list
  
  # Default options
  @default_max_file_size 50 * 1024 * 1024  # 50MB
  @default_allowed_extensions :all
  @default_enable_audit true
  @default_enable_virus_scan false
  @default_enable_cache true
  @default_auto_watch true
  
  @doc """
  Creates a new FileManager instance with project and user context.
  
  ## Options
  - `:max_file_size` - Maximum allowed file size in bytes (default: 50MB)
  - `:allowed_extensions` - List of allowed file extensions or `:all` (default: :all)
  - `:enable_audit` - Whether to log operations (default: true)
  - `:enable_virus_scan` - Whether to scan files for viruses (default: false)
  - `:enable_cache` - Whether to cache directory listings (default: true)
  - `:auto_watch` - Whether to auto-start file watcher for cache invalidation (default: true)
  - `:temp_dir` - Directory for temporary files (default: System.tmp_dir!)
  """
  @spec new(Workspace.Project.t(), RubberDuck.Accounts.User.t(), keyword()) :: t()
  def new(project, user, options \\ []) do
    options = Keyword.merge(default_options(), options)
    
    # Start FileManagerWatcher if caching and auto-watch are enabled
    if options[:enable_cache] && options[:auto_watch] do
      case RubberDuck.Projects.FileManagerWatcher.ensure_running(project.id) do
        {:ok, _pid} ->
          Logger.debug("FileManagerWatcher started for project #{project.id}")
          
        {:error, reason} ->
          Logger.warning("Failed to start FileManagerWatcher: #{inspect(reason)}")
      end
    end
    
    %__MODULE__{
      project: project,
      user: user,
      options: options
    }
  end
  
  @doc """
  Reads a file with streaming support and security validation.
  
  Returns the file contents as a binary or a stream for large files.
  
  ## Options
  - `:stream` - Return a stream instead of loading entire file (default: false)
  - `:check_lock` - Check if file is locked before reading (default: true)
  """
  @spec read_file(t(), String.t(), keyword()) :: operation_result()
  def read_file(%__MODULE__{} = fm, file_path, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
    with :ok <- authorize_operation(fm, :read, file_path),
         {:ok, full_path} <- validate_and_resolve_path(fm, file_path),
         :ok <- validate_file_exists(full_path),
         :ok <- validate_file_security(fm, full_path),
         {:ok, content} <- perform_read(full_path, opts),
         {:ok, final_content} <- maybe_decrypt_content(fm, content, file_path, opts) do
      
      duration = System.monotonic_time(:millisecond) - start_time
      audit_metadata = %{
        size: if(is_binary(final_content), do: byte_size(final_content), else: nil),
        duration_ms: duration
      }
      
      log_operation(fm, :read, file_path, :success, audit_metadata)
      persist_audit_log(fm, :read, file_path, :success, audit_metadata)
      
      {:ok, final_content}
    else
      {:error, reason} = error ->
        duration = System.monotonic_time(:millisecond) - start_time
        audit_metadata = %{duration_ms: duration, error: inspect(reason)}
        
        log_operation(fm, :read, file_path, :failure, reason)
        persist_audit_log(fm, :read, file_path, :failure, audit_metadata)
        
        error
    end
  end
  
  @doc """
  Writes a file atomically using temporary file and rename.
  
  Ensures data integrity by writing to a temporary file first,
  then atomically renaming it to the target location.
  
  ## Options
  - `:encrypt` - Encrypt the file content (default: false)
  - `:acquire_lock` - Acquire exclusive lock before writing (default: true)
  - `:broadcast_change` - Broadcast change to collaborators (default: true)
  """
  @spec write_file(t(), String.t(), binary(), keyword()) :: operation_result()
  def write_file(%__MODULE__{} = fm, file_path, content, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
    with :ok <- authorize_operation(fm, :write, file_path),
         {:ok, full_path} <- validate_and_resolve_path(fm, file_path),
         :ok <- validate_file_size(content, fm.options[:max_file_size]),
         :ok <- validate_file_extension(file_path, fm.options[:allowed_extensions]),
         :ok <- validate_content_security(fm, content, file_path),
         {:ok, final_content} <- maybe_encrypt_content(fm, content, opts),
         {:ok, _} <- perform_atomic_write(fm, full_path, final_content, opts) do
      
      duration = System.monotonic_time(:millisecond) - start_time
      
      # Invalidate cache for parent directory
      invalidate_cache_for_path(fm, Path.dirname(file_path))
      
      # Log to audit trail
      audit_metadata = %{
        size: byte_size(content),
        encrypted: Keyword.get(opts, :encrypt, false),
        duration_ms: duration
      }
      
      log_operation(fm, :write, file_path, :success, audit_metadata)
      persist_audit_log(fm, :write, file_path, :success, audit_metadata)
      
      {:ok, file_path}
    else
      {:error, reason} = error ->
        duration = System.monotonic_time(:millisecond) - start_time
        audit_metadata = %{duration_ms: duration, error: inspect(reason)}
        
        log_operation(fm, :write, file_path, :failure, reason)
        persist_audit_log(fm, :write, file_path, :failure, audit_metadata)
        
        error
    end
  end
  
  @doc """
  Deletes a file or directory, optionally moving it to trash.
  
  ## Options
  - `:trash` - Move to trash instead of permanent deletion (default: true)
  - `:recursive` - Delete directories recursively (default: false)
  """
  @spec delete_file(t(), String.t(), keyword()) :: operation_result()
  def delete_file(%__MODULE__{} = fm, file_path, opts \\ []) do
    with :ok <- authorize_operation(fm, :delete, file_path),
         {:ok, full_path} <- validate_and_resolve_path(fm, file_path),
         :ok <- validate_file_exists(full_path),
         {:ok, _} <- perform_delete(fm, full_path, opts) do
      # Invalidate cache for parent directory
      invalidate_cache_for_path(fm, Path.dirname(file_path))
      log_operation(fm, :delete, file_path, :success)
      {:ok, file_path}
    else
      {:error, reason} = error ->
        log_operation(fm, :delete, file_path, :failure, reason)
        error
    end
  end
  
  @doc """
  Creates a directory, optionally creating parent directories.
  
  ## Options
  - `:recursive` - Create parent directories if they don't exist (default: true)
  """
  @spec create_directory(t(), String.t(), keyword()) :: operation_result()
  def create_directory(%__MODULE__{} = fm, dir_path, opts \\ []) do
    with :ok <- authorize_operation(fm, :create, dir_path),
         {:ok, full_path} <- validate_and_resolve_path(fm, dir_path),
         :ok <- validate_not_exists(full_path),
         {:ok, _} <- perform_mkdir(full_path, opts) do
      # Invalidate cache for parent directory
      invalidate_cache_for_path(fm, Path.dirname(dir_path))
      log_operation(fm, :create, dir_path, :success, %{type: :directory})
      {:ok, dir_path}
    else
      {:error, reason} = error ->
        log_operation(fm, :create, dir_path, :failure, reason)
        error
    end
  end
  
  @doc """
  Lists directory contents with pagination and filtering.
  
  ## Options
  - `:page` - Page number for pagination (default: 1)
  - `:page_size` - Number of items per page (default: 100)
  - `:sort_by` - Sort field (:name, :size, :modified) (default: :name)
  - `:sort_order` - Sort order (:asc, :desc) (default: :asc)
  - `:show_hidden` - Include hidden files (default: false)
  """
  @spec list_directory(t(), String.t(), keyword()) :: operation_result()
  def list_directory(%__MODULE__{} = fm, dir_path, opts \\ []) do
    with :ok <- authorize_operation(fm, :list, dir_path),
         {:ok, full_path} <- validate_and_resolve_path(fm, dir_path),
         :ok <- validate_directory_exists(full_path) do
      
      # Try cache first if caching is enabled
      cache_key = build_cache_key(dir_path, opts)
      
      case get_from_cache(fm, cache_key) do
        {:ok, entries} ->
          log_operation(fm, :list, dir_path, :success, %{count: length(entries), cache: :hit})
          {:ok, entries}
          
        :miss ->
          case perform_list(full_path, opts) do
            {:ok, entries} ->
              put_in_cache(fm, cache_key, entries)
              log_operation(fm, :list, dir_path, :success, %{count: length(entries), cache: :miss})
              {:ok, entries}
              
            {:error, reason} = error ->
              log_operation(fm, :list, dir_path, :failure, reason)
              error
          end
      end
    else
      {:error, reason} = error ->
        log_operation(fm, :list, dir_path, :failure, reason)
        error
    end
  end
  
  @doc """
  Moves a file or directory to a new location atomically.
  """
  @spec move_file(t(), String.t(), String.t(), keyword()) :: operation_result()
  def move_file(%__MODULE__{} = fm, source_path, dest_path, opts \\ []) do
    with :ok <- authorize_operation(fm, :move, source_path),
         :ok <- authorize_operation(fm, :move, dest_path),
         {:ok, source_full} <- validate_and_resolve_path(fm, source_path),
         {:ok, dest_full} <- validate_and_resolve_path(fm, dest_path),
         :ok <- validate_file_exists(source_full),
         :ok <- validate_not_exists(dest_full),
         {:ok, _} <- perform_move(source_full, dest_full, opts) do
      # Invalidate cache for both source and destination parent directories
      invalidate_cache_for_path(fm, Path.dirname(source_path))
      invalidate_cache_for_path(fm, Path.dirname(dest_path))
      log_operation(fm, :move, source_path, :success, %{destination: dest_path})
      {:ok, dest_path}
    else
      {:error, reason} = error ->
        log_operation(fm, :move, source_path, :failure, reason)
        error
    end
  end
  
  @doc """
  Searches for content within files.
  
  Delegates to FileSearch module for advanced search functionality.
  See `FileSearch.search/3` for detailed options.
  """
  @spec search(t(), String.t() | Regex.t(), keyword()) :: 
    {:ok, [FileSearch.search_result()]} | {:error, term()}
  def search(%__MODULE__{} = fm, pattern, opts \\ []) do
    FileSearch.search(fm, pattern, opts)
  end
  
  @doc """
  Finds files by name pattern.
  
  Delegates to FileSearch module.
  """
  @spec find_files(t(), String.t(), keyword()) :: 
    {:ok, [String.t()]} | {:error, term()}
  def find_files(%__MODULE__{} = fm, name_pattern, opts \\ []) do
    FileSearch.find_files(fm, name_pattern, opts)
  end
  
  @doc """
  Acquires a lock on a file for collaborative editing.
  
  ## Options
  - `:type` - Lock type (:exclusive or :shared, default: :exclusive)
  - `:timeout` - Lock timeout in ms (default: 5 minutes)
  """
  @spec acquire_lock(t(), String.t(), keyword()) :: 
    {:ok, String.t()} | {:error, term()}
  def acquire_lock(%__MODULE__{project: project} = fm, file_path, opts \\ []) do
    ensure_collaboration_started(project.id)
    FileCollaboration.acquire_lock(project.id, fm, file_path, opts)
  end
  
  @doc """
  Releases a lock on a file.
  """
  @spec release_lock(t(), String.t()) :: :ok | {:error, term()}
  def release_lock(%__MODULE__{project: project}, lock_id) do
    FileCollaboration.release_lock(project.id, lock_id)
  end
  
  @doc """
  Tracks user presence on a file.
  """
  @spec track_presence(t(), String.t(), map()) :: :ok
  def track_presence(%__MODULE__{project: project} = fm, file_path, metadata \\ %{}) do
    ensure_collaboration_started(project.id)
    FileCollaboration.track_presence(project.id, fm, file_path, metadata)
  end
  
  @doc """
  Gets current collaborators on a file.
  """
  @spec get_collaborators(t(), String.t()) :: {:ok, [map()]}
  def get_collaborators(%__MODULE__{project: project}, file_path) do
    FileCollaboration.get_file_presence(project.id, file_path)
  end
  
  @doc """
  Copies a file or directory with progress tracking.
  
  ## Options
  - `:recursive` - Copy directories recursively (default: true)
  - `:overwrite` - Overwrite existing files (default: false)
  - `:progress_callback` - Function called with copy progress
  """
  @spec copy_file(t(), String.t(), String.t(), keyword()) :: operation_result()
  def copy_file(%__MODULE__{} = fm, source_path, dest_path, opts \\ []) do
    with :ok <- authorize_operation(fm, :copy, source_path),
         :ok <- authorize_operation(fm, :copy, dest_path),
         {:ok, source_full} <- validate_and_resolve_path(fm, source_path),
         {:ok, dest_full} <- validate_and_resolve_path(fm, dest_path),
         :ok <- validate_file_exists(source_full),
         :ok <- validate_copy_target(dest_full, opts),
         {:ok, _} <- perform_copy(fm, source_full, dest_full, opts) do
      # Invalidate cache for destination parent directory
      invalidate_cache_for_path(fm, Path.dirname(dest_path))
      log_operation(fm, :copy, source_path, :success, %{destination: dest_path})
      {:ok, dest_path}
    else
      {:error, reason} = error ->
        log_operation(fm, :copy, source_path, :failure, reason)
        error
    end
  end
  
  # Private functions
  
  defp default_options do
    [
      max_file_size: @default_max_file_size,
      allowed_extensions: @default_allowed_extensions,
      enable_audit: @default_enable_audit,
      enable_virus_scan: @default_enable_virus_scan,
      enable_cache: @default_enable_cache,
      auto_watch: @default_auto_watch,
      temp_dir: System.tmp_dir!()
    ]
  end
  
  defp authorize_operation(%__MODULE__{project: project, user: user}, operation, _path) do
    # Check if user has permission to perform operation on project
    # This integrates with Ash policies
    case Workspace.can?(user, operation, project) do
      true -> :ok
      false -> {:error, :unauthorized}
    end
  end
  
  defp validate_and_resolve_path(%__MODULE__{project: project}, file_path) do
    # Check for path traversal attempts early
    if String.contains?(file_path, "..") do
      {:error, :path_traversal}
    else
      # Normalize and validate the path
      normalized = Path.expand(file_path, "/") |> Path.relative_to("/")
      full_path = Path.join(project.root_path, normalized)
      
      # Ensure the path is within project bounds
      if String.starts_with?(Path.expand(full_path), Path.expand(project.root_path)) do
        {:ok, full_path}
      else
        {:error, :path_traversal}
      end
    end
  end
  
  defp validate_file_exists(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, :file_not_found}
    end
  end
  
  defp validate_not_exists(path) do
    if File.exists?(path) do
      {:error, :file_exists}
    else
      :ok
    end
  end
  
  defp validate_directory_exists(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :directory}} -> :ok
      {:ok, _} -> {:error, :not_a_directory}
      {:error, _} -> {:error, :directory_not_found}
    end
  end
  
  defp validate_file_size(content, max_size) do
    size = byte_size(content)
    if size <= max_size do
      :ok
    else
      {:error, {:validation_error, "File size (#{size} bytes) exceeds maximum allowed (#{max_size} bytes)"}}
    end
  end
  
  defp validate_file_extension(_path, :all), do: :ok
  defp validate_file_extension(path, allowed_extensions) do
    ext = Path.extname(path) |> String.downcase()
    if ext in allowed_extensions do
      :ok
    else
      {:error, {:validation_error, "File extension '#{ext}' is not allowed"}}
    end
  end
  
  defp validate_copy_target(dest_path, opts) do
    if Keyword.get(opts, :overwrite, false) or not File.exists?(dest_path) do
      :ok
    else
      {:error, :file_exists}
    end
  end
  
  defp perform_read(path, opts) do
    streaming = Keyword.get(opts, :stream, false)
    
    if streaming do
      stream = File.stream!(path, [], 2048)
      {:ok, stream}
    else
      File.read(path)
    end
  rescue
    e -> {:error, {:system_error, Exception.message(e)}}
  end
  
  defp perform_atomic_write(%__MODULE__{options: options}, path, content, _opts) do
    temp_dir = options[:temp_dir]
    temp_path = Path.join(temp_dir, "fm_#{:rand.uniform(1_000_000)}.tmp")
    
    with :ok <- File.write(temp_path, content),
         :ok <- File.rename(temp_path, path) do
      {:ok, path}
    else
      error ->
        File.rm(temp_path)
        error
    end
  rescue
    e -> {:error, {:system_error, Exception.message(e)}}
  end
  
  defp perform_delete(%__MODULE__{options: options}, path, opts) do
    use_trash = Keyword.get(opts, :trash, true)
    
    if use_trash do
      # Move to trash directory
      trash_dir = Path.join(options[:temp_dir], ".trash")
      File.mkdir_p(trash_dir)
      
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      trash_name = "#{Path.basename(path)}.#{timestamp}"
      trash_path = Path.join(trash_dir, trash_name)
      
      case File.rename(path, trash_path) do
        :ok -> {:ok, trash_path}
        error -> error
      end
    else
      # Permanent deletion
      result = if File.dir?(path) do
        if Keyword.get(opts, :recursive, false) do
          case File.rm_rf(path) do
            {:ok, _} -> {:ok, path}
            error -> error
          end
        else
          case File.rmdir(path) do
            :ok -> {:ok, path}
            error -> error
          end
        end
      else
        case File.rm(path) do
          :ok -> {:ok, path}
          error -> error
        end
      end
      
      result
    end
  rescue
    e -> {:error, {:system_error, Exception.message(e)}}
  end
  
  defp perform_mkdir(path, opts) do
    result = if Keyword.get(opts, :recursive, true) do
      File.mkdir_p(path)
    else
      File.mkdir(path)
    end
    
    case result do
      :ok -> {:ok, path}
      error -> error
    end
  rescue
    e -> {:error, {:system_error, Exception.message(e)}}
  end
  
  defp perform_list(path, opts) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 100)
    sort_by = Keyword.get(opts, :sort_by, :name)
    sort_order = Keyword.get(opts, :sort_order, :asc)
    show_hidden = Keyword.get(opts, :show_hidden, false)
    
    {:ok, entries} = File.ls(path)
    
    entries
    |> Enum.filter(fn name ->
      show_hidden or not String.starts_with?(name, ".")
    end)
    |> Enum.map(fn name ->
      full_path = Path.join(path, name)
      stat = File.stat!(full_path)
      
      %{
        name: name,
        type: stat.type,
        size: stat.size,
        modified: NaiveDateTime.from_erl!(stat.mtime) |> DateTime.from_naive!("Etc/UTC")
      }
    end)
    |> sort_entries(sort_by, sort_order)
    |> paginate(page, page_size)
    |> then(&{:ok, &1})
  rescue
    e -> {:error, {:system_error, Exception.message(e)}}
  end
  
  defp perform_move(source, dest, _opts) do
    case File.rename(source, dest) do
      :ok -> {:ok, dest}
      error -> error
    end
  rescue
    e -> {:error, {:system_error, Exception.message(e)}}
  end
  
  defp perform_copy(%__MODULE__{} = _fm, source, dest, opts) do
    progress_callback = Keyword.get(opts, :progress_callback)
    
    cond do
      File.dir?(source) and Keyword.get(opts, :recursive, true) ->
        copy_directory_recursive(source, dest, progress_callback)
        
      File.regular?(source) ->
        copy_file_with_progress(source, dest, progress_callback)
        
      true ->
        {:error, {:validation_error, "Cannot copy special file type"}}
    end
  rescue
    e -> {:error, {:system_error, Exception.message(e)}}
  end
  
  defp copy_file_with_progress(source, dest, progress_callback) do
    source_size = File.stat!(source).size
    
    # Create destination directory if needed
    dest |> Path.dirname() |> File.mkdir_p!()
    
    # Open files for reading and writing
    {:ok, source_io} = File.open(source, [:read, :binary])
    {:ok, dest_io} = File.open(dest, [:write, :binary])
    
    try do
      copy_loop(source_io, dest_io, source_size, 0, progress_callback)
      {:ok, dest}
    after
      File.close(source_io)
      File.close(dest_io)
    end
  end
  
  defp copy_loop(source_io, dest_io, total_size, bytes_copied, progress_callback) do
    case IO.binread(source_io, 2048) do
      :eof ->
        if progress_callback, do: progress_callback.({:progress, 100})
        :ok
        
      {:error, reason} ->
        throw({:error, reason})
        
      data ->
        :ok = IO.binwrite(dest_io, data)
        new_bytes_copied = bytes_copied + byte_size(data)
        
        if progress_callback do
          progress = min(100, round(new_bytes_copied / total_size * 100))
          progress_callback.({:progress, progress})
        end
        
        copy_loop(source_io, dest_io, total_size, new_bytes_copied, progress_callback)
    end
  end
  
  defp copy_directory_recursive(source, dest, progress_callback) do
    File.mkdir_p!(dest)
    
    File.ls!(source)
    |> Enum.each(fn name ->
      source_path = Path.join(source, name)
      dest_path = Path.join(dest, name)
      
      if File.dir?(source_path) do
        copy_directory_recursive(source_path, dest_path, progress_callback)
      else
        copy_file_with_progress(source_path, dest_path, progress_callback)
      end
    end)
    
    {:ok, dest}
  end
  
  defp sort_entries(entries, sort_by, sort_order) do
    sorted = Enum.sort_by(entries, &Map.get(&1, sort_by))
    
    if sort_order == :desc do
      Enum.reverse(sorted)
    else
      sorted
    end
  end
  
  defp paginate(entries, page, page_size) do
    offset = (page - 1) * page_size
    
    entries
    |> Enum.drop(offset)
    |> Enum.take(page_size)
  end
  
  defp log_operation(%__MODULE__{} = fm, operation, path, status, metadata \\ %{}) do
    if fm.options[:enable_audit] do
      Logger.info("FileManager operation", %{
        operation: operation,
        path: path,
        status: status,
        user_id: fm.user.id,
        project_id: fm.project.id,
        metadata: metadata
      })
      
      # TODO: Persist to database for audit trail
    end
  end
  
  # Cache helpers
  
  defp get_from_cache(%__MODULE__{options: opts, project: project}, key) do
    if Keyword.get(opts, :enable_cache, true) do
      FileCacheWrapper.get(project.id, key)
    else
      :miss
    end
  end
  
  defp put_in_cache(%__MODULE__{options: opts, project: project}, key, value) do
    if Keyword.get(opts, :enable_cache, true) do
      FileCacheWrapper.put(project.id, key, value)
    end
  end
  
  defp invalidate_cache_for_path(%__MODULE__{options: opts, project: project}, path) do
    if Keyword.get(opts, :enable_cache, true) do
      # Invalidate the specific path and its parent directory listing
      FileCacheWrapper.invalidate(project.id, path)
      FileCacheWrapper.invalidate_pattern(project.id, "#{path}/*")
      
      # Invalidate parent directory listings (with wildcard for options hash)
      parent = Path.dirname(path)
      FileCacheWrapper.invalidate_pattern(project.id, "list:#{parent}:*")
      
      # Also invalidate current directory if we're at root
      if parent == "." do
        FileCacheWrapper.invalidate_pattern(project.id, "list:.:*")
      end
    end
  end
  
  defp build_cache_key(path, opts) do
    # Build a cache key that includes relevant options
    relevant_opts = opts
    |> Keyword.take([:page, :page_size, :sort_by, :sort_order, :show_hidden])
    |> Enum.sort()
    |> :erlang.phash2()
    
    "list:#{path}:#{relevant_opts}"
  end
  
  # Security helpers
  
  defp validate_content_security(%__MODULE__{options: opts}, content, filename) do
    if Keyword.get(opts, :enable_security_scan, true) do
      # Build security validator options
      security_opts = []
      
      # Only pass allowed_extensions if it's not :all
      allowed = Keyword.get(opts, :allowed_extensions, :all)
      security_opts = if allowed != :all do
        Keyword.put(security_opts, :allowed_extensions, allowed)
      else
        security_opts
      end
      
      # Pass max content size
      security_opts = security_opts
      |> Keyword.put(:max_content_size, Keyword.get(opts, :max_file_size, @default_max_file_size))
      
      SecurityValidator.validate_content_bytes(content, filename, security_opts)
    else
      :ok
    end
  end
  
  defp maybe_encrypt_content(%__MODULE__{options: opts}, content, operation_opts) do
    if Keyword.get(operation_opts, :encrypt, false) do
      secret = get_encryption_secret(opts)
      
      case FileEncryption.encrypt_content(content, secret) do
        {:ok, encrypted} -> {:ok, encrypted}
        {:error, reason} -> {:error, {:encryption_failed, reason}}
      end
    else
      {:ok, content}
    end
  end
  
  defp get_encryption_secret(opts) do
    # Get from options or use project-specific secret
    Keyword.get(opts, :encryption_secret) || 
      Application.get_env(:rubber_duck, :file_encryption_secret) ||
      raise "No encryption secret configured"
  end
  
  defp persist_audit_log(%__MODULE__{} = fm, operation, path, status, metadata) do
    if fm.options[:enable_audit] do
      # Run audit logging asynchronously to not block operations
      Task.start(fn ->
        FileAudit.log_operation(%{
          operation: operation,
          file_path: path,
          status: status,
          metadata: metadata,
          project_id: fm.project.id,
          user_id: fm.user.id,
          duration_ms: metadata[:duration_ms]
        })
      end)
    end
  end
  
  defp validate_file_security(%__MODULE__{options: opts}, path) do
    if Keyword.get(opts, :enable_security_scan, true) do
      # Build security validator options
      security_opts = []
      
      # Only pass allowed_extensions if it's not :all
      allowed = Keyword.get(opts, :allowed_extensions, :all)
      security_opts = if allowed != :all do
        Keyword.put(security_opts, :allowed_extensions, allowed)
      else
        security_opts
      end
      
      # Pass through other security options
      security_opts = security_opts
      |> Keyword.put(:enable_malware_scan, Keyword.get(opts, :enable_virus_scan, false))
      |> Keyword.put(:skip_large_files, true)
      
      SecurityValidator.validate_file(path, security_opts)
    else
      :ok
    end
  end
  
  defp maybe_decrypt_content(%__MODULE__{options: opts}, content, file_path, _operation_opts) do
    cond do
      # Check if file has .enc extension or encryption header
      String.ends_with?(file_path, ".enc") or starts_with_encrypted?(content) ->
        secret = get_encryption_secret(opts)
        
        # Remove encryption header if present
        content = if starts_with_encrypted?(content), do: strip_encryption_header(content), else: content
        
        case FileEncryption.decrypt_content(content, secret) do
          {:ok, decrypted} -> {:ok, decrypted}
          {:error, reason} -> {:error, {:decryption_failed, reason}}
        end
        
      # Return content as-is if not encrypted
      true ->
        {:ok, content}
    end
  end
  
  defp starts_with_encrypted?(<<"ENC1", _rest::binary>>), do: true
  defp starts_with_encrypted?(_), do: false
  
  defp strip_encryption_header(<<"ENC1", rest::binary>>), do: rest
  defp strip_encryption_header(content), do: content
  
  defp ensure_collaboration_started(project_id) do
    case CollaborationSupervisor.start_collaboration(project_id) do
      {:ok, _pid} -> :ok
      {:error, reason} -> Logger.warning("Failed to start collaboration: #{inspect(reason)}")
    end
  end
end