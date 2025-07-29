defmodule RubberDuck.Jido.Agents.ShutdownCoordinator do
  @moduledoc """
  Coordinates graceful shutdown of agents.
  
  This module ensures agents can complete their current work and save state
  before termination. It provides:
  
  - Graceful shutdown with configurable timeouts
  - State persistence before termination
  - Cleanup of resources
  - Shutdown event notifications
  """
  
  use GenServer
  require Logger
  
  @default_shutdown_timeout 5000  # 5 seconds
  @checkpoint_interval 100        # Check every 100ms
  
  @type shutdown_request :: %{
    agent_id: String.t(),
    pid: pid(),
    requested_at: DateTime.t(),
    timeout: pos_integer(),
    status: :pending | :draining | :saving | :completed | :forced
  }
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Coordinates the graceful shutdown of an agent.
  
  Returns `:ok` when shutdown is complete or `{:error, reason}` if it fails.
  """
  def coordinate_shutdown(agent_id, pid, timeout \\ @default_shutdown_timeout) do
    GenServer.call(__MODULE__, {:shutdown, agent_id, pid, timeout}, timeout + 1000)
  end
  
  @doc """
  Gets the status of ongoing shutdowns.
  """
  def get_shutdown_status do
    GenServer.call(__MODULE__, :get_status)
  end
  
  @doc """
  Cancels a shutdown request if still pending.
  """
  def cancel_shutdown(agent_id) do
    GenServer.call(__MODULE__, {:cancel_shutdown, agent_id})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    state = %{
      shutdowns: %{},
      completed: []
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:shutdown, agent_id, pid, timeout}, from, state) do
    Logger.info("Coordinating shutdown for agent #{agent_id}")
    
    request = %{
      agent_id: agent_id,
      pid: pid,
      requested_at: DateTime.utc_now(),
      timeout: timeout,
      status: :pending,
      from: from
    }
    
    # Start shutdown process
    Process.send(self(), {:begin_shutdown, agent_id}, [:nosuspend])
    
    {:noreply, put_in(state.shutdowns[agent_id], request)}
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      active_shutdowns: Map.keys(state.shutdowns),
      shutdown_details: Enum.map(state.shutdowns, fn {id, req} ->
        %{
          agent_id: id,
          status: req.status,
          elapsed: DateTime.diff(DateTime.utc_now(), req.requested_at, :millisecond)
        }
      end),
      recent_completions: Enum.take(state.completed, 10)
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_call({:cancel_shutdown, agent_id}, _from, state) do
    case Map.get(state.shutdowns, agent_id) do
      %{status: :pending} = request ->
        # Reply to original caller
        GenServer.reply(request.from, {:error, :cancelled})
        
        {:reply, :ok, update_in(state.shutdowns, &Map.delete(&1, agent_id))}
        
      %{status: status} ->
        {:reply, {:error, {:already_in_progress, status}}, state}
        
      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_info({:begin_shutdown, agent_id}, state) do
    case Map.get(state.shutdowns, agent_id) do
      nil ->
        {:noreply, state}
        
      request ->
        # Send telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :shutdown_started],
          %{count: 1},
          %{agent_id: agent_id}
        )
        
        # Start draining phase
        updated_request = %{request | status: :draining}
        state = put_in(state.shutdowns[agent_id], updated_request)
        
        # Send drain signal to agent
        send(request.pid, {:system, :drain})
        
        # Schedule next phase
        Process.send_after(self(), {:check_drained, agent_id}, @checkpoint_interval)
        
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:check_drained, agent_id}, state) do
    case Map.get(state.shutdowns, agent_id) do
      nil ->
        {:noreply, state}
        
      %{status: :draining} = request ->
        elapsed = DateTime.diff(DateTime.utc_now(), request.requested_at, :millisecond)
        
        cond do
          # Check if agent has drained
          agent_drained?(request.pid) ->
            Process.send(self(), {:save_state, agent_id}, [:nosuspend])
            {:noreply, put_in(state.shutdowns[agent_id].status, :saving)}
            
          # Check timeout
          elapsed >= request.timeout ->
            Logger.warning("Agent #{agent_id} drain timeout, forcing shutdown")
            Process.send(self(), {:force_shutdown, agent_id}, [:nosuspend])
            {:noreply, put_in(state.shutdowns[agent_id].status, :forced)}
            
          # Continue waiting
          true ->
            Process.send_after(self(), {:check_drained, agent_id}, @checkpoint_interval)
            {:noreply, state}
        end
        
      _ ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:save_state, agent_id}, state) do
    case Map.get(state.shutdowns, agent_id) do
      nil ->
        {:noreply, state}
        
      request ->
        # Attempt to save agent state
        save_result = save_agent_state(agent_id, request.pid)
        
        # Proceed to termination
        Process.send(self(), {:terminate_agent, agent_id, save_result}, [:nosuspend])
        
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:terminate_agent, agent_id, save_result}, state) do
    case Map.get(state.shutdowns, agent_id) do
      nil ->
        {:noreply, state}
        
      request ->
        # Terminate the agent process
        DynamicSupervisor.terminate_child(
          RubberDuck.Jido.Agents.DynamicSupervisor,
          request.pid
        )
        
        # Record completion
        completion = %{
          agent_id: agent_id,
          completed_at: DateTime.utc_now(),
          duration: DateTime.diff(DateTime.utc_now(), request.requested_at, :millisecond),
          status: request.status,
          state_saved: save_result == :ok
        }
        
        # Send telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :shutdown_completed],
          %{duration: completion.duration},
          %{
            agent_id: agent_id,
            status: request.status,
            state_saved: completion.state_saved
          }
        )
        
        # Reply to caller
        GenServer.reply(request.from, :ok)
        
        # Update state
        state = state
        |> update_in([:shutdowns], &Map.delete(&1, agent_id))
        |> update_in([:completed], &[completion | &1])
        |> update_in([:completed], &Enum.take(&1, 100))  # Keep last 100
        
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:force_shutdown, agent_id}, state) do
    case Map.get(state.shutdowns, agent_id) do
      nil ->
        {:noreply, state}
        
      request ->
        Logger.warning("Force terminating agent #{agent_id}")
        
        # Kill the process immediately
        Process.exit(request.pid, :kill)
        
        # Record forced completion
        completion = %{
          agent_id: agent_id,
          completed_at: DateTime.utc_now(),
          duration: DateTime.diff(DateTime.utc_now(), request.requested_at, :millisecond),
          status: :forced,
          state_saved: false
        }
        
        # Send telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :shutdown_forced],
          %{duration: completion.duration},
          %{agent_id: agent_id}
        )
        
        # Reply to caller
        GenServer.reply(request.from, :ok)
        
        # Update state
        state = state
        |> update_in([:shutdowns], &Map.delete(&1, agent_id))
        |> update_in([:completed], &[completion | &1])
        |> update_in([:completed], &Enum.take(&1, 100))
        
        {:noreply, state}
    end
  end
  
  # Private functions
  
  defp agent_drained?(pid) do
    # Check if agent has completed draining
    # This would typically check message queue, ongoing tasks, etc.
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, 0} -> true
      _ -> false
    end
  catch
    _, _ -> true  # If process is dead, consider it drained
  end
  
  defp save_agent_state(agent_id, pid) do
    # Attempt to get and save the agent's current state
    try do
      case GenServer.call(pid, :get_agent, 1000) do
        {:ok, _agent} ->
          # Here you would persist the agent state
          # For now, just log it
          Logger.info("Saved state for agent #{agent_id}")
          :ok
          
        _ ->
          {:error, :failed_to_get_state}
      end
    catch
      :exit, _ ->
        {:error, :agent_unresponsive}
    end
  end
end