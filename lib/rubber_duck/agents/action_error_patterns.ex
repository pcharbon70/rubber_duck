defmodule RubberDuck.Agents.ActionErrorPatterns do
  @moduledoc """
  Common error handling patterns for Jido Actions.
  
  Provides reusable patterns for handling errors in different types of operations
  commonly performed by Actions, such as file I/O, database operations, API calls,
  and async operations.
  """
  
  alias RubberDuck.Agents.ErrorHandling
  require Logger
  
  # File I/O Patterns
  
  @doc """
  Safely reads a file with proper error handling.
  """
  def safe_file_read(path) do
    ErrorHandling.safe_execute(fn ->
      case File.read(path) do
        {:ok, content} -> 
          {:ok, content}
        {:error, :enoent} ->
          ErrorHandling.resource_error("File not found: #{path}", %{path: path})
        {:error, :eacces} ->
          ErrorHandling.permission_error("Permission denied: #{path}", %{path: path})
        {:error, reason} ->
          ErrorHandling.resource_error("Failed to read file: #{path}", %{path: path, reason: reason})
      end
    end)
  end
  
  @doc """
  Safely writes to a file with proper error handling.
  """
  def safe_file_write(path, content) do
    ErrorHandling.safe_execute(fn ->
      case File.write(path, content) do
        :ok -> 
          {:ok, %{path: path, bytes_written: byte_size(content)}}
        {:error, :enospc} ->
          ErrorHandling.resource_error("No space left on device", %{path: path})
        {:error, :eacces} ->
          ErrorHandling.permission_error("Permission denied: #{path}", %{path: path})
        {:error, reason} ->
          ErrorHandling.resource_error("Failed to write file: #{path}", %{path: path, reason: reason})
      end
    end)
  end
  
  @doc """
  Safely creates a directory with proper error handling.
  """
  def safe_mkdir(path) do
    ErrorHandling.safe_execute(fn ->
      case File.mkdir_p(path) do
        :ok -> 
          {:ok, %{path: path}}
        {:error, :eacces} ->
          ErrorHandling.permission_error("Permission denied: #{path}", %{path: path})
        {:error, reason} ->
          ErrorHandling.resource_error("Failed to create directory: #{path}", %{path: path, reason: reason})
      end
    end)
  end
  
  # Database Operation Patterns
  
  @doc """
  Safely executes a database query with retry logic.
  """
  def safe_db_query(query_fn, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    
    ErrorHandling.with_retry(fn ->
      try do
        query_fn.()
      rescue
        e in DBConnection.ConnectionError ->
          ErrorHandling.database_error("Database connection failed", %{error: Exception.message(e)})
        
        e in Postgrex.Error ->
          handle_postgres_error(e)
        
        e in Ecto.Query.CastError ->
          ErrorHandling.validation_error("Query cast error", %{error: Exception.message(e)})
        
        e ->
          ErrorHandling.database_error("Database query failed", %{error: Exception.message(e)})
      end
    end, max_retries: max_retries)
  end
  
  @doc """
  Safely executes a database transaction.
  """
  def safe_transaction(repo, transaction_fn, opts \\ []) do
    ErrorHandling.safe_execute(fn ->
      case repo.transaction(transaction_fn, opts) do
        {:ok, result} -> 
          {:ok, result}
        {:error, :rollback} ->
          ErrorHandling.database_error("Transaction rolled back", %{})
        {:error, reason} ->
          ErrorHandling.database_error("Transaction failed", %{reason: inspect(reason)})
      end
    end)
  end
  
  # API/HTTP Request Patterns
  
  @doc """
  Safely makes an HTTP request with retry logic and timeout handling.
  """
  def safe_http_request(request_fn, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    max_retries = Keyword.get(opts, :max_retries, 3)
    
    ErrorHandling.with_retry(fn ->
      task = Task.async(fn ->
        try do
          request_fn.()
        rescue
          e in HTTPoison.Error ->
            handle_http_error(e)
          
          e in Jason.DecodeError ->
            ErrorHandling.validation_error("Failed to decode JSON response", %{error: Exception.message(e)})
          
          e ->
            ErrorHandling.api_error("HTTP request failed", %{error: Exception.message(e)})
        end
      end)
      
      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> 
          result
        nil ->
          ErrorHandling.timeout_error("HTTP request timed out", %{timeout_ms: timeout})
      end
    end, max_retries: max_retries)
  end
  
  @doc """
  Safely processes an API response with rate limit handling.
  """
  def safe_api_response(response) do
    case response do
      {:ok, %{status_code: code, body: body}} when code in 200..299 ->
        {:ok, body}
      
      {:ok, %{status_code: 429, headers: headers}} ->
        retry_after = extract_retry_after(headers)
        ErrorHandling.rate_limit_error("API rate limit exceeded", %{retry_after: retry_after})
      
      {:ok, %{status_code: 401}} ->
        ErrorHandling.permission_error("API authentication failed", %{})
      
      {:ok, %{status_code: 403}} ->
        ErrorHandling.permission_error("API authorization failed", %{})
      
      {:ok, %{status_code: code, body: body}} when code in 500..599 ->
        ErrorHandling.api_error("API server error", %{status_code: code, body: body})
      
      {:ok, %{status_code: code, body: body}} ->
        ErrorHandling.api_error("API request failed", %{status_code: code, body: body})
      
      {:error, reason} ->
        ErrorHandling.api_error("API request error", %{reason: inspect(reason)})
    end
  end
  
  # Async Operation Patterns
  
  @doc """
  Safely executes async operations with timeout and error handling.
  """
  def safe_async(operations, opts \\ []) when is_list(operations) do
    timeout = Keyword.get(opts, :timeout, 5000)
    on_error = Keyword.get(opts, :on_error, :continue)  # :continue | :halt
    
    tasks = Enum.map(operations, fn operation ->
      Task.async(fn ->
        ErrorHandling.safe_execute(fn -> operation.() end)
      end)
    end)
    
    results = tasks
    |> Task.yield_many(timeout)
    |> Enum.map(fn {task, result} ->
      case result do
        {:ok, value} -> 
          value
        {:exit, reason} ->
          ErrorHandling.system_error("Task crashed", %{reason: inspect(reason)})
        nil ->
          Task.shutdown(task, :brutal_kill)
          ErrorHandling.timeout_error("Task timed out", %{timeout_ms: timeout})
      end
    end)
    
    case on_error do
      :halt ->
        # Stop on first error
        Enum.find(results, fn
          {:error, _} -> true
          _ -> false
        end) || {:ok, Enum.map(results, fn {:ok, result} -> result end)}
      
      :continue ->
        # Aggregate all results
        ErrorHandling.aggregate_errors(results)
    end
  end
  
  @doc """
  Safely processes data in batches with error recovery.
  """
  def safe_batch_process(items, process_fn, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 100)
    on_error = Keyword.get(opts, :on_error, :continue)
    
    items
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce({[], []}, fn batch, {successes, failures} ->
      batch_results = Enum.map(batch, fn item ->
        ErrorHandling.safe_execute(fn -> process_fn.(item) end)
      end)
      
      {batch_successes, batch_failures} = Enum.split_with(batch_results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      if on_error == :halt && batch_failures != [] do
        # Stop processing on first error
        {successes, failures ++ batch_failures}
      else
        {successes ++ batch_successes, failures ++ batch_failures}
      end
    end)
    |> then(fn {successes, failures} ->
      if failures == [] do
        {:ok, Enum.map(successes, fn {:ok, result} -> result end)}
      else
        ErrorHandling.aggregate_errors(successes ++ failures)
      end
    end)
  end
  
  # JSON Handling Patterns
  
  @doc """
  Safely encodes data to JSON.
  """
  def safe_json_encode(data) do
    ErrorHandling.safe_execute(fn ->
      case Jason.encode(data) do
        {:ok, json} -> 
          {:ok, json}
        {:error, reason} ->
          ErrorHandling.validation_error("JSON encoding failed", %{reason: inspect(reason)})
      end
    end)
  end
  
  @doc """
  Safely decodes JSON data.
  """
  def safe_json_decode(json) do
    ErrorHandling.safe_execute(fn ->
      case Jason.decode(json) do
        {:ok, data} -> 
          {:ok, data}
        {:error, %Jason.DecodeError{} = error} ->
          ErrorHandling.validation_error("JSON decoding failed", %{
            position: error.position,
            data: String.slice(json, 0, 100)
          })
      end
    end)
  end
  
  # Process Management Patterns
  
  @doc """
  Safely calls a GenServer with timeout handling.
  """
  def safe_genserver_call(server, request, timeout \\ 5000) do
    ErrorHandling.safe_execute(fn ->
      try do
        GenServer.call(server, request, timeout)
      catch
        :exit, {:timeout, _} ->
          ErrorHandling.timeout_error("GenServer call timed out", %{
            server: inspect(server),
            request: inspect(request),
            timeout_ms: timeout
          })
        
        :exit, {:noproc, _} ->
          ErrorHandling.resource_error("GenServer not found", %{server: inspect(server)})
        
        :exit, reason ->
          ErrorHandling.system_error("GenServer call failed", %{
            server: inspect(server),
            reason: inspect(reason)
          })
      end
    end)
  end
  
  # Private Helpers
  
  defp handle_postgres_error(error) do
    case error.postgres do
      %{code: :unique_violation} ->
        ErrorHandling.validation_error("Unique constraint violation", %{error: error.message})
      
      %{code: :foreign_key_violation} ->
        ErrorHandling.validation_error("Foreign key violation", %{error: error.message})
      
      %{code: :not_null_violation} ->
        ErrorHandling.validation_error("Not null constraint violation", %{error: error.message})
      
      %{code: :deadlock_detected} ->
        ErrorHandling.database_error("Database deadlock detected", %{error: error.message, recoverable: true})
      
      _ ->
        ErrorHandling.database_error("Database error", %{error: error.message})
    end
  end
  
  defp handle_http_error(error) do
    case error.reason do
      :timeout ->
        ErrorHandling.timeout_error("HTTP request timeout", %{})
      
      :econnrefused ->
        ErrorHandling.network_error("Connection refused", %{})
      
      :nxdomain ->
        ErrorHandling.network_error("Domain not found", %{})
      
      {:tls_alert, reason} ->
        ErrorHandling.network_error("TLS error", %{reason: reason})
      
      reason ->
        ErrorHandling.network_error("HTTP error", %{reason: inspect(reason)})
    end
  end
  
  defp extract_retry_after(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} ->
        case Integer.parse(value) do
          {seconds, _} -> seconds * 1000
          :error -> 60_000
        end
      nil ->
        60_000
    end
  end
end