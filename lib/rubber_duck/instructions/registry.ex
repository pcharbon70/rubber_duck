defmodule RubberDuck.Instructions.Registry do
  @moduledoc """
  Centralized registry for managing loaded instruction files.

  Provides tracking of loaded instructions, version management,
  duplicate handling, and hot reloading capabilities.

  ## Features

  - Thread-safe instruction storage using ETS
  - Version tracking with content hashing
  - Duplicate detection and resolution
  - Hot reloading with file system monitoring
  - Rule activation and deactivation
  - Performance metrics and monitoring
  """

  use GenServer
  require Logger
  alias RubberDuck.Instructions.FileManager

  @type instruction_id :: String.t()
  @type instruction_entry :: %{
          id: instruction_id(),
          file: FileManager.instruction_file(),
          version: String.t(),
          loaded_at: DateTime.t(),
          active: boolean(),
          usage_count: integer(),
          last_used: DateTime.t()
        }

  # ETS table names
  @instructions_table :instruction_registry
  @versions_table :instruction_versions
  @metrics_table :instruction_metrics

  # Registry state
  defstruct [
    :instructions_table,
    :versions_table,
    :metrics_table,
    :file_watcher_pid,
    :monitored_paths,
    :auto_reload,
    :stats
  ]

  ## Public API

  @doc """
  Starts the instruction registry server.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Loads instructions from the specified path into the registry.

  Returns the number of instructions loaded.
  """
  @spec load_instructions(String.t(), keyword()) :: {:ok, integer()} | {:error, term()}
  def load_instructions(path, opts \\ []) do
    GenServer.call(__MODULE__, {:load_instructions, path, opts})
  end

  @doc """
  Registers a single instruction file in the registry.
  """
  @spec register_instruction(FileManager.instruction_file()) :: {:ok, instruction_id()} | {:error, term()}
  def register_instruction(instruction_file) do
    GenServer.call(__MODULE__, {:register_instruction, instruction_file})
  end

  @doc """
  Retrieves an instruction by its ID.
  """
  @spec get_instruction(instruction_id()) :: {:ok, instruction_entry()} | {:error, :not_found}
  def get_instruction(instruction_id) do
    case :ets.lookup(@instructions_table, instruction_id) do
      [{^instruction_id, entry}] -> {:ok, entry}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Lists all registered instructions, optionally filtered by criteria.

  ## Options

  - `:type` - Filter by instruction type (:always, :auto, :agent, :manual)
  - `:scope` - Filter by scope (:project, :workspace, :global, :directory)
  - `:active` - Filter by active status (true/false)
  - `:limit` - Limit number of results
  """
  @spec list_instructions(keyword()) :: [instruction_entry()]
  def list_instructions(opts \\ []) do
    GenServer.call(__MODULE__, {:list_instructions, opts})
  end

  @doc """
  Activates an instruction for use.
  """
  @spec activate_instruction(instruction_id()) :: :ok | {:error, term()}
  def activate_instruction(instruction_id) do
    GenServer.call(__MODULE__, {:activate_instruction, instruction_id})
  end

  @doc """
  Deactivates an instruction.
  """
  @spec deactivate_instruction(instruction_id()) :: :ok | {:error, term()}
  def deactivate_instruction(instruction_id) do
    GenServer.call(__MODULE__, {:deactivate_instruction, instruction_id})
  end

  @doc """
  Removes an instruction from the registry.
  """
  @spec unregister_instruction(instruction_id()) :: :ok | {:error, term()}
  def unregister_instruction(instruction_id) do
    GenServer.call(__MODULE__, {:unregister_instruction, instruction_id})
  end

  @doc """
  Reloads an instruction from disk.
  """
  @spec reload_instruction(instruction_id()) :: {:ok, instruction_entry()} | {:error, term()}
  def reload_instruction(instruction_id) do
    GenServer.call(__MODULE__, {:reload_instruction, instruction_id})
  end

  @doc """
  Returns registry statistics and metrics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Enables or disables auto-reloading of instructions when files change.
  """
  @spec set_auto_reload(boolean()) :: :ok
  def set_auto_reload(enabled) do
    GenServer.call(__MODULE__, {:set_auto_reload, enabled})
  end

  ## GenServer Callbacks

  @impl GenServer
  def init(opts) do
    # Create ETS tables
    instructions_table = :ets.new(@instructions_table, [:named_table, :set, :public, read_concurrency: true])
    versions_table = :ets.new(@versions_table, [:named_table, :set, :public])
    metrics_table = :ets.new(@metrics_table, [:named_table, :set, :public])

    auto_reload = Keyword.get(opts, :auto_reload, false)

    state = %__MODULE__{
      instructions_table: instructions_table,
      versions_table: versions_table,
      metrics_table: metrics_table,
      file_watcher_pid: nil,
      monitored_paths: MapSet.new(),
      auto_reload: auto_reload,
      stats: init_stats()
    }

    Logger.info("Instruction registry started")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:load_instructions, path, opts}, _from, state) do
    case FileManager.discover_files(path, opts) do
      {:ok, files} ->
        {loaded_count, new_state} = load_instruction_files(files, state)
        {:reply, {:ok, loaded_count}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:register_instruction, instruction_file}, _from, state) do
    case register_instruction_file(instruction_file, state) do
      {:ok, instruction_id, new_state} ->
        {:reply, {:ok, instruction_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:list_instructions, opts}, _from, state) do
    instructions = list_instructions_with_filters(opts)
    {:reply, instructions, state}
  end

  @impl GenServer
  def handle_call({:activate_instruction, instruction_id}, _from, state) do
    case update_instruction_status(instruction_id, true) do
      :ok ->
        increment_metric(:activations)
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:deactivate_instruction, instruction_id}, _from, state) do
    case update_instruction_status(instruction_id, false) do
      :ok ->
        increment_metric(:deactivations)
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:unregister_instruction, instruction_id}, _from, state) do
    case unregister_instruction_by_id(instruction_id) do
      :ok ->
        new_state = remove_from_monitoring(instruction_id, state)
        increment_metric(:unregistrations)
        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:reload_instruction, instruction_id}, _from, state) do
    case reload_instruction_by_id(instruction_id) do
      {:ok, entry} ->
        increment_metric(:reloads)
        {:reply, {:ok, entry}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = get_current_stats(state)
    {:reply, stats, state}
  end

  @impl GenServer
  def handle_call({:set_auto_reload, enabled}, _from, state) do
    new_state = %{state | auto_reload: enabled}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info({:file_changed, file_path}, %{auto_reload: true} = state) do
    Logger.debug("File changed: #{file_path}, reloading instruction")

    case find_instruction_by_path(file_path) do
      {:ok, instruction_id} ->
        case reload_instruction_by_id(instruction_id) do
          {:ok, _entry} ->
            increment_metric(:auto_reloads)
            Logger.info("Auto-reloaded instruction: #{instruction_id}")

          {:error, reason} ->
            Logger.warning("Failed to auto-reload instruction #{instruction_id}: #{inspect(reason)}")
        end

      {:error, :not_found} ->
        Logger.debug("File change detected for unregistered file: #{file_path}")
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:file_changed, _file_path}, state) do
    # Auto-reload disabled, ignore file changes
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp load_instruction_files(files, state) do
    {loaded_count, new_state} =
      Enum.reduce(files, {0, state}, fn file, {count, acc_state} ->
        case register_instruction_file(file, acc_state) do
          {:ok, _id, updated_state} -> {count + 1, updated_state}
          {:error, _reason} -> {count, acc_state}
        end
      end)

    increment_metric(:load_operations)
    {loaded_count, new_state}
  end

  defp register_instruction_file(instruction_file, state) do
    instruction_id = generate_instruction_id(instruction_file)
    version = calculate_version(instruction_file)

    # Check for duplicates
    case check_for_duplicate(instruction_id, version) do
      :ok ->
        entry = %{
          id: instruction_id,
          file: instruction_file,
          version: version,
          loaded_at: DateTime.utc_now(),
          active: should_auto_activate?(instruction_file),
          usage_count: 0,
          last_used: DateTime.utc_now()
        }

        :ets.insert(@instructions_table, {instruction_id, entry})
        :ets.insert(@versions_table, {instruction_id, version})

        new_state = add_to_monitoring(instruction_file.path, state)
        increment_metric(:registrations)

        Logger.debug("Registered instruction: #{instruction_id}")
        {:ok, instruction_id, new_state}

      {:error, :duplicate} ->
        {:error, :duplicate_instruction}
    end
  end

  defp generate_instruction_id(instruction_file) do
    # Generate unique ID based on path and scope
    base = "#{instruction_file.scope}:#{Path.basename(instruction_file.path)}"
    hash = :crypto.hash(:sha256, instruction_file.path) |> Base.encode16(case: :lower)
    "#{base}:#{String.slice(hash, 0, 8)}"
  end

  defp calculate_version(instruction_file) do
    # Calculate version hash based on content and metadata
    content_hash = :crypto.hash(:sha256, instruction_file.content)
    metadata_hash = :crypto.hash(:sha256, :erlang.term_to_binary(instruction_file.metadata))

    combined_hash = :crypto.hash(:sha256, content_hash <> metadata_hash)
    Base.encode16(combined_hash, case: :lower) |> String.slice(0, 16)
  end

  defp check_for_duplicate(instruction_id, version) do
    case :ets.lookup(@versions_table, instruction_id) do
      [{^instruction_id, ^version}] -> {:error, :duplicate}
      _ -> :ok
    end
  end

  defp should_auto_activate?(instruction_file) do
    instruction_file.type == :always
  end

  defp list_instructions_with_filters(opts) do
    type_filter = Keyword.get(opts, :type)
    scope_filter = Keyword.get(opts, :scope)
    active_filter = Keyword.get(opts, :active)
    limit = Keyword.get(opts, :limit)

    instructions =
      @instructions_table
      |> :ets.tab2list()
      |> Enum.map(fn {_id, entry} -> entry end)
      |> apply_filters(type_filter, scope_filter, active_filter)
      |> maybe_limit(limit)

    instructions
  end

  defp apply_filters(instructions, type_filter, scope_filter, active_filter) do
    instructions
    |> maybe_filter_by_type(type_filter)
    |> maybe_filter_by_scope(scope_filter)
    |> maybe_filter_by_active(active_filter)
  end

  defp maybe_filter_by_type(instructions, nil), do: instructions

  defp maybe_filter_by_type(instructions, type) do
    Enum.filter(instructions, &(&1.file.type == type))
  end

  defp maybe_filter_by_scope(instructions, nil), do: instructions

  defp maybe_filter_by_scope(instructions, scope) do
    Enum.filter(instructions, &(&1.file.scope == scope))
  end

  defp maybe_filter_by_active(instructions, nil), do: instructions

  defp maybe_filter_by_active(instructions, active) do
    Enum.filter(instructions, &(&1.active == active))
  end

  defp maybe_limit(instructions, nil), do: instructions

  defp maybe_limit(instructions, limit) when is_integer(limit) and limit > 0 do
    Enum.take(instructions, limit)
  end

  defp maybe_limit(instructions, _), do: instructions

  defp update_instruction_status(instruction_id, active) do
    case :ets.lookup(@instructions_table, instruction_id) do
      [{^instruction_id, entry}] ->
        updated_entry = %{entry | active: active}
        :ets.insert(@instructions_table, {instruction_id, updated_entry})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  defp unregister_instruction_by_id(instruction_id) do
    case :ets.lookup(@instructions_table, instruction_id) do
      [{^instruction_id, _entry}] ->
        :ets.delete(@instructions_table, instruction_id)
        :ets.delete(@versions_table, instruction_id)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  defp reload_instruction_by_id(instruction_id) do
    case :ets.lookup(@instructions_table, instruction_id) do
      [{^instruction_id, entry}] ->
        case FileManager.load_file(entry.file.path) do
          {:ok, updated_file} ->
            new_version = calculate_version(updated_file)
            updated_entry = %{entry | file: updated_file, version: new_version, loaded_at: DateTime.utc_now()}

            :ets.insert(@instructions_table, {instruction_id, updated_entry})
            :ets.insert(@versions_table, {instruction_id, new_version})

            {:ok, updated_entry}

          error ->
            error
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp find_instruction_by_path(file_path) do
    instructions = :ets.tab2list(@instructions_table)

    case Enum.find(instructions, fn {_id, entry} -> entry.file.path == file_path end) do
      {instruction_id, _entry} -> {:ok, instruction_id}
      nil -> {:error, :not_found}
    end
  end

  defp add_to_monitoring(file_path, state) do
    new_monitored_paths = MapSet.put(state.monitored_paths, file_path)
    %{state | monitored_paths: new_monitored_paths}
  end

  defp remove_from_monitoring(instruction_id, state) do
    case :ets.lookup(@instructions_table, instruction_id) do
      [{^instruction_id, entry}] ->
        new_monitored_paths = MapSet.delete(state.monitored_paths, entry.file.path)
        %{state | monitored_paths: new_monitored_paths}

      [] ->
        state
    end
  end

  defp init_stats do
    %{
      registrations: 0,
      unregistrations: 0,
      activations: 0,
      deactivations: 0,
      reloads: 0,
      auto_reloads: 0,
      load_operations: 0
    }
  end

  defp increment_metric(metric_name) do
    :ets.update_counter(@metrics_table, metric_name, 1, {metric_name, 0})
  end

  defp get_current_stats(state) do
    instruction_count = :ets.info(@instructions_table, :size)
    active_count = count_active_instructions()

    metrics =
      @metrics_table
      |> :ets.tab2list()
      |> Enum.into(%{})

    %{
      total_instructions: instruction_count,
      active_instructions: active_count,
      monitored_paths: MapSet.size(state.monitored_paths),
      auto_reload_enabled: state.auto_reload,
      metrics: metrics,
      uptime: get_uptime()
    }
  end

  defp count_active_instructions do
    @instructions_table
    |> :ets.tab2list()
    |> Enum.count(fn {_id, entry} -> entry.active end)
  end

  defp get_uptime do
    # Simple uptime calculation - could be enhanced
    DateTime.utc_now()
  end
end
