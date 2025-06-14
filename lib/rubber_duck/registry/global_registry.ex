defmodule RubberDuck.Registry.GlobalRegistry do
  @moduledoc """
  Global process registry using Syn for cluster-wide process discovery and management.
  Provides seamless process location across all nodes in the distributed cluster
  with automatic failover and load balancing capabilities.
  """
  require Logger

  @doc """
  Registers a process globally with optional metadata for load balancing.
  """
  def register(name, pid \\ self(), metadata \\ %{}) do
    case :syn.register(name, pid, metadata) do
      :ok ->
        Logger.debug("Successfully registered process #{inspect(name)} on node #{node()}")
        :ok
      
      {:error, :taken} ->
        Logger.warn("Process name #{inspect(name)} already taken")
        {:error, :already_registered}
      
      {:error, reason} ->
        Logger.error("Failed to register process #{inspect(name)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Unregisters a process from the global registry.
  """
  def unregister(name) do
    case :syn.unregister(name) do
      :ok ->
        Logger.debug("Successfully unregistered process #{inspect(name)}")
        :ok
      
      {:error, :not_registered} ->
        Logger.debug("Process #{inspect(name)} was not registered")
        :ok
      
      {:error, reason} ->
        Logger.error("Failed to unregister process #{inspect(name)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Finds a process by name across the cluster.
  """
  def whereis(name) do
    case :syn.whereis(name) do
      :undefined ->
        nil
      
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          pid
        else
          Logger.warn("Found dead process for #{inspect(name)}, cleaning up")
          unregister(name)
          nil
        end
    end
  end

  @doc """
  Gets metadata for a registered process.
  """
  def get_metadata(name) do
    case :syn.get_meta(name) do
      :undefined ->
        {:error, :not_found}
      
      metadata ->
        {:ok, metadata}
    end
  end

  @doc """
  Updates metadata for a registered process.
  """
  def update_metadata(name, metadata) do
    case :syn.put_meta(name, metadata) do
      :ok ->
        Logger.debug("Updated metadata for #{inspect(name)}")
        :ok
      
      {:error, reason} ->
        Logger.error("Failed to update metadata for #{inspect(name)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists all registered processes across the cluster.
  """
  def list_processes do
    try do
      :syn.get_members(:default)
    rescue
      e ->
        Logger.error("Failed to list processes: #{inspect(e)}")
        []
    end
  end

  @doc """
  Lists processes by a pattern or filter function.
  """
  def list_processes_by_pattern(pattern) when is_binary(pattern) do
    list_processes()
    |> Enum.filter(fn {name, _pid, _metadata} ->
      name_str = to_string(name)
      String.contains?(name_str, pattern)
    end)
  end

  def list_processes_by_pattern(filter_fn) when is_function(filter_fn, 1) do
    list_processes()
    |> Enum.filter(filter_fn)
  end

  @doc """
  Finds processes by metadata criteria.
  """
  def find_by_metadata(criteria) when is_map(criteria) do
    list_processes()
    |> Enum.filter(fn {_name, _pid, metadata} ->
      matches_criteria?(metadata, criteria)
    end)
  end

  @doc """
  Registers a process with automatic re-registration on node changes.
  """
  def register_persistent(name, pid \\ self(), metadata \\ %{}) do
    enhanced_metadata = Map.merge(metadata, %{
      registered_at: System.monotonic_time(:millisecond),
      node: node(),
      persistent: true
    })
    
    case register(name, pid, enhanced_metadata) do
      :ok ->
        # Monitor the process for automatic cleanup
        ref = Process.monitor(pid)
        RubberDuck.Registry.ProcessMonitor.add_monitoring(name, pid, ref)
        :ok
      
      error ->
        error
    end
  end

  @doc """
  Finds the least loaded process from a group of processes.
  """
  def find_least_loaded(process_pattern) do
    candidates = list_processes_by_pattern(process_pattern)
    
    case candidates do
      [] ->
        {:error, :no_processes_found}
      
      processes ->
        least_loaded = Enum.min_by(processes, fn {_name, _pid, metadata} ->
          Map.get(metadata, :load, 0)
        end)
        
        {name, pid, _metadata} = least_loaded
        {:ok, {name, pid}}
    end
  end

  @doc """
  Distributes a task to available processes using round-robin.
  """
  def distribute_task(process_pattern, task_fn) when is_function(task_fn, 1) do
    case list_processes_by_pattern(process_pattern) do
      [] ->
        {:error, :no_processes_available}
      
      processes ->
        # Simple round-robin selection
        selected_process = select_round_robin(processes)
        
        case selected_process do
          {name, pid, _metadata} ->
            try do
              result = task_fn.(pid)
              update_process_load(name, 1)
              {:ok, result}
            rescue
              e ->
                Logger.error("Task execution failed for #{inspect(name)}: #{inspect(e)}")
                {:error, {:task_failed, e}}
            after
              update_process_load(name, -1)
            end
          
          nil ->
            {:error, :no_healthy_processes}
        end
    end
  end

  @doc """
  Gets cluster-wide statistics about registered processes.
  """
  def get_cluster_stats do
    processes = list_processes()
    nodes = :syn.get_cluster_nodes()
    
    stats_by_node = Enum.group_by(processes, fn {_name, pid, _metadata} ->
      node(pid)
    end)
    
    %{
      total_processes: length(processes),
      total_nodes: length(nodes),
      nodes: nodes,
      processes_by_node: Enum.map(stats_by_node, fn {node, procs} ->
        {node, length(procs)}
      end) |> Enum.into(%{}),
      cluster_health: calculate_cluster_health(stats_by_node, nodes)
    }
  end

  @doc """
  Handles node join events for process re-distribution.
  """
  def handle_node_join(node) do
    Logger.info("Node joined cluster: #{node}")
    
    # Trigger process rebalancing if needed
    spawn(fn -> rebalance_processes_for_node(node) end)
    
    :ok
  end

  @doc """
  Handles node leave events for process failover.
  """
  def handle_node_leave(node) do
    Logger.warn("Node left cluster: #{node}")
    
    # Find processes that were on the departed node
    lost_processes = find_processes_on_node(node)
    
    if length(lost_processes) > 0 do
      Logger.warn("Lost #{length(lost_processes)} processes from node #{node}")
      
      # Trigger recovery for lost processes
      spawn(fn -> recover_lost_processes(lost_processes) end)
    end
    
    :ok
  end

  # Private functions

  defp matches_criteria?(metadata, criteria) do
    Enum.all?(criteria, fn {key, value} ->
      Map.get(metadata, key) == value
    end)
  end

  defp select_round_robin(processes) do
    # Simple round-robin based on current time
    index = rem(System.monotonic_time(:microsecond), length(processes))
    Enum.at(processes, index)
  end

  defp update_process_load(name, delta) do
    case get_metadata(name) do
      {:ok, metadata} ->
        current_load = Map.get(metadata, :load, 0)
        new_load = max(0, current_load + delta)
        new_metadata = Map.put(metadata, :load, new_load)
        update_metadata(name, new_metadata)
      
      {:error, _} ->
        :ok
    end
  end

  defp calculate_cluster_health(stats_by_node, nodes) do
    if length(nodes) == 0 do
      :unhealthy
    else
      active_nodes = map_size(stats_by_node)
      health_ratio = active_nodes / length(nodes)
      
      cond do
        health_ratio >= 0.8 -> :healthy
        health_ratio >= 0.5 -> :degraded
        true -> :unhealthy
      end
    end
  end

  defp rebalance_processes_for_node(new_node) do
    # Check if rebalancing is needed
    stats = get_cluster_stats()
    
    if should_rebalance?(stats) do
      Logger.info("Triggering process rebalancing after node join: #{new_node}")
      trigger_process_rebalancing()
    end
  end

  defp find_processes_on_node(node) do
    list_processes()
    |> Enum.filter(fn {_name, pid, _metadata} ->
      node(pid) == node
    end)
  end

  defp recover_lost_processes(lost_processes) do
    Logger.info("Attempting to recover #{length(lost_processes)} lost processes")
    
    Enum.each(lost_processes, fn {name, _pid, metadata} ->
      if Map.get(metadata, :persistent, false) do
        attempt_process_recovery(name, metadata)
      end
    end)
  end

  defp attempt_process_recovery(name, metadata) do
    Logger.info("Attempting to recover process: #{inspect(name)}")
    
    # Try to restart the process based on its metadata
    case Map.get(metadata, :recovery_module) do
      nil ->
        Logger.warn("No recovery module specified for #{inspect(name)}")
      
      module when is_atom(module) ->
        try do
          case apply(module, :recover_process, [name, metadata]) do
            {:ok, new_pid} ->
              register_persistent(name, new_pid, metadata)
              Logger.info("Successfully recovered process #{inspect(name)}")
            
            {:error, reason} ->
              Logger.error("Failed to recover process #{inspect(name)}: #{inspect(reason)}")
          end
        rescue
          e ->
            Logger.error("Recovery attempt failed for #{inspect(name)}: #{inspect(e)}")
        end
    end
  end

  defp should_rebalance?(stats) do
    # Simple heuristic: rebalance if load is very uneven
    processes_by_node = stats.processes_by_node
    
    if map_size(processes_by_node) < 2 do
      false
    else
      values = Map.values(processes_by_node)
      max_load = Enum.max(values)
      min_load = Enum.min(values)
      
      # Rebalance if difference is more than 50%
      (max_load - min_load) / max_load > 0.5
    end
  end

  defp trigger_process_rebalancing do
    # Send rebalancing event to interested processes
    case whereis(:process_rebalancer) do
      nil ->
        Logger.debug("No process rebalancer registered")
      
      pid ->
        send(pid, :trigger_rebalancing)
    end
  end
end