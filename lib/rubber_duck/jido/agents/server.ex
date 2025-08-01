defmodule RubberDuck.Jido.Agents.Server do
  @moduledoc """
  GenServer wrapper for Jido agents.
  
  This server holds a Jido agent as state and provides a process-based interface
  while maintaining the data-structure nature of Jido agents. It handles:
  
  - Agent lifecycle (initialization, state updates, termination)
  - Action execution through the agent
  - State persistence and recovery
  - Health monitoring integration
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Jido
  alias RubberDuck.Jido.Registries.SignalActionRegistry
  
  @type state :: %{
    agent: Jido.Agent.t(),
    agent_id: String.t(),
    agent_module: module(),
    metadata: map(),
    stats: map()
  }
  
  # Client API
  
  @doc """
  Starts an agent server.
  
  ## Options
  - `:agent_module` - The Jido agent module (required)
  - `:agent_id` - Unique identifier for this agent instance
  - `:initial_state` - Initial state for the agent
  - `:metadata` - Additional metadata
  """
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    
    GenServer.start_link(__MODULE__, opts, name: via_tuple(agent_id))
  end
  
  @doc """
  Gets the agent ID from a server process.
  """
  def get_id(server) do
    GenServer.call(server, :get_id)
  catch
    :exit, _ -> {:error, :agent_dead}
  end
  
  @doc """
  Gets detailed information about the agent.
  """
  def get_info(server) do
    GenServer.call(server, :get_info)
  catch
    :exit, _ -> {:error, :agent_dead}
  end
  
  @doc """
  Gets the current agent state.
  """
  def get_agent(server) do
    GenServer.call(server, :get_agent)
  end
  
  @doc """
  Executes an action on the agent.
  """
  def execute_action(server, action, params \\ %{}) do
    GenServer.call(server, {:execute_action, action, params})
  end
  
  @doc """
  Updates the agent's state.
  """
  def update_state(server, updates) do
    GenServer.call(server, {:update_state, updates})
  end
  
  @doc """
  Sends a signal to the agent (if it has signal routing).
  """
  def send_signal(server, signal) do
    GenServer.cast(server, {:signal, signal})
  end
  
  @doc """
  Performs a health check on the agent.
  """
  def health_check(server) do
    GenServer.call(server, :health_check, 5000)
  catch
    :exit, _ -> {:error, :timeout}
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    agent_module = Keyword.fetch!(opts, :agent_module)
    agent_id = Keyword.fetch!(opts, :agent_id)
    initial_state = Keyword.get(opts, :initial_state, %{})
    metadata = Keyword.get(opts, :metadata, %{})
    
    Logger.info("Initializing agent server for #{agent_module} (#{agent_id})")
    
    # Create the Jido agent
    case create_agent(agent_module, initial_state) do
      {:ok, agent} ->
        state = %{
          agent: agent,
          agent_id: agent_id,
          agent_module: agent_module,
          metadata: metadata,
          stats: %{
            started_at: DateTime.utc_now(),
            actions_executed: 0,
            signals_received: 0,
            errors: 0,
            current_load: 0,
            processing_count: 0
          }
        }
        
        # Note: Registration is handled by the supervisor
        
        # Send telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :initialized],
          %{count: 1},
          %{agent_module: agent_module, agent_id: agent_id}
        )
        
        # Also emit lifecycle telemetry
        RubberDuck.Jido.Agents.Telemetry.agent_spawned(agent_id, agent_module, metadata)
        
        {:ok, state}
        
      {:error, reason} ->
        Logger.error("Failed to create agent: #{inspect(reason)}")
        {:stop, reason}
    end
  end
  
  @impl true
  def handle_call(:get_id, _from, state) do
    {:reply, {:ok, state.agent_id}, state}
  end
  
  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      agent_id: state.agent_id,
      agent_module: state.agent_module,
      metadata: state.metadata,
      stats: state.stats,
      restart_policy: get_restart_policy(state),
      health_status: check_health(state)
    }
    
    {:reply, {:ok, info}, state}
  end
  
  @impl true
  def handle_call(:get_agent, _from, state) do
    {:reply, {:ok, state.agent}, state}
  end
  
  @impl true
  def handle_call({:execute_action, action, params}, _from, state) do
    Logger.debug("Executing action #{inspect(action)} on agent #{state.agent_id}")
    
    # Update load metrics
    new_stats = state.stats
    |> Map.update!(:current_load, &(&1 + 1))
    |> Map.update!(:processing_count, &(&1 + 1))
    
    # Report load to registry
    RubberDuck.Jido.Agents.Registry.update_load(state.agent_id, new_stats.current_load)
    
    state = %{state | stats: new_stats}
    
    # Use telemetry for action execution
    start_time = System.monotonic_time()
    metadata = %{agent_id: state.agent_id, agent_module: state.agent_module, action: action}
    
    # Emit start event
    :telemetry.execute(
      [:rubber_duck, :agent, :action, :start],
      %{system_time: System.system_time()},
      metadata
    )
    
    # Execute the action through the agent module
    result = if function_exported?(state.agent_module, :execute_action, 3) do
      case state.agent_module.execute_action(state.agent, action, params) do
        {:ok, _result, updated_agent} -> {:ok, updated_agent}
        {:error, _} = error -> error
      end
    else
      # Fallback to plan/run for agents not yet migrated
      with {:ok, planned_agent} <- state.agent_module.plan(state.agent, action, params),
           run_result <- state.agent_module.run(planned_agent) do
        case run_result do
          {:ok, executed_agent, _metadata} -> {:ok, executed_agent}
          {:ok, executed_agent} -> {:ok, executed_agent}
          error -> error
        end
      end
    end
    
    duration = System.monotonic_time() - start_time
    
    # Update stats and agent based on result
    {reply, new_state} = case result do
      {:ok, updated_agent} ->
        stats = state.stats
        |> Map.update!(:actions_executed, &(&1 + 1))
        |> Map.update!(:current_load, &(max(0, &1 - 1)))
        
        # Report decreased load to registry
        RubberDuck.Jido.Agents.Registry.update_load(state.agent_id, stats.current_load)
        
        # Emit stop event
        :telemetry.execute(
          [:rubber_duck, :agent, :action, :stop],
          %{duration: duration},
          metadata
        )
        
        {{:ok, updated_agent}, %{state | agent: updated_agent, stats: stats}}
        
      {:error, reason} = error ->
        stats = state.stats
        |> Map.update!(:actions_executed, &(&1 + 1))
        |> Map.update!(:errors, &(&1 + 1))
        |> Map.update!(:current_load, &(max(0, &1 - 1)))
        
        # Report decreased load to registry
        RubberDuck.Jido.Agents.Registry.update_load(state.agent_id, stats.current_load)
        
        # Emit exception event
        :telemetry.execute(
          [:rubber_duck, :agent, :action, :exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: reason})
        )
        
        # Emit error telemetry
        RubberDuck.Jido.Agents.Telemetry.agent_error(state.agent_id, reason, metadata)
        
        {error, %{state | stats: stats}}
    end
    
    {:reply, reply, new_state}
  end
  
  @impl true
  def handle_call({:update_state, updates}, _from, state) do
    case state.agent_module.set(state.agent, updates) do
      {:ok, updated_agent} ->
        {:reply, :ok, %{state | agent: updated_agent}}
        
      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call(:health_check, _from, state) do
    health = check_health(state)
    {:reply, {:ok, health}, state}
  end

  @impl true
  def handle_call({:health_probe, probe_type}, _from, state) do
    result = perform_health_probe(probe_type, state)
    {:reply, result, state}
  end
  
  @impl true
  def handle_cast({:signal, signal}, state) do
    Logger.debug("Agent #{state.agent_id} received signal: #{inspect(signal["type"])}")
    
    stats = Map.update!(state.stats, :signals_received, &(&1 + 1))
    
    # Route signal through action system
    new_state = case route_signal_to_actions(state, signal) do
      {:ok, %{agent: updated_agent}} ->
        %{state | agent: updated_agent, stats: stats}
        
      {:error, reason} ->
        Logger.error("Signal routing failed: #{inspect(reason)}")
        stats = Map.update!(stats, :errors, &(&1 + 1))
        %{state | stats: stats}
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:system, :drain}, state) do
    # Handle graceful shutdown drain phase
    Logger.debug("Agent #{state.agent_id} entering drain phase")
    {:noreply, state}
  end
  
  @impl true
  def handle_info(msg, state) do
    Logger.warning("Agent server #{state.agent_id} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  @impl true
  def terminate(reason, state) do
    Logger.info("Agent server #{state.agent_id} terminating: #{inspect(reason)}")
    
    # Note: Unregistration is handled by the Supervisor when it stops agents
    # The Registry also monitors processes and auto-unregisters on termination
    
    # Send telemetry
    :telemetry.execute(
      [:rubber_duck, :jido, :agent, :terminated],
      %{count: 1},
      %{
        agent_id: state.agent_id,
        agent_module: state.agent_module,
        reason: reason
      }
    )
    
    # Also emit lifecycle telemetry
    RubberDuck.Jido.Agents.Telemetry.agent_terminated(state.agent_id, reason, %{
      agent_module: state.agent_module,
      uptime: DateTime.diff(DateTime.utc_now(), state.stats.started_at, :second)
    })
    
    :ok
  end
  
  # Private functions
  
  defp via_tuple(agent_id) do
    {:via, Registry, {RubberDuck.Jido.Agents.ProcessRegistry, agent_id}}
  end
  
  defp create_agent(agent_module, initial_state) do
    # Create agent using agent module's new/0 function and then set state
    try do
      agent = agent_module.new()
      
      # Check if we got an agent struct
      if is_struct(agent) and Map.has_key?(agent, :__struct__) do
        # Set initial state if provided
        if map_size(initial_state) > 0 do
          case agent_module.set(agent, initial_state) do
            {:ok, updated_agent} -> {:ok, updated_agent}
            error -> error
          end
        else
          {:ok, agent}
        end
      else
        {:error, {:invalid_agent, agent}}
      end
    rescue
      e ->
        {:error, e}
    end
  end
  
  defp check_health(state) do
    uptime = DateTime.diff(DateTime.utc_now(), state.stats.started_at, :second)
    error_rate = if state.stats.actions_executed > 0 do
      state.stats.errors / state.stats.actions_executed
    else
      0.0
    end
    
    %{
      status: determine_health_status(error_rate, uptime),
      uptime_seconds: uptime,
      actions_executed: state.stats.actions_executed,
      signals_received: state.stats.signals_received,
      error_rate: error_rate,
      last_check: DateTime.utc_now()
    }
  end
  
  defp determine_health_status(error_rate, uptime) do
    cond do
      uptime < 5 -> :starting
      error_rate > 0.5 -> :unhealthy
      error_rate > 0.1 -> :degraded
      true -> :healthy
    end
  end
  
  defp get_restart_policy(state) do
    # Check ETS for policy override
    case :ets.lookup(:agent_restart_policies, state.agent_id) do
      [{_, policy}] -> policy
      [] -> :permanent  # default
    end
  rescue
    _ -> :permanent
  end

  defp perform_health_probe(:liveness, state) do
    # Liveness: Is the agent process responding?
    # We're already in a handle_call, so if we're here, we're alive
    {:ok, %{
      alive: true,
      agent_id: state.agent_id,
      uptime: DateTime.diff(DateTime.utc_now(), state.stats.started_at, :second)
    }}
  end

  defp perform_health_probe(:readiness, state) do
    # Readiness: Can the agent accept new work?
    # Check current load and error rate
    error_rate = if state.stats.actions_executed > 0 do
      state.stats.errors / state.stats.actions_executed
    else
      0.0
    end
    
    ready = state.stats.current_load < 10 and error_rate < 0.5
    
    {:ok, %{
      ready: ready,
      current_load: state.stats.current_load,
      error_rate: error_rate,
      processing_count: state.stats.processing_count
    }}
  end

  defp perform_health_probe(:startup, state) do
    # Startup: Has the agent completed initialization?
    uptime = DateTime.diff(DateTime.utc_now(), state.stats.started_at, :second)
    
    # Consider started if uptime > 5 seconds and we've executed at least one action
    # or if uptime > 30 seconds regardless
    started = uptime > 30 or (uptime > 5 and state.stats.actions_executed > 0)
    
    {:ok, %{
      started: started,
      uptime: uptime,
      actions_executed: state.stats.actions_executed
    }}
  end

  defp perform_health_probe(unknown_probe, _state) do
    {:error, {:unknown_probe_type, unknown_probe}}
  end
  
  defp route_signal_to_actions(state, signal) do
    # Check if agent has signal mappings
    if function_exported?(state.agent_module, :signal_mappings, 0) do
      # Register mappings if not already done
      ensure_mappings_registered(state.agent_module)
      
      # Route through action registry
      SignalActionRegistry.route_signal(state.agent_id, state.agent_module, signal)
    else
      # No action support
      {:error, :no_action_support}
    end
  end
  
  defp ensure_mappings_registered(agent_module) do
    # Check if already registered (could use ETS for caching)
    case SignalActionRegistry.get_adapter(agent_module) do
      {:ok, _adapter} ->
        :ok
        
      {:error, :not_found} ->
        # Get mappings and register them
        mappings = agent_module.signal_mappings()
        |> Enum.map(fn {pattern, {action, extractor}} ->
          %{
            pattern: pattern,
            action: action,
            extractor: extractor
          }
        end)
        
        SignalActionRegistry.register_agent_mappings(agent_module, mappings)
    end
  end
end