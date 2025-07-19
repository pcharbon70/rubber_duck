defmodule RubberDuck.CoT.ConversationManager do
  @moduledoc """
  GenServer that manages Chain-of-Thought reasoning sessions.

  Handles execution of reasoning chains, tracks conversation history,
  and maintains state across reasoning steps.
  """

  use GenServer
  require Logger

  alias RubberDuck.CoT.{Executor, Validator, Formatter}

  @default_timeout 120_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes a reasoning chain with the given query.
  """
  def execute_chain(chain_module, query, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_chain, chain_module, query, opts}, @default_timeout)
  end

  @doc """
  Gets the history of a reasoning session.
  """
  def get_history(session_id) do
    GenServer.call(__MODULE__, {:get_history, session_id})
  end

  @doc """
  Clears the history for a session.
  """
  def clear_history(session_id) do
    GenServer.call(__MODULE__, {:clear_history, session_id})
  end

  @doc """
  Gets current statistics about reasoning performance.
  """
  def get_stats() do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      sessions: %{},
      stats: %{
        total_chains: 0,
        successful_chains: 0,
        failed_chains: 0,
        total_steps: 0,
        avg_steps_per_chain: 0.0,
        cache_hits: 0,
        cache_misses: 0
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:execute_chain, chain_module, query, opts}, _from, state) do
    session_id = generate_session_id()

    # Initialize session
    session = %{
      id: session_id,
      chain_module: chain_module,
      query: query,
      opts: opts,
      steps: [],
      status: :running,
      started_at: DateTime.utc_now(),
      context: %{}
    }

    # Get chain configuration
    chain_config = get_chain_config(chain_module)

    # Execute the chain
    case execute_reasoning_chain(session, chain_config, state) do
      {:ok, result, updated_session} ->
        # Update state
        new_state =
          state
          |> put_in([:sessions, session_id], updated_session)
          |> update_stats(:success, updated_session)

        {:reply, {:ok, result}, new_state}

      {:error, reason, updated_session} ->
        # Update state with failed session
        new_state =
          state
          |> put_in([:sessions, session_id], Map.put(updated_session, :status, :failed))
          |> update_stats(:failure, updated_session)

        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call({:get_history, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:reply, {:error, :session_not_found}, state}
      session -> {:reply, {:ok, session}, state}
    end
  end

  @impl true
  def handle_call({:clear_history, session_id}, _from, state) do
    new_state = update_in(state.sessions, &Map.delete(&1, session_id))
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  # Private functions

  defp generate_session_id() do
    "cot_session_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp get_chain_config(chain_module) do
    # Get the compiled chain configuration
    RubberDuck.CoT.Chain.reasoning_chain(chain_module)
    |> List.first()
  end

  defp execute_reasoning_chain(session, chain_config, _state) do
    # Check cache first
    cache_key = generate_cache_key(session.query, chain_config)

    case check_cache(cache_key, chain_config) do
      {:ok, cached_result} ->
        Logger.info("CoT cache hit for query: #{String.slice(session.query, 0, 50)}...")
        updated_session = Map.put(session, :cached, true)
        {:ok, cached_result, updated_session}

      :miss ->
        # Execute the chain
        Logger.info("Starting CoT reasoning chain: #{chain_config.name}")

        # Get steps from chain configuration and add chain module reference
        steps = chain_config.entities[:step] || []

        steps_with_module =
          Enum.map(steps, fn step ->
            Map.put(step, :__chain_module__, session.chain_module)
          end)

        # Execute steps
        case Executor.execute_steps(steps_with_module, session, chain_config) do
          {:ok, final_result, executed_session} ->
            # Validate the result
            case Validator.validate_chain_result(final_result, executed_session) do
              :ok ->
                # Format the result
                formatted_result = Formatter.format_result(final_result, executed_session)

                # Cache the result
                cache_result(cache_key, formatted_result, chain_config)

                # Update session
                completed_session =
                  executed_session
                  |> Map.put(:status, :completed)
                  |> Map.put(:completed_at, DateTime.utc_now())
                  |> Map.put(:result, formatted_result)

                {:ok, formatted_result, completed_session}

              {:error, validation_errors} ->
                {:error, {:validation_failed, validation_errors}, executed_session}
            end

          {:error, reason, failed_session} ->
            {:error, reason, failed_session}
        end
    end
  end

  defp generate_cache_key(query, chain_config) do
    data = "#{chain_config.name}:#{query}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp check_cache(key, chain_config) do
    _ttl = Map.get(chain_config, :cache_ttl, 900)

    case :ets.lookup(:cot_cache, key) do
      [{^key, result, expiry}] ->
        if DateTime.compare(DateTime.utc_now(), expiry) == :lt do
          {:ok, result}
        else
          :ets.delete(:cot_cache, key)
          :miss
        end

      [] ->
        :miss
    end
  rescue
    _ -> :miss
  end

  defp cache_result(key, result, chain_config) do
    ttl = Map.get(chain_config, :cache_ttl, 900)
    expiry = DateTime.add(DateTime.utc_now(), ttl, :second)

    # Ensure cache table exists
    ensure_cache_table()

    :ets.insert(:cot_cache, {key, result, expiry})
    :ok
  rescue
    _ -> :ok
  end

  defp ensure_cache_table() do
    case :ets.info(:cot_cache) do
      :undefined ->
        :ets.new(:cot_cache, [:set, :public, :named_table])

      _ ->
        :ok
    end
  end

  defp update_stats(state, :success, session) do
    steps_count = length(session.steps)

    state
    |> update_in([:stats, :total_chains], &(&1 + 1))
    |> update_in([:stats, :successful_chains], &(&1 + 1))
    |> update_in([:stats, :total_steps], &(&1 + steps_count))
    |> update_in([:stats, :avg_steps_per_chain], fn _ ->
      total_chains = state.stats.total_chains + 1
      total_steps = state.stats.total_steps + steps_count
      if total_chains > 0, do: total_steps / total_chains, else: 0.0
    end)
    |> update_in([:stats, if(Map.get(session, :cached, false), do: :cache_hits, else: :cache_misses)], &(&1 + 1))
  end

  defp update_stats(state, :failure, session) do
    steps_count = length(session.steps)

    state
    |> update_in([:stats, :total_chains], &(&1 + 1))
    |> update_in([:stats, :failed_chains], &(&1 + 1))
    |> update_in([:stats, :total_steps], &(&1 + steps_count))
  end
end
