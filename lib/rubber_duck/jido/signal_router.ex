defmodule RubberDuck.Jido.SignalRouter do
  @moduledoc """
  Routes CloudEvents signals to appropriate Jido actions with strict validation.
  
  This module handles:
  - Strict CloudEvents 1.0 validation
  - Dynamic signal to action mapping via Config
  - Dead letter queue for failed signals
  - Broadcasting signals to multiple agents
  - Signal pattern matching and subscriptions
  
  All signals must be valid CloudEvents. No backward compatibility is provided.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Jido.{AgentRegistry, Runtime}
  alias RubberDuck.Jido.CloudEvents.Validator
  alias RubberDuck.Jido.SignalRouter.{Config, DeadLetterQueue}
  
  @subscription_table :rubber_duck_jido_subscriptions
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Routes a signal to an agent with strict CloudEvents validation.
  
  The signal must be a valid CloudEvent or it will be rejected.
  Failed signals are sent to the dead letter queue.
  """
  @spec route(map(), map()) :: :ok | {:error, term()}
  def route(agent, signal) do
    GenServer.call(__MODULE__, {:route, agent, signal})
  end
  
  @doc """
  Internal routing function used by DLQ for retries.
  """
  @spec route_with_validation(map()) :: :ok | {:error, term()}
  def route_with_validation(signal) do
    GenServer.call(__MODULE__, {:route_validated, signal})
  end
  
  @doc """
  Broadcasts a signal to all matching agents.
  
  The signal must be a valid CloudEvent.
  """
  @spec broadcast(map(), keyword()) :: :ok | {:error, term()}
  def broadcast(signal, opts \\ []) do
    GenServer.call(__MODULE__, {:broadcast, signal, opts})
  end
  
  @doc """
  Subscribes an agent to signals matching a pattern.
  """
  @spec subscribe(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def subscribe(agent_id, pattern, opts \\ []) do
    GenServer.call(__MODULE__, {:subscribe, agent_id, pattern, opts})
  end
  
  @doc """
  Unsubscribes from a signal pattern.
  """
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(subscription_id) do
    GenServer.call(__MODULE__, {:unsubscribe, subscription_id})
  end
  
  @doc """
  Gets signal routing statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Create subscription table
    :ets.new(@subscription_table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true
    ])
    
    state = %{
      stats: %{
        routed: 0,
        broadcast: 0,
        errors: 0,
        validation_failures: 0,
        dlq_sent: 0
      }
    }
    
    Logger.info("SignalRouter started with strict CloudEvents validation")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:route, agent, signal}, _from, state) do
    # Validate CloudEvent format
    case Validator.validate(signal) do
      :ok ->
        do_route(agent, signal, state)
        
      {:error, validation_errors} ->
        Logger.error("Invalid CloudEvent: #{inspect(validation_errors)}")
        
        # Send to DLQ
        {:ok, _id} = DeadLetterQueue.add(signal, {:validation_failed, validation_errors})
        
        state = state
        |> update_in([:stats, :validation_failures], &(&1 + 1))
        |> update_in([:stats, :dlq_sent], &(&1 + 1))
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :signal_router, :validation_failed],
          %{count: 1},
          %{errors: validation_errors}
        )
        
        {:reply, {:error, {:validation_failed, validation_errors}}, state}
    end
  end
  
  @impl true
  def handle_call({:route_validated, signal}, _from, state) do
    # For DLQ retries - assumes signal is already validated
    case find_agent_for_signal(signal) do
      {:ok, agent} ->
        do_route(agent, signal, state)
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:broadcast, signal, opts}, _from, state) do
    # Validate CloudEvent format
    case Validator.validate(signal) do
      :ok ->
        # Async broadcast
        GenServer.cast(self(), {:do_broadcast, signal, opts})
        
        state = update_in(state.stats.broadcast, &(&1 + 1))
        {:reply, :ok, state}
        
      {:error, validation_errors} ->
        Logger.error("Invalid CloudEvent for broadcast: #{inspect(validation_errors)}")
        
        state = update_in(state.stats.validation_failures, &(&1 + 1))
        {:reply, {:error, {:validation_failed, validation_errors}}, state}
    end
  end
  
  @impl true
  def handle_call({:subscribe, agent_id, pattern, opts}, _from, state) do
    subscription_id = generate_subscription_id()
    
    subscription = %{
      id: subscription_id,
      agent_id: agent_id,
      pattern: pattern,
      priority: Keyword.get(opts, :priority, 50),
      filters: Keyword.get(opts, :filters, []),
      created_at: DateTime.utc_now()
    }
    
    # Store subscription
    :ets.insert(@subscription_table, {subscription_id, subscription})
    
    Logger.debug("Agent #{agent_id} subscribed to pattern #{pattern}")
    
    {:reply, {:ok, subscription_id}, state}
  end
  
  @impl true
  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    :ets.delete(@subscription_table, subscription_id)
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    stats = Map.merge(state.stats, %{
      subscriptions: :ets.info(@subscription_table, :size),
      dlq_stats: DeadLetterQueue.stats()
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:do_broadcast, signal, opts}, state) do
    signal_type = signal["type"]
    
    # Find matching subscriptions
    matching_agents = find_matching_subscriptions(signal_type, signal)
    
    # Apply optional filters
    filtered_agents = apply_broadcast_filters(matching_agents, opts)
    
    # Route to each agent
    Enum.each(filtered_agents, fn agent_id ->
      case AgentRegistry.get(agent_id) do
        {:ok, agent} ->
          spawn(fn -> do_route_internal(agent, signal) end)
          
        {:error, :not_found} ->
          # Clean up stale subscription
          cleanup_agent_subscriptions(agent_id)
      end
    end)
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp do_route(agent, signal, state) do
    case do_route_internal(agent, signal) do
      :ok ->
        state = update_in(state.stats.routed, &(&1 + 1))
        {:reply, :ok, state}
        
      {:error, reason} = error ->
        Logger.error("Failed to route signal: #{inspect(reason)}")
        
        # Send to DLQ with agent_id in metadata
        signal_with_agent = ensure_agent_in_extensions(signal, agent.id)
        {:ok, _id} = DeadLetterQueue.add(signal_with_agent, reason, agent_id: agent.id)
        
        state = state
        |> update_in([:stats, :errors], &(&1 + 1))
        |> update_in([:stats, :dlq_sent], &(&1 + 1))
        
        {:reply, error, state}
    end
  end
  
  defp do_route_internal(agent, signal) do
    # Find action for signal type using Config
    case Config.find_route(signal["type"]) do
      {:ok, action_module, param_extractor} ->
        params = param_extractor.(signal)
        
        # Execute action
        case Runtime.execute(agent, action_module, params) do
          {:ok, _result, updated_agent} ->
            # Update the agent in the registry
            AgentRegistry.update(updated_agent)
            
            # Emit telemetry
            :telemetry.execute(
              [:rubber_duck, :signal_router, :routed],
              %{count: 1},
              %{signal_type: signal["type"], agent_id: agent.id}
            )
            
            :ok
            
          {:error, reason} ->
            {:error, {:action_failed, reason}}
        end
        
      {:error, :no_route} ->
        {:error, {:no_route, signal["type"]}}
    end
  end
  
  defp find_agent_for_signal(signal) do
    # For DLQ retries, we need to find an appropriate agent
    # This is a simplified version - in production you might store agent_id with the signal
    case signal["extensions"]["agent_id"] do
      nil -> {:error, :no_agent_specified}
      agent_id -> AgentRegistry.get(agent_id)
    end
  end
  
  defp find_matching_subscriptions(signal_type, signal) do
    :ets.tab2list(@subscription_table)
    |> Enum.filter(fn {_id, sub} ->
      pattern_matches?(signal_type, sub.pattern) and
      filters_match?(signal, sub.filters)
    end)
    |> Enum.sort_by(fn {_id, sub} -> -sub.priority end)
    |> Enum.map(fn {_id, sub} -> sub.agent_id end)
    |> Enum.uniq()
  end
  
  defp pattern_matches?(signal_type, pattern) do
    if String.contains?(pattern, "*") do
      regex = 
        pattern
        |> String.replace(".", "\\.")
        |> String.replace("*", ".*")
        |> Regex.compile!()
      
      Regex.match?(regex, signal_type)
    else
      signal_type == pattern
    end
  end
  
  defp filters_match?(_signal, []), do: true
  defp filters_match?(signal, filters) do
    Enum.all?(filters, fn filter ->
      apply_filter(signal, filter)
    end)
  end
  
  defp apply_filter(signal, {:source, pattern}) do
    pattern_matches?(signal["source"], pattern)
  end
  defp apply_filter(signal, {:subject, pattern}) do
    case signal["subject"] do
      nil -> false
      subject -> pattern_matches?(subject, pattern)
    end
  end
  defp apply_filter(_signal, _), do: true
  
  defp apply_broadcast_filters(agent_ids, opts) do
    agent_ids
    |> filter_by_module(opts[:module])
    |> filter_by_limit(opts[:limit])
  end
  
  defp filter_by_module(agent_ids, nil), do: agent_ids
  defp filter_by_module(agent_ids, module) do
    Enum.filter(agent_ids, fn agent_id ->
      case AgentRegistry.get(agent_id) do
        {:ok, agent} -> agent.module == module
        _ -> false
      end
    end)
  end
  
  defp filter_by_limit(agent_ids, nil), do: agent_ids
  defp filter_by_limit(agent_ids, limit) do
    Enum.take(agent_ids, limit)
  end
  
  defp cleanup_agent_subscriptions(agent_id) do
    :ets.select_delete(@subscription_table, [
      {{:_, %{agent_id: :"$1"}}, [{:==, :"$1", agent_id}], [true]}
    ])
  end
  
  defp generate_subscription_id do
    "sub_#{Uniq.UUID.uuid4()}"
  end
  
  defp ensure_agent_in_extensions(signal, agent_id) do
    extensions = Map.get(signal, "extensions", %{})
    updated_extensions = Map.put(extensions, "agent_id", agent_id)
    Map.put(signal, "extensions", updated_extensions)
  end
end