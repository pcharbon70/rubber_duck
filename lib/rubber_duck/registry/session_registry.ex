defmodule RubberDuck.Registry.SessionRegistry do
  @moduledoc """
  Specialized registry for session management across the distributed cluster.
  Handles session lifecycle, automatic failover, and load balancing for
  AI assistant sessions with persistent state management.
  """
  require Logger

  alias RubberDuck.Registry.{GlobalRegistry, ProcessMonitor}

  @session_prefix "session"
  @session_timeout 30 * 60 * 1000  # 30 minutes

  @doc """
  Creates a new session and registers it globally.
  """
  def create_session(session_id, opts \\ []) do
    session_name = build_session_name(session_id)
    
    session_config = %{
      session_id: session_id,
      created_at: System.monotonic_time(:millisecond),
      timeout: Keyword.get(opts, :timeout, @session_timeout),
      node_preference: Keyword.get(opts, :node_preference, node()),
      persistent: Keyword.get(opts, :persistent, true),
      recovery_module: Keyword.get(opts, :recovery_module, __MODULE__)
    }
    
    case start_session_process(session_id, session_config) do
      {:ok, pid} ->
        metadata = Map.merge(session_config, %{
          type: :session,
          load: 0,
          status: :active,
          last_activity: System.monotonic_time(:millisecond)
        })
        
        case GlobalRegistry.register_persistent(session_name, pid, metadata) do
          :ok ->
            Logger.info("Created session #{session_id} on node #{node()}")
            {:ok, session_id, pid}
          
          error ->
            # Cleanup the process if registration failed
            GenServer.stop(pid, :shutdown)
            error
        end
      
      error ->
        error
    end
  end

  @doc """
  Finds an existing session across the cluster.
  """
  def find_session(session_id) do
    session_name = build_session_name(session_id)
    
    case GlobalRegistry.whereis(session_name) do
      nil ->
        {:error, :session_not_found}
      
      pid ->
        case GlobalRegistry.get_metadata(session_name) do
          {:ok, metadata} ->
            # Update last activity
            update_session_activity(session_name)
            {:ok, pid, metadata}
          
          error ->
            error
        end
    end
  end

  @doc """
  Destroys a session and cleans up its resources.
  """
  def destroy_session(session_id) do
    session_name = build_session_name(session_id)
    
    case GlobalRegistry.whereis(session_name) do
      nil ->
        {:error, :session_not_found}
      
      pid ->
        # Stop the session process
        GenServer.stop(pid, :shutdown)
        
        # Unregister from global registry
        GlobalRegistry.unregister(session_name)
        
        # Remove from monitoring
        ProcessMonitor.remove_monitoring(session_name)
        
        Logger.info("Destroyed session #{session_id}")
        :ok
    end
  end

  @doc """
  Lists all active sessions across the cluster.
  """
  def list_sessions do
    GlobalRegistry.list_processes_by_pattern(@session_prefix)
    |> Enum.map(fn {name, pid, metadata} ->
      session_id = extract_session_id(name)
      
      %{
        session_id: session_id,
        pid: pid,
        node: node(pid),
        metadata: metadata,
        status: Map.get(metadata, :status, :unknown)
      }
    end)
  end

  @doc """
  Finds the least loaded node for creating a new session.
  """
  def find_optimal_node_for_session do
    case GlobalRegistry.get_cluster_stats() do
      %{processes_by_node: node_loads} when map_size(node_loads) > 0 ->
        # Find node with least sessions
        session_loads = calculate_session_loads_by_node()
        
        optimal_node = Enum.min_by(session_loads, fn {_node, load} -> load end)
        |> elem(0)
        
        {:ok, optimal_node}
      
      _ ->
        # Fallback to current node
        {:ok, node()}
    end
  end

  @doc """
  Migrates a session to another node for load balancing.
  """
  def migrate_session(session_id, target_node) do
    session_name = build_session_name(session_id)
    
    case find_session(session_id) do
      {:ok, current_pid, metadata} ->
        if node(current_pid) == target_node do
          {:ok, :already_on_target_node}
        else
          perform_session_migration(session_id, current_pid, target_node, metadata)
        end
      
      error ->
        error
    end
  end

  @doc """
  Updates session activity timestamp.
  """
  def update_session_activity(session_id) when is_binary(session_id) do
    session_name = build_session_name(session_id)
    update_session_activity(session_name)
  end

  def update_session_activity(session_name) when is_atom(session_name) do
    case GlobalRegistry.get_metadata(session_name) do
      {:ok, metadata} ->
        updated_metadata = Map.put(metadata, :last_activity, System.monotonic_time(:millisecond))
        GlobalRegistry.update_metadata(session_name, updated_metadata)
      
      error ->
        error
    end
  end

  @doc """
  Checks for expired sessions and cleans them up.
  """
  def cleanup_expired_sessions do
    current_time = System.monotonic_time(:millisecond)
    
    expired_sessions = list_sessions()
    |> Enum.filter(fn session ->
      last_activity = Map.get(session.metadata, :last_activity, 0)
      timeout = Map.get(session.metadata, :timeout, @session_timeout)
      
      (current_time - last_activity) > timeout
    end)
    
    Enum.each(expired_sessions, fn session ->
      Logger.info("Cleaning up expired session: #{session.session_id}")
      destroy_session(session.session_id)
    end)
    
    {:ok, length(expired_sessions)}
  end

  @doc """
  Gets session statistics across the cluster.
  """
  def get_session_stats do
    sessions = list_sessions()
    
    stats_by_node = Enum.group_by(sessions, & &1.node)
    stats_by_status = Enum.group_by(sessions, &Map.get(&1.metadata, :status, :unknown))
    
    %{
      total_sessions: length(sessions),
      sessions_by_node: Enum.map(stats_by_node, fn {node, sessions} ->
        {node, length(sessions)}
      end) |> Enum.into(%{}),
      sessions_by_status: Enum.map(stats_by_status, fn {status, sessions} ->
        {status, length(sessions)}
      end) |> Enum.into(%{}),
      avg_session_age: calculate_average_session_age(sessions),
      oldest_session: find_oldest_session(sessions)
    }
  end

  @doc """
  Recovery function called by ProcessMonitor for failed sessions.
  """
  def recover_process(session_name, metadata) do
    session_id = extract_session_id(session_name)
    
    Logger.info("Attempting to recover session: #{session_id}")
    
    # Extract session configuration from metadata
    session_config = %{
      session_id: session_id,
      created_at: Map.get(metadata, :created_at, System.monotonic_time(:millisecond)),
      timeout: Map.get(metadata, :timeout, @session_timeout),
      persistent: true,
      recovery_module: __MODULE__,
      recovered: true
    }
    
    case start_session_process(session_id, session_config) do
      {:ok, pid} ->
        Logger.info("Successfully recovered session #{session_id}")
        {:ok, pid}
      
      error ->
        Logger.error("Failed to recover session #{session_id}: #{inspect(error)}")
        error
    end
  end

  # Private functions

  defp build_session_name(session_id) do
    String.to_atom("#{@session_prefix}_#{session_id}")
  end

  defp extract_session_id(session_name) when is_atom(session_name) do
    session_name
    |> Atom.to_string()
    |> String.replace_prefix("#{@session_prefix}_", "")
  end

  defp start_session_process(session_id, session_config) do
    # Start a simple GenServer for the session
    case RubberDuck.Session.SessionServer.start_link(session_id: session_id, config: session_config) do
      {:ok, pid} ->
        {:ok, pid}
      
      {:error, {:already_started, pid}} ->
        {:ok, pid}
      
      error ->
        Logger.error("Failed to start session process for #{session_id}: #{inspect(error)}")
        error
    end
  end

  defp calculate_session_loads_by_node do
    sessions = list_sessions()
    
    # Get all cluster nodes
    cluster_nodes = case GlobalRegistry.get_cluster_stats() do
      %{nodes: nodes} -> nodes
      _ -> [node()]
    end
    
    # Initialize with zero load for all nodes
    base_loads = Enum.map(cluster_nodes, &{&1, 0}) |> Enum.into(%{})
    
    # Count sessions per node
    Enum.reduce(sessions, base_loads, fn session, acc ->
      Map.update(acc, session.node, 1, &(&1 + 1))
    end)
  end

  defp perform_session_migration(session_id, current_pid, target_node, metadata) do
    Logger.info("Migrating session #{session_id} from #{node(current_pid)} to #{target_node}")
    
    try do
      # Get current session state
      session_state = GenServer.call(current_pid, :get_state)
      
      # Start new session process on target node
      case Node.spawn_link(target_node, fn ->
        start_session_process(session_id, Map.put(metadata, :migrated_from, node(current_pid)))
      end) do
        {:ok, new_pid} ->
          # Transfer state to new process
          GenServer.call(new_pid, {:restore_state, session_state})
          
          # Update registry
          session_name = build_session_name(session_id)
          GlobalRegistry.unregister(session_name)
          
          updated_metadata = Map.merge(metadata, %{
            migrated_at: System.monotonic_time(:millisecond),
            previous_node: node(current_pid)
          })
          
          case GlobalRegistry.register_persistent(session_name, new_pid, updated_metadata) do
            :ok ->
              # Stop old process
              GenServer.stop(current_pid, :shutdown)
              
              Logger.info("Successfully migrated session #{session_id} to #{target_node}")
              {:ok, new_pid}
            
            error ->
              # Cleanup new process if registration failed
              GenServer.stop(new_pid, :shutdown)
              error
          end
        
        error ->
          error
      end
    rescue
      e ->
        Logger.error("Session migration failed: #{inspect(e)}")
        {:error, {:migration_failed, e}}
    end
  end

  defp calculate_average_session_age(sessions) do
    if length(sessions) == 0 do
      0
    else
      current_time = System.monotonic_time(:millisecond)
      
      total_age = Enum.reduce(sessions, 0, fn session, acc ->
        created_at = Map.get(session.metadata, :created_at, current_time)
        acc + (current_time - created_at)
      end)
      
      div(total_age, length(sessions))
    end
  end

  defp find_oldest_session(sessions) do
    case Enum.min_by(sessions, fn session ->
      Map.get(session.metadata, :created_at, System.monotonic_time(:millisecond))
    end, fn -> nil end) do
      nil -> nil
      session -> session.session_id
    end
  end
end