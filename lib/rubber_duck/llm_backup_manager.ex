defmodule RubberDuck.LLMBackupManager do
  @moduledoc """
  Specialized backup and recovery manager for LLM data.
  
  Provides granular backup and recovery operations for LLM responses
  and provider status data, with options for selective restoration
  and data migration between environments.
  """
  
  alias RubberDuck.TransactionWrapper
  require Logger
  
  @backup_format_version "1.0"
  @chunk_size 1000
  
  @doc """
  Create a selective backup of LLM data with filtering options
  """
  def create_llm_backup(backup_path, opts \\ []) do
    filters = Keyword.get(opts, :filters, %{})
    include_expired = Keyword.get(opts, :include_expired, false)
    compress = Keyword.get(opts, :compress, true)
    
    Logger.info("Starting LLM data backup to #{backup_path}")
    start_time = :erlang.system_time(:millisecond)
    
    try do
      backup_data = %{
        format_version: @backup_format_version,
        created_at: :erlang.system_time(:millisecond),
        node: node(),
        filters: filters,
        data: %{
          llm_responses: export_responses(filters, include_expired),
          llm_provider_status: export_provider_status(filters)
        }
      }
      
      # Write backup file
      case write_backup_file(backup_path, backup_data, compress) do
        :ok ->
          end_time = :erlang.system_time(:millisecond)
          duration = end_time - start_time
          
          stats = calculate_backup_stats(backup_data)
          Logger.info("LLM backup completed in #{duration}ms: #{inspect(stats)}")
          
          {:ok, %{
            backup_path: backup_path,
            duration_ms: duration,
            stats: stats
          }}
        
        {:error, reason} ->
          Logger.error("Failed to write LLM backup file: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("LLM backup failed with exception: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end
  
  @doc """
  Restore LLM data from backup with selective options
  """
  def restore_llm_backup(backup_path, opts \\ []) do
    overwrite_existing = Keyword.get(opts, :overwrite_existing, false)
    restore_responses = Keyword.get(opts, :restore_responses, true)
    restore_provider_status = Keyword.get(opts, :restore_provider_status, true)
    target_node = Keyword.get(opts, :target_node, node())
    
    Logger.info("Starting LLM data restore from #{backup_path}")
    start_time = :erlang.system_time(:millisecond)
    
    try do
      case read_backup_file(backup_path) do
        {:ok, backup_data} ->
          case validate_backup_data(backup_data) do
            :ok ->
              stats = restore_data(backup_data, %{
                overwrite_existing: overwrite_existing,
                restore_responses: restore_responses,
                restore_provider_status: restore_provider_status,
                target_node: target_node
              })
              
              end_time = :erlang.system_time(:millisecond)
              duration = end_time - start_time
              
              Logger.info("LLM restore completed in #{duration}ms: #{inspect(stats)}")
              
              {:ok, %{
                duration_ms: duration,
                stats: stats
              }}
            
            {:error, reason} ->
              {:error, {:invalid_backup, reason}}
          end
        
        {:error, reason} ->
          Logger.error("Failed to read LLM backup file: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("LLM restore failed with exception: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end
  
  @doc """
  Migrate LLM data between different format versions
  """
  def migrate_backup(old_backup_path, new_backup_path, target_version \\ @backup_format_version) do
    Logger.info("Migrating LLM backup from #{old_backup_path} to #{new_backup_path}")
    
    case read_backup_file(old_backup_path) do
      {:ok, backup_data} ->
        migrated_data = migrate_backup_format(backup_data, target_version)
        
        case write_backup_file(new_backup_path, migrated_data, true) do
          :ok ->
            Logger.info("LLM backup migration completed")
            {:ok, %{
              old_version: backup_data.format_version,
              new_version: target_version,
              migrated_path: new_backup_path
            }}
          
          error ->
            error
        end
      
      error ->
        error
    end
  end
  
  @doc """
  Verify the integrity of an LLM backup file
  """
  def verify_backup(backup_path) do
    case read_backup_file(backup_path) do
      {:ok, backup_data} ->
        case validate_backup_data(backup_data) do
          :ok ->
            stats = calculate_backup_stats(backup_data)
            
            {:ok, %{
              format_version: backup_data.format_version,
              created_at: backup_data.created_at,
              source_node: backup_data.node,
              stats: stats,
              integrity: :valid
            }}
          
          {:error, reason} ->
            {:error, {:invalid_backup, reason}}
        end
      
      error ->
        error
    end
  end
  
  # Private Functions
  
  defp export_responses(filters, include_expired) do
    current_time = :erlang.system_time(:millisecond)
    
    TransactionWrapper.read_transaction(fn ->
      # Build query pattern based on filters
      base_pattern = {:llm_responses, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      
      conditions = []
      
      conditions = if include_expired do
        conditions
      else
        [{:>, {:element, 12, :"$_"}, current_time} | conditions]  # expires_at > current_time
      end
      
      # Add provider filter if specified
      conditions = case Map.get(filters, :provider) do
        nil -> conditions
        provider -> [{:==, {:element, 4, :"$_"}, provider} | conditions]
      end
      
      # Add time range filter if specified
      conditions = case Map.get(filters, :since) do
        nil -> conditions
        since -> [{:>=, {:element, 11, :"$_"}, since} | conditions]
      end
      
      query_spec = [{base_pattern, conditions, [:"$_"]}]
      
      :mnesia.select(:llm_responses, query_spec)
      |> Enum.chunk_every(@chunk_size)
      |> Enum.to_list()
    end)
  end
  
  defp export_provider_status(filters) do
    TransactionWrapper.read_transaction(fn ->
      base_pattern = {:llm_provider_status, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      
      conditions = case Map.get(filters, :provider_status) do
        nil -> []
        status -> [{:==, {:element, 4, :"$_"}, status}]
      end
      
      query_spec = [{base_pattern, conditions, [:"$_"]}]
      
      :mnesia.select(:llm_provider_status, query_spec)
      |> Enum.chunk_every(@chunk_size)
      |> Enum.to_list()
    end)
  end
  
  defp write_backup_file(backup_path, backup_data, compress) do
    # Ensure backup directory exists
    backup_dir = Path.dirname(backup_path)
    File.mkdir_p(backup_dir)
    
    encoded_data = :erlang.term_to_binary(backup_data, [:compressed])
    
    final_data = if compress do
      :zlib.gzip(encoded_data)
    else
      encoded_data
    end
    
    File.write(backup_path, final_data)
  end
  
  defp read_backup_file(backup_path) do
    case File.read(backup_path) do
      {:ok, file_data} ->
        try do
          # Try to decompress first
          decompressed_data = try do
            :zlib.gunzip(file_data)
          rescue
            _ -> file_data  # Not compressed
          end
          
          backup_data = :erlang.binary_to_term(decompressed_data, [:safe])
          {:ok, backup_data}
        rescue
          error ->
            {:error, {:decode_error, error}}
        end
      
      error ->
        error
    end
  end
  
  defp validate_backup_data(backup_data) do
    required_fields = [:format_version, :created_at, :node, :data]
    
    cond do
      not is_map(backup_data) ->
        {:error, :invalid_format}
      
      not Enum.all?(required_fields, &Map.has_key?(backup_data, &1)) ->
        {:error, :missing_required_fields}
      
      not is_map(backup_data.data) ->
        {:error, :invalid_data_format}
      
      backup_data.format_version != @backup_format_version ->
        Logger.warning("Backup format version mismatch: #{backup_data.format_version} vs #{@backup_format_version}")
        :ok  # Allow different versions for migration
      
      true ->
        :ok
    end
  end
  
  defp restore_data(backup_data, opts) do
    stats = %{
      responses_restored: 0,
      responses_skipped: 0,
      provider_status_restored: 0,
      provider_status_skipped: 0,
      errors: []
    }
    
    stats = if opts.restore_responses do
      restore_responses(backup_data.data.llm_responses, opts, stats)
    else
      stats
    end
    
    stats = if opts.restore_provider_status do
      restore_provider_status(backup_data.data.llm_provider_status, opts, stats)
    else
      stats
    end
    
    stats
  end
  
  defp restore_responses(response_chunks, opts, stats) when is_list(response_chunks) do
    Enum.reduce(response_chunks, stats, fn chunk, acc_stats ->
      Enum.reduce(chunk, acc_stats, fn record, record_stats ->
        restore_single_response(record, opts, record_stats)
      end)
    end)
  end
  
  defp restore_single_response(record, opts, stats) do
    {_, response_id, _, _, _, _, _, _, _, _, _, _, _, _} = record
    
    # Update node field to target node
    updated_record = put_elem(record, 13, opts.target_node)
    
    case TransactionWrapper.read_transaction(fn -> :mnesia.read(:llm_responses, response_id) end) do
      {:ok, []} ->
        # Record doesn't exist, safe to insert
        case TransactionWrapper.create_record(:llm_responses, updated_record, broadcast: false) do
          {:ok, _} ->
            %{stats | responses_restored: stats.responses_restored + 1}
          {:error, reason} ->
            error = {:response_restore_failed, response_id, reason}
            %{stats | errors: [error | stats.errors]}
        end
      
      {:ok, [_existing]} ->
        if opts.overwrite_existing do
          case TransactionWrapper.write_transaction(:llm_responses, :update, updated_record, broadcast: false) do
            {:ok, _} ->
              %{stats | responses_restored: stats.responses_restored + 1}
            {:error, reason} ->
              error = {:response_update_failed, response_id, reason}
              %{stats | errors: [error | stats.errors]}
          end
        else
          %{stats | responses_skipped: stats.responses_skipped + 1}
        end
      
      {:error, reason} ->
        error = {:response_read_failed, response_id, reason}
        %{stats | errors: [error | stats.errors]}
    end
  end
  
  defp restore_provider_status(status_chunks, opts, stats) when is_list(status_chunks) do
    Enum.reduce(status_chunks, stats, fn chunk, acc_stats ->
      Enum.reduce(chunk, acc_stats, fn record, record_stats ->
        restore_single_provider_status(record, opts, record_stats)
      end)
    end)
  end
  
  defp restore_single_provider_status(record, opts, stats) do
    {_, provider_id, _, _, _, _, _, _, _, _, _, _, _, _} = record
    
    # Update node field to target node
    updated_record = put_elem(record, 13, opts.target_node)
    
    case TransactionWrapper.read_transaction(fn -> :mnesia.read(:llm_provider_status, provider_id) end) do
      {:ok, []} ->
        # Record doesn't exist, safe to insert
        case TransactionWrapper.create_record(:llm_provider_status, updated_record, broadcast: false) do
          {:ok, _} ->
            %{stats | provider_status_restored: stats.provider_status_restored + 1}
          {:error, reason} ->
            error = {:provider_status_restore_failed, provider_id, reason}
            %{stats | errors: [error | stats.errors]}
        end
      
      {:ok, [_existing]} ->
        if opts.overwrite_existing do
          case TransactionWrapper.write_transaction(:llm_provider_status, :update, updated_record, broadcast: false) do
            {:ok, _} ->
              %{stats | provider_status_restored: stats.provider_status_restored + 1}
            {:error, reason} ->
              error = {:provider_status_update_failed, provider_id, reason}
              %{stats | errors: [error | stats.errors]}
          end
        else
          %{stats | provider_status_skipped: stats.provider_status_skipped + 1}
        end
      
      {:error, reason} ->
        error = {:provider_status_read_failed, provider_id, reason}
        %{stats | errors: [error | stats.errors]}
    end
  end
  
  defp calculate_backup_stats(backup_data) do
    response_count = backup_data.data.llm_responses
    |> List.flatten()
    |> length()
    
    provider_status_count = backup_data.data.llm_provider_status
    |> List.flatten()
    |> length()
    
    %{
      total_responses: response_count,
      total_provider_status: provider_status_count,
      format_version: backup_data.format_version,
      created_at: backup_data.created_at,
      source_node: backup_data.node
    }
  end
  
  defp migrate_backup_format(backup_data, target_version) do
    # For now, just update the version field
    # In future versions, this would handle actual data transformations
    %{backup_data | 
      format_version: target_version,
      migrated_at: :erlang.system_time(:millisecond),
      migrated_by: node()
    }
  end
end