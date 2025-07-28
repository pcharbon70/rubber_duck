defmodule RubberDuck.Jido.SignalRouter do
  @moduledoc """
  Routes CloudEvents signals to appropriate Jido actions.
  
  This module handles:
  - Signal to action mapping
  - Signal pattern matching and subscriptions
  - Broadcasting signals to multiple agents
  - CloudEvents format compliance
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Jido
  alias RubberDuck.Jido.{AgentRegistry, Runtime}
  
  @subscription_table :rubber_duck_jido_subscriptions
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Routes a signal to an agent by converting it to appropriate actions.
  """
  @spec route(map(), map()) :: :ok | {:error, term()}
  def route(agent, signal) do
    GenServer.call(__MODULE__, {:route, agent, signal})
  end
  
  @doc """
  Broadcasts a signal to all matching agents.
  """
  @spec broadcast(map(), keyword()) :: :ok
  def broadcast(signal, opts \\ []) do
    GenServer.cast(__MODULE__, {:broadcast, signal, opts})
  end
  
  @doc """
  Subscribes an agent to signals matching a pattern.
  """
  @spec subscribe(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def subscribe(agent_id, pattern) do
    GenServer.call(__MODULE__, {:subscribe, agent_id, pattern})
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
      :public,
      :bag,
      read_concurrency: true
    ])
    
    state = %{
      stats: %{
        routed: 0,
        broadcast: 0,
        errors: 0
      },
      signal_mappings: load_signal_mappings()
    }
    
    Logger.info("SignalRouter started")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:route, agent, signal}, _from, state) do
    # Convert to CloudEvent format if needed
    cloud_event = ensure_cloud_event(signal)
    
    # Find matching action
    case map_signal_to_action(cloud_event, state.signal_mappings) do
      {:ok, action_module, params} ->
        # Execute action asynchronously
        Task.start(fn ->
          case Runtime.execute(agent, action_module, params) do
            {:ok, _result, updated_agent} ->
              # Update the agent in the registry
              AgentRegistry.update(updated_agent)
              
            {:error, reason} ->
              Logger.error("Failed to execute action #{inspect(action_module)}: #{inspect(reason)}")
          end
        end)
        
        state = update_in(state.stats.routed, &(&1 + 1))
        {:reply, :ok, state}
        
      {:error, :no_mapping} ->
        Logger.warning("No action mapping for signal type: #{cloud_event["type"]}")
        state = update_in(state.stats.errors, &(&1 + 1))
        {:reply, {:error, :no_action_mapping}, state}
    end
  end
  
  @impl true
  def handle_call({:subscribe, agent_id, pattern}, _from, state) do
    subscription_id = generate_subscription_id()
    
    # Store subscription
    :ets.insert(@subscription_table, {pattern, agent_id, subscription_id})
    
    Logger.debug("Agent #{agent_id} subscribed to pattern #{pattern}")
    
    {:reply, {:ok, subscription_id}, state}
  end
  
  @impl true
  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    # Remove all entries with this subscription_id
    :ets.match_delete(@subscription_table, {:_, :_, subscription_id})
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    stats = Map.merge(state.stats, %{
      subscriptions: :ets.info(@subscription_table, :size)
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:broadcast, signal, opts}, state) do
    # Convert to CloudEvent
    cloud_event = ensure_cloud_event(signal)
    signal_type = cloud_event["type"]
    
    # Find matching subscriptions
    matching_agents = find_matching_subscriptions(signal_type)
    
    # Apply optional filters
    filtered_agents = apply_broadcast_filters(matching_agents, opts)
    
    # Route to each agent
    Enum.each(filtered_agents, fn agent_id ->
      case AgentRegistry.get(agent_id) do
        {:ok, agent} ->
          handle_call({:route, agent, cloud_event}, nil, state)
          
        {:error, :not_found} ->
          # Clean up stale subscription
          :ets.match_delete(@subscription_table, {:_, agent_id, :_})
      end
    end)
    
    state = update_in(state.stats.broadcast, &(&1 + 1))
    {:noreply, state}
  end
  
  # Private functions
  
  defp ensure_cloud_event(%{"specversion" => _} = event), do: event
  defp ensure_cloud_event(signal) do
    %{
      "specversion" => "1.0",
      "id" => Uniq.UUID.uuid4(),
      "source" => signal["source"] || "rubber_duck.jido",
      "type" => signal["type"] || signal[:type] || "unknown",
      "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "datacontenttype" => "application/json",
      "data" => signal["data"] || signal[:data] || signal
    }
  end
  
  defp map_signal_to_action(cloud_event, mappings) do
    signal_type = cloud_event["type"]
    
    # Check direct mappings first
    case Map.get(mappings, signal_type) do
      nil ->
        # Try pattern matching
        find_pattern_mapping(signal_type, mappings)
        
      {action_module, param_extractor} ->
        params = param_extractor.(cloud_event)
        {:ok, action_module, params}
    end
  end
  
  defp find_pattern_mapping(signal_type, mappings) do
    Enum.find_value(mappings, {:error, :no_mapping}, fn
      {pattern, {action_module, param_extractor}} when is_binary(pattern) ->
        if String.contains?(pattern, "*") && pattern_matches?(signal_type, pattern) do
          params = param_extractor.(%{"type" => signal_type})
          {:ok, action_module, params}
        else
          nil
        end
        
      _ ->
        nil
    end)
  end
  
  defp pattern_matches?(signal_type, pattern) do
    regex = 
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("*", ".*")
      |> Regex.compile!()
    
    Regex.match?(regex, signal_type)
  end
  
  defp find_matching_subscriptions(signal_type) do
    :ets.foldl(
      fn
        {pattern, agent_id, _sub_id}, acc ->
          if pattern_matches?(signal_type, pattern) do
            [agent_id | acc]
          else
            acc
          end
      end,
      [],
      @subscription_table
    )
    |> Enum.uniq()
  end
  
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
  
  defp generate_subscription_id do
    "sub_#{Uniq.UUID.uuid4()}"
  end
  
  defp load_signal_mappings do
    # Default signal to action mappings
    # Can be extended or loaded from config
    %{
      "increment" => {RubberDuck.Jido.Actions.Increment, &extract_increment_params/1},
      "add_message" => {RubberDuck.Jido.Actions.AddMessage, &extract_message_params/1},
      "update_status" => {RubberDuck.Jido.Actions.UpdateStatus, &extract_status_params/1}
    }
  end
  
  defp extract_increment_params(event) do
    data = event["data"] || %{}
    %{amount: data["amount"] || 1}
  end
  
  defp extract_message_params(event) do
    data = event["data"] || %{}
    %{
      message: data["message"] || "",
      timestamp: data["timestamp"] != false
    }
  end
  
  defp extract_status_params(event) do
    data = event["data"] || %{}
    %{
      status: String.to_atom(data["status"] || "idle"),
      reason: data["reason"]
    }
  end
end