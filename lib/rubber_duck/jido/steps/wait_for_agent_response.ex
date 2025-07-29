defmodule RubberDuck.Jido.Steps.WaitForAgentResponse do
  @moduledoc """
  A Reactor step that waits for a response from one or more agents.
  
  This step enables synchronization patterns where workflows need to
  wait for agents to complete work or reach certain states.
  
  ## Arguments
  
  - `:agent_ids` - Single agent ID or list of agent IDs to wait for
  - `:condition` - What to wait for (:ready, :completed, custom function)
  - `:aggregation` - How to aggregate multiple responses (:all, :any, :majority)
  
  ## Options
  
  - `:timeout` - Maximum wait time (default: 10000ms)
  - `:poll_interval` - How often to check (default: 100ms)
  
  ## Example
  
      step :wait_for_workers, RubberDuck.Jido.Steps.WaitForAgentResponse do
        argument :agent_ids, result(:spawn_workers)
        argument :condition, value(:ready)
        argument :aggregation, value(:all)
      end
  """
  
  use Reactor.Step
  
  alias RubberDuck.Jido.Agents.{Registry, Server}
  
  @default_timeout 10_000
  @default_poll_interval 100
  
  @doc false
  @impl true
  def run(arguments, _context, options) do
    timeout = options[:timeout] || @default_timeout
    poll_interval = options[:poll_interval] || @default_poll_interval
    
    agent_ids = normalize_agent_ids(arguments.agent_ids)
    aggregation = arguments[:aggregation] || :all
    
    deadline = System.monotonic_time(:millisecond) + timeout
    
    wait_for_responses(agent_ids, arguments.condition, aggregation, deadline, poll_interval)
  end
  
  @doc false
  @impl true
  def compensate({:error, :timeout}, _arguments, _context, _options) do
    # Allow retry on timeout
    :retry
  end
  
  def compensate(_error, _arguments, _context, _options) do
    :ok
  end
  
  # Private functions
  
  defp normalize_agent_ids(ids) when is_list(ids), do: ids
  defp normalize_agent_ids(id), do: [id]
  
  defp wait_for_responses(agent_ids, condition, aggregation, deadline, poll_interval) do
    case check_responses(agent_ids, condition) do
      {:ok, responses} ->
        evaluate_aggregation(responses, aggregation)
        
      {:partial, responses} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, {:timeout, responses}}
        else
          Process.sleep(poll_interval)
          wait_for_responses(agent_ids, condition, aggregation, deadline, poll_interval)
        end
    end
  end
  
  defp check_responses(agent_ids, condition) do
    responses = Enum.map(agent_ids, fn agent_id ->
      case check_agent_condition(agent_id, condition) do
        {:ok, response} -> {:ok, agent_id, response}
        {:error, reason} -> {:error, agent_id, reason}
        :pending -> {:pending, agent_id}
      end
    end)
    
    pending = Enum.filter(responses, &match?({:pending, _}, &1))
    
    if Enum.empty?(pending) do
      {:ok, responses}
    else
      {:partial, responses}
    end
  end
  
  defp check_agent_condition(agent_id, :ready) do
    with {:ok, agent} <- Registry.get_agent(agent_id),
         {:ok, health} <- Server.health_check(agent.pid) do
      if health.ready do
        {:ok, :ready}
      else
        :pending
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp check_agent_condition(agent_id, :completed) do
    with {:ok, agent} <- Registry.get_agent(agent_id) do
      case Server.get_agent(agent.pid) do
        {:ok, state} ->
          if Map.get(state, :status) == :completed do
            {:ok, state}
          else
            :pending
          end
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp check_agent_condition(agent_id, condition) when is_function(condition) do
    with {:ok, agent} <- Registry.get_agent(agent_id),
         {:ok, state} <- Server.get_agent(agent.pid) do
      case condition.(state) do
        true -> {:ok, state}
        false -> :pending
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp evaluate_aggregation(responses, :all) do
    errors = Enum.filter(responses, &match?({:error, _, _}, &1))
    
    if Enum.empty?(errors) do
      results = Enum.map(responses, fn {:ok, agent_id, response} -> {agent_id, response} end)
      {:ok, Map.new(results)}
    else
      {:error, {:failed_agents, errors}}
    end
  end
  
  defp evaluate_aggregation(responses, :any) do
    successful = Enum.filter(responses, &match?({:ok, _, _}, &1))
    
    if Enum.empty?(successful) do
      {:error, :no_successful_responses}
    else
      {:ok, agent_id, response} = List.first(successful)
      {:ok, {agent_id, response}}
    end
  end
  
  defp evaluate_aggregation(responses, :majority) do
    successful = Enum.filter(responses, &match?({:ok, _, _}, &1))
    total = length(responses)
    required = div(total, 2) + 1
    
    if length(successful) >= required do
      results = Enum.map(successful, fn {:ok, agent_id, response} -> {agent_id, response} end)
      {:ok, Map.new(results)}
    else
      {:error, {:insufficient_responses, length(successful), required}}
    end
  end
end