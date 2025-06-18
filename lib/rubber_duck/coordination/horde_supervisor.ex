defmodule RubberDuck.Coordination.HordeSupervisor do
  @moduledoc """
  Distributed supervisor using Horde for cluster-wide process management.
  Provides automatic process distribution, failover, and load balancing
  across all nodes in the distributed cluster with dynamic child management.
  """
  use Horde.DynamicSupervisor
  require Logger


  @doc """
  Starts the distributed supervisor.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Horde.DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Starts a child process under distributed supervision.
  """
  def start_child(child_spec, placement_strategy \\ :automatic) do
    case placement_strategy do
      :automatic ->
        Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
      
      {:node, target_node} ->
        start_child_on_node(child_spec, target_node)
      
      :least_loaded ->
        start_child_on_least_loaded_node(child_spec)
      
      :round_robin ->
        start_child_round_robin(child_spec)
    end
  end

  @doc """
  Terminates a child process across the cluster.
  """
  def terminate_child(child_pid) when is_pid(child_pid) do
    Horde.DynamicSupervisor.terminate_child(__MODULE__, child_pid)
  end

  def terminate_child(child_id) when is_binary(child_id) do
    case find_child_pid(child_id) do
      {:ok, pid} ->
        Horde.DynamicSupervisor.terminate_child(__MODULE__, pid)
      
      :not_found ->
        {:error, :child_not_found}
    end
  end

  @doc """
  Lists all children across the distributed supervisor.
  """
  def which_children do
    Horde.DynamicSupervisor.which_children(__MODULE__)
  end

  @doc """
  Counts children across all nodes.
  """
  def count_children do
    Horde.DynamicSupervisor.count_children(__MODULE__)
  end

  @doc """
  Gets comprehensive supervisor statistics.
  """
  def get_supervisor_stats do
    children = which_children()
    count = count_children()
    
    children_by_node = Enum.group_by(children, fn {_id, pid, _type, _modules} ->
      if is_pid(pid), do: node(pid), else: :unknown
    end)
    
    %{
      total_children: count.active,
      total_supervisors: count.supervisors,
      total_workers: count.workers,
      children_by_node: Enum.map(children_by_node, fn {node, children} ->
        {node, length(children)}
      end) |> Enum.into(%{}),
      cluster_nodes: get_cluster_members(),
      load_distribution: calculate_load_distribution(children_by_node)
    }
  end

  @doc """
  Migrates a child process to another node.
  """
  def migrate_child(child_id, target_node) do
    with {:ok, current_pid} <- find_child_pid(child_id),
         {:ok, child_spec} <- get_child_spec(current_pid),
         {:ok, new_pid} <- start_child_on_node(child_spec, target_node),
         :ok <- transfer_child_state(current_pid, new_pid),
         :ok <- terminate_child(current_pid) do
      
      Logger.info("Successfully migrated child #{child_id} to node #{target_node}")
      {:ok, new_pid}
    else
      error ->
        Logger.error("Failed to migrate child #{child_id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Triggers load balancing across cluster nodes.
  """
  def balance_load do
    stats = get_supervisor_stats()
    
    case analyze_load_imbalance(stats) do
      {:balanced, _} ->
        Logger.debug("Cluster load is already balanced")
        {:ok, :already_balanced}
      
      {:imbalanced, rebalancing_plan} ->
        Logger.info("Executing load balancing plan: #{length(rebalancing_plan)} migrations")
        execute_rebalancing_plan(rebalancing_plan)
    end
  end

  @doc """
  Handles node join events for process redistribution.
  """
  def handle_node_join(new_node) do
    Logger.info("Handling node join: #{new_node}")
    
    # Check if rebalancing is needed
    spawn(fn ->
      :timer.sleep(5000)  # Wait for node to fully join
      balance_load()
    end)
    
    :ok
  end

  @doc """
  Handles node leave events for process recovery.
  """
  def handle_node_leave(departed_node) do
    Logger.warning("Handling node departure: #{departed_node}")
    
    # Horde automatically handles process migration, but we can log it
    children_before = count_children()
    
    spawn(fn ->
      :timer.sleep(2000)  # Wait for migrations to complete
      children_after = count_children()
      
      if children_after.active < children_before.active do
        lost_children = children_before.active - children_after.active
        Logger.warning("Lost #{lost_children} children after node departure")
      else
        Logger.info("All children successfully migrated after node departure")
      end
    end)
    
    :ok
  end

  @doc """
  Gets cluster membership information.
  """
  def get_cluster_members do
    Horde.DynamicSupervisor.members(__MODULE__)
  end

  @doc """
  Registers for cluster events.
  """
  def subscribe_to_cluster_events do
    # Subscribe to libcluster events
    :net_kernel.monitor_nodes(true)
    Logger.info("Subscribed to cluster node events")
    :ok
  end

  @impl true
  def init(opts) do
    Logger.info("Starting Horde Distributed Supervisor on node #{node()}")
    
    # Subscribe to cluster events
    subscribe_to_cluster_events()
    
    [
      strategy: :one_for_one,
      members: :auto,
      distribution_strategy: Horde.UniformDistribution
    ]
    |> Keyword.merge(opts)
    |> Horde.DynamicSupervisor.init()
  end

  # Private functions

  defp start_child_on_node(child_spec, target_node) do
    if target_node == node() do
      Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
    else
      case :rpc.call(target_node, Horde.DynamicSupervisor, :start_child, [__MODULE__, child_spec]) do
        {:ok, pid} -> {:ok, pid}
        {:error, reason} -> {:error, reason}
        {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
      end
    end
  end

  defp start_child_on_least_loaded_node(child_spec) do
    case find_least_loaded_node() do
      {:ok, target_node} ->
        start_child_on_node(child_spec, target_node)
      
      {:error, :no_nodes} ->
        # Fallback to automatic placement
        Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
    end
  end

  defp start_child_round_robin(child_spec) do
    case get_next_round_robin_node() do
      {:ok, target_node} ->
        start_child_on_node(child_spec, target_node)
      
      {:error, :no_nodes} ->
        Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
    end
  end

  defp find_child_pid(child_id) do
    children = which_children()
    
    case Enum.find(children, fn {id, _pid, _type, _modules} -> id == child_id end) do
      {_id, pid, _type, _modules} -> {:ok, pid}
      nil -> :not_found
    end
  end

  defp get_child_spec(_pid) do
    # In a real implementation, this would extract the child spec
    # For now, return a placeholder
    {:ok, %{id: :placeholder, start: {GenServer, :start_link, []}}}
  end

  defp transfer_child_state(_from_pid, _to_pid) do
    # In a real implementation, this would transfer state between processes
    # For now, just return success
    :ok
  end

  defp find_least_loaded_node do
    stats = get_supervisor_stats()
    
    case stats.children_by_node do
      children_by_node when map_size(children_by_node) > 0 ->
        {least_loaded_node, _count} = Enum.min_by(children_by_node, fn {_node, count} -> count end)
        {:ok, least_loaded_node}
      
      _ ->
        {:error, :no_nodes}
    end
  end

  defp get_next_round_robin_node do
    cluster_nodes = get_cluster_members()
    
    case cluster_nodes do
      [] -> {:error, :no_nodes}
      nodes ->
        # Simple round-robin based on current time
        index = rem(System.monotonic_time(:microsecond), length(nodes))
        {:ok, Enum.at(nodes, index)}
    end
  end

  defp calculate_load_distribution(children_by_node) do
    if map_size(children_by_node) == 0 do
      %{balance_score: 1.0, variance: 0.0}
    else
      counts = Map.values(children_by_node)
      avg_count = Enum.sum(counts) / length(counts)
      
      variance = Enum.reduce(counts, 0, fn count, acc ->
        acc + :math.pow(count - avg_count, 2)
      end) / length(counts)
      
      max_count = Enum.max(counts)
      min_count = Enum.min(counts)
      
      balance_score = if max_count > 0 do
        1.0 - ((max_count - min_count) / max_count)
      else
        1.0
      end
      
      %{
        balance_score: balance_score,
        variance: variance,
        avg_children_per_node: avg_count,
        max_children_per_node: max_count,
        min_children_per_node: min_count
      }
    end
  end

  defp analyze_load_imbalance(stats) do
    load_dist = stats.load_distribution
    
    # Consider imbalanced if balance score is below threshold
    if load_dist.balance_score < 0.7 do
      rebalancing_plan = generate_rebalancing_plan(stats)
      {:imbalanced, rebalancing_plan}
    else
      {:balanced, load_dist}
    end
  end

  defp generate_rebalancing_plan(stats) do
    children_by_node = stats.children_by_node
    avg_children = stats.load_distribution.avg_children_per_node
    
    # Find overloaded and underloaded nodes
    overloaded_nodes = Enum.filter(children_by_node, fn {_node, count} ->
      count > avg_children * 1.3
    end)
    
    underloaded_nodes = Enum.filter(children_by_node, fn {_node, count} ->
      count < avg_children * 0.7
    end)
    
    # Generate migration plan
    generate_migration_plan(overloaded_nodes, underloaded_nodes)
  end

  defp generate_migration_plan(overloaded_nodes, underloaded_nodes) do
    # Simplified migration plan generation
    Enum.flat_map(overloaded_nodes, fn {from_node, count} ->
      case underloaded_nodes do
        [] -> []
        [{to_node, _} | _] ->
          children_to_move = div(count, 4)  # Move 25% of children
          
          for _i <- 1..children_to_move do
            %{
              action: :migrate,
              from_node: from_node,
              to_node: to_node,
              reason: :load_balancing
            }
          end
      end
    end)
  end

  defp execute_rebalancing_plan(plan) do
    results = Enum.map(plan, fn migration ->
      execute_migration(migration)
    end)
    
    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))
    
    Logger.info("Rebalancing completed: #{successful} successful, #{failed} failed")
    
    {:ok, %{successful: successful, failed: failed, total: length(results)}}
  end

  defp execute_migration(%{from_node: from_node, to_node: to_node}) do
    # Find a child on the from_node to migrate
    children = which_children()
    
    from_node_children = Enum.filter(children, fn {_id, pid, _type, _modules} ->
      is_pid(pid) and node(pid) == from_node
    end)
    
    case from_node_children do
      [] ->
        {:error, :no_children_to_migrate}
      
      [{child_id, _pid, _type, _modules} | _] ->
        migrate_child(child_id, to_node)
    end
  end
end