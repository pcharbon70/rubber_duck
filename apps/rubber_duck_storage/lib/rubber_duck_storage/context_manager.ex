defmodule RubberDuckStorage.ContextManager do
  @moduledoc """
  GenServer for managing conversation context persistence, versioning, and retrieval.

  This module handles:
  - Context serialization and deserialization
  - Context versioning for rollback capabilities
  - Context merging strategies
  - Context pruning to manage memory usage
  - Context search functionality
  """

  use GenServer
  require Logger

  alias RubberDuckStorage.Repos.ConversationRepo

  @context_table :context_cache
  @version_table :context_versions
  @max_versions_per_conversation 10
  @prune_interval :timer.minutes(30)

  defstruct [
    :context_table,
    :version_table,
    :prune_timer
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores context for a conversation with versioning.
  """
  def store_context(conversation_id, context, version \\ nil) do
    GenServer.call(__MODULE__, {:store_context, conversation_id, context, version})
  end

  @doc """
  Retrieves the latest context for a conversation.
  """
  def get_context(conversation_id) do
    GenServer.call(__MODULE__, {:get_context, conversation_id})
  end

  @doc """
  Retrieves a specific version of context for a conversation.
  """
  def get_context_version(conversation_id, version) do
    GenServer.call(__MODULE__, {:get_context_version, conversation_id, version})
  end

  @doc """
  Merges new context with existing context using the specified strategy.
  """
  def merge_context(conversation_id, new_context, strategy \\ :deep_merge) do
    GenServer.call(__MODULE__, {:merge_context, conversation_id, new_context, strategy})
  end

  @doc """
  Searches for conversations with context matching the given criteria.
  """
  def search_context(search_params) do
    GenServer.call(__MODULE__, {:search_context, search_params})
  end

  @doc """
  Prunes old context versions for a conversation.
  """
  def prune_context(conversation_id) do
    GenServer.call(__MODULE__, {:prune_context, conversation_id})
  end

  @doc """
  Gets context version history for a conversation.
  """
  def get_version_history(conversation_id) do
    GenServer.call(__MODULE__, {:get_version_history, conversation_id})
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    # Create ETS tables for in-memory context caching
    context_table = :ets.new(@context_table, [:set, :protected, :named_table])
    version_table = :ets.new(@version_table, [:bag, :protected, :named_table])

    # Set up periodic pruning
    prune_timer = Process.send_after(self(), :prune_old_versions, @prune_interval)

    state = %__MODULE__{
      context_table: context_table,
      version_table: version_table,
      prune_timer: prune_timer
    }

    Logger.info(
      "ContextManager started with tables: #{inspect(context_table)}, #{inspect(version_table)}"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:store_context, conversation_id, context, version}, _from, state) do
    version = version || generate_version()
    timestamp = DateTime.utc_now()

    # Store in ETS cache
    :ets.insert(state.context_table, {conversation_id, context, version, timestamp})

    # Store version in version table
    :ets.insert(state.version_table, {conversation_id, version, context, timestamp})

    # Persist to database
    case ConversationRepo.change(conversation_id, %{context: serialize_context(context)}) do
      {:ok, _conversation} ->
        Logger.debug("Context stored for conversation #{conversation_id}, version #{version}")
        {:reply, {:ok, version}, state}

      {:error, reason} ->
        Logger.error(
          "Failed to persist context for conversation #{conversation_id}: #{inspect(reason)}"
        )

        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_context, conversation_id}, _from, state) do
    case :ets.lookup(state.context_table, conversation_id) do
      [{^conversation_id, context, version, _timestamp}] ->
        {:reply, {:ok, context, version}, state}

      [] ->
        # Not in cache, try to load from database
        case load_context_from_db(conversation_id) do
          {:ok, context, version} ->
            # Cache the loaded context
            timestamp = DateTime.utc_now()
            :ets.insert(state.context_table, {conversation_id, context, version, timestamp})
            {:reply, {:ok, context, version}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_context_version, conversation_id, version}, _from, state) do
    case :ets.match(state.version_table, {conversation_id, version, :"$1", :"$2"}) do
      [[context, _timestamp]] ->
        {:reply, {:ok, context}, state}

      [] ->
        # Version not found in cache
        {:reply, {:error, :version_not_found}, state}
    end
  end

  @impl true
  def handle_call({:merge_context, conversation_id, new_context, strategy}, _from, state) do
    case :ets.lookup(state.context_table, conversation_id) do
      [{^conversation_id, existing_context, _version, _timestamp}] ->
        merged_context = merge_contexts(existing_context, new_context, strategy)

        store_result =
          handle_call({:store_context, conversation_id, merged_context, nil}, nil, state)

        {:reply, elem(store_result, 1), elem(store_result, 2)}

      [] ->
        # No existing context, store new context as initial
        store_result =
          handle_call({:store_context, conversation_id, new_context, nil}, nil, state)

        {:reply, elem(store_result, 1), elem(store_result, 2)}
    end
  end

  @impl true
  def handle_call({:search_context, search_params}, _from, state) do
    # Search through cached contexts
    matches =
      :ets.tab2list(state.context_table)
      |> Enum.filter(fn {_conversation_id, context, _version, _timestamp} ->
        matches_search_criteria?(context, search_params)
      end)
      |> Enum.map(fn {conversation_id, context, version, timestamp} ->
        %{
          conversation_id: conversation_id,
          context: context,
          version: version,
          timestamp: timestamp
        }
      end)

    {:reply, {:ok, matches}, state}
  end

  @impl true
  def handle_call({:prune_context, conversation_id}, _from, state) do
    # Get all versions for this conversation
    versions =
      :ets.lookup(state.version_table, conversation_id)
      |> Enum.sort_by(fn {_id, _version, _context, timestamp} -> timestamp end, {:desc, DateTime})

    # Keep only the latest N versions
    {_keep, to_delete} = Enum.split(versions, @max_versions_per_conversation)

    # Delete old versions
    Enum.each(to_delete, fn {id, version, _context, _timestamp} ->
      :ets.delete_object(state.version_table, {id, version, :_, :_})
    end)

    pruned_count = length(to_delete)

    Logger.debug(
      "Pruned #{pruned_count} old context versions for conversation #{conversation_id}"
    )

    {:reply, {:ok, pruned_count}, state}
  end

  @impl true
  def handle_call({:get_version_history, conversation_id}, _from, state) do
    versions =
      :ets.lookup(state.version_table, conversation_id)
      |> Enum.map(fn {_id, version, _context, timestamp} ->
        %{version: version, timestamp: timestamp}
      end)
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

    {:reply, {:ok, versions}, state}
  end

  @impl true
  def handle_info(:prune_old_versions, state) do
    # Prune old versions across all conversations
    all_conversations =
      :ets.tab2list(state.context_table)
      |> Enum.map(fn {conversation_id, _context, _version, _timestamp} -> conversation_id end)
      |> Enum.uniq()

    Enum.each(all_conversations, fn conversation_id ->
      handle_call({:prune_context, conversation_id}, nil, state)
    end)

    # Schedule next pruning
    prune_timer = Process.send_after(self(), :prune_old_versions, @prune_interval)
    {:noreply, %{state | prune_timer: prune_timer}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.prune_timer do
      Process.cancel_timer(state.prune_timer)
    end

    :ok
  end

  # Private Helper Functions

  defp load_context_from_db(conversation_id) do
    case ConversationRepo.get(conversation_id) do
      nil ->
        {:error, :conversation_not_found}

      conversation ->
        context = deserialize_context(conversation.context || %{})
        version = generate_version()
        {:ok, context, version}
    end
  end

  defp serialize_context(context) do
    # Use Jason for JSON serialization
    case Jason.encode(context) do
      {:ok, json} -> json
      {:error, _} -> "{}"
    end
  end

  defp deserialize_context(context_data) when is_binary(context_data) do
    case Jason.decode(context_data) do
      {:ok, context} -> context
      {:error, _} -> %{}
    end
  end

  defp deserialize_context(context_data) when is_map(context_data), do: context_data
  defp deserialize_context(_), do: %{}

  defp merge_contexts(existing, new, :deep_merge) do
    Map.merge(existing, new, fn
      _key, existing_val, new_val when is_map(existing_val) and is_map(new_val) ->
        merge_contexts(existing_val, new_val, :deep_merge)

      _key, _existing_val, new_val ->
        new_val
    end)
  end

  defp merge_contexts(existing, new, :shallow_merge) do
    Map.merge(existing, new)
  end

  defp merge_contexts(_existing, new, :replace) do
    new
  end

  defp merge_contexts(existing, new, :append) when is_list(existing) and is_list(new) do
    existing ++ new
  end

  defp merge_contexts(_existing, new, :append) do
    new
  end

  defp matches_search_criteria?(context, search_params) do
    Enum.all?(search_params, fn {key, value} ->
      case Map.get(context, key) do
        nil -> false
        context_value -> matches_value?(context_value, value)
      end
    end)
  end

  defp matches_value?(context_value, search_value)
       when is_binary(context_value) and is_binary(search_value) do
    String.contains?(String.downcase(context_value), String.downcase(search_value))
  end

  defp matches_value?(context_value, search_value) do
    context_value == search_value
  end

  defp generate_version do
    :crypto.strong_rand_bytes(8)
    |> Base.encode64(padding: false)
  end
end
