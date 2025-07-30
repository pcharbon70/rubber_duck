defmodule RubberDuck.Jido.Agents.EssentialAgents do
  @moduledoc """
  Manages the startup of essential system agents.
  
  This module ensures core agents are started when the application boots.
  """
  
  require Logger
  
  alias RubberDuck.Agents.ConversationRouterAgent
  alias RubberDuck.Agents.PlanningConversationAgent
  alias RubberDuck.Agents.CodeAnalysisAgent
  alias RubberDuck.Agents.EnhancementConversationAgent
  alias RubberDuck.Agents.GeneralConversationAgent
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
      },
      
      # Planning Conversation Agent - handles planning discussions
      {
        PlanningConversationAgent,
        %{},  # Initial state
        [
          id: "planning_conversation_main",
          restart: :permanent,
          tags: ["essential", "planning", "conversation"],
          capabilities: [:planning_creation, :planning_discussion, :critics_integration],
          metadata: %{
            description: "Main planning conversation agent",
            critical: true
          }
        ]
      },
      
      # Code Analysis Agent - handles code analysis operations
      {
        CodeAnalysisAgent,
        %{},  # Initial state
        [
          id: "code_analysis_main",
          restart: :permanent,
          tags: ["essential", "analysis"],
          capabilities: [:static_analysis, :llm_enhancement, :cot_analysis],
          metadata: %{
            description: "Main code analysis agent",
            critical: true
          }
        ]
      },
      
      # Enhancement Conversation Agent - handles enhancement discussions
      {
        EnhancementConversationAgent,
        %{},  # Initial state
        [
          id: "enhancement_conversation_main",
          restart: :permanent,
          tags: ["essential", "enhancement", "conversation"],
          capabilities: [:enhancement_coordination, :technique_selection, :suggestion_generation],
          metadata: %{
            description: "Main enhancement conversation agent",
            critical: true
          }
        ]
      },
      
      # General Conversation Agent - handles general conversations
      {
        GeneralConversationAgent,
        %{},  # Initial state
        [
          id: "general_conversation_main",
          restart: :permanent,
          tags: ["essential", "conversation", "general"],
          capabilities: [:general_conversation, :context_switching, :topic_management],
          metadata: %{
            description: "Main general conversation agent",
            critical: true
          }
        ]
      }
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