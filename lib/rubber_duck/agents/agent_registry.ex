defmodule RubberDuck.Agents.AgentRegistry do
  @moduledoc """
  Custom registry for agents that supports advanced querying capabilities.

  This registry solves the limitations of Elixir's standard Registry by:
  - Supporting queries by agent type
  - Finding agents by capabilities
  - Enabling efficient broadcasts to agent groups
  - Supporting pub/sub with event types
  - Providing metadata-based queries

  ## Architecture

  Uses a GenServer with ETS tables for efficient lookups:
  - `:agent_registry` - Main registry table with agent metadata
  - `:agent_capabilities` - Capability index for fast capability lookups
  - `:event_subscribers` - Event subscription tracking

  ## Example Usage

      # Register an agent
      AgentRegistry.register_agent("analysis_1", self(), %{
        type: :analysis,
        capabilities: [:code_analysis, :security_review],
        status: :idle
      })

      # Find agents by type
      {:ok, agents} = AgentRegistry.find_by_type(:analysis)

      # Find agents by capability
      {:ok, agents} = AgentRegistry.find_by_capability(:code_generation)

      # Subscribe to events
      AgentRegistry.subscribe(:task_completed, self())

      # Broadcast to agent type
      AgentRegistry.broadcast_to_type(:analysis, {:update, config})
  """

  use GenServer

  require Logger

  # Client API

  @doc """
  Starts the agent registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers an agent with metadata.
  """
  def register_agent(agent_id, pid, metadata) do
    GenServer.call(__MODULE__, {:register_agent, agent_id, pid, metadata})
  end

  @doc """
  Unregisters an agent.
  """
  def unregister_agent(agent_id) do
    GenServer.call(__MODULE__, {:unregister_agent, agent_id})
  end

  @doc """
  Updates agent metadata.
  """
  def update_agent(agent_id, updates) do
    GenServer.call(__MODULE__, {:update_agent, agent_id, updates})
  end

  @doc """
  Looks up an agent by ID.
  """
  def lookup_agent(agent_id) do
    case :ets.lookup(:agent_registry, agent_id) do
      [{^agent_id, pid, metadata}] ->
        if Process.alive?(pid) do
          {:ok, pid, metadata}
        else
          # Clean up dead process
          unregister_agent(agent_id)
          {:error, :agent_not_found}
        end

      [] ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  Finds all agents of a specific type.
  """
  def find_by_type(agent_type) do
    agents =
      :ets.match_object(:agent_registry, {:_, :_, %{type: agent_type}})
      |> Enum.filter(fn {_id, pid, _meta} -> Process.alive?(pid) end)
      |> Enum.map(fn {id, pid, meta} -> {id, pid, meta} end)

    {:ok, agents}
  end

  @doc """
  Finds agents with a specific capability.
  """
  def find_by_capability(capability) do
    case :ets.lookup(:agent_capabilities, capability) do
      [{^capability, agent_ids}] ->
        agents =
          agent_ids
          |> Enum.map(&lookup_agent/1)
          |> Enum.filter(fn
            {:ok, _, _} -> true
            _ -> false
          end)
          |> Enum.map(fn {:ok, pid, meta} -> {pid, meta} end)

        {:ok, agents}

      [] ->
        {:ok, []}
    end
  end

  @doc """
  Finds all agents matching a filter function.
  """
  def find_by_filter(filter_fn) when is_function(filter_fn, 1) do
    agents =
      :ets.tab2list(:agent_registry)
      |> Enum.filter(fn {_id, pid, metadata} ->
        Process.alive?(pid) && filter_fn.(metadata)
      end)

    {:ok, agents}
  end

  @doc """
  Lists all registered agents.
  """
  def list_agents do
    agents =
      :ets.tab2list(:agent_registry)
      |> Enum.filter(fn {_id, pid, _meta} -> Process.alive?(pid) end)

    {:ok, agents}
  end

  @doc """
  Broadcasts a message to all agents of a specific type.
  """
  def broadcast_to_type(agent_type, message) do
    {:ok, agents} = find_by_type(agent_type)

    count =
      Enum.reduce(agents, 0, fn {_id, pid, _meta}, acc ->
        send(pid, message)
        acc + 1
      end)

    {:ok, count}
  end

  @doc """
  Broadcasts a message to agents with a specific capability.
  """
  def broadcast_to_capability(capability, message) do
    {:ok, agents} = find_by_capability(capability)

    count =
      Enum.reduce(agents, 0, fn {pid, _meta}, acc ->
        send(pid, message)
        acc + 1
      end)

    {:ok, count}
  end

  @doc """
  Subscribes to an event type.
  """
  def subscribe(event_type, subscriber_pid) do
    GenServer.call(__MODULE__, {:subscribe, event_type, subscriber_pid})
  end

  @doc """
  Unsubscribes from an event type.
  """
  def unsubscribe(event_type, subscriber_pid) do
    GenServer.call(__MODULE__, {:unsubscribe, event_type, subscriber_pid})
  end

  @doc """
  Publishes an event to all subscribers.
  """
  def publish_event(event_type, event_data) do
    case :ets.lookup(:event_subscribers, event_type) do
      [{^event_type, subscribers}] ->
        Enum.each(subscribers, fn pid ->
          if Process.alive?(pid) do
            send(pid, {:agent_event, event_type, event_data})
          end
        end)

        {:ok, length(subscribers)}

      [] ->
        {:ok, 0}
    end
  end

  @doc """
  Gets count of agents by type.
  """
  def agent_counts_by_type do
    :ets.tab2list(:agent_registry)
    |> Enum.filter(fn {_id, pid, _meta} -> Process.alive?(pid) end)
    |> Enum.group_by(fn {_id, _pid, meta} -> meta.type end)
    |> Map.new(fn {type, agents} -> {type, length(agents)} end)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables
    :ets.new(:agent_registry, [:set, :protected, :named_table])
    :ets.new(:agent_capabilities, [:set, :protected, :named_table])
    :ets.new(:event_subscribers, [:set, :protected, :named_table])

    # Set up process monitoring
    Process.flag(:trap_exit, true)

    {:ok, %{monitors: %{}}}
  end

  @impl true
  def handle_call({:register_agent, agent_id, pid, metadata}, _from, state) do
    # Monitor the process
    monitor_ref = Process.monitor(pid)

    # Store in main registry
    :ets.insert(:agent_registry, {agent_id, pid, metadata})

    # Update capability index
    if capabilities = Map.get(metadata, :capabilities, []) do
      Enum.each(capabilities, fn capability ->
        update_capability_index(capability, agent_id, :add)
      end)
    end

    # Track monitor
    new_monitors = Map.put(state.monitors, monitor_ref, agent_id)

    Logger.debug("Registered agent #{agent_id} with type #{metadata.type}")

    {:reply, :ok, %{state | monitors: new_monitors}}
  end

  @impl true
  def handle_call({:unregister_agent, agent_id}, _from, state) do
    case :ets.lookup(:agent_registry, agent_id) do
      [{^agent_id, _pid, metadata}] ->
        # Remove from main registry
        :ets.delete(:agent_registry, agent_id)

        # Update capability index
        if capabilities = Map.get(metadata, :capabilities, []) do
          Enum.each(capabilities, fn capability ->
            update_capability_index(capability, agent_id, :remove)
          end)
        end

        # Find and remove monitor
        {_monitor_ref, new_monitors} =
          Enum.find(state.monitors, fn {_ref, id} -> id == agent_id end)
          |> case do
            {ref, ^agent_id} ->
              Process.demonitor(ref, [:flush])
              {ref, Map.delete(state.monitors, ref)}

            nil ->
              {nil, state.monitors}
          end

        Logger.debug("Unregistered agent #{agent_id}")

        {:reply, :ok, %{state | monitors: new_monitors}}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:update_agent, agent_id, updates}, _from, state) do
    case :ets.lookup(:agent_registry, agent_id) do
      [{^agent_id, pid, metadata}] ->
        # Handle capability updates
        old_capabilities = Map.get(metadata, :capabilities, [])
        new_capabilities = Map.get(updates, :capabilities, old_capabilities)

        if old_capabilities != new_capabilities do
          # Remove old capabilities
          Enum.each(old_capabilities -- new_capabilities, fn cap ->
            update_capability_index(cap, agent_id, :remove)
          end)

          # Add new capabilities
          Enum.each(new_capabilities -- old_capabilities, fn cap ->
            update_capability_index(cap, agent_id, :add)
          end)
        end

        # Update metadata
        new_metadata = Map.merge(metadata, updates)
        :ets.insert(:agent_registry, {agent_id, pid, new_metadata})

        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:subscribe, event_type, subscriber_pid}, _from, state) do
    current_subscribers =
      case :ets.lookup(:event_subscribers, event_type) do
        [{^event_type, subs}] -> subs
        [] -> []
      end

    if subscriber_pid not in current_subscribers do
      :ets.insert(:event_subscribers, {event_type, [subscriber_pid | current_subscribers]})
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:unsubscribe, event_type, subscriber_pid}, _from, state) do
    case :ets.lookup(:event_subscribers, event_type) do
      [{^event_type, subscribers}] ->
        new_subscribers = List.delete(subscribers, subscriber_pid)

        if new_subscribers == [] do
          :ets.delete(:event_subscribers, event_type)
        else
          :ets.insert(:event_subscribers, {event_type, new_subscribers})
        end

      [] ->
        :ok
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        {:noreply, state}

      agent_id ->
        # Clean up the agent registration
        GenServer.cast(self(), {:cleanup_agent, agent_id})
        new_monitors = Map.delete(state.monitors, monitor_ref)
        {:noreply, %{state | monitors: new_monitors}}
    end
  end

  @impl true
  def handle_cast({:cleanup_agent, agent_id}, state) do
    # This is async to avoid blocking on DOWN messages
    case :ets.lookup(:agent_registry, agent_id) do
      [{^agent_id, _pid, metadata}] ->
        :ets.delete(:agent_registry, agent_id)

        # Clean up capabilities
        if capabilities = Map.get(metadata, :capabilities, []) do
          Enum.each(capabilities, fn capability ->
            update_capability_index(capability, agent_id, :remove)
          end)
        end

        Logger.debug("Cleaned up agent #{agent_id} after process exit")

      [] ->
        :ok
    end

    {:noreply, state}
  end

  # Private Functions

  defp update_capability_index(capability, agent_id, :add) do
    current_agents =
      case :ets.lookup(:agent_capabilities, capability) do
        [{^capability, agents}] -> agents
        [] -> []
      end

    if agent_id not in current_agents do
      :ets.insert(:agent_capabilities, {capability, [agent_id | current_agents]})
    end
  end

  defp update_capability_index(capability, agent_id, :remove) do
    case :ets.lookup(:agent_capabilities, capability) do
      [{^capability, agents}] ->
        new_agents = List.delete(agents, agent_id)

        if new_agents == [] do
          :ets.delete(:agent_capabilities, capability)
        else
          :ets.insert(:agent_capabilities, {capability, new_agents})
        end

      [] ->
        :ok
    end
  end
end
