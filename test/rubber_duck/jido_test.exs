defmodule RubberDuck.JidoTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido
  alias RubberDuck.Jido.Agents.ExampleAgent
  alias RubberDuck.Jido.Actions.{Increment, AddMessage, UpdateStatus}
  
  describe "agent creation" do
    test "creates agent with default state" do
      {:ok, agent} = Jido.create_agent(ExampleAgent)
      
      assert agent.module == ExampleAgent
      assert agent.state.counter == 0
      assert agent.state.messages == []
      assert agent.state.status == :idle
      assert agent.metadata.version == 1
    end
    
    test "creates agent with custom initial state" do
      {:ok, agent} = Jido.create_agent(ExampleAgent, %{counter: 42})
      
      assert agent.state.counter == 42
      assert agent.state.messages == []  # Other defaults still applied
    end
    
    test "generates unique agent IDs" do
      {:ok, agent1} = Jido.create_agent(ExampleAgent)
      {:ok, agent2} = Jido.create_agent(ExampleAgent)
      
      assert agent1.id != agent2.id
    end
  end
  
  describe "action execution" do
    setup do
      {:ok, agent} = Jido.create_agent(ExampleAgent)
      {:ok, agent: agent}
    end
    
    test "executes increment action", %{agent: agent} do
      {:ok, result, updated_agent} = Jido.execute_action(agent, Increment, %{amount: 5})
      
      assert result.value == 5
      assert result.increased_by == 5
      assert updated_agent.state.counter == 5
      assert updated_agent.metadata.version == 2
    end
    
    test "executes add message action", %{agent: agent} do
      {:ok, result, updated_agent} = Jido.execute_action(agent, AddMessage, %{
        message: "Hello Jido"
      })
      
      assert result.message_added =~ "Hello Jido"
      assert result.total_messages == 1
      assert length(updated_agent.state.messages) == 1
    end
    
    test "executes update status action", %{agent: agent} do
      {:ok, result, updated_agent} = Jido.execute_action(agent, UpdateStatus, %{
        status: :error,
        reason: "Processing"
      })
      
      # The on_before_run callback sets status to :busy, so old_status will be :busy
      assert result.old_status == :busy
      assert result.new_status == :error
      assert result.changed == true
      # The on_after_run callback sets it back to :idle
      assert updated_agent.state.status == :idle
    end
    
    test "calls lifecycle callbacks", %{agent: agent} do
      # Status should change to busy during execution, then back to idle
      assert agent.state.status == :idle
      
      {:ok, _result, updated_agent} = Jido.execute_action(agent, Increment, %{amount: 1})
      
      assert updated_agent.state.status == :idle
      assert updated_agent.state.last_action =~ "Increment"
    end
  end
  
  describe "agent management" do
    test "gets agent by ID" do
      {:ok, agent} = Jido.create_agent(ExampleAgent)
      
      {:ok, retrieved} = Jido.get_agent(agent.id)
      assert retrieved.id == agent.id
    end
    
    test "lists all agents" do
      {:ok, agent1} = Jido.create_agent(ExampleAgent)
      {:ok, agent2} = Jido.create_agent(ExampleAgent)
      
      agents = Jido.list_agents()
      agent_ids = Enum.map(agents, & &1.id)
      
      assert agent1.id in agent_ids
      assert agent2.id in agent_ids
    end
    
    test "deletes agent" do
      {:ok, agent} = Jido.create_agent(ExampleAgent)
      
      assert :ok = Jido.delete_agent(agent)
      assert {:error, :not_found} = Jido.get_agent(agent.id)
    end
  end
  
  describe "signal routing" do
    setup do
      {:ok, agent} = Jido.create_agent(ExampleAgent)
      {:ok, agent: agent}
    end
    
    test "routes increment signal to action", %{agent: agent} do
      :ok = Jido.send_signal(agent, %{
        "type" => "increment",
        "data" => %{"amount" => 3}
      })
      
      # Allow async processing
      Process.sleep(50)
      
      {:ok, updated_agent} = Jido.get_agent(agent.id)
      assert updated_agent.state.counter == 3
    end
  end
  
  describe "system status" do
    test "returns system metrics" do
      {:ok, _agent1} = Jido.create_agent(ExampleAgent)
      {:ok, _agent2} = Jido.create_agent(ExampleAgent)
      
      status = Jido.system_status()
      
      assert status.agents.total >= 2
      assert status.agents.by_type[ExampleAgent] >= 2
      assert is_map(status.runtime)
      assert is_map(status.signals)
    end
  end
end