defmodule RubberDuck.ILP.Context.Storage do
  @moduledoc """
  Distributed context storage with hash-based deduplication.
  Supports multiple storage backends including Mnesia, ETS, and file system.
  """

  @doc """
  Initializes the storage backend.
  """
  def initialize(backend_type) do
    case backend_type do
      :mnesia -> initialize_mnesia()
      :ets -> initialize_ets()
      :file_system -> initialize_file_system()
      _ -> {:error, :unsupported_backend}
    end
  end

  @doc """
  Stores compressed context data with metadata.
  """
  def store(backend, context_id, compressed_data, metadata) do
    case backend.type do
      :mnesia -> store_mnesia(backend, context_id, compressed_data, metadata)
      :ets -> store_ets(backend, context_id, compressed_data, metadata)
      :file_system -> store_file_system(backend, context_id, compressed_data, metadata)
    end
  end

  @doc """
  Retrieves context data and metadata.
  """
  def get(backend, context_id) do
    case backend.type do
      :mnesia -> get_mnesia(backend, context_id)
      :ets -> get_ets(backend, context_id)
      :file_system -> get_file_system(backend, context_id)
    end
  end

  @doc """
  Deletes context data.
  """
  def delete(backend, context_id) do
    case backend.type do
      :mnesia -> delete_mnesia(backend, context_id)
      :ets -> delete_ets(backend, context_id)
      :file_system -> delete_file_system(backend, context_id)
    end
  end

  @doc """
  Lists all stored context IDs.
  """
  def list_contexts(backend) do
    case backend.type do
      :mnesia -> list_contexts_mnesia(backend)
      :ets -> list_contexts_ets(backend)
      :file_system -> list_contexts_file_system(backend)
    end
  end

  # Mnesia backend implementation
  
  defp initialize_mnesia do
    table_name = :context_storage
    
    case :mnesia.create_table(table_name, [
      attributes: [:context_id, :compressed_data, :metadata, :created_at, :hash],
      type: :set,
      disc_copies: [node()]
    ]) do
      {:atomic, :ok} ->
        %{type: :mnesia, table: table_name}
      
      {:aborted, {:already_exists, ^table_name}} ->
        %{type: :mnesia, table: table_name}
      
      {:aborted, reason} ->
        {:error, {:mnesia_init_failed, reason}}
    end
  end

  defp store_mnesia(backend, context_id, compressed_data, metadata) do
    hash = calculate_hash(compressed_data)
    created_at = System.monotonic_time(:millisecond)
    
    record = {context_id, compressed_data, metadata, created_at, hash}
    
    case :mnesia.transaction(fn ->
      :mnesia.write(backend.table, record, :write)
    end) do
      {:atomic, :ok} -> {:ok, context_id}
      {:aborted, reason} -> {:error, {:mnesia_store_failed, reason}}
    end
  end

  defp get_mnesia(backend, context_id) do
    case :mnesia.transaction(fn ->
      :mnesia.read(backend.table, context_id)
    end) do
      {:atomic, [{^context_id, compressed_data, metadata, _created_at, _hash}]} ->
        {:ok, compressed_data, metadata}
      
      {:atomic, []} ->
        {:error, :not_found}
      
      {:aborted, reason} ->
        {:error, {:mnesia_get_failed, reason}}
    end
  end

  defp delete_mnesia(backend, context_id) do
    case :mnesia.transaction(fn ->
      :mnesia.delete(backend.table, context_id, :write)
    end) do
      {:atomic, :ok} -> {:ok, context_id}
      {:aborted, reason} -> {:error, {:mnesia_delete_failed, reason}}
    end
  end

  defp list_contexts_mnesia(backend) do
    case :mnesia.transaction(fn ->
      :mnesia.all_keys(backend.table)
    end) do
      {:atomic, keys} -> {:ok, keys}
      {:aborted, reason} -> {:error, {:mnesia_list_failed, reason}}
    end
  end

  # ETS backend implementation
  
  defp initialize_ets do
    table_name = :context_storage_ets
    
    case :ets.new(table_name, [:set, :public, :named_table]) do
      ^table_name ->
        %{type: :ets, table: table_name}
      
      {:error, reason} ->
        {:error, {:ets_init_failed, reason}}
    end
  end

  defp store_ets(backend, context_id, compressed_data, metadata) do
    hash = calculate_hash(compressed_data)
    created_at = System.monotonic_time(:millisecond)
    
    record = {context_id, compressed_data, metadata, created_at, hash}
    
    case :ets.insert(backend.table, record) do
      true -> {:ok, context_id}
      false -> {:error, :ets_store_failed}
    end
  end

  defp get_ets(backend, context_id) do
    case :ets.lookup(backend.table, context_id) do
      [{^context_id, compressed_data, metadata, _created_at, _hash}] ->
        {:ok, compressed_data, metadata}
      
      [] ->
        {:error, :not_found}
    end
  end

  defp delete_ets(backend, context_id) do
    case :ets.delete(backend.table, context_id) do
      true -> {:ok, context_id}
      false -> {:error, :ets_delete_failed}
    end
  end

  defp list_contexts_ets(backend) do
    keys = :ets.foldl(fn {context_id, _, _, _, _}, acc ->
      [context_id | acc]
    end, [], backend.table)
    
    {:ok, keys}
  end

  # File system backend implementation
  
  defp initialize_file_system do
    storage_dir = Path.join([System.tmp_dir(), "rubber_duck_context_storage"])
    
    case File.mkdir_p(storage_dir) do
      :ok ->
        %{type: :file_system, directory: storage_dir}
      
      {:error, reason} ->
        {:error, {:file_system_init_failed, reason}}
    end
  end

  defp store_file_system(backend, context_id, compressed_data, metadata) do
    file_path = Path.join(backend.directory, "#{context_id}.ctx")
    
    data_to_store = %{
      compressed_data: compressed_data,
      metadata: metadata,
      created_at: System.monotonic_time(:millisecond),
      hash: calculate_hash(compressed_data)
    }
    
    encoded_data = :erlang.term_to_binary(data_to_store)
    
    case File.write(file_path, encoded_data) do
      :ok -> {:ok, context_id}
      {:error, reason} -> {:error, {:file_write_failed, reason}}
    end
  end

  defp get_file_system(backend, context_id) do
    file_path = Path.join(backend.directory, "#{context_id}.ctx")
    
    case File.read(file_path) do
      {:ok, encoded_data} ->
        try do
          %{compressed_data: compressed_data, metadata: metadata} = :erlang.binary_to_term(encoded_data)
          {:ok, compressed_data, metadata}
        rescue
          _ -> {:error, :corrupt_data}
        end
      
      {:error, :enoent} ->
        {:error, :not_found}
      
      {:error, reason} ->
        {:error, {:file_read_failed, reason}}
    end
  end

  defp delete_file_system(backend, context_id) do
    file_path = Path.join(backend.directory, "#{context_id}.ctx")
    
    case File.rm(file_path) do
      :ok -> {:ok, context_id}
      {:error, :enoent} -> {:ok, context_id}  # Already deleted
      {:error, reason} -> {:error, {:file_delete_failed, reason}}
    end
  end

  defp list_contexts_file_system(backend) do
    case File.ls(backend.directory) do
      {:ok, files} ->
        context_ids = files
        |> Enum.filter(&String.ends_with?(&1, ".ctx"))
        |> Enum.map(&String.replace_suffix(&1, ".ctx", ""))
        
        {:ok, context_ids}
      
      {:error, reason} ->
        {:error, {:file_list_failed, reason}}
    end
  end

  # Utility functions
  
  defp calculate_hash(data) do
    :crypto.hash(:sha256, data) |> Base.encode16()
  end
end