defmodule RubberDuck.MnesiaManager do
  use GenServer
  require Logger

  @moduledoc """
  Manages Mnesia database schema, tables, and operations for the distributed
  RubberDuck system. Handles initialization, replication, backup/recovery,
  and health monitoring.
  """

  defstruct [
    :status,
    :config,
    :start_time,
    :tables
  ]

  @required_tables [:sessions, :models, :model_stats, :cluster_nodes]

  @table_definitions %{
    sessions: [
      attributes: [:session_id, :messages, :metadata, :created_at, :updated_at, :node],
      type: :bag,
      storage_type: :ram_copies
    ],
    models: [
      attributes: [:name, :type, :endpoint, :capabilities, :health_status, :health_reason, :registered_at, :node],
      type: :set,
      storage_type: :ram_copies
    ],
    model_stats: [
      attributes: [:model_name, :success_count, :failure_count, :total_latency, :average_latency, :last_updated],
      type: :set,
      storage_type: :ram_copies
    ],
    cluster_nodes: [
      attributes: [:node_name, :status, :joined_at, :last_seen, :metadata],
      type: :ordered_set,
      storage_type: :ram_copies
    ]
  }

  # Client API

  def start_link(opts \\ []) do
    config = Keyword.get(opts, :config, %{})
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def initialize_schema(pid \\ __MODULE__) do
    GenServer.call(pid, :initialize_schema, 30_000)
  end

  def get_tables(pid \\ __MODULE__) do
    GenServer.call(pid, :get_tables)
  end

  def get_table_info(pid \\ __MODULE__, table) do
    GenServer.call(pid, {:get_table_info, table})
  end

  def table_exists?(pid \\ __MODULE__, table) do
    GenServer.call(pid, {:table_exists, table})
  end

  def get_storage_type(pid \\ __MODULE__, table) do
    GenServer.call(pid, {:get_storage_type, table})
  end

  def get_table_nodes(pid \\ __MODULE__, table) do
    GenServer.call(pid, {:get_table_nodes, table})
  end

  def create_backup(pid \\ __MODULE__, backup_path) do
    GenServer.call(pid, {:create_backup, backup_path}, 60_000)
  end

  def restore_backup(pid \\ __MODULE__, backup_path) do
    GenServer.call(pid, {:restore_backup, backup_path}, 60_000)
  end

  def health_check(pid \\ __MODULE__) do
    GenServer.call(pid, :health_check)
  end

  def get_info(pid \\ __MODULE__) do
    GenServer.call(pid, :get_info)
  end

  def get_cluster_status(pid \\ __MODULE__) do
    GenServer.call(pid, :get_cluster_status)
  end

  # Server Callbacks

  @impl true
  def init(config) do
    state = %__MODULE__{
      status: :initializing,
      config: config,
      start_time: :os.system_time(:millisecond),
      tables: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:initialize_schema, _from, state) do
    case initialize_mnesia_schema() do
      :ok ->
        case create_tables() do
          :ok ->
            new_state = %{state | status: :running, tables: @required_tables}
            {:reply, :ok, new_state}
          {:error, reason} ->
            Logger.error("Failed to create tables: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
      {:error, reason} ->
        Logger.error("Failed to initialize schema: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_tables, _from, state) do
    tables = case :mnesia.system_info(:tables) do
      list when is_list(list) -> 
        Enum.filter(list, &(&1 in @required_tables))
      _ -> 
        []
    end
    {:reply, tables, state}
  end

  @impl true
  def handle_call({:get_table_info, table}, _from, state) do
    info = %{
      type: safe_table_info(table, :type),
      size: safe_table_info(table, :size),
      memory: safe_table_info(table, :memory),
      storage_type: safe_table_info(table, :storage_type)
    }
    {:reply, info, state}
  end

  @impl true
  def handle_call({:table_exists, table}, _from, state) do
    exists = case safe_table_info(table, :type) do
      nil -> false
      _ -> true
    end
    {:reply, exists, state}
  end

  @impl true
  def handle_call({:get_storage_type, table}, _from, state) do
    storage_type = safe_table_info(table, :storage_type)
    {:reply, storage_type, state}
  end

  @impl true
  def handle_call({:get_table_nodes, table}, _from, state) do
    nodes = case safe_table_info(table, :ram_copies) do
      nodes when is_list(nodes) -> nodes
      _ ->
        case safe_table_info(table, :disc_copies) do
          nodes when is_list(nodes) -> nodes
          _ ->
            case safe_table_info(table, :disc_only_copies) do
              nodes when is_list(nodes) -> nodes
              _ -> [node()]
            end
        end
    end
    {:reply, nodes, state}
  end

  @impl true
  def handle_call({:create_backup, backup_path}, _from, state) do
    result = try do
      case :mnesia.backup(to_charlist(backup_path)) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, reason}
    end
    {:reply, result, state}
  end

  @impl true
  def handle_call({:restore_backup, backup_path}, _from, state) do
    result = try do
      case :mnesia.restore(to_charlist(backup_path), []) do
        {:atomic, _} -> :ok
        {:aborted, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, reason}
    end
    {:reply, result, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    uptime = :os.system_time(:millisecond) - state.start_time
    
    info = %{
      status: state.status,
      mnesia_running: mnesia_running?(),
      tables: state.tables,
      memory: :erlang.memory(),
      uptime: uptime
    }
    
    {:reply, info, state}
  end

  @impl true
  def handle_call(:get_cluster_status, _from, state) do
    running_nodes = safe_system_info(:running_db_nodes)
    all_nodes = safe_system_info(:db_nodes)
    stopped_nodes = all_nodes -- running_nodes
    
    status = %{
      running_nodes: running_nodes,
      stopped_nodes: stopped_nodes,
      master_node: safe_system_info(:master_node),
      schema_location: safe_system_info(:schema_location)
    }
    
    {:reply, status, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :mnesia.stop()
    :ok
  end

  # Private Functions

  defp initialize_mnesia_schema do
    case :mnesia.create_schema([node()]) do
      :ok -> 
        start_mnesia()
      {:error, {_, {:already_exists, _}}} -> 
        start_mnesia()
      {:error, reason} -> 
        {:error, reason}
    end
  end

  defp start_mnesia do
    case :mnesia.start() do
      :ok -> :ok
      {:error, {_, {:already_started, _}}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_tables do
    results = Enum.map(@table_definitions, fn {table_name, opts} ->
      create_table(table_name, opts)
    end)
    
    case Enum.find(results, &(&1 != :ok)) do
      nil -> :ok
      error -> error
    end
  end

  defp create_table(table_name, opts) do
    attributes = Keyword.get(opts, :attributes)
    table_type = Keyword.get(opts, :type, :set)
    storage_type = Keyword.get(opts, :storage_type, :ram_copies)
    
    table_opts = [
      {storage_type, [node()]},
      attributes: attributes,
      type: table_type
    ]
    
    case :mnesia.create_table(table_name, table_opts) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, _}} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp safe_table_info(table, key) do
    try do
      :mnesia.table_info(table, key)
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  defp safe_system_info(key) do
    try do
      :mnesia.system_info(key)
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  defp mnesia_running? do
    try do
      :mnesia.system_info(:is_running) == :yes
    rescue
      _ -> false
    end
  end
end