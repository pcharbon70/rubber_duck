defmodule RubberDuck.Jido.Agents.EssentialAgents do
  @moduledoc """
  Manages the startup of essential system agents.
  
  This module ensures core agents are started when the application boots.
  """
  
  require Logger
  
  alias RubberDuck.Agents.ConversationRouterAgent
  alias RubberDuck.Jido.Agents.Supervisor
  
  @doc """
  Starts all essential agents for the system.
  """
  def start_all do
    Logger.info("Starting essential Jido agents...")
    
    agents = [
      # Conversation Router Agent - handles incoming query routing
      {
        ConversationRouterAgent,
        %{},  # Initial state
        [
          id: "conversation_router_main",
          restart: :permanent,
          tags: ["essential", "routing"],
          capabilities: [:signal_routing, :query_classification],
          metadata: %{
            description: "Main conversation routing agent",
            critical: true
          }
        ]
      }
      # Add more essential agents here as needed
    ]
    
    results = Enum.map(agents, fn {module, initial_state, opts} ->
      Logger.info("Starting agent: #{inspect(module)}")
      
      case Supervisor.start_agent(module, initial_state, opts) do
        {:ok, pid} ->
          Logger.info("Successfully started #{inspect(module)} with pid #{inspect(pid)}")
          {:ok, module, pid}
          
        {:error, reason} = error ->
          Logger.error("Failed to start #{inspect(module)}: #{inspect(reason)}")
          error
      end
    end)
    
    successful = Enum.count(results, &match?({:ok, _, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))
    
    Logger.info("Essential agents startup complete. Success: #{successful}, Failed: #{failed}")
    
    if failed > 0 do
      {:error, {:partial_failure, results}}
    else
      {:ok, results}
    end
  end
  
  @doc """
  Stops all essential agents gracefully.
  """
  def stop_all do
    Logger.info("Stopping essential agents...")
    
    essential_agents = Supervisor.find_by_tag("essential")
    
    Enum.each(essential_agents, fn agent_info ->
      Logger.info("Stopping agent: #{agent_info.id}")
      Supervisor.stop_agent(agent_info.id)
    end)
    
    :ok
  end
  
  @doc """
  Checks the health of all essential agents.
  """
  def health_check do
    essential_agents = Supervisor.find_by_tag("essential")
    
    health_results = Enum.map(essential_agents, fn agent_info ->
      case GenServer.call(agent_info.pid, :health_check, 5000) do
        {:ok, health} ->
          {agent_info.id, :healthy, health}
          
        {:error, reason} ->
          {agent_info.id, :unhealthy, reason}
          
        exception ->
          {agent_info.id, :error, exception}
      end
    end)
    
    all_healthy = Enum.all?(health_results, fn {_, status, _} -> status == :healthy end)
    
    %{
      all_healthy: all_healthy,
      agents: health_results
    }
  end
end