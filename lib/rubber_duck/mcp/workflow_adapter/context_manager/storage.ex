defmodule RubberDuck.MCP.WorkflowAdapter.ContextManager.Storage do
  @moduledoc """
  Storage backend for workflow context management.

  Provides efficient storage and retrieval of workflow contexts using ETS
  with optional persistence to disk for durability.
  """

  # TODO: Implement StorageBehaviour when needed
  # @behaviour RubberDuck.MCP.WorkflowAdapter.ContextManager.StorageBehaviour

  require Logger

  @type storage_state :: %{
          table: atom(),
          persistent: boolean(),
          storage_path: String.t() | nil
        }

  @table_name :workflow_contexts

  @doc """
  Initializes the storage backend.
  """
  @spec init(keyword()) :: {:ok, storage_state()}
  def init(opts) do
    persistent = Keyword.get(opts, :persistent, false)
    storage_path = Keyword.get(opts, :storage_path, "priv/contexts")

    # Create ETS table for contexts
    table = :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    state = %{
      table: table,
      persistent: persistent,
      storage_path: storage_path
    }

    # Load persisted contexts if enabled
    if persistent do
      load_persisted_contexts(state)
    end

    {:ok, state}
  end

  @doc """
  Stores a context in the storage backend.
  """
  @spec store_context(storage_state(), map()) :: :ok | {:error, term()}
  def store_context(state, context) do
    try do
      # Store in ETS
      :ets.insert(state.table, {context.id, context})

      # Persist to disk if enabled
      if state.persistent do
        persist_context(state, context)
      end

      :ok
    rescue
      error ->
        Logger.error("Failed to store context #{context.id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Retrieves a context from the storage backend.
  """
  @spec get_context(storage_state(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_context(state, context_id) do
    case :ets.lookup(state.table, context_id) do
      [{^context_id, context}] ->
        {:ok, context}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Deletes a context from the storage backend.
  """
  @spec delete_context(storage_state(), String.t()) :: :ok | {:error, term()}
  def delete_context(state, context_id) do
    try do
      # Delete from ETS
      :ets.delete(state.table, context_id)

      # Delete from persistent storage if enabled
      if state.persistent do
        delete_persisted_context(state, context_id)
      end

      :ok
    rescue
      error ->
        Logger.error("Failed to delete context #{context_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Lists contexts matching the given filters.
  """
  @spec list_contexts(storage_state(), keyword()) :: [map()]
  def list_contexts(state, filters) do
    # Get all contexts from ETS
    all_contexts =
      :ets.tab2list(state.table)
      |> Enum.map(fn {_id, context} -> context end)

    # Apply filters
    filtered_contexts = apply_filters(all_contexts, filters)

    # Apply limit if specified
    limit = Keyword.get(filters, :limit)

    if limit do
      Enum.take(filtered_contexts, limit)
    else
      filtered_contexts
    end
  end

  @doc """
  Cleans up expired contexts.
  """
  @spec cleanup_expired_contexts(storage_state()) :: integer()
  def cleanup_expired_contexts(state) do
    current_time = DateTime.utc_now()

    # Find expired contexts
    expired_contexts =
      :ets.tab2list(state.table)
      |> Enum.filter(fn {_id, context} ->
        case context.expires_at do
          nil -> false
          expires_at -> DateTime.compare(current_time, expires_at) == :gt
        end
      end)

    # Delete expired contexts
    Enum.each(expired_contexts, fn {context_id, _context} ->
      delete_context(state, context_id)
    end)

    length(expired_contexts)
  end

  @doc """
  Gets storage statistics.
  """
  @spec get_stats(storage_state()) :: map()
  def get_stats(state) do
    total_contexts = :ets.info(state.table, :size)

    # Calculate expired contexts
    current_time = DateTime.utc_now()

    expired_count =
      :ets.tab2list(state.table)
      |> Enum.count(fn {_id, context} ->
        case context.expires_at do
          nil -> false
          expires_at -> DateTime.compare(current_time, expires_at) == :gt
        end
      end)

    %{
      total_contexts: total_contexts,
      expired_contexts: expired_count,
      active_contexts: total_contexts - expired_count,
      persistent_storage: state.persistent,
      storage_path: state.storage_path
    }
  end

  # Private helper functions

  defp load_persisted_contexts(state) do
    if File.exists?(state.storage_path) do
      try do
        File.ls!(state.storage_path)
        |> Enum.each(fn filename ->
          if String.ends_with?(filename, ".json") do
            load_context_file(state, Path.join(state.storage_path, filename))
          end
        end)

        Logger.info("Loaded persisted contexts from #{state.storage_path}")
      rescue
        error ->
          Logger.error("Failed to load persisted contexts: #{inspect(error)}")
      end
    end
  end

  defp load_context_file(state, filepath) do
    try do
      content = File.read!(filepath)
      context = Jason.decode!(content, keys: :atoms)

      # Convert datetime strings back to DateTime structs
      context = deserialize_context(context)

      :ets.insert(state.table, {context.id, context})
    rescue
      error ->
        Logger.error("Failed to load context file #{filepath}: #{inspect(error)}")
    end
  end

  defp persist_context(state, context) do
    if state.storage_path do
      try do
        # Ensure storage directory exists
        File.mkdir_p!(state.storage_path)

        # Serialize context to JSON
        serialized_context = serialize_context(context)
        json_content = Jason.encode!(serialized_context, pretty: true)

        # Write to file
        filepath = Path.join(state.storage_path, "#{context.id}.json")
        File.write!(filepath, json_content)
      rescue
        error ->
          Logger.error("Failed to persist context #{context.id}: #{inspect(error)}")
      end
    end
  end

  defp delete_persisted_context(state, context_id) do
    if state.storage_path do
      filepath = Path.join(state.storage_path, "#{context_id}.json")

      if File.exists?(filepath) do
        File.rm!(filepath)
      end
    end
  end

  defp serialize_context(context) do
    context
    |> Map.update!(:created_at, &DateTime.to_iso8601/1)
    |> Map.update!(:updated_at, &DateTime.to_iso8601/1)
    |> Map.update(:expires_at, nil, fn
      nil -> nil
      datetime -> DateTime.to_iso8601(datetime)
    end)
  end

  defp deserialize_context(context) do
    context
    |> Map.update!(:created_at, fn datetime_string ->
      {:ok, datetime, _} = DateTime.from_iso8601(datetime_string)
      datetime
    end)
    |> Map.update!(:updated_at, fn datetime_string ->
      {:ok, datetime, _} = DateTime.from_iso8601(datetime_string)
      datetime
    end)
    |> Map.update(:expires_at, nil, fn
      nil ->
        nil

      datetime_string ->
        {:ok, datetime, _} = DateTime.from_iso8601(datetime_string)
        datetime
    end)
  end

  defp apply_filters(contexts, filters) do
    Enum.filter(contexts, fn context ->
      Enum.all?(filters, fn {key, value} ->
        apply_filter(context, key, value)
      end)
    end)
  end

  defp apply_filter(context, :user_id, user_id) do
    get_in(context, [:data, "user_id"]) == user_id ||
      get_in(context, [:data, :user_id]) == user_id
  end

  defp apply_filter(context, :session_id, session_id) do
    get_in(context, [:data, "session_id"]) == session_id ||
      get_in(context, [:data, :session_id]) == session_id
  end

  defp apply_filter(context, :created_after, datetime) do
    DateTime.compare(context.created_at, datetime) != :lt
  end

  defp apply_filter(context, :created_before, datetime) do
    DateTime.compare(context.created_at, datetime) != :gt
  end

  defp apply_filter(context, :version, version) do
    context.version == version
  end

  defp apply_filter(context, :has_metadata, key) do
    Map.has_key?(context.metadata, key)
  end

  defp apply_filter(_context, :limit, _limit) do
    # Limit is handled separately in list_contexts
    true
  end

  defp apply_filter(_context, _key, _value) do
    # Unknown filter, ignore
    true
  end
end
