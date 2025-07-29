defmodule RubberDuck.Jido.Agents.RegistryTest do
  use ExUnit.Case, async: false
  alias RubberDuck.Jido.Agents.Registry
  
  setup do
    # Start Registry for each test
    {:ok, _pid} = start_supervised(Registry)
    :ok
  end
  
  describe "register/3" do
    test "successfully registers an agent" do
      agent_id = "test_agent_#{System.unique_integer()}"
      pid = self()
      metadata = %{
        module: TestAgent,
        tags: [:worker, :compute],
        capabilities: [:process_data],
        node: node()
      }
      
      assert :ok = Registry.register(agent_id, pid, metadata)
      
      # Verify registration
      assert {:ok, info} = Registry.get_agent(agent_id)
      assert info.id == agent_id
      assert info.pid == pid
      assert info.module == TestAgent
      assert :worker in info.tags
      assert :compute in info.tags
      assert :process_data in info.capabilities
    end
    
    test "prevents duplicate registration with different pid" do
      agent_id = "test_agent_#{System.unique_integer()}"
      pid1 = self()
      {:ok, pid2} = Agent.start_link(fn -> nil end)
      
      assert :ok = Registry.register(agent_id, pid1, %{})
      assert {:error, :already_registered} = Registry.register(agent_id, pid2, %{})
      
      Agent.stop(pid2)
    end
    
    test "allows re-registration with same pid (updates metadata)" do
      agent_id = "test_agent_#{System.unique_integer()}"
      pid = self()
      
      assert :ok = Registry.register(agent_id, pid, %{tags: [:old]})
      assert :ok = Registry.register(agent_id, pid, %{tags: [:new]})
      
      assert {:ok, info} = Registry.get_agent(agent_id)
      assert info.tags == [:new]
    end
  end
  
  describe "unregister/1" do
    test "successfully unregisters an agent" do
      agent_id = "test_agent_#{System.unique_integer()}"
      pid = self()
      
      assert :ok = Registry.register(agent_id, pid, %{})
      assert :ok = Registry.unregister(agent_id)
      assert {:error, :not_found} = Registry.get_agent(agent_id)
    end
    
    test "returns ok for non-existent agent" do
      assert :ok = Registry.unregister("non_existent")
    end
  end
  
  describe "automatic unregistration on process death" do
    test "unregisters agent when process dies" do
      agent_id = "test_agent_#{System.unique_integer()}"
      
      # Start a process that will die
      {:ok, pid} = Agent.start_link(fn -> nil end)
      
      assert :ok = Registry.register(agent_id, pid, %{})
      assert {:ok, _} = Registry.get_agent(agent_id)
      
      # Kill the process
      Agent.stop(pid)
      
      # Give Registry time to handle DOWN message
      Process.sleep(50)
      
      assert {:error, :not_found} = Registry.get_agent(agent_id)
    end
  end
  
  describe "update_metadata/2" do
    test "updates agent metadata" do
      agent_id = "test_agent_#{System.unique_integer()}"
      pid = self()
      
      assert :ok = Registry.register(agent_id, pid, %{status: :idle})
      assert :ok = Registry.update_metadata(agent_id, %{status: :busy, task: "processing"})
      
      assert {:ok, info} = Registry.get_agent(agent_id)
      assert info.metadata.status == :busy
      assert info.metadata.task == "processing"
    end
    
    test "returns error for non-existent agent" do
      assert {:error, :not_found} = Registry.update_metadata("non_existent", %{})
    end
  end
  
  describe "update_load/2" do
    test "updates agent load metric" do
      agent_id = "test_agent_#{System.unique_integer()}"
      pid = self()
      
      assert :ok = Registry.register(agent_id, pid, %{})
      assert :ok = Registry.update_load(agent_id, 5)
      
      assert {:ok, info} = Registry.get_agent(agent_id)
      assert info.metadata.load == 5
    end
  end
  
  describe "find_by_tag/1" do
    test "finds agents by tag" do
      agent1_id = "test_agent_#{System.unique_integer()}"
      agent2_id = "test_agent_#{System.unique_integer()}"
      agent3_id = "test_agent_#{System.unique_integer()}"
      
      Registry.register(agent1_id, self(), %{tags: [:worker, :compute]})
      Registry.register(agent2_id, self(), %{tags: [:worker, :io]})
      Registry.register(agent3_id, self(), %{tags: [:supervisor]})
      
      workers = Registry.find_by_tag(:worker)
      assert length(workers) == 2
      assert Enum.all?(workers, fn agent -> :worker in agent.tags end)
      
      compute_agents = Registry.find_by_tag(:compute)
      assert length(compute_agents) == 1
      assert List.first(compute_agents).id == agent1_id
    end
    
    test "returns empty list when no agents match" do
      assert [] = Registry.find_by_tag(:non_existent_tag)
    end
  end
  
  describe "find_by_capability/1" do
    test "finds agents by capability" do
      agent1_id = "test_agent_#{System.unique_integer()}"
      agent2_id = "test_agent_#{System.unique_integer()}"
      
      Registry.register(agent1_id, self(), %{capabilities: [:read, :write]})
      Registry.register(agent2_id, self(), %{capabilities: [:read]})
      
      readers = Registry.find_by_capability(:read)
      assert length(readers) == 2
      
      writers = Registry.find_by_capability(:write)
      assert length(writers) == 1
      assert List.first(writers).id == agent1_id
    end
  end
  
  describe "find_by_module/1" do
    test "finds agents by module" do
      agent1_id = "test_agent_#{System.unique_integer()}"
      agent2_id = "test_agent_#{System.unique_integer()}"
      
      Registry.register(agent1_id, self(), %{module: ModuleA})
      Registry.register(agent2_id, self(), %{module: ModuleB})
      Registry.register("agent3", self(), %{module: ModuleA})
      
      module_a_agents = Registry.find_by_module(ModuleA)
      assert length(module_a_agents) == 2
      assert Enum.all?(module_a_agents, fn agent -> agent.module == ModuleA end)
    end
  end
  
  describe "find_by_node/1" do
    test "finds agents by node" do
      agent_id = "test_agent_#{System.unique_integer()}"
      current_node = node()
      
      Registry.register(agent_id, self(), %{node: current_node})
      
      agents = Registry.find_by_node(current_node)
      assert length(agents) >= 1
      assert Enum.any?(agents, fn agent -> agent.id == agent_id end)
    end
  end
  
  describe "get_least_loaded/1" do
    test "returns agent with lowest load" do
      agent1_id = "test_agent_#{System.unique_integer()}"
      agent2_id = "test_agent_#{System.unique_integer()}"
      agent3_id = "test_agent_#{System.unique_integer()}"
      
      Registry.register(agent1_id, self(), %{tags: [:worker]})
      Registry.register(agent2_id, self(), %{tags: [:worker]})
      Registry.register(agent3_id, self(), %{tags: [:worker]})
      
      Registry.update_load(agent1_id, 10)
      Registry.update_load(agent2_id, 5)
      Registry.update_load(agent3_id, 15)
      
      assert {:ok, agent} = Registry.get_least_loaded(:worker)
      assert agent.id == agent2_id
      assert agent.metadata.load == 5
    end
    
    test "returns error when no agents available" do
      assert {:error, :no_agents} = Registry.get_least_loaded(:non_existent_tag)
    end
    
    test "returns least loaded from all agents when no tag specified" do
      agent1_id = "test_agent_#{System.unique_integer()}"
      agent2_id = "test_agent_#{System.unique_integer()}"
      
      Registry.register(agent1_id, self(), %{})
      Registry.register(agent2_id, self(), %{})
      
      Registry.update_load(agent1_id, 10)
      Registry.update_load(agent2_id, 5)
      
      assert {:ok, agent} = Registry.get_least_loaded()
      assert agent.id == agent2_id
    end
  end
  
  describe "query/1" do
    test "queries agents with multiple criteria" do
      agent1_id = "test_agent_#{System.unique_integer()}"
      agent2_id = "test_agent_#{System.unique_integer()}"
      agent3_id = "test_agent_#{System.unique_integer()}"
      
      Registry.register(agent1_id, self(), %{
        module: TestAgent,
        tags: [:worker, :compute],
        capabilities: [:process]
      })
      
      Registry.register(agent2_id, self(), %{
        module: TestAgent,
        tags: [:worker],
        capabilities: [:store]
      })
      
      Registry.register(agent3_id, self(), %{
        module: OtherAgent,
        tags: [:worker, :compute],
        capabilities: [:process]
      })
      
      # Query by module and tag
      results = Registry.query(%{module: TestAgent, tags: :compute})
      assert length(results) == 1
      assert List.first(results).id == agent1_id
      
      # Query by capability
      results = Registry.query(%{capabilities: :process})
      assert length(results) == 2
      assert Enum.all?(results, fn agent -> :process in agent.capabilities end)
      
      # Query with multiple criteria
      results = Registry.query(%{
        module: TestAgent,
        tags: :worker,
        capabilities: :store
      })
      assert length(results) == 1
      assert List.first(results).id == agent2_id
    end
    
    test "returns empty list when no agents match criteria" do
      assert [] = Registry.query(%{module: NonExistentModule})
    end
  end
  
  describe "list_agents/0" do
    test "lists all registered agents" do
      agent1_id = "test_agent_#{System.unique_integer()}"
      agent2_id = "test_agent_#{System.unique_integer()}"
      
      Registry.register(agent1_id, self(), %{})
      Registry.register(agent2_id, self(), %{})
      
      agents = Registry.list_agents()
      agent_ids = Enum.map(agents, & &1.id)
      
      assert agent1_id in agent_ids
      assert agent2_id in agent_ids
    end
  end
end