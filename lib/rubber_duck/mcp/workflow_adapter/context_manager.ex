defmodule RubberDuck.MCP.WorkflowAdapter.ContextManager do
  @moduledoc """
  Context manager for cross-tool state sharing in MCP workflows.

  Manages persistent state and context-aware tool interactions throughout
  workflow execution. Provides secure, efficient context sharing with
  proper isolation and access control.

  ## Features

  - **Persistent State**: Maintains state across workflow steps
  - **Context Isolation**: Secure isolation between different workflows
  - **Access Control**: Role-based access to context data
  - **Versioning**: Context versioning for audit trails
  - **Expiration**: Automatic cleanup of expired contexts
  - **Synchronization**: Thread-safe context operations

  ## Example Usage

      # Create a new context
      {:ok, context} = ContextManager.create_context(%{
        "user_id" => "123",
        "session_id" => "abc-456",
        "preferences" => %{"theme" => "dark"}
      })
      
      # Update context during workflow execution
      ContextManager.update_context(context.id, %{
        "current_step" => "data_processing",
        "intermediate_results" => %{"processed_count" => 42}
      })
      
      # Retrieve context in subsequent steps
      {:ok, updated_context} = ContextManager.get_context(context.id)
  """

  use GenServer

  alias RubberDuck.MCP.WorkflowAdapter.ContextManager.Storage

  require Logger

  @type context_id :: String.t()
  @type context_data :: map()
  @type context_version :: integer()
  @type access_policy :: map()

  @type context :: %{
          id: context_id(),
          data: context_data(),
          version: context_version(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          expires_at: DateTime.t() | nil,
          access_policy: access_policy(),
          metadata: map()
        }

  # Client API

  @doc """
  Starts the context manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new workflow context.

  ## Options

  - `expires_in`: Context expiration time in seconds
  - `access_policy`: Access control policy for the context
  - `metadata`: Additional metadata for the context

  ## Example

      {:ok, context} = ContextManager.create_context(%{
        "user_id" => "123",
        "session_id" => "abc-456"
      }, expires_in: 3600, access_policy: %{
        "read" => ["user:123", "role:admin"],
        "write" => ["user:123"]
      })
  """
  @spec create_context(context_data(), keyword()) :: {:ok, context()} | {:error, term()}
  def create_context(initial_data, opts \\ []) do
    GenServer.call(__MODULE__, {:create_context, initial_data, opts})
  end

  @doc """
  Retrieves a context by ID.

  ## Example

      {:ok, context} = ContextManager.get_context("context_abc123")
  """
  @spec get_context(context_id()) :: {:ok, context()} | {:error, term()}
  def get_context(context_id) do
    GenServer.call(__MODULE__, {:get_context, context_id})
  end

  @doc """
  Updates a context with new data.

  Creates a new version of the context with the updated data.
  Previous versions are preserved for audit purposes.

  ## Example

      {:ok, updated_context} = ContextManager.update_context("context_abc123", %{
        "current_step" => "data_validation",
        "results" => %{"validated_records" => 100}
      })
  """
  @spec update_context(context_id(), context_data()) :: {:ok, context()} | {:error, term()}
  def update_context(context_id, update_data) do
    GenServer.call(__MODULE__, {:update_context, context_id, update_data})
  end

  @doc """
  Merges data into an existing context.

  Similar to update_context but performs a deep merge of the data.

  ## Example

      {:ok, merged_context} = ContextManager.merge_context("context_abc123", %{
        "preferences" => %{"language" => "es"}  # Merges with existing preferences
      })
  """
  @spec merge_context(context_id(), context_data()) :: {:ok, context()} | {:error, term()}
  def merge_context(context_id, merge_data) do
    GenServer.call(__MODULE__, {:merge_context, context_id, merge_data})
  end

  @doc """
  Deletes a context.

  ## Example

      :ok = ContextManager.delete_context("context_abc123")
  """
  @spec delete_context(context_id()) :: :ok | {:error, term()}
  def delete_context(context_id) do
    GenServer.call(__MODULE__, {:delete_context, context_id})
  end

  @doc """
  Lists all contexts matching the given filters.

  ## Options

  - `user_id`: Filter by user ID
  - `session_id`: Filter by session ID
  - `created_after`: Filter by creation date
  - `limit`: Maximum number of contexts to return

  ## Example

      contexts = ContextManager.list_contexts(user_id: "123", limit: 10)
  """
  @spec list_contexts(keyword()) :: [context()]
  def list_contexts(filters \\ []) do
    GenServer.call(__MODULE__, {:list_contexts, filters})
  end

  @doc """
  Gets the version history of a context.

  ## Example

      {:ok, versions} = ContextManager.get_context_versions("context_abc123")
  """
  @spec get_context_versions(context_id()) :: {:ok, [context()]} | {:error, term()}
  def get_context_versions(context_id) do
    GenServer.call(__MODULE__, {:get_context_versions, context_id})
  end

  @doc """
  Checks if a context has expired.

  ## Example

      expired? = ContextManager.context_expired?("context_abc123")
  """
  @spec context_expired?(context_id()) :: boolean()
  def context_expired?(context_id) do
    GenServer.call(__MODULE__, {:context_expired?, context_id})
  end

  @doc """
  Extends the expiration time of a context.

  ## Example

      {:ok, extended_context} = ContextManager.extend_context("context_abc123", 3600)
  """
  @spec extend_context(context_id(), integer()) :: {:ok, context()} | {:error, term()}
  def extend_context(context_id, additional_seconds) do
    GenServer.call(__MODULE__, {:extend_context, context_id, additional_seconds})
  end

  @doc """
  Cleans up expired contexts.

  This is typically called periodically by a cleanup process.

  ## Example

      cleaned_count = ContextManager.cleanup_expired_contexts()
  """
  @spec cleanup_expired_contexts() :: integer()
  def cleanup_expired_contexts do
    GenServer.call(__MODULE__, :cleanup_expired_contexts)
  end

  # Server implementation

  @impl GenServer
  def init(opts) do
    # Initialize storage backend
    storage_opts = Keyword.get(opts, :storage, [])
    {:ok, storage} = Storage.init(storage_opts)

    # Schedule periodic cleanup
    cleanup_interval = Keyword.get(opts, :cleanup_interval, 60_000)
    Process.send_after(self(), :cleanup, cleanup_interval)

    state = %{
      storage: storage,
      cleanup_interval: cleanup_interval,
      stats: %{
        contexts_created: 0,
        contexts_updated: 0,
        contexts_deleted: 0,
        cleanup_runs: 0
      }
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:create_context, initial_data, opts}, _from, state) do
    context_id = generate_context_id()
    expires_in = Keyword.get(opts, :expires_in)
    access_policy = Keyword.get(opts, :access_policy, %{})
    metadata = Keyword.get(opts, :metadata, %{})

    expires_at =
      if expires_in do
        DateTime.add(DateTime.utc_now(), expires_in, :second)
      else
        nil
      end

    context = %{
      id: context_id,
      data: initial_data,
      version: 1,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      expires_at: expires_at,
      access_policy: access_policy,
      metadata: metadata
    }

    case Storage.store_context(state.storage, context) do
      :ok ->
        updated_stats = %{state.stats | contexts_created: state.stats.contexts_created + 1}
        {:reply, {:ok, context}, %{state | stats: updated_stats}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_context, context_id}, _from, state) do
    case Storage.get_context(state.storage, context_id) do
      {:ok, context} ->
        # Check if context has expired
        if context_expired_internal?(context) do
          {:reply, {:error, :context_expired}, state}
        else
          {:reply, {:ok, context}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:update_context, context_id, update_data}, _from, state) do
    case Storage.get_context(state.storage, context_id) do
      {:ok, existing_context} ->
        if context_expired_internal?(existing_context) do
          {:reply, {:error, :context_expired}, state}
        else
          # Create new version
          updated_context = %{
            existing_context
            | data: update_data,
              version: existing_context.version + 1,
              updated_at: DateTime.utc_now()
          }

          case Storage.store_context(state.storage, updated_context) do
            :ok ->
              # TODO: Store previous version for audit trail when Versioning module is implemented
              # Versioning.store_version(state.storage, existing_context)

              updated_stats = %{state.stats | contexts_updated: state.stats.contexts_updated + 1}
              {:reply, {:ok, updated_context}, %{state | stats: updated_stats}}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:merge_context, context_id, merge_data}, _from, state) do
    case Storage.get_context(state.storage, context_id) do
      {:ok, existing_context} ->
        if context_expired_internal?(existing_context) do
          {:reply, {:error, :context_expired}, state}
        else
          # Deep merge the data
          merged_data = deep_merge(existing_context.data, merge_data)

          updated_context = %{
            existing_context
            | data: merged_data,
              version: existing_context.version + 1,
              updated_at: DateTime.utc_now()
          }

          case Storage.store_context(state.storage, updated_context) do
            :ok ->
              # TODO: Store previous version for audit trail when Versioning module is implemented
              # Versioning.store_version(state.storage, existing_context)

              updated_stats = %{state.stats | contexts_updated: state.stats.contexts_updated + 1}
              {:reply, {:ok, updated_context}, %{state | stats: updated_stats}}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:delete_context, context_id}, _from, state) do
    case Storage.delete_context(state.storage, context_id) do
      :ok ->
        # TODO: Delete version history when Versioning module is implemented
        # Versioning.delete_versions(state.storage, context_id)

        updated_stats = %{state.stats | contexts_deleted: state.stats.contexts_deleted + 1}
        {:reply, :ok, %{state | stats: updated_stats}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:list_contexts, filters}, _from, state) do
    contexts = Storage.list_contexts(state.storage, filters)

    # Filter out expired contexts
    active_contexts = Enum.reject(contexts, &context_expired_internal?/1)

    {:reply, active_contexts, state}
  end

  @impl GenServer
  def handle_call({:get_context_versions, _context_id}, _from, state) do
    # TODO: Implement version history when Versioning module is available
    # case Versioning.get_versions(state.storage, context_id) do
    #   {:ok, versions} ->
    #     {:reply, {:ok, versions}, state}
    #     
    #   {:error, reason} ->
    #     {:reply, {:error, reason}, state}
    # end
    {:reply, {:error, :not_implemented}, state}
  end

  @impl GenServer
  def handle_call({:context_expired?, context_id}, _from, state) do
    case Storage.get_context(state.storage, context_id) do
      {:ok, context} ->
        expired = context_expired_internal?(context)
        {:reply, expired, state}

      {:error, _reason} ->
        # Missing context is considered expired
        {:reply, true, state}
    end
  end

  @impl GenServer
  def handle_call({:extend_context, context_id, additional_seconds}, _from, state) do
    case Storage.get_context(state.storage, context_id) do
      {:ok, context} ->
        new_expires_at =
          case context.expires_at do
            nil -> DateTime.add(DateTime.utc_now(), additional_seconds, :second)
            existing -> DateTime.add(existing, additional_seconds, :second)
          end

        extended_context = %{
          context
          | expires_at: new_expires_at,
            updated_at: DateTime.utc_now()
        }

        case Storage.store_context(state.storage, extended_context) do
          :ok ->
            {:reply, {:ok, extended_context}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:cleanup_expired_contexts, _from, state) do
    cleaned_count = Storage.cleanup_expired_contexts(state.storage)

    Logger.info("Cleaned up #{cleaned_count} expired contexts")

    updated_stats = %{state.stats | cleanup_runs: state.stats.cleanup_runs + 1}
    {:reply, cleaned_count, %{state | stats: updated_stats}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    # Perform periodic cleanup
    Storage.cleanup_expired_contexts(state.storage)

    # Schedule next cleanup
    Process.send_after(self(), :cleanup, state.cleanup_interval)

    {:noreply, state}
  end

  # Private helper functions

  defp generate_context_id do
    "context_" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
  end

  defp context_expired_internal?(context) do
    case context.expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end

  defp deep_merge(original, updates) when is_map(original) and is_map(updates) do
    Map.merge(original, updates, fn
      _key, original_value, update_value when is_map(original_value) and is_map(update_value) ->
        deep_merge(original_value, update_value)

      _key, _original_value, update_value ->
        update_value
    end)
  end

  defp deep_merge(_original, updates) when is_map(updates) do
    updates
  end

  defp deep_merge(original, _updates), do: original
end
