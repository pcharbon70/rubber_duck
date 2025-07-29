defmodule RubberDuck.Jido.Steps.ExecuteAgentAction do
  @moduledoc """
  A Reactor step that executes an action on a Jido agent.
  
  This step bridges the Reactor workflow system with our Jido agent system,
  allowing workflows to coordinate agent actions.
  
  ## Arguments
  
  - `:agent_id` - The ID of the agent to execute the action on
  - `:action` - The action module to execute
  - `:params` - Parameters to pass to the action
  
  ## Options
  
  - `:timeout` - Timeout for the action execution (default: 5000ms)
  - `:async` - Whether to execute asynchronously (default: true)
  
  ## Example
  
      step :process_data, RubberDuck.Jido.Steps.ExecuteAgentAction do
        argument :agent_id, result(:select_agent)
        argument :action, value(ProcessDataAction)
        argument :params, input(:data)
      end
  """
  
  use Reactor.Step
  
  alias RubberDuck.Jido.Agents.{Registry, Server}
  
  @doc false
  @impl true
  def run(arguments, _context, options) do
    timeout = options[:timeout] || 5000
    
    with {:ok, agent} <- get_agent(arguments.agent_id),
         {:ok, result} <- execute_action(agent.pid, arguments.action, arguments.params, timeout) do
      {:ok, result}
    else
      {:error, :agent_not_found} ->
        {:error, "Agent #{arguments.agent_id} not found"}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc false
  @impl true
  def compensate({:error, reason}, _arguments, _context, _options) do
    case reason do
      # Retry on transient errors
      :timeout -> :retry
      {:timeout, _} -> :retry
      :noproc -> :retry
      
      # Don't retry on permanent errors
      _ -> :ok
    end
  end
  
  @doc false
  @impl true
  def undo(result, arguments, _context, _options) do
    # If the action has an undo operation, execute it
    if function_exported?(arguments.action, :undo, 2) do
      with {:ok, agent} <- get_agent(arguments.agent_id) do
        case Server.execute_action(agent.pid, arguments.action, %{undo: true, original_result: result}) do
          {:ok, _} -> :ok
          {:error, _} -> :ok  # Best effort undo
        end
      end
    else
      :ok
    end
  end
  
  # Private functions
  
  defp get_agent(agent_id) do
    case Registry.get_agent(agent_id) do
      {:ok, agent} -> {:ok, agent}
      {:error, _} -> {:error, :agent_not_found}
    end
  end
  
  defp execute_action(pid, action, params, _timeout) do
    Server.execute_action(pid, action, params)
  end
end