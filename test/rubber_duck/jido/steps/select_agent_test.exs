defmodule RubberDuck.Jido.Steps.SelectAgentTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Jido.Steps.SelectAgent
  alias RubberDuck.Jido.Agents.{Supervisor, Registry}

  # Test agent with different capabilities
  defmodule TestAgentA do
    use RubberDuck.Jido.BaseAgent,
      name: "test_agent_a",
      description: "Agent A for testing"

    @impl true
    def init(initial_state) do
      state = Map.merge(initial_state, %{
        capabilities: [:text_processing, :analysis],
        load: initial_state[:load] || 0
      })
      {:ok, state}
    end
  end

  defmodule TestAgentB do
    use RubberDuck.Jido.BaseAgent,
      name: "test_agent_b", 
      description: "Agent B for testing"

    @impl true
    def init(initial_state) do
      state = Map.merge(initial_state, %{
        capabilities: [:data_processing, :analysis],
        load: initial_state[:load] || 0
      })
      {:ok, state}
    end
  end

  setup do
    # Start the supervisor
    {:ok, _} = start_supervised(Supervisor)
    
    # Start multiple test agents with different capabilities and loads
    {:ok, agent_a1} = Supervisor.start_agent(
      TestAgentA,
      %{load: 1},
      id: "agent_a1_#{System.unique_integer()}",
      tags: [:processor],
      capabilities: [:text_processing, :analysis]
    )
    
    {:ok, agent_a2} = Supervisor.start_agent(
      TestAgentA,
      %{load: 5},
      id: "agent_a2_#{System.unique_integer()}",
      tags: [:processor],
      capabilities: [:text_processing, :analysis]
    )
    
    {:ok, agent_b1} = Supervisor.start_agent(
      TestAgentB,
      %{load: 2},
      id: "agent_b1_#{System.unique_integer()}",
      tags: [:analyzer],
      capabilities: [:data_processing, :analysis]  
    )
    
    # Give agents time to register
    Process.sleep(100)
    
    {:ok, 
      agent_a1: agent_a1,
      agent_a2: agent_a2,
      agent_b1: agent_b1
    }
  end

  describe "run/3 with capability selection" do
    test "selects agent with required capability" do
      arguments = %{
        capabilities: [:text_processing]
      }
      
      assert {:ok, agent_id} = SelectAgent.run(arguments, %{}, [])
      assert is_binary(agent_id)
      
      # Verify the agent has the required capability
      {:ok, agent} = Registry.get_agent(agent_id)
      assert :text_processing in agent.capabilities
    end

    test "selects least loaded agent when multiple match" do
      arguments = %{
        capabilities: [:analysis]  # Both agent types have this
      }
      
      assert {:ok, agent_id} = SelectAgent.run(arguments, %{}, [])
      {:ok, agent} = Registry.get_agent(agent_id)
      
      # Should select the agent with load=1 (agent_a1)
      assert agent.load == 1
    end

    test "returns error when no agent has required capabilities" do
      arguments = %{
        capabilities: [:nonexistent_capability]
      }
      
      assert {:error, "No agents found with required capabilities"} = 
        SelectAgent.run(arguments, %{}, [])
    end
  end

  describe "run/3 with tag selection" do
    test "selects agent with required tags" do
      arguments = %{
        tags: [:processor]
      }
      
      assert {:ok, agent_id} = SelectAgent.run(arguments, %{}, [])
      {:ok, agent} = Registry.get_agent(agent_id)
      assert :processor in agent.tags
    end

    test "selects least loaded agent among tagged agents" do
      arguments = %{
        tags: [:processor]  # Both agent_a1 and agent_a2 have this tag
      }
      
      assert {:ok, agent_id} = SelectAgent.run(arguments, %{}, [])
      {:ok, agent} = Registry.get_agent(agent_id)
      
      # Should select agent_a1 (load=1) over agent_a2 (load=5)
      assert agent.load == 1
    end
  end

  describe "run/3 with combined selection" do
    test "selects agent matching both capabilities and tags" do
      arguments = %{
        capabilities: [:data_processing],
        tags: [:analyzer]
      }
      
      assert {:ok, agent_id} = SelectAgent.run(arguments, %{}, [])
      {:ok, agent} = Registry.get_agent(agent_id)
      
      assert :data_processing in agent.capabilities
      assert :analyzer in agent.tags
    end

    test "returns error when no agent matches both criteria" do
      arguments = %{
        capabilities: [:text_processing],
        tags: [:analyzer]  # No agent has both text_processing AND analyzer tag
      }
      
      assert {:error, "No agents found with required capabilities"} = 
        SelectAgent.run(arguments, %{}, [])
    end
  end

  describe "run/3 with strategy option" do
    test "uses least_loaded strategy by default" do
      arguments = %{
        capabilities: [:analysis]
      }
      
      assert {:ok, agent_id} = SelectAgent.run(arguments, %{}, [])
      {:ok, agent} = Registry.get_agent(agent_id)
      assert agent.load == 1  # Should pick the least loaded
    end

    test "uses random strategy when specified" do
      arguments = %{
        capabilities: [:analysis]
      }
      
      # Run multiple times to test randomness
      results = for _ <- 1..10 do
        {:ok, agent_id} = SelectAgent.run(arguments, %{}, strategy: :random)
        {:ok, agent} = Registry.get_agent(agent_id)
        agent.load
      end
      
      # Should get different load values (not always the same)
      unique_loads = Enum.uniq(results)
      assert length(unique_loads) > 1
    end

    test "uses round_robin strategy when specified" do
      arguments = %{
        capabilities: [:analysis]
      }
      
      # Run multiple times
      results = for _ <- 1..6 do
        {:ok, agent_id} = SelectAgent.run(arguments, %{}, strategy: :round_robin)
        {:ok, agent} = Registry.get_agent(agent_id)
        agent.load
      end
      
      # Should cycle through different agents
      unique_loads = Enum.uniq(results)
      assert length(unique_loads) > 1
    end
  end

  describe "run/3 edge cases" do
    test "handles empty capabilities list" do
      arguments = %{
        capabilities: []
      }
      
      # Should select any agent (no capability filtering)
      assert {:ok, agent_id} = SelectAgent.run(arguments, %{}, [])
      assert is_binary(agent_id)
    end

    test "handles nil capabilities" do
      arguments = %{}
      
      # Should select any agent
      assert {:ok, agent_id} = SelectAgent.run(arguments, %{}, [])
      assert is_binary(agent_id)
    end

    test "returns error when no agents are available" do
      # Stop all agents
      Registry.list_agents()
      |> Enum.each(fn agent ->
        Supervisor.stop_agent(agent.id)
      end)
      
      # Give time for cleanup
      Process.sleep(50)
      
      arguments = %{
        capabilities: [:any]
      }
      
      assert {:error, "No agents available"} = 
        SelectAgent.run(arguments, %{}, [])
    end
  end

  describe "compensate/4" do
    test "returns retry for temporary failures" do
      error = {:error, :no_agents_available}
      assert :retry = SelectAgent.compensate(error, %{}, %{}, [])
    end

    test "returns ok for permanent failures" do
      error = {:error, "No agents found with required capabilities"}
      assert :ok = SelectAgent.compensate(error, %{}, %{}, [])
    end
  end
end