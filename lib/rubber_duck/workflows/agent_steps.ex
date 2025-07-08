defmodule RubberDuck.Workflows.AgentSteps do
  @moduledoc """
  Reactor step implementations for agent-based operations.

  This module provides reusable step types that integrate the agent system
  with Reactor workflows, enabling complex multi-agent orchestration.

  ## Available Steps

  - `start_agent/1` - Start an agent of specified type
  - `execute_agent_task/1` - Execute a task on a specific agent
  - `coordinate_agents/1` - Coordinate multiple agents for complex tasks
  - `aggregate_agent_results/1` - Aggregate results from multiple agents
  - `broadcast_to_agents/1` - Broadcast a message to agent groups

  ## Example Usage

      defmodule MyWorkflow do
        use Reactor
        
        step :start_research_agent do
          run RubberDuck.Workflows.AgentSteps.start_agent(%{
            type: :research,
            config: %{memory_tier: :short_term}
          })
        end
        
        step :research_context do
          run RubberDuck.Workflows.AgentSteps.execute_agent_task(%{
            agent_id: result(:start_research_agent),
            task: {:research_context, %{query: "authentication patterns"}}
          })
        end
      end
  """

  alias RubberDuck.Agents.{AgentRegistry, Communication, Supervisor}

  require Logger

  @doc """
  Starts an agent of the specified type.

  ## Arguments

  - `type` - Agent type (:research, :analysis, :generation, :review)
  - `config` - Agent configuration map (optional)

  ## Returns

  - `{:ok, agent_id}` - The started agent's ID
  - `{:error, reason}` - If agent startup fails
  """
  def start_agent(arguments, _context, _options) do
    type = Map.fetch!(arguments, :type)
    config = Map.get(arguments, :config, %{})

    case Supervisor.start_agent(type, config) do
      {:ok, _pid} ->
        # Generate agent ID based on type and timestamp
        agent_id = generate_agent_id(type)
        {:ok, agent_id}

      {:error, reason} = error ->
        Logger.error("Failed to start #{type} agent: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Executes a task on a specific agent.

  ## Arguments

  - `agent_id` - Target agent ID
  - `task` - Task to execute (tuple with task type and params)
  - `timeout` - Task timeout in milliseconds (default: 30_000)

  ## Returns

  - `{:ok, result}` - Task execution result
  - `{:error, reason}` - If task execution fails
  """
  def execute_agent_task(arguments, _context, _options) do
    agent_id = Map.fetch!(arguments, :agent_id)
    task = Map.fetch!(arguments, :task)
    timeout = Map.get(arguments, :timeout, 30_000)

    case Communication.request_response(agent_id, task, timeout) do
      {:ok, result} ->
        Logger.debug("Agent #{agent_id} completed task: #{inspect(task)}")
        {:ok, result}

      {:error, reason} = error ->
        Logger.error("Agent task failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Coordinates multiple agents for complex tasks.

  ## Arguments

  - `coordination_spec` - Specification for multi-agent coordination
    - `steps` - List of coordination steps with agent types and tasks
    - `strategy` - Coordination strategy (:sequential, :parallel, :consensus)
    - `timeout` - Overall timeout for coordination

  ## Returns

  - `{:ok, results}` - Aggregated results from all agents
  - `{:error, reason}` - If coordination fails
  """
  def coordinate_agents(arguments, context, _options) do
    spec = Map.fetch!(arguments, :coordination_spec)
    _workflow_id = Map.get(context, :workflow_id, generate_workflow_id())

    # TODO: Implement when Coordinator module is available
    # For now, return a placeholder implementation
    Logger.warning("Coordinator not yet implemented, returning mock coordination")

    case spec.strategy do
      :sequential ->
        # Simple sequential execution mock
        results =
          Enum.map(spec.steps, fn step ->
            %{agent_type: step.agent_type, task: step.task, result: {:ok, :mock_result}}
          end)

        {:ok, results}

      _ ->
        {:error, {:not_implemented, "Coordinator module not yet available"}}
    end
  end

  @doc """
  Aggregates results from multiple agent executions.

  ## Arguments

  - `results` - List of agent results to aggregate
  - `strategy` - Aggregation strategy (:merge, :consensus, :priority, :custom)
  - `custom_aggregator` - Custom aggregation function (optional)

  ## Returns

  - `{:ok, aggregated_result}` - The aggregated result
  - `{:error, reason}` - If aggregation fails
  """
  def aggregate_agent_results(arguments, _context, _options) do
    results = Map.fetch!(arguments, :results)
    strategy = Map.get(arguments, :strategy, :merge)
    custom_aggregator = Map.get(arguments, :custom_aggregator)

    try do
      aggregated =
        case strategy do
          :merge ->
            merge_results(results)

          :consensus ->
            find_consensus(results)

          :priority ->
            select_by_priority(results)

          :custom when is_function(custom_aggregator, 1) ->
            custom_aggregator.(results)

          _ ->
            {:error, {:invalid_strategy, strategy}}
        end

      case aggregated do
        {:error, _} = error -> error
        result -> {:ok, result}
      end
    rescue
      exception ->
        Logger.error("Result aggregation failed: #{Exception.message(exception)}")
        {:error, {:aggregation_failed, Exception.message(exception)}}
    end
  end

  @doc """
  Broadcasts a message to a group of agents.

  ## Arguments

  - `message` - Message to broadcast
  - `target` - Broadcast target
    - `{:type, agent_type}` - Broadcast to all agents of a type
    - `{:capability, capability}` - Broadcast to agents with capability
    - `{:all, filter_fn}` - Broadcast to all agents matching filter

  ## Returns

  - `{:ok, count}` - Number of agents that received the message
  - `{:error, reason}` - If broadcast fails
  """
  def broadcast_to_agents(arguments, _context, _options) do
    message = Map.fetch!(arguments, :message)
    target = Map.fetch!(arguments, :target)

    result =
      case target do
        {:type, agent_type} ->
          AgentRegistry.broadcast_to_type(agent_type, message)

        {:capability, capability} ->
          AgentRegistry.broadcast_to_capability(capability, message)

        {:all, filter_fn} when is_function(filter_fn, 1) ->
          broadcast_with_filter(message, filter_fn)

        _ ->
          {:error, {:invalid_target, target}}
      end

    case result do
      {:ok, count} ->
        Logger.debug("Broadcast sent to #{count} agents")
        {:ok, count}

      {:error, reason} = error ->
        Logger.error("Broadcast failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Waits for agent events and collects results.

  ## Arguments

  - `event_type` - Type of event to wait for
  - `count` - Number of events to collect
  - `timeout` - Collection timeout

  ## Returns

  - `{:ok, events}` - Collected events
  - `{:error, :timeout}` - If timeout expires
  """
  def collect_agent_events(arguments, _context, _options) do
    event_type = Map.fetch!(arguments, :event_type)
    count = Map.fetch!(arguments, :count)
    timeout = Map.get(arguments, :timeout, 60_000)

    collector_pid = self()

    # Subscribe to events
    AgentRegistry.subscribe(event_type, collector_pid)

    # Collect events
    result = collect_events([], count, timeout)

    # Unsubscribe
    AgentRegistry.unsubscribe(event_type, collector_pid)

    result
  end

  # Private functions

  defp generate_agent_id(type) do
    timestamp = System.system_time(:millisecond)
    random = :rand.uniform(9999)
    "#{type}_#{timestamp}_#{random}"
  end

  defp generate_workflow_id do
    "workflow_#{System.system_time(:millisecond)}_#{:rand.uniform(9999)}"
  end

  defp merge_results(results) do
    Enum.reduce(results, %{}, fn result, acc ->
      Map.merge(acc, result, fn _k, v1, v2 ->
        cond do
          is_list(v1) and is_list(v2) -> v1 ++ v2
          is_map(v1) and is_map(v2) -> Map.merge(v1, v2)
          true -> v2
        end
      end)
    end)
  end

  defp find_consensus(results) do
    # Group by common values and find majority
    results
    |> Enum.group_by(& &1)
    |> Enum.max_by(fn {_value, group} -> length(group) end)
    |> elem(0)
  end

  defp select_by_priority(results) do
    # Assume results have priority metadata
    results
    |> Enum.filter(&Map.has_key?(&1, :priority))
    |> Enum.max_by(&Map.get(&1, :priority), fn -> List.first(results) end)
  end

  defp broadcast_with_filter(message, filter_fn) do
    case AgentRegistry.list_agents() do
      {:ok, agents} ->
        matching_agents =
          agents
          |> Enum.filter(fn {_id, _pid, metadata} -> filter_fn.(metadata) end)

        count =
          Enum.reduce(matching_agents, 0, fn {_id, pid, _metadata}, acc ->
            send(pid, message)
            acc + 1
          end)

        {:ok, count}

      error ->
        error
    end
  end

  defp collect_events(events, 0, _timeout), do: {:ok, Enum.reverse(events)}

  defp collect_events(events, remaining, timeout) do
    receive do
      {:agent_event, _type, event_data} ->
        collect_events([event_data | events], remaining - 1, timeout)
    after
      timeout ->
        {:error, :timeout}
    end
  end
end
