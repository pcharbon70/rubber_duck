defmodule RubberDuck.Commands.CommandSupervisor do
  @moduledoc """
  Distributed supervisor for CommandHandler processes using Horde.DynamicSupervisor.
  
  Manages the lifecycle of command execution processes across the distributed cluster,
  providing automatic load balancing, fault tolerance, and state handoff capabilities.
  """
  
  use Horde.DynamicSupervisor
  require Logger
  
  alias RubberDuck.Commands.CommandHandler
  
  @doc """
  Starts the distributed command supervisor.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Horde.DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Starts a command handler with the given configuration.
  
  ## Options
  - `:placement_strategy` - How to place the command across nodes
    - `:automatic` (default) - Let Horde decide based on distribution strategy
    - `{:node, node}` - Start on specific node
    - `:least_loaded` - Start on node with fewest command handlers
    - `:round_robin` - Distribute using round-robin across nodes
  """
  def start_command(command_config, opts \\ []) do
    placement_strategy = Keyword.get(opts, :placement_strategy, :automatic)
    
    child_spec = %{
      id: command_config.command_id,
      start: {CommandHandler, :start_link, [command_config]},
      restart: :temporary,
      type: :worker
    }
    
    case placement_strategy do
      :automatic ->
        Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
        
      {:node, target_node} ->
        start_command_on_node(child_spec, target_node)
        
      :least_loaded ->
        start_command_on_least_loaded_node(child_spec)
        
      :round_robin ->
        start_command_round_robin(child_spec)
    end
  end
  
  @doc """
  Terminates a command handler.
  """
  def terminate_command(command_pid) when is_pid(command_pid) do
    Horde.DynamicSupervisor.terminate_child(__MODULE__, command_pid)
  end
  
  def terminate_command(command_id) when is_binary(command_id) do
    case find_command_pid(command_id) do
      {:ok, pid} ->
        Horde.DynamicSupervisor.terminate_child(__MODULE__, pid)
      :not_found ->
        {:error, :command_not_found}
    end
  end
  
  @doc """
  Finds a command handler by command ID.
  """
  def find_command(command_id) do
    case find_command_pid(command_id) do
      {:ok, pid} -> {:ok, pid}
      :not_found -> {:error, :command_not_found}
    end
  end
  
  @doc """
  Lists all active command handlers.
  """
  def list_commands do
    Horde.DynamicSupervisor.which_children(__MODULE__)
  end
  
  @doc """
  Gets command supervisor statistics.
  """
  def get_stats do
    children = list_commands()
    count = Horde.DynamicSupervisor.count_children(__MODULE__)
    
    commands_by_node = Enum.group_by(children, fn {_id, pid, _type, _modules} ->
      if is_pid(pid), do: node(pid), else: :unknown
    end)
    
    commands_by_status = get_commands_by_status(children)
    
    %{
      total_commands: count.active,
      active_commands: count.workers,
      commands_by_node: Enum.map(commands_by_node, fn {node, commands} ->
        {node, length(commands)}
      end) |> Enum.into(%{}),
      commands_by_status: commands_by_status,
      cluster_nodes: get_cluster_members(),
      load_distribution: calculate_load_distribution(commands_by_node)
    }
  end
  
  @doc """
  Migrates a command to another node with state preservation.
  """
  def migrate_command(command_id, target_node) do
    with {:ok, current_pid} <- find_command_pid(command_id),
         {:ok, handoff_data} <- CommandHandler.handoff_state(current_pid),
         {:ok, new_pid} <- start_command_on_node_with_data(handoff_data, target_node),
         :ok <- terminate_command(current_pid) do
      
      Logger.info("Successfully migrated command #{command_id} to node #{target_node}")
      {:ok, new_pid}
    else
      error ->
        Logger.error("Failed to migrate command #{command_id}: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Balances command load across cluster nodes.
  """
  def balance_load do
    stats = get_stats()
    
    case analyze_command_load_imbalance(stats) do
      {:balanced, _} ->
        Logger.debug("Command load is already balanced")
        {:ok, :already_balanced}
        
      {:imbalanced, rebalancing_plan} ->
        Logger.info("Executing command load balancing: #{length(rebalancing_plan)} migrations")
        execute_command_rebalancing(rebalancing_plan)
    end
  end
  
  @doc """
  Handles graceful shutdown of all commands with state preservation.
  """
  def shutdown_gracefully(timeout \\ 30_000) do
    children = list_commands()
    
    Logger.info("Gracefully shutting down #{length(children)} commands")
    
    # Give commands time to complete or save state
    shutdown_tasks = Enum.map(children, fn {command_id, pid, _type, _modules} ->
      Task.async(fn ->
        try do
          # Try to get handoff state before termination
          case CommandHandler.handoff_state(pid) do
            {:ok, handoff_data} ->
              # Store handoff data for potential recovery
              store_handoff_data(command_id, handoff_data)
              
            {:error, reason} ->
              Logger.warning("Could not get handoff state for #{command_id}: #{inspect(reason)}")
          end
          
          # Terminate the command
          case terminate_command(pid) do
            :ok -> {:ok, command_id}
            {:error, reason} -> {:error, {command_id, reason}}
          end
        catch
          kind, reason ->
            Logger.error("Error during graceful shutdown of #{command_id}: #{inspect({kind, reason})}")
            {:error, {command_id, {kind, reason}}}
        end
      end)
    end)
    
    # Wait for all shutdowns to complete
    results = Task.await_many(shutdown_tasks, timeout)
    
    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))
    
    Logger.info("Graceful shutdown completed: #{successful} successful, #{failed} failed")
    
    {:ok, %{successful: successful, failed: failed, total: length(results)}}
  end
  
  @doc """
  Gets cluster membership information.
  """
  def get_cluster_members do
    try do
      Horde.DynamicSupervisor.which_children(__MODULE__)
      |> Enum.map(fn {_id, pid, _type, _modules} -> if is_pid(pid), do: node(pid), else: node() end)
      |> Enum.uniq()
    catch
      _, _ -> [node()]
    end
  end
  
  @doc """
  Handles node join events for command redistribution.
  """
  def handle_node_join(new_node) do
    Logger.info("Handling node join for command distribution: #{new_node}")
    
    # Delay rebalancing to let the node stabilize
    spawn(fn ->
      :timer.sleep(5000)
      balance_load()
    end)
    
    :ok
  end
  
  @doc """
  Handles node leave events for command recovery.
  """
  def handle_node_leave(departed_node) do
    Logger.warning("Handling node departure for command recovery: #{departed_node}")
    
    # Monitor for lost commands and potential state recovery
    spawn(fn ->
      :timer.sleep(2000)
      check_for_lost_commands(departed_node)
    end)
    
    :ok
  end
  
  @impl true
  def init(opts) do
    Logger.info("Starting Command Distributed Supervisor on node #{node()}")
    
    [
      strategy: :one_for_one,
      members: :auto,
      distribution_strategy: Horde.UniformDistribution,
      max_children: 10_000,
      max_seconds: 10,
      max_restarts: 3
    ]
    |> Keyword.merge(opts)
    |> Horde.DynamicSupervisor.init()
  end
  
  # Private Functions
  
  defp start_command_on_node(child_spec, target_node) do
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
  
  defp start_command_on_node_with_data(handoff_data, target_node) do
    child_spec = %{
      id: handoff_data.command_id,
      start: {CommandHandler, :start_link, [handoff_data]},
      restart: :temporary,
      type: :worker
    }
    
    start_command_on_node(child_spec, target_node)
  end
  
  defp start_command_on_least_loaded_node(child_spec) do
    case find_least_loaded_node() do
      {:ok, target_node} ->
        start_command_on_node(child_spec, target_node)
      {:error, :no_nodes} ->
        Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
    end
  end
  
  defp start_command_round_robin(child_spec) do
    case get_next_round_robin_node() do
      {:ok, target_node} ->
        start_command_on_node(child_spec, target_node)
      {:error, :no_nodes} ->
        Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
    end
  end
  
  defp find_command_pid(command_id) do
    children = list_commands()
    
    case Enum.find(children, fn {id, _pid, _type, _modules} -> id == command_id end) do
      {_id, pid, _type, _modules} -> {:ok, pid}
      nil -> :not_found
    end
  end
  
  defp get_commands_by_status(children) do
    Enum.reduce(children, %{}, fn {_id, pid, _type, _modules}, acc ->
      if is_pid(pid) do
        try do
          state = CommandHandler.get_state(pid)
          status = state.status
          Map.update(acc, status, 1, &(&1 + 1))
        catch
          _, _ -> Map.update(acc, :unknown, 1, &(&1 + 1))
        end
      else
        Map.update(acc, :unknown, 1, &(&1 + 1))
      end
    end)
  end
  
  defp find_least_loaded_node do
    stats = get_stats()
    
    case stats.commands_by_node do
      commands_by_node when map_size(commands_by_node) > 0 ->
        {least_loaded_node, _count} = Enum.min_by(commands_by_node, fn {_node, count} -> count end)
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
        index = rem(System.monotonic_time(:microsecond), length(nodes))
        {:ok, Enum.at(nodes, index)}
    end
  end
  
  defp calculate_load_distribution(commands_by_node) do
    if map_size(commands_by_node) == 0 do
      %{balance_score: 1.0, variance: 0.0}
    else
      counts = Map.values(commands_by_node)
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
        avg_commands_per_node: avg_count,
        max_commands_per_node: max_count,
        min_commands_per_node: min_count
      }
    end
  end
  
  defp analyze_command_load_imbalance(stats) do
    load_dist = stats.load_distribution
    
    # Consider imbalanced if balance score is below threshold or variance is high
    if load_dist.balance_score < 0.8 or load_dist.variance > 10 do
      rebalancing_plan = generate_command_rebalancing_plan(stats)
      {:imbalanced, rebalancing_plan}
    else
      {:balanced, load_dist}
    end
  end
  
  defp generate_command_rebalancing_plan(stats) do
    commands_by_node = stats.commands_by_node
    avg_commands = stats.load_distribution.avg_commands_per_node
    
    # Find overloaded and underloaded nodes
    overloaded_nodes = Enum.filter(commands_by_node, fn {_node, count} ->
      count > avg_commands * 1.5
    end)
    
    underloaded_nodes = Enum.filter(commands_by_node, fn {_node, count} ->
      count < avg_commands * 0.5
    end)
    
    generate_command_migration_plan(overloaded_nodes, underloaded_nodes)
  end
  
  defp generate_command_migration_plan(overloaded_nodes, underloaded_nodes) do
    Enum.flat_map(overloaded_nodes, fn {from_node, count} ->
      case underloaded_nodes do
        [] -> []
        [{to_node, _} | _] ->
          commands_to_move = div(count - trunc(count * 0.8), 1)  # Move excess commands
          
          for _i <- 1..max(1, commands_to_move) do
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
  
  defp execute_command_rebalancing(plan) do
    results = Enum.map(plan, fn migration ->
      execute_command_migration(migration)
    end)
    
    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))
    
    Logger.info("Command rebalancing completed: #{successful} successful, #{failed} failed")
    
    {:ok, %{successful: successful, failed: failed, total: length(results)}}
  end
  
  defp execute_command_migration(%{from_node: from_node, to_node: to_node}) do
    children = list_commands()
    
    from_node_commands = Enum.filter(children, fn {_id, pid, _type, _modules} ->
      is_pid(pid) and node(pid) == from_node
    end)
    
    case from_node_commands do
      [] ->
        {:error, :no_commands_to_migrate}
      [{command_id, _pid, _type, _modules} | _] ->
        migrate_command(command_id, to_node)
    end
  end
  
  defp store_handoff_data(command_id, _handoff_data) do
    # In a real implementation, this would store to Mnesia or persistent storage
    # For now, we'll just log it
    Logger.debug("Storing handoff data for command #{command_id}")
    :ok
  end
  
  defp check_for_lost_commands(departed_node) do
    # Check if any commands were lost and potentially recover from handoff data
    current_stats = get_stats()
    Logger.info("Checking for lost commands after node #{departed_node} departure: #{inspect(current_stats.commands_by_status)}")
    :ok
  end
end