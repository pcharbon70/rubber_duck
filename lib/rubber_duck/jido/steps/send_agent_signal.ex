defmodule RubberDuck.Jido.Steps.SendAgentSignal do
  @moduledoc """
  A Reactor step that sends a signal to a Jido agent.
  
  This step allows workflows to send asynchronous signals to agents,
  enabling event-driven coordination patterns.
  
  ## Arguments
  
  - `:agent_id` - The ID of the agent to send the signal to
  - `:signal` - The signal to send (any term)
  - `:broadcast` - Optional: if true, broadcast to all agents with a tag
  
  ## Options
  
  - `:wait_for_ack` - Whether to wait for acknowledgment (default: false)
  - `:timeout` - Timeout when waiting for ack (default: 1000ms)
  
  ## Example
  
      step :notify_agent, RubberDuck.Jido.Steps.SendAgentSignal do
        argument :agent_id, result(:coordinator_id)
        argument :signal, value({:task_completed, :success})
      end
  """
  
  use Reactor.Step
  
  alias RubberDuck.Jido.Agents.{Registry, Server}
  
  @doc false
  @impl true
  def run(arguments, _context, options) do
    wait_for_ack = options[:wait_for_ack] || false
    timeout = options[:timeout] || 1000
    
    if arguments[:broadcast] do
      broadcast_signal(arguments.agent_id, arguments.signal, wait_for_ack, timeout)
    else
      send_signal(arguments.agent_id, arguments.signal, wait_for_ack, timeout)
    end
  end
  
  @doc false
  @impl true
  def compensate(_error, _arguments, _context, _options) do
    # Signals are fire-and-forget by nature, no compensation needed
    :ok
  end
  
  # Private functions
  
  defp send_signal(agent_id, signal, wait_for_ack, timeout) do
    with {:ok, agent} <- Registry.get_agent(agent_id) do
      if wait_for_ack do
        # Use call for acknowledgment
        try do
          GenServer.call(agent.pid, {:signal, signal}, timeout)
          {:ok, :acknowledged}
        catch
          :exit, {:timeout, _} -> {:error, :timeout}
          :exit, {:noproc, _} -> {:error, :agent_not_found}
        end
      else
        # Use cast for fire-and-forget
        Server.send_signal(agent.pid, signal)
        {:ok, :sent}
      end
    else
      {:error, _} -> {:error, :agent_not_found}
    end
  end
  
  defp broadcast_signal(tag, signal, wait_for_ack, timeout) do
    agents = Registry.find_by_tag(tag)
    
    if wait_for_ack do
      # Wait for all agents to acknowledge
      tasks = Enum.map(agents, fn agent ->
        Task.async(fn ->
          try do
            GenServer.call(agent.pid, {:signal, signal}, timeout)
            {:ok, agent.id}
          catch
            :exit, _ -> {:error, agent.id}
          end
        end)
      end)
      
      results = Task.await_many(tasks, timeout + 100)
      failed = Enum.filter(results, &match?({:error, _}, &1))
      
      if Enum.empty?(failed) do
        {:ok, {:broadcast_sent, length(agents)}}
      else
        {:error, {:partial_broadcast, length(agents) - length(failed), length(failed)}}
      end
    else
      # Fire and forget to all agents
      Enum.each(agents, fn agent ->
        Server.send_signal(agent.pid, signal)
      end)
      
      {:ok, {:broadcast_sent, length(agents)}}
    end
  end
end