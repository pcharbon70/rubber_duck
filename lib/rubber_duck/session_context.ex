defmodule RubberDuck.SessionContext do
  @moduledoc """
  Session context management for user-specific configurations.

  This module provides session-aware context that includes user LLM
  preferences and automatically resolves configuration for LLM requests.

  ## Features

  - Session-based user identification
  - Automatic LLM configuration resolution
  - Context persistence across requests
  - User preference caching
  - Fallback to global configuration
  """

  use GenServer
  require Logger

  alias RubberDuck.{UserConfig, LLM}

  @type session_id :: String.t()
  @type user_id :: String.t()
  @type context :: %{
          session_id: session_id(),
          user_id: user_id(),
          llm_config: map(),
          preferences: map(),
          last_used_provider: atom() | nil,
          last_used_model: String.t() | nil,
          request_count: non_neg_integer(),
          created_at: DateTime.t(),
          last_activity: DateTime.t()
        }

  # 5 minutes
  @default_cleanup_interval 300_000

  # Client API

  @doc """
  Starts the session context manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates or updates session context.
  """
  @spec create_context(session_id(), user_id(), map()) :: {:ok, context()} | {:error, term()}
  def create_context(session_id, user_id, opts \\ %{}) do
    GenServer.call(__MODULE__, {:create_context, session_id, user_id, opts})
  end

  @doc """
  Gets session context.
  """
  @spec get_context(session_id()) :: {:ok, context()} | {:error, :not_found}
  def get_context(session_id) do
    GenServer.call(__MODULE__, {:get_context, session_id})
  end

  @doc """
  Updates user preferences in the session context.
  """
  @spec update_preferences(session_id(), map()) :: :ok | {:error, term()}
  def update_preferences(session_id, preferences) do
    GenServer.call(__MODULE__, {:update_preferences, session_id, preferences})
  end

  @doc """
  Gets the resolved LLM configuration for a session.

  This function resolves the user's LLM preferences and returns the
  provider and model that should be used for this session.
  """
  @spec get_llm_config(session_id()) :: {:ok, %{provider: atom(), model: String.t()}} | {:error, term()}
  def get_llm_config(session_id) do
    GenServer.call(__MODULE__, {:get_llm_config, session_id})
  end

  @doc """
  Records LLM usage for a session.

  This updates the session context with the provider and model used,
  and optionally updates the user's configuration usage statistics.
  """
  @spec record_llm_usage(session_id(), atom(), String.t()) :: :ok
  def record_llm_usage(session_id, provider, model) do
    GenServer.call(__MODULE__, {:record_llm_usage, session_id, provider, model})
  end

  @doc """
  Removes session context.
  """
  @spec remove_context(session_id()) :: :ok
  def remove_context(session_id) do
    GenServer.call(__MODULE__, {:remove_context, session_id})
  end

  @doc """
  Lists all active session contexts.
  """
  @spec list_contexts() :: [context()]
  def list_contexts do
    GenServer.call(__MODULE__, :list_contexts)
  end

  @doc """
  Gets session context statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server implementation

  @impl GenServer
  def init(opts) do
    # Create ETS table for session contexts
    :ets.new(:session_contexts, [:set, :public, :named_table])

    # Schedule cleanup
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)
    schedule_cleanup(cleanup_interval)

    state = %{
      cleanup_interval: cleanup_interval,
      stats: %{
        contexts_created: 0,
        contexts_updated: 0,
        contexts_removed: 0,
        llm_requests: 0
      }
    }

    Logger.info("Session Context Manager started")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:create_context, session_id, user_id, opts}, _from, state) do
    # Get user's LLM configuration
    llm_config =
      case UserConfig.get_resolved_config(user_id) do
        {:ok, config} -> config
        {:error, _} -> %{provider: nil, model: nil}
      end

    # Create context
    context = %{
      session_id: session_id,
      user_id: user_id,
      llm_config: llm_config,
      preferences: Map.get(opts, :preferences, %{}),
      last_used_provider: nil,
      last_used_model: nil,
      request_count: 0,
      created_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now()
    }

    # Store context
    :ets.insert(:session_contexts, {session_id, context})

    new_state = update_in(state.stats.contexts_created, &(&1 + 1))

    Logger.debug("Created session context for user #{user_id} (session: #{session_id})")
    {:reply, {:ok, context}, new_state}
  end

  @impl GenServer
  def handle_call({:get_context, session_id}, _from, state) do
    case :ets.lookup(:session_contexts, session_id) do
      [{^session_id, context}] ->
        {:reply, {:ok, context}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:update_preferences, session_id, preferences}, _from, state) do
    case :ets.lookup(:session_contexts, session_id) do
      [{^session_id, context}] ->
        updated_context = %{
          context
          | preferences: Map.merge(context.preferences, preferences),
            last_activity: DateTime.utc_now()
        }

        :ets.insert(:session_contexts, {session_id, updated_context})
        new_state = update_in(state.stats.contexts_updated, &(&1 + 1))

        {:reply, :ok, new_state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_llm_config, session_id}, _from, state) do
    case :ets.lookup(:session_contexts, session_id) do
      [{^session_id, context}] ->
        # Return the user's resolved LLM config
        case context.llm_config do
          %{provider: provider, model: model} when not is_nil(provider) and not is_nil(model) ->
            {:reply, {:ok, %{provider: provider, model: model}}, state}

          _ ->
            # Fall back to global configuration
            case LLM.Config.get_current_provider_and_model() do
              {provider, model} when not is_nil(provider) and not is_nil(model) ->
                {:reply, {:ok, %{provider: provider, model: model}}, state}

              _ ->
                {:reply, {:error, :no_llm_config}, state}
            end
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:record_llm_usage, session_id, provider, model}, _from, state) do
    case :ets.lookup(:session_contexts, session_id) do
      [{^session_id, context}] ->
        # Update context with usage
        updated_context = %{
          context
          | last_used_provider: provider,
            last_used_model: model,
            request_count: context.request_count + 1,
            last_activity: DateTime.utc_now()
        }

        :ets.insert(:session_contexts, {session_id, updated_context})

        # Update user's LLM config usage in the background
        Task.start(fn ->
          case UserConfig.get_provider_config(context.user_id, provider) do
            {:ok, _config} ->
              # Increment usage through Memory domain
              RubberDuck.Memory.increment_usage(context.user_id, provider)

            {:error, _} ->
              # User doesn't have this provider configured, skip
              :ok
          end
        end)

        new_state = update_in(state.stats.llm_requests, &(&1 + 1))

        {:reply, :ok, new_state}

      [] ->
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_call({:remove_context, session_id}, _from, state) do
    :ets.delete(:session_contexts, session_id)
    new_state = update_in(state.stats.contexts_removed, &(&1 + 1))

    Logger.debug("Removed session context for session #{session_id}")
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:list_contexts, _from, state) do
    contexts =
      :ets.tab2list(:session_contexts)
      |> Enum.map(fn {_session_id, context} -> context end)
      |> Enum.sort_by(& &1.last_activity, {:desc, DateTime})

    {:reply, contexts, state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats =
      Map.merge(state.stats, %{
        active_contexts: :ets.info(:session_contexts, :size),
        uptime_ms: System.monotonic_time(:millisecond)
      })

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    # Remove stale contexts (older than 1 hour)
    one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

    # Get all contexts and filter stale ones
    # ETS match specifications don't work well with map field access
    all_contexts = :ets.tab2list(:session_contexts)
    
    stale_contexts = 
      all_contexts
      |> Enum.filter(fn {_session_id, context} ->
        DateTime.compare(context.last_activity, one_hour_ago) == :lt
      end)
      |> Enum.map(fn {session_id, _context} -> session_id end)

    removed_count =
      Enum.reduce(stale_contexts, 0, fn session_id, count ->
        :ets.delete(:session_contexts, session_id)
        count + 1
      end)

    if removed_count > 0 do
      Logger.info("Cleaned up #{removed_count} stale session contexts")
    end

    new_state = update_in(state.stats.contexts_removed, &(&1 + removed_count))

    # Schedule next cleanup
    schedule_cleanup(state.cleanup_interval)

    {:noreply, new_state}
  end

  # Private functions

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end

  @doc """
  Helper function to create or get session context with user-aware LLM config.

  This is a convenience function that can be used in channels or other
  contexts to ensure session context is properly initialized.
  """
  @spec ensure_context(session_id(), user_id(), map()) :: {:ok, context()} | {:error, term()}
  def ensure_context(session_id, user_id, opts \\ %{}) do
    case get_context(session_id) do
      {:ok, context} ->
        {:ok, context}

      {:error, :not_found} ->
        create_context(session_id, user_id, opts)
    end
  end

  @doc """
  Helper function to get LLM completion options with user context.

  This function takes standard LLM options and enhances them with
  user-specific configuration from the session context.
  """
  @spec enhance_llm_options(session_id(), keyword()) :: keyword()
  def enhance_llm_options(session_id, opts) do
    case get_llm_config(session_id) do
      {:ok, %{provider: provider, model: model}} ->
        # Get user_id from context for tracking
        user_id =
          case get_context(session_id) do
            {:ok, context} -> context.user_id
            _ -> nil
          end

        # Enhance options with user config
        opts
        |> Keyword.put_new(:model, model)
        |> Keyword.put_new(:user_id, user_id)
        |> Keyword.put(:provider, provider)

      {:error, _} ->
        # Return original options if no user config
        opts
    end
  end
end
