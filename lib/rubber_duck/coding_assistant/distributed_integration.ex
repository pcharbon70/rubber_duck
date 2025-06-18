defmodule RubberDuck.CodingAssistant.DistributedIntegration do
  @moduledoc """
  Integration layer between the coding assistance engines and the existing
  distributed infrastructure (Horde, Syn, GlobalRegistry).
  
  This module provides seamless integration of the new AI coding assistance
  engines with RubberDuck's existing distributed architecture, ensuring:
  
  - Engines are properly distributed across cluster nodes
  - Engine discovery works with the global registry
  - Load balancing leverages existing coordination mechanisms
  - Health monitoring integrates with cluster management
  - Failover and recovery use established patterns
  
  ## Architecture Integration
  
  The engine system integrates with:
  - `RubberDuck.Coordination.HordeSupervisor` for distributed supervision
  - `RubberDuck.Registry.GlobalRegistry` for cluster-wide discovery
  - Existing telemetry and monitoring infrastructure
  - Established health check and failover patterns
  
  ## Usage
  
      # Start engines across the cluster
      DistributedIntegration.start_distributed_engines()
      
      # Get cluster-wide engine status
      status = DistributedIntegration.get_cluster_engine_status()
      
      # Route requests to optimal engines
      {:ok, result} = DistributedIntegration.route_request(request, :code_analysis)
  """

  require Logger
  
  alias RubberDuck.CodingAssistant.EngineRegistry
  alias RubberDuck.Coordination.HordeSupervisor
  alias RubberDuck.Registry.GlobalRegistry

  @engine_types [
    RubberDuck.CodingAssistant.Engines.CodeAnalyser,
    RubberDuck.CodingAssistant.Engines.ExplanationEngine,
    RubberDuck.CodingAssistant.Engines.RefactoringEngine,
    RubberDuck.CodingAssistant.Engines.TestGenerator
  ]

  @doc """
  Start distributed coding assistance engines across the cluster.
  
  This integrates with the existing HordeSupervisor to ensure engines
  are properly distributed and managed.
  """
  def start_distributed_engines(opts \\ []) do
    Logger.info("Starting distributed coding assistance engines")
    
    # Ensure engine registry is running
    case start_engine_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> 
        Logger.error("Failed to start engine registry: #{inspect(error)}")
        error
    end
    
    # Start each engine type across the cluster
    results = Enum.map(@engine_types, fn engine_module ->
      start_distributed_engine(engine_module, opts)
    end)
    
    # Register engines in global registry for cluster-wide discovery
    register_engines_globally()
    
    # Report results
    successful = Enum.count(results, &match?({:ok, _}, &1))
    total = length(results)
    
    Logger.info("Started #{successful}/#{total} distributed engines")
    
    if successful > 0 do
      {:ok, %{successful: successful, total: total, results: results}}
    else
      {:error, :no_engines_started}
    end
  end

  @doc """
  Get comprehensive cluster-wide engine status.
  """
  def get_cluster_engine_status do
    # Get local engine status
    local_engines = EngineRegistry.list_engines(include_metadata: true)
    
    # Get cluster-wide statistics
    cluster_stats = GlobalRegistry.get_cluster_stats()
    horde_stats = HordeSupervisor.get_supervisor_stats()
    
    # Combine information
    %{
      local_engines: %{
        count: length(local_engines),
        by_type: group_engines_by_type(local_engines),
        by_health: group_engines_by_health(local_engines)
      },
      cluster_wide: %{
        total_nodes: cluster_stats.total_nodes,
        active_nodes: length(cluster_stats.nodes),
        cluster_health: cluster_stats.cluster_health,
        processes_by_node: cluster_stats.processes_by_node
      },
      distributed_supervision: %{
        total_children: horde_stats.total_children,
        children_by_node: horde_stats.children_by_node,
        load_distribution: horde_stats.load_distribution
      },
      engine_registry: EngineRegistry.get_registry_stats()
    }
  end

  @doc """
  Route a request to the optimal engine using distributed discovery.
  
  This leverages both the local EngineRegistry and GlobalRegistry
  to find the best available engine across the cluster.
  """
  def route_request(request, required_capabilities) when is_list(required_capabilities) do
    # First try local engines for lowest latency
    case find_local_engine(required_capabilities, request) do
      {:ok, engine_info} ->
        Logger.debug("Routing request to local engine: #{engine_info.engine}")
        execute_request(engine_info, request)
        
      {:error, :no_local_engines} ->
        # Fall back to cluster-wide search
        case find_remote_engine(required_capabilities, request) do
          {:ok, engine_info} ->
            Logger.debug("Routing request to remote engine: #{engine_info.engine} on #{engine_info.node}")
            execute_remote_request(engine_info, request)
            
          {:error, reason} ->
            Logger.warning("No suitable engines found for capabilities #{inspect(required_capabilities)}: #{reason}")
            {:error, :no_engines_available}
        end
    end
  end

  def route_request(request, capability) when is_atom(capability) do
    route_request(request, [capability])
  end

  @doc """
  Trigger cluster-wide engine load balancing.
  
  This integrates with the existing HordeSupervisor load balancing
  to ensure optimal engine distribution.
  """
  def balance_engine_load do
    Logger.info("Triggering cluster-wide engine load balancing")
    
    # Get current distribution
    status = get_cluster_engine_status()
    
    # Analyze if rebalancing is needed
    case analyze_engine_distribution(status) do
      {:balanced, distribution} ->
        Logger.debug("Engine distribution is already balanced: #{inspect(distribution)}")
        {:ok, :already_balanced}
        
      {:imbalanced, imbalance_info} ->
        Logger.info("Engine distribution is imbalanced: #{inspect(imbalance_info)}")
        
        # Use HordeSupervisor's load balancing for engine processes
        case HordeSupervisor.balance_load() do
          {:ok, result} ->
            Logger.info("Engine load balancing completed: #{inspect(result)}")
            {:ok, result}
            
          {:error, reason} ->
            Logger.error("Engine load balancing failed: #{reason}")
            {:error, reason}
        end
    end
  end

  @doc """
  Handle cluster node events for engine management.
  """
  def handle_node_join(new_node) do
    Logger.info("Handling node join for engine management: #{new_node}")
    
    # Notify existing components
    HordeSupervisor.handle_node_join(new_node)
    GlobalRegistry.handle_node_join(new_node)
    
    # Trigger engine rebalancing after a short delay
    spawn(fn ->
      Process.sleep(5_000)  # Wait for node to stabilize
      balance_engine_load()
    end)
    
    :ok
  end

  def handle_node_leave(departed_node) do
    Logger.warning("Handling node departure for engine management: #{departed_node}")
    
    # Notify existing components
    HordeSupervisor.handle_node_leave(departed_node)
    GlobalRegistry.handle_node_leave(departed_node)
    
    # Check for lost engines and trigger recovery
    spawn(fn ->
      Process.sleep(2_000)  # Wait for migrations to complete
      check_and_recover_lost_engines(departed_node)
    end)
    
    :ok
  end

  @doc """
  Monitor cluster health and engine availability.
  """
  def monitor_cluster_health do
    spawn(fn ->
      health_monitor_loop()
    end)
  end

  # Private implementation

  defp start_engine_registry do
    case EngineRegistry.start_link() do
      {:ok, pid} ->
        # Register in global registry for cluster visibility
        GlobalRegistry.register_persistent(:engine_registry, pid, %{
          type: :engine_registry,
          node: node(),
          capabilities: [:engine_discovery, :engine_management]
        })
        {:ok, pid}
        
      error ->
        error
    end
  end

  defp start_distributed_engine(engine_module, opts) do
    config = Keyword.get(opts, :config, %{})
    placement = Keyword.get(opts, :placement, :automatic)
    
    # Create child spec for the engine
    child_spec = %{
      id: engine_module,
      start: {engine_module, :start_link, [config]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
    
    # Start using distributed supervisor
    case HordeSupervisor.start_child(child_spec, placement) do
      {:ok, pid} ->
        Logger.debug("Started distributed engine #{engine_module} on #{node(pid)}")
        {:ok, pid}
        
      {:error, {:already_started, pid}} ->
        Logger.debug("Engine #{engine_module} already running on #{node(pid)}")
        {:ok, pid}
        
      error ->
        Logger.error("Failed to start distributed engine #{engine_module}: #{inspect(error)}")
        error
    end
  end

  defp register_engines_globally do
    # Register engine types for global discovery
    Enum.each(@engine_types, fn engine_module ->
      name = {:coding_assistant_engine, engine_module}
      
      # Find local instance
      case EngineRegistry.list_engines(engine_module) do
        [engine_info | _] ->
          GlobalRegistry.register_persistent(name, engine_info.pid, %{
            type: :coding_assistant_engine,
            engine_module: engine_module,
            capabilities: engine_info.capabilities,
            node: node()
          })
          
        [] ->
          Logger.debug("No local instance of #{engine_module} to register globally")
      end
    end)
  end

  defp find_local_engine(capabilities, request) do
    criteria = %{
      capabilities: capabilities,
      strategy: determine_selection_strategy(request),
      exclude_unhealthy: true,
      preferred_node: node()
    }
    
    EngineRegistry.get_best_engine(capabilities, criteria)
  end

  defp find_remote_engine(capabilities, request) do
    # Search globally for engines with required capabilities
    pattern = "coding_assistant_engine"
    
    candidates = GlobalRegistry.list_processes_by_pattern(pattern)
    |> Enum.filter(fn {_name, _pid, metadata} ->
      engine_capabilities = Map.get(metadata, :capabilities, [])
      has_all_capabilities?(engine_capabilities, capabilities)
    end)
    
    case candidates do
      [] ->
        {:error, :no_remote_engines}
        
      engines ->
        # Select best remote engine
        selected = select_best_remote_engine(engines, request)
        {:ok, format_remote_engine_info(selected)}
    end
  end

  defp execute_request(engine_info, request) do
    try do
      case Map.get(request, :type, :real_time) do
        :real_time ->
          GenServer.call(engine_info.pid, {:process_real_time, request.data}, 10_000)
          
        :batch ->
          GenServer.call(engine_info.pid, {:process_batch, request.data}, 30_000)
      end
    catch
      :exit, {:timeout, _} ->
        {:error, :timeout}
      :exit, reason ->
        {:error, {:engine_died, reason}}
    end
  end

  defp execute_remote_request(engine_info, request) do
    # Execute request on remote node
    case :rpc.call(engine_info.node, GenServer, :call, [
      engine_info.pid, 
      {:process_real_time, request.data}, 
      10_000
    ]) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
    end
  end

  defp group_engines_by_type(engines) do
    Enum.group_by(engines, & &1.engine)
    |> Map.new(fn {type, engines} -> {type, length(engines)} end)
  end

  defp group_engines_by_health(engines) do
    Enum.group_by(engines, & &1.health)
    |> Map.new(fn {health, engines} -> {health, length(engines)} end)
  end

  defp analyze_engine_distribution(status) do
    children_by_node = status.distributed_supervision.children_by_node
    load_distribution = status.distributed_supervision.load_distribution
    
    # Consider imbalanced if balance score is below threshold
    if load_distribution.balance_score < 0.7 do
      {:imbalanced, %{
        balance_score: load_distribution.balance_score,
        variance: load_distribution.variance,
        recommendation: :rebalance_needed
      }}
    else
      {:balanced, %{
        balance_score: load_distribution.balance_score,
        distribution: children_by_node
      }}
    end
  end

  defp check_and_recover_lost_engines(departed_node) do
    Logger.info("Checking for lost engines on departed node: #{departed_node}")
    
    # Check if any engine types are missing
    missing_engines = Enum.filter(@engine_types, fn engine_module ->
      case EngineRegistry.list_engines(engine_module) do
        [] -> true  # No instances running
        _engines -> false
      end
    end)
    
    if length(missing_engines) > 0 do
      Logger.warning("Recovering #{length(missing_engines)} missing engine types")
      
      Enum.each(missing_engines, fn engine_module ->
        case start_distributed_engine(engine_module, []) do
          {:ok, _pid} ->
            Logger.info("Successfully recovered engine: #{engine_module}")
          {:error, reason} ->
            Logger.error("Failed to recover engine #{engine_module}: #{reason}")
        end
      end)
    else
      Logger.info("All engine types are still available after node departure")
    end
  end

  defp health_monitor_loop do
    Process.sleep(30_000)  # Check every 30 seconds
    
    try do
      status = get_cluster_engine_status()
      
      # Check cluster health
      case status.cluster_wide.cluster_health do
        :unhealthy ->
          Logger.warning("Cluster health is unhealthy: #{inspect(status)}")
          
        :degraded ->
          Logger.info("Cluster health is degraded: #{inspect(status)}")
          
        :healthy ->
          Logger.debug("Cluster health is good")
      end
      
      # Check engine distribution
      case analyze_engine_distribution(status) do
        {:imbalanced, _} ->
          Logger.info("Triggering automatic load balancing due to imbalance")
          balance_engine_load()
          
        {:balanced, _} ->
          :ok
      end
      
    rescue
      e ->
        Logger.error("Health monitoring error: #{inspect(e)}")
    end
    
    health_monitor_loop()
  end

  defp determine_selection_strategy(request) do
    case Map.get(request, :priority, :normal) do
      :urgent -> :health_weighted
      :normal -> :least_loaded
      :low -> :round_robin
    end
  end

  defp has_all_capabilities?(engine_capabilities, required_capabilities) do
    Enum.all?(required_capabilities, fn cap -> cap in engine_capabilities end)
  end

  defp select_best_remote_engine(engines, request) do
    # Simple selection based on node load
    strategy = determine_selection_strategy(request)
    
    case strategy do
      :least_loaded ->
        Enum.min_by(engines, fn {_name, _pid, metadata} ->
          Map.get(metadata, :load, 0)
        end)
        
      :health_weighted ->
        healthy_engines = Enum.filter(engines, fn {_name, _pid, metadata} ->
          Map.get(metadata, :health, :unknown) == :healthy
        end)
        
        case healthy_engines do
          [] -> List.first(engines)  # Fall back to any engine
          [engine | _] -> engine
        end
        
      :round_robin ->
        index = rem(System.monotonic_time(:microsecond), length(engines))
        Enum.at(engines, index)
    end
  end

  defp format_remote_engine_info({name, pid, metadata}) do
    %{
      name: name,
      pid: pid,
      node: node(pid),
      engine: Map.get(metadata, :engine_module),
      capabilities: Map.get(metadata, :capabilities, []),
      metadata: metadata
    }
  end
end