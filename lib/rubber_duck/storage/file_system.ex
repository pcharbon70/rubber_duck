defmodule RubberDuck.Storage.FileSystem do
  @moduledoc """
  File system-based storage implementation for tool results.
  
  Provides persistent storage of tool execution results using the local file system.
  """
  
  require Logger
  
  @storage_dir "priv/storage/results"
  
  @doc """
  Stores a result to the file system.
  """
  @spec store(String.t(), term()) :: :ok | {:error, atom()}
  def store(key, data) do
    file_path = build_file_path(key)
    
    with :ok <- ensure_directory(file_path),
         {:ok, encoded_data} <- encode_data(data),
         :ok <- write_file(file_path, encoded_data) do
      Logger.debug("Stored result to #{file_path}")
      :ok
    else
      {:error, reason} -> 
        Logger.error("Failed to store result: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Retrieves a result from the file system.
  """
  @spec retrieve(String.t()) :: {:ok, term()} | {:error, atom()}
  def retrieve(key) do
    file_path = build_file_path(key)
    
    with {:ok, raw_data} <- read_file(file_path),
         {:ok, decoded_data} <- decode_data(raw_data) do
      {:ok, decoded_data}
    else
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> 
        Logger.error("Failed to retrieve result: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Deletes a result from the file system.
  """
  @spec delete(String.t()) :: :ok | {:error, atom()}
  def delete(key) do
    file_path = build_file_path(key)
    
    case File.rm(file_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok # Already deleted
      {:error, reason} -> 
        Logger.error("Failed to delete result: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Lists all stored results.
  """
  @spec list() :: {:ok, [String.t()]} | {:error, atom()}
  def list do
    case File.ls(@storage_dir) do
      {:ok, files} ->
        keys = Enum.map(files, &decode_file_name/1)
        {:ok, keys}
      {:error, :enoent} ->
        {:ok, []}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Lists results for a specific tool.
  """
  @spec list_for_tool(String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def list_for_tool(tool_name) do
    case list() do
      {:ok, keys} ->
        filtered_keys = Enum.filter(keys, fn key ->
          String.starts_with?(key, "results/#{tool_name}/")
        end)
        {:ok, filtered_keys}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Gets storage statistics.
  """
  @spec stats() :: map()
  def stats do
    case File.ls(@storage_dir) do
      {:ok, files} ->
        total_files = length(files)
        total_size = Enum.reduce(files, 0, fn file, acc ->
          file_path = Path.join(@storage_dir, file)
          case File.stat(file_path) do
            {:ok, %{size: size}} -> acc + size
            _ -> acc
          end
        end)
        
        %{
          total_files: total_files,
          total_size_bytes: total_size,
          storage_directory: @storage_dir
        }
      {:error, :enoent} ->
        %{
          total_files: 0,
          total_size_bytes: 0,
          storage_directory: @storage_dir
        }
      {:error, reason} ->
        %{error: reason}
    end
  end
  
  @doc """
  Cleans up old results based on age.
  """
  @spec cleanup_old_results(non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def cleanup_old_results(max_age_seconds) do
    case File.ls(@storage_dir) do
      {:ok, files} ->
        current_time = System.system_time(:second)
        deleted_count = 
          Enum.reduce(files, 0, fn file, acc ->
            file_path = Path.join(@storage_dir, file)
            case File.stat(file_path) do
              {:ok, %{mtime: mtime}} ->
                file_age = current_time - :calendar.datetime_to_gregorian_seconds(mtime)
                if file_age > max_age_seconds do
                  case File.rm(file_path) do
                    :ok -> acc + 1
                    {:error, _} -> acc
                  end
                else
                  acc
                end
              _ -> acc
            end
          end)
        
        {:ok, deleted_count}
      {:error, :enoent} ->
        {:ok, 0}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Private functions
  
  defp build_file_path(key) do
    # Replace path separators with safe characters
    safe_key = String.replace(key, "/", "_")
    encoded_key = Base.encode64(safe_key, padding: false)
    
    Path.join(@storage_dir, "#{encoded_key}.json")
  end
  
  defp decode_file_name(file_name) do
    base_name = Path.basename(file_name, ".json")
    
    case Base.decode64(base_name, padding: false) do
      {:ok, decoded} -> String.replace(decoded, "_", "/")
      :error -> file_name
    end
  end
  
  defp ensure_directory(file_path) do
    dir_path = Path.dirname(file_path)
    
    case File.mkdir_p(dir_path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp encode_data(data) do
    try do
      encoded = Jason.encode!(data)
      {:ok, encoded}
    rescue
      error -> {:error, {:encoding_failed, Exception.message(error)}}
    end
  end
  
  defp decode_data(raw_data) do
    try do
      decoded = Jason.decode!(raw_data, keys: :atoms)
      {:ok, decoded}
    rescue
      error -> {:error, {:decoding_failed, Exception.message(error)}}
    end
  end
  
  defp write_file(file_path, data) do
    case File.write(file_path, data) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp read_file(file_path) do
    case File.read(file_path) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end
end