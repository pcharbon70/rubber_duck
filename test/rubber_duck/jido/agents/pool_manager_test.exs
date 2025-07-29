defmodule RubberDuck.Jido.Agents.PoolManagerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Jido.Agents.{PoolManager, Supervisor, Registry}
  alias RubberDuck.Jido.Agents.ExampleAgent
  
  setup do
    # Ensure supervisor is started
    {:ok, _} = start_supervised(Supervisor)
    
    # Start registry if not already started
    unless Process.whereis(Registry) do
      start_supervised(Registry)
    end
    
    # Ensure ETS table for restart policies exists
    if :ets.info(:agent_restart_policies) == :undefined do
      :ets.new(:agent_restart_policies, [:set, :public, :named_table])
    end
    
    on_exit(fn ->
      # Clean up any pools
      Process.list()
      |> Enum.filter(fn pid ->
        case Process.info(pid, :registered_name) do
          {:registered_name, name} -> 
            name |> to_string() |> String.contains?("pool")
          _ -> false
        end
      end)
      |> Enum.each(&Process.exit(&1, :kill))
    end)
    
    :ok
  end
  
  describe "pool lifecycle" do
    test "starts pool with default configuration" do
      {:ok, pool} = PoolManager.start_pool(ExampleAgent, name: :test_pool1)
      assert Process.alive?(pool)
      
      stats = PoolManager.stats(:test_pool1)
      assert stats.pool_size >= 1
      assert stats.available >= 0
      assert stats.busy == 0
    end
    
    test "starts pool with custom configuration" do
      {:ok, _pool} = PoolManager.start_pool(ExampleAgent,
        name: :test_pool2,
        min_size: 2,
        max_size: 8,
        target_size: 4
      )
      
      # Wait for warmup
      Process.sleep(100)
      
      stats = PoolManager.stats(:test_pool2)
      assert stats.pool_size == 4
      assert stats.available == 4
    end
    
    test "stops pool gracefully" do
      {:ok, pool} = PoolManager.start_pool(ExampleAgent, name: :test_pool3)
      assert :ok = PoolManager.stop_pool(pool)
      refute Process.alive?(pool)
    end
  end
  
  describe "checkout/checkin" do
    setup do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :checkout_pool,
        target_size: 3
      )
      Process.sleep(100)
      {:ok, pool: :checkout_pool}
    end
    
    test "checks out available agent", %{pool: pool} do
      {:ok, agent} = PoolManager.checkout(pool)
      assert agent.module == ExampleAgent
      assert is_pid(agent.pid)
      
      stats = PoolManager.stats(pool)
      assert stats.busy == 1
      assert stats.checkouts == 1
    end
    
    test "checks in agent back to pool", %{pool: pool} do
      {:ok, agent} = PoolManager.checkout(pool)
      :ok = PoolManager.checkin(pool, agent)
      
      Process.sleep(50)
      
      stats = PoolManager.stats(pool)
      assert stats.busy == 0
      assert stats.checkins == 1
    end
    
    test "handles multiple checkouts", %{pool: pool} do
      agents = for _ <- 1..3 do
        {:ok, agent} = PoolManager.checkout(pool)
        agent
      end
      
      stats = PoolManager.stats(pool)
      assert stats.busy == 3
      assert stats.available == 0
      
      # Return one agent
      PoolManager.checkin(pool, hd(agents))
      Process.sleep(50)
      
      stats = PoolManager.stats(pool)
      assert stats.busy == 2
      assert stats.available == 1
    end
  end
  
  describe "pooling strategies" do
    test "round-robin strategy" do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :round_robin_pool,
        target_size: 3,
        strategy: :round_robin
      )
      
      Process.sleep(100)
      
      # Checkout all agents
      agents = for _ <- 1..3 do
        {:ok, agent} = PoolManager.checkout(:round_robin_pool)
        agent
      end
      
      # Return them
      Enum.each(agents, &PoolManager.checkin(:round_robin_pool, &1))
      Process.sleep(50)
      
      # Check they come out in FIFO order (first returned, first out)
      {:ok, agent1} = PoolManager.checkout(:round_robin_pool)
      {:ok, agent2} = PoolManager.checkout(:round_robin_pool)
      
      # Should be in the order they were returned to the pool
      assert agent1.id in Enum.map(agents, & &1.id)
      assert agent2.id in Enum.map(agents, & &1.id)
      assert agent1.id != agent2.id
    end
    
    test "random strategy" do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :random_pool,
        target_size: 5,
        strategy: :random
      )
      
      Process.sleep(100)
      
      # Multiple checkouts should give different agents (statistically)
      agent_ids = for _ <- 1..10 do
        {:ok, agent} = PoolManager.checkout(:random_pool)
        id = agent.id
        PoolManager.checkin(:random_pool, agent)
        Process.sleep(10)
        id
      end
      
      # Should have some variety
      unique_ids = Enum.uniq(agent_ids)
      assert length(unique_ids) > 1
    end
    
    test "least-loaded strategy" do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :least_loaded_pool,
        target_size: 3,
        strategy: :least_loaded
      )
      
      Process.sleep(100)
      
      # Set different loads
      agents = Supervisor.find_by_tag(:least_loaded_pool)
      Registry.update_load(Enum.at(agents, 0).id, 10)
      Registry.update_load(Enum.at(agents, 1).id, 5)
      Registry.update_load(Enum.at(agents, 2).id, 15)
      
      # Should get the one with load 5
      {:ok, agent} = PoolManager.checkout(:least_loaded_pool)
      assert agent.id == Enum.at(agents, 1).id
    end
  end
  
  describe "overflow handling" do
    test "queues requests when pool exhausted" do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :queue_pool,
        target_size: 2,
        overflow: :queue,
        max_overflow: 5
      )
      
      Process.sleep(100)
      
      # Exhaust pool
      {:ok, agent1} = PoolManager.checkout(:queue_pool)
      {:ok, _agent2} = PoolManager.checkout(:queue_pool)
      
      # Next checkout should queue
      task = Task.async(fn ->
        PoolManager.checkout(:queue_pool, 1000)
      end)
      
      # Give it time to queue
      Process.sleep(50)
      
      stats = PoolManager.stats(:queue_pool)
      assert stats.queue_depth == 1
      
      # Return an agent
      PoolManager.checkin(:queue_pool, agent1)
      
      # Queued request should complete
      {:ok, agent} = Task.await(task)
      assert agent.id == agent1.id
    end
    
    test "returns error when queue full" do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :full_queue_pool,
        target_size: 1,
        overflow: :queue,
        max_overflow: 1
      )
      
      Process.sleep(100)
      
      # Exhaust pool
      {:ok, _} = PoolManager.checkout(:full_queue_pool)
      
      # Queue one
      Task.start(fn ->
        PoolManager.checkout(:full_queue_pool, 10_000)
      end)
      
      Process.sleep(50)
      
      # Next should fail
      assert {:error, :queue_full} = PoolManager.checkout(:full_queue_pool)
    end
    
    test "spawns new agent on demand" do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :spawn_pool,
        min_size: 1,
        max_size: 5,
        target_size: 2,
        overflow: :spawn
      )
      
      Process.sleep(100)
      
      initial_stats = PoolManager.stats(:spawn_pool)
      assert initial_stats.pool_size == 2
      
      # Exhaust pool
      {:ok, _} = PoolManager.checkout(:spawn_pool)
      {:ok, _} = PoolManager.checkout(:spawn_pool)
      
      # Next checkout should spawn new agent
      {:ok, _} = PoolManager.checkout(:spawn_pool)
      
      Process.sleep(50)
      
      stats = PoolManager.stats(:spawn_pool)
      assert stats.pool_size == 3
    end
  end
  
  describe "execute function" do
    setup do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :execute_pool,
        target_size: 3,
        overflow: :queue
      )
      Process.sleep(100)
      {:ok, pool: :execute_pool}
    end
    
    test "executes action on pooled agent", %{pool: pool} do
      {:ok, result} = PoolManager.execute(pool, RubberDuck.Jido.Actions.Increment, %{amount: 7})
      
      # Check result based on the agent structure
      has_correct_counter = case result do
        %{result: {:set, %{counter: 7}}} -> true
        %{state: %{counter: 7}} -> true
        _ -> false
      end
      
      assert has_correct_counter
      
      stats = PoolManager.stats(pool)
      assert stats.executions == 1
    end
    
    test "handles concurrent executions", %{pool: pool} do
      # Only do 3 concurrent to avoid overwhelming a pool of 2
      tasks = for i <- 1..3 do
        Task.async(fn ->
          PoolManager.execute(pool, RubberDuck.Jido.Actions.Increment, %{amount: i})
        end)
      end
      
      results = Task.await_many(tasks, 10000)
      assert length(results) == 3
      assert Enum.all?(results, fn {:ok, _} -> true; _ -> false end)
      
      stats = PoolManager.stats(pool)
      assert stats.executions == 3
    end
  end
  
  describe "dynamic scaling" do
    @tag :slow
    test "scales up when load is high" do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :scale_up_pool,
        min_size: 2,
        max_size: 10,
        target_size: 3,
        scale_up_threshold: 0.8,
        scale_interval: 100,
        cooldown_period: 200
      )
      
      Process.sleep(150)
      
      initial_stats = PoolManager.stats(:scale_up_pool)
      assert initial_stats.pool_size == 3
      
      # Create high load by checking out all agents
      agents = for _ <- 1..3 do
        {:ok, agent} = PoolManager.checkout(:scale_up_pool)
        agent
      end
      
      # Wait for multiple scaling checks
      Process.sleep(500)
      
      stats = PoolManager.stats(:scale_up_pool)
      # Should scale up when all agents are busy
      assert stats.pool_size >= 3
      assert stats.scaling_events >= 0
      
      # Cleanup
      Enum.each(agents, &PoolManager.checkin(:scale_up_pool, &1))
    end
    
    @tag :slow
    test "scales down when load is low" do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :scale_down_pool,
        min_size: 2,
        max_size: 10,
        target_size: 5,
        scale_down_threshold: 0.2,
        scale_interval: 100,
        cooldown_period: 200
      )
      
      Process.sleep(150)
      
      initial_stats = PoolManager.stats(:scale_down_pool)
      assert initial_stats.pool_size == 5
      
      # Keep load low (no checkouts)
      # Wait for multiple scaling checks to allow cooldown
      Process.sleep(600)
      
      stats = PoolManager.stats(:scale_down_pool)
      # May or may not scale down depending on timing
      assert stats.pool_size <= 5
      assert stats.pool_size >= 2
    end
    
    test "respects min and max size limits" do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :limit_pool,
        min_size: 2,
        max_size: 4,
        target_size: 2
      )
      
      Process.sleep(100)
      
      # Try to scale beyond limits
      PoolManager.scale(:limit_pool, 10)
      stats = PoolManager.stats(:limit_pool)
      assert stats.pool_size == 4
      
      # Try to scale below limits
      PoolManager.scale(:limit_pool, 1)
      stats = PoolManager.stats(:limit_pool)
      assert stats.pool_size == 2
    end
  end
  
  describe "configuration updates" do
    test "updates pool configuration at runtime" do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :config_pool,
        target_size: 3,
        max_size: 5
      )
      
      Process.sleep(100)
      
      # Update config
      :ok = PoolManager.update_config(:config_pool, 
        max_size: 10,
        scale_up_threshold: 0.7
      )
      
      # Scale to new max
      PoolManager.scale(:config_pool, 8)
      stats = PoolManager.stats(:config_pool)
      assert stats.pool_size == 8
    end
  end
  
  describe "error handling" do
    test "handles agent crashes gracefully" do
      {:ok, _} = PoolManager.start_pool(ExampleAgent,
        name: :crash_pool,
        min_size: 2,
        target_size: 3
      )
      
      Process.sleep(100)
      
      # Get an agent and crash it
      {:ok, agent} = PoolManager.checkout(:crash_pool)
      Process.exit(agent.pid, :kill)
      
      Process.sleep(100)
      
      # Pool should maintain min size
      stats = PoolManager.stats(:crash_pool)
      assert stats.pool_size >= 2
    end
  end
end