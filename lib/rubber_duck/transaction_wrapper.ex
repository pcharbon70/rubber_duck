defmodule RubberDuck.TransactionWrapper do
  require Logger

  @moduledoc """
  Provides wrapper functions for common distributed Mnesia operations with
  automatic retry logic, timeout handling, and error recovery patterns.
  Integrates with StateSynchronizer for change broadcasting.
  """

  @default_timeout 5000
  @default_retries 3
  @backoff_base 1000

  @doc """
  Execute a read transaction with automatic retry on conflicts
  """
  def read_transaction(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    retries = Keyword.get(opts, :retries, @default_retries)
    
    execute_with_retry(fun, :read, timeout, retries)
  end

  @doc """
  Execute a write transaction with change broadcasting
  """
  def write_transaction(table, operation, record, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    retries = Keyword.get(opts, :retries, @default_retries)
    metadata = Keyword.get(opts, :metadata, %{})
    broadcast = Keyword.get(opts, :broadcast, true)

    transaction_fun = fn ->
      result = case operation do
        :create -> mnesia_write(table, record)
        :update -> mnesia_write(table, record)
        :delete -> mnesia_delete(table, record)
        :upsert -> mnesia_upsert(table, record)
      end

      if broadcast do
        RubberDuck.StateSynchronizer.broadcast_change(table, operation, record, metadata)
      end

      result
    end

    execute_with_retry(transaction_fun, :write, timeout, retries)
  end

  @doc """
  Create a new record with automatic ID generation if needed
  """
  def create_record(table, record, opts \\ []) do
    record_with_id = ensure_record_id(table, record)
    write_transaction(table, :create, record_with_id, opts)
  end

  @doc """
  Update an existing record with conflict detection
  """
  def update_record(table, id, updates, opts \\ []) do
    transaction_fun = fn ->
      case :mnesia.read(table, id) do
        [] ->
          {:error, :not_found}
        [current_record] ->
          updated_record = apply_updates(current_record, updates)
          :mnesia.write(updated_record)
          {:ok, updated_record}
      end
    end

    case execute_with_retry(transaction_fun, :write, Keyword.get(opts, :timeout, @default_timeout), Keyword.get(opts, :retries, @default_retries)) do
      {:ok, record} ->
        if Keyword.get(opts, :broadcast, true) do
          RubberDuck.StateSynchronizer.broadcast_change(table, :update, record, Keyword.get(opts, :metadata, %{}))
        end
        {:ok, record}
      error ->
        error
    end
  end

  @doc """
  Delete a record by ID
  """
  def delete_record(table, id, opts \\ []) do
    transaction_fun = fn ->
      case :mnesia.read(table, id) do
        [] ->
          {:error, :not_found}
        [record] ->
          :mnesia.delete({table, id})
          {:ok, record}
      end
    end

    case execute_with_retry(transaction_fun, :write, Keyword.get(opts, :timeout, @default_timeout), Keyword.get(opts, :retries, @default_retries)) do
      {:ok, record} ->
        if Keyword.get(opts, :broadcast, true) do
          RubberDuck.StateSynchronizer.broadcast_change(table, :delete, record, Keyword.get(opts, :metadata, %{}))
        end
        {:ok, record}
      error ->
        error
    end
  end

  @doc """
  Read records with optional filtering
  """
  def read_records(table, filter \\ :all, opts \\ []) do
    transaction_fun = fn ->
      case filter do
        :all ->
          :mnesia.select(table, [{{table, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6"}, [], [:"$$"]}])
        {:id, id} ->
          :mnesia.read(table, id)
        {:match, pattern} ->
          :mnesia.select(table, pattern)
        {:index, {index_attr, value}} ->
          :mnesia.index_read(table, value, index_attr)
      end
    end

    read_transaction(transaction_fun, opts)
  end

  @doc """
  Perform a bulk operation with batching
  """
  def bulk_operation(table, operations, opts \\ []) when is_list(operations) do
    batch_size = Keyword.get(opts, :batch_size, 100)
    timeout = Keyword.get(opts, :timeout, @default_timeout * 2)
    broadcast = Keyword.get(opts, :broadcast, true)

    operations
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {_status, results} ->
      case execute_bulk_batch(table, batch, timeout, broadcast) do
        {:ok, batch_results} ->
          {:cont, {:ok, results ++ batch_results}}
        {:error, reason} ->
          {:halt, {:error, {reason, results}}}
      end
    end)
  end

  @doc """
  Get table statistics and metadata
  """
  def table_info(table) do
    read_transaction(fn ->
      %{
        size: :mnesia.table_info(table, :size),
        type: :mnesia.table_info(table, :type),
        memory: :mnesia.table_info(table, :memory),
        storage_type: :mnesia.table_info(table, :storage_type),
        attributes: :mnesia.table_info(table, :attributes)
      }
    end)
  end

  # Private Functions

  defp execute_with_retry(fun, operation_type, timeout, retries) do
    try do
      case :mnesia.transaction(fun, timeout) do
        {:atomic, result} ->
          {:ok, result}
        {:aborted, reason} ->
          handle_transaction_error(fun, reason, operation_type, timeout, retries)
      end
    catch
      :exit, reason ->
        {:error, {:transaction_exit, reason}}
    end
  end

  defp handle_transaction_error(fun, reason, operation_type, timeout, retries) when retries > 0 do
    case should_retry?(reason, operation_type) do
      true ->
        Logger.debug("Transaction failed (#{inspect(reason)}), retrying... (#{retries} attempts left)")
        
        # Exponential backoff
        backoff_time = @backoff_base * ((@default_retries - retries) + 1)
        :timer.sleep(backoff_time)
        
        execute_with_retry(fun, operation_type, timeout, retries - 1)
      false ->
        {:error, {:transaction_failed, reason}}
    end
  end

  defp handle_transaction_error(_fun, reason, _operation_type, _timeout, 0) do
    Logger.error("Transaction failed after all retries: #{inspect(reason)}")
    {:error, {:transaction_failed_after_retries, reason}}
  end

  defp should_retry?(reason, _operation_type) do
    case reason do
      :no_transaction ->
        true
      {:aborted, _} ->
        true
      {:timeout, _} ->
        true
      :timeout ->
        true
      {:nodedown, _} ->
        true
      _ ->
        false
    end
  end

  defp mnesia_write(table, record) do
    record_tuple = case record do
      tuple when is_tuple(tuple) -> record
      map when is_map(map) -> map_to_tuple(table, map)
      _ -> {table, record}
    end
    
    :mnesia.write(record_tuple)
    record
  end

  defp mnesia_delete(table, record) do
    key = case record do
      tuple when is_tuple(tuple) -> elem(tuple, 1)
      map when is_map(map) -> get_primary_key(table, map)
      key -> key
    end
    
    :mnesia.delete({table, key})
    record
  end

  defp mnesia_upsert(table, record) do
    key = case record do
      tuple when is_tuple(tuple) -> elem(tuple, 1)
      map when is_map(map) -> get_primary_key(table, map)
      _ -> nil
    end

    if key && :mnesia.read(table, key) != [] do
      mnesia_write(table, record)
    else
      mnesia_write(table, record)
    end
  end

  defp execute_bulk_batch(table, operations, timeout, broadcast) do
    transaction_fun = fn ->
      results = Enum.map(operations, fn {operation, record} ->
        case operation do
          :create -> mnesia_write(table, record)
          :update -> mnesia_write(table, record)
          :delete -> mnesia_delete(table, record)
          :upsert -> mnesia_upsert(table, record)
        end
      end)

      if broadcast do
        Enum.each(operations, fn {operation, record} ->
          RubberDuck.StateSynchronizer.broadcast_change(table, operation, record, %{bulk: true})
        end)
      end

      results
    end

    case :mnesia.transaction(transaction_fun, timeout) do
      {:atomic, results} -> {:ok, results}
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp ensure_record_id(table, record) do
    case record do
      map when is_map(map) ->
        case get_primary_key(table, map) do
          nil -> Map.put(map, get_primary_key_field(table), generate_id())
          _ -> map
        end
      tuple when is_tuple(tuple) ->
        if elem(tuple, 1) == nil do
          put_elem(tuple, 1, generate_id())
        else
          tuple
        end
      _ ->
        record
    end
  end

  defp apply_updates(current_record, updates) when is_map(updates) do
    case current_record do
      tuple when is_tuple(tuple) ->
        # Convert tuple to map, apply updates, convert back
        map = tuple_to_map(tuple)
        updated_map = Map.merge(map, updates)
        map_to_tuple(elem(tuple, 0), updated_map)
      map when is_map(map) ->
        Map.merge(map, updates)
      _ ->
        current_record
    end
  end

  defp apply_updates(current_record, updates) when is_list(updates) do
    Enum.reduce(updates, current_record, fn {key, value}, acc ->
      apply_single_update(acc, key, value)
    end)
  end

  defp apply_single_update(record, key, value) when is_tuple(record) do
    # Simple tuple update - would need table schema info for robust implementation
    record
  end

  defp apply_single_update(record, key, value) when is_map(record) do
    Map.put(record, key, value)
  end

  defp map_to_tuple(table, map) do
    # Convert map to tuple based on table schema
    # This is a simplified implementation
    case table do
      :sessions ->
        {table, 
         Map.get(map, :session_id), 
         Map.get(map, :messages), 
         Map.get(map, :metadata), 
         Map.get(map, :created_at), 
         Map.get(map, :updated_at), 
         Map.get(map, :node)}
      :models ->
        {table,
         Map.get(map, :name),
         Map.get(map, :type),
         Map.get(map, :endpoint),
         Map.get(map, :capabilities),
         Map.get(map, :health_status),
         Map.get(map, :health_reason),
         Map.get(map, :registered_at),
         Map.get(map, :node)}
      _ ->
        {table, map}
    end
  end

  defp tuple_to_map(tuple) do
    case tuple do
      {:sessions, session_id, messages, metadata, created_at, updated_at, node} ->
        %{session_id: session_id, messages: messages, metadata: metadata, 
          created_at: created_at, updated_at: updated_at, node: node}
      {:models, name, type, endpoint, capabilities, health_status, health_reason, registered_at, node} ->
        %{name: name, type: type, endpoint: endpoint, capabilities: capabilities,
          health_status: health_status, health_reason: health_reason, 
          registered_at: registered_at, node: node}
      _ ->
        %{}
    end
  end

  defp get_primary_key(table, map) do
    case table do
      :sessions -> Map.get(map, :session_id)
      :models -> Map.get(map, :name)
      :model_stats -> Map.get(map, :model_name)
      :cluster_nodes -> Map.get(map, :node_name)
      _ -> Map.get(map, :id)
    end
  end

  defp get_primary_key_field(table) do
    case table do
      :sessions -> :session_id
      :models -> :name
      :model_stats -> :model_name
      :cluster_nodes -> :node_name
      _ -> :id
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64() |> binary_part(0, 16)
  end
end