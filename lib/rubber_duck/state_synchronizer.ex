defmodule RubberDuck.StateSynchronizer do
  use GenServer
  require Logger

  @moduledoc """
  Manages distributed state synchronization across cluster nodes using Mnesia
  transactions and OTP pg for event broadcasting. Handles conflict resolution,
  state reconciliation, and change propagation to maintain consistency.
  """

  defstruct [
    :node_id,
    :pg_scope,
    :subscribers,
    :conflict_strategy,
    :sync_stats
  ]

  @pg_scope :rubber_duck_sync
  @sync_timeout 30_000
  @reconcile_interval 60_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Perform a distributed transaction with automatic synchronization
  """
  def sync_transaction(fun, opts \\ []) do
    GenServer.call(__MODULE__, {:sync_transaction, fun, opts}, @sync_timeout)
  end

  @doc """
  Broadcast a state change event to all cluster nodes
  """
  def broadcast_change(table, operation, record, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:broadcast_change, table, operation, record, metadata})
  end

  @doc """
  Subscribe to state changes for specific tables
  """
  def subscribe_to_changes(tables) when is_list(tables) do
    GenServer.call(__MODULE__, {:subscribe, tables})
  end

  @doc """
  Trigger state reconciliation with a specific node
  """
  def reconcile_with_node(node) do
    GenServer.call(__MODULE__, {:reconcile_node, node}, @sync_timeout)
  end

  @doc """
  Get synchronization statistics
  """
  def get_sync_stats do
    GenServer.call(__MODULE__, :get_sync_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, node())
    conflict_strategy = Keyword.get(opts, :conflict_strategy, :last_writer_wins)

    # Initialize pg scope
    case :pg.start_link(@pg_scope) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Join global sync group
    :pg.join(@pg_scope, "state_sync:global", self())

    # Monitor cluster membership
    :net_kernel.monitor_nodes(true)

    # Schedule periodic reconciliation
    schedule_reconciliation()

    state = %__MODULE__{
      node_id: node_id,
      pg_scope: @pg_scope,
      subscribers: %{},
      conflict_strategy: conflict_strategy,
      sync_stats: %{
        transactions: 0,
        conflicts: 0,
        broadcasts: 0,
        reconciliations: 0
      }
    }

    Logger.info("StateSynchronizer started on node #{node_id}")
    {:ok, state}
  end

  @impl true
  def handle_call({:sync_transaction, fun, opts}, from, state) do
    timeout = Keyword.get(opts, :timeout, 5000)
    retry_count = Keyword.get(opts, :retry_count, 3)

    Task.start(fn ->
      result = execute_sync_transaction(fun, timeout, retry_count)
      GenServer.reply(from, result)
    end)

    new_stats = update_stat(state.sync_stats, :transactions, 1)
    {:noreply, %{state | sync_stats: new_stats}}
  end

  @impl true
  def handle_call({:subscribe, tables}, {pid, _tag}, state) do
    # Subscribe to pg groups for each table
    Enum.each(tables, fn table ->
      :pg.join(@pg_scope, "state_change:#{table}", pid)
    end)

    # Track local subscribers
    new_subscribers = Map.put(state.subscribers, pid, tables)
    
    # Monitor subscriber process
    Process.monitor(pid)

    {:reply, :ok, %{state | subscribers: new_subscribers}}
  end

  @impl true
  def handle_call({:reconcile_node, target_node}, _from, state) do
    result = perform_node_reconciliation(target_node)
    new_stats = update_stat(state.sync_stats, :reconciliations, 1)
    {:reply, result, %{state | sync_stats: new_stats}}
  end

  @impl true
  def handle_call(:get_sync_stats, _from, state) do
    stats = Map.put(state.sync_stats, :node_id, state.node_id)
    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:broadcast_change, table, operation, record, metadata}, state) do
    event = %{
      table: table,
      operation: operation,
      record: record,
      metadata: metadata,
      timestamp: System.system_time(:microsecond),
      node: state.node_id
    }

    # Broadcast to table-specific group
    broadcast_to_group("state_change:#{table}", {:state_change, event})

    # Broadcast to global group
    broadcast_to_group("state_sync:global", {:state_change, event})

    new_stats = update_stat(state.sync_stats, :broadcasts, 1)
    {:noreply, %{state | sync_stats: new_stats}}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("Node #{node} joined cluster, triggering reconciliation")
    
    # Trigger reconciliation with new node
    Task.start(fn ->
      :timer.sleep(5000) # Wait for node to stabilize
      perform_node_reconciliation(node)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.warning("Node #{node} left cluster")
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconcile_cluster, state) do
    # Periodic cluster-wide reconciliation
    connected_nodes = Node.list()
    
    Enum.each(connected_nodes, fn node ->
      Task.start(fn -> perform_node_reconciliation(node) end)
    end)

    schedule_reconciliation()
    {:noreply, state}
  end

  @impl true
  def handle_info({"state_change:" <> table, {:state_change, event}}, state) do
    # Handle incoming state change from other nodes
    if event.node != state.node_id do
      Logger.debug("Received state change for #{table} from #{event.node}")
      handle_remote_state_change(event)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up subscriber tracking
    new_subscribers = Map.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  @impl true
  def terminate(_reason, _state) do
    :net_kernel.monitor_nodes(false)
    :ok
  end

  # Private Functions

  defp execute_sync_transaction(fun, timeout, retry_count) do
    try do
      case :mnesia.transaction(fun, timeout) do
        {:atomic, result} -> 
          {:ok, result}
        {:aborted, {:transaction_aborted, reason}} ->
          handle_transaction_abort(fun, reason, timeout, retry_count)
        {:aborted, reason} ->
          {:error, {:transaction_failed, reason}}
      end
    catch
      :exit, reason -> {:error, {:transaction_exit, reason}}
    end
  end

  defp handle_transaction_abort(fun, reason, timeout, retry_count) when retry_count > 0 do
    Logger.debug("Transaction aborted (#{inspect(reason)}), retrying...")
    
    # Exponential backoff
    sleep_time = (4 - retry_count) * 1000
    :timer.sleep(sleep_time)
    
    execute_sync_transaction(fun, timeout, retry_count - 1)
  end

  defp handle_transaction_abort(_fun, reason, _timeout, 0) do
    {:error, {:transaction_failed_after_retries, reason}}
  end

  defp perform_node_reconciliation(target_node) do
    Logger.info("Starting reconciliation with node #{target_node}")
    
    try do
      # Get table checksums from both nodes
      local_checksums = calculate_table_checksums()
      remote_checksums = :rpc.call(target_node, __MODULE__, :calculate_table_checksums, [])
      
      case remote_checksums do
        {:badrpc, reason} ->
          {:error, {:rpc_failed, reason}}
        checksums when is_map(checksums) ->
          reconcile_table_differences(local_checksums, checksums, target_node)
        _ ->
          {:error, :invalid_remote_response}
      end
    rescue
      error -> {:error, {:reconciliation_error, error}}
    end
  end

  def calculate_table_checksums do
    tables = [:sessions, :models, :model_stats, :cluster_nodes]
    
    Enum.reduce(tables, %{}, fn table, acc ->
      checksum = case :mnesia.table_info(table, :size) do
        size when is_integer(size) ->
          # Simple checksum based on record count and last update
          records = :mnesia.dirty_select(table, [{{table, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6"}, [], [:"$$"]}])
          :crypto.hash(:sha256, :erlang.term_to_binary({size, records}))
        _ ->
          nil
      end
      
      Map.put(acc, table, checksum)
    end)
  end

  defp reconcile_table_differences(local_checksums, remote_checksums, target_node) do
    differences = find_checksum_differences(local_checksums, remote_checksums)
    
    if Enum.empty?(differences) do
      Logger.debug("No differences found during reconciliation with #{target_node}")
      :ok
    else
      Logger.info("Found differences in tables: #{inspect(differences)}")
      sync_table_differences(differences, target_node)
    end
  end

  defp find_checksum_differences(local, remote) do
    Enum.reduce(local, [], fn {table, local_checksum}, acc ->
      case Map.get(remote, table) do
        ^local_checksum -> acc
        _ -> [table | acc]
      end
    end)
  end

  defp sync_table_differences(tables, target_node) do
    Enum.reduce(tables, :ok, fn table, acc ->
      case acc do
        :ok -> sync_single_table(table, target_node)
        error -> error
      end
    end)
  end

  defp sync_single_table(table, target_node) do
    Logger.info("Synchronizing table #{table} with node #{target_node}")
    
    # For now, implement simple last-writer-wins
    # In production, you'd want more sophisticated merge strategies
    try do
      local_records = :mnesia.dirty_select(table, [{{table, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6"}, [], [:"$$"]}])
      remote_records = :rpc.call(target_node, :mnesia, :dirty_select, [table, [{{table, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6"}, [], [:"$$"]}]])
      
      case remote_records do
        {:badrpc, reason} ->
          {:error, {:sync_failed, reason}}
        records when is_list(records) ->
          merge_table_records(table, local_records, records)
        _ ->
          {:error, :invalid_remote_records}
      end
    rescue
      error -> {:error, {:sync_error, error}}
    end
  end

  defp merge_table_records(table, local_records, remote_records) do
    # Simple merge strategy - could be enhanced with vector clocks
    all_records = (local_records ++ remote_records)
    unique_records = Enum.uniq_by(all_records, fn [key | _] -> key end)
    
    :mnesia.transaction(fn ->
      :mnesia.clear_table(table)
      Enum.each(unique_records, fn record ->
        :mnesia.write({table, record})
      end)
    end)
  end

  defp handle_remote_state_change(event) do
    # Handle incoming state changes from other nodes
    # This could trigger local cache invalidation, re-computation, etc.
    Logger.debug("Processing remote state change: #{inspect(event)}")
    
    # For now, just log the change
    # In a full implementation, you'd update local caches,
    # trigger dependent computations, etc.
    :ok
  end

  defp broadcast_to_group(group, message) do
    case :pg.get_members(@pg_scope, group) do
      [] -> 
        Logger.debug("No subscribers for group #{group}")
      pids ->
        Enum.each(pids, fn pid ->
          send(pid, {group, message})
        end)
    end
  end

  defp schedule_reconciliation do
    Process.send_after(self(), :reconcile_cluster, @reconcile_interval)
  end

  defp update_stat(stats, key, increment) do
    Map.update(stats, key, increment, &(&1 + increment))
  end
end