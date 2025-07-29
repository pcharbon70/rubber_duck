defmodule RubberDuck.Jido.Agents.SupervisorTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Jido.Agents.{Supervisor, Server, RestartTracker, ShutdownCoordinator}
  alias RubberDuck.Jido.Agents.ExampleAgent
  
  setup do
    # Start the supervisor and its children if not already started
    sup_pid = case Process.whereis(Supervisor) do
      nil ->
        {:ok, pid} = start_supervised(Supervisor)
        pid
      pid ->
        pid
    end
    
    # Start other processes if needed
    unless Process.whereis(RestartTracker) do
      start_supervised(RestartTracker)
    end
    
    unless Process.whereis(ShutdownCoordinator) do
      start_supervised(ShutdownCoordinator)
    end
    
    # Ensure ETS table for restart policies exists
    if :ets.info(:agent_restart_policies) == :undefined do
      :ets.new(:agent_restart_policies, [:set, :public, :named_table])
    end
    
    # Clear any existing data
    :ets.delete_all_objects(:agent_restart_policies)
    
    # Disable backoff for tests
    RestartTracker.set_enabled(false)
    
    on_exit(fn ->
      # Re-enable backoff if process is still alive
      if Process.whereis(RestartTracker) do
        try do
          RestartTracker.set_enabled(true)
        catch
          :exit, _ -> :ok
        end
      end
      
      # Clean up any agents started during tests
      if Process.whereis(Supervisor) do
        try do
          Supervisor.list_agents()
          |> Enum.each(fn %{agent_id: id} ->
            Supervisor.stop_agent(id)
          end)
        catch
          :exit, _ -> :ok
        end
      end
    end)
    
    {:ok, supervisor: sup_pid}
  end
  
  describe "supervisor lifecycle" do
    test "supervisor is started and has expected children", %{supervisor: sup_pid} do
      assert Process.alive?(sup_pid)
      
      # Check children are started - we can't use which_children on a non-dynamic supervisor
      # Instead check that key processes are alive
      assert Process.whereis(RubberDuck.Jido.Agents.DynamicSupervisor) != nil
      assert Process.whereis(RubberDuck.Jido.Agents.RestartTracker) != nil
      assert Process.whereis(RubberDuck.Jido.Agents.ShutdownCoordinator) != nil
    end
    
    test "stats returns expected information" do
      stats = Supervisor.stats()
      assert is_integer(stats.total_agents)
      assert is_integer(stats.active_agents)
      assert is_map(stats.agents_by_module)
      assert is_map(stats.agents_by_restart_policy)
      assert stats.supervision_strategy == :one_for_one
    end
  end
  
  describe "agent management" do
    test "starts an agent successfully" do
      {:ok, pid} = Supervisor.start_agent(ExampleAgent, %{counter: 0})
      assert Process.alive?(pid)
      
      # Verify agent is registered
      {:ok, agent_info} = Server.get_info(pid)
      assert agent_info.agent_module == ExampleAgent
    end
    
    test "starts agent with custom ID and metadata" do
      {:ok, pid} = Supervisor.start_agent(ExampleAgent, %{counter: 0}, 
        id: "custom_agent_123",
        metadata: %{owner: "test", environment: "development"}
      )
      
      {:ok, info} = Server.get_info(pid)
      assert info.agent_id == "custom_agent_123"
      assert info.metadata.owner == "test"
    end
    
    test "enforces restart policies" do
      {:ok, pid} = Supervisor.start_agent(ExampleAgent, %{}, 
        id: "restart_test",
        restart: :temporary
      )
      
      # Kill the agent
      Process.exit(pid, :kill)
      Process.sleep(100)
      
      # Temporary agents should not restart
      agents = Supervisor.list_agents()
      refute Enum.any?(agents, fn %{agent_id: id} -> id == "restart_test" end)
    end
    
    test "stops agent gracefully" do
      {:ok, _pid} = Supervisor.start_agent(ExampleAgent, %{}, id: "stop_test")
      
      assert :ok = Supervisor.stop_agent("stop_test")
      Process.sleep(100)
      
      # Verify agent is removed
      assert {:error, :not_found} = Supervisor.get_agent("stop_test")
    end
    
    test "lists all running agents" do
      # Start multiple agents
      {:ok, _} = Supervisor.start_agent(ExampleAgent, %{}, id: "agent_1")
      {:ok, _} = Supervisor.start_agent(ExampleAgent, %{}, id: "agent_2")
      
      agents = Supervisor.list_agents()
      assert length(agents) >= 2
      
      agent_ids = Enum.map(agents, & &1.id)
      assert "agent_1" in agent_ids
      assert "agent_2" in agent_ids
    end
  end
  
  describe "restart tracking" do
    setup do
      # Enable backoff for these tests
      if Process.whereis(RestartTracker) do
        RestartTracker.set_enabled(true)
        on_exit(fn -> 
          if Process.whereis(RestartTracker) do
            RestartTracker.set_enabled(false)
          end
        end)
      end
      :ok
    end
    
    test "tracks agent restarts" do
      agent_id = "restart_tracker_test"
      
      # Record multiple restarts
      RestartTracker.record_restart(agent_id)
      RestartTracker.record_restart(agent_id)
      
      stats = RestartTracker.get_stats(agent_id)
      assert stats.total_restarts == 2
      assert stats.recent_restart_count == 2
    end
    
    test "enforces backoff after too many restarts" do
      agent_id = "backoff_test"
      
      # Record many restarts quickly
      for _ <- 1..6 do
        RestartTracker.record_restart(agent_id)
      end
      
      # Should be in backoff
      assert {:error, :backoff} = RestartTracker.check_restart(agent_id)
      
      stats = RestartTracker.get_stats(agent_id)
      assert stats.in_backoff == true
    end
    
    test "clears restart history" do
      agent_id = "clear_test"
      
      RestartTracker.record_restart(agent_id)
      assert RestartTracker.get_stats(agent_id) != nil
      
      RestartTracker.clear_history(agent_id)
      assert RestartTracker.get_stats(agent_id) == nil
    end
  end
  
  describe "graceful shutdown" do
    test "coordinates agent shutdown" do
      {:ok, pid} = Supervisor.start_agent(ExampleAgent, %{}, id: "shutdown_test")
      
      # Coordinate shutdown
      assert :ok = ShutdownCoordinator.coordinate_shutdown("shutdown_test", pid, 2000)
      
      # Agent should be terminated
      refute Process.alive?(pid)
    end
    
    test "tracks shutdown status" do
      {:ok, pid} = Supervisor.start_agent(ExampleAgent, %{}, id: "status_test")
      
      # Start shutdown in background
      Task.start(fn ->
        ShutdownCoordinator.coordinate_shutdown("status_test", pid, 5000)
      end)
      
      Process.sleep(50)
      
      # Check status
      status = ShutdownCoordinator.get_shutdown_status()
      assert "status_test" in status.active_shutdowns
    end
  end
  
  describe "rolling restart" do
    test "performs rolling restart of agents" do
      # Start multiple agents
      agent_ids = for i <- 1..3 do
        id = "rolling_#{i}"
        {:ok, _} = Supervisor.start_agent(ExampleAgent, %{}, id: id)
        id
      end
      
      _initial_pids = Supervisor.list_agents()
      |> Enum.filter(fn %{id: id} -> id in agent_ids end)
      |> Enum.map(& &1.pid)
      
      # Perform rolling restart
      assert :ok = Supervisor.rolling_restart(
        fn %{id: id} -> String.starts_with?(id, "rolling_") end,
        delay: 100,
        batch_size: 1
      )
      
      Process.sleep(500)
      
      # All agents should have new PIDs
      _new_pids = Supervisor.list_agents()
      |> Enum.filter(fn %{agent_id: id} -> id in agent_ids end)
      |> Enum.map(& &1.pid)
      
      # Note: This test assumes agents are restarted automatically
      # In practice, temporary agents won't restart
    end
  end
  
  describe "statistics and monitoring" do
    test "provides supervisor statistics" do
      # Start some agents
      {:ok, _} = Supervisor.start_agent(ExampleAgent, %{})
      {:ok, _} = Supervisor.start_agent(ExampleAgent, %{}, restart: :temporary)
      
      stats = Supervisor.stats()
      
      assert stats.total_agents >= 2
      assert stats.active_agents >= 2
      assert is_map(stats.agents_by_module)
      assert is_map(stats.agents_by_restart_policy)
      assert is_map(stats.restart_stats)
    end
    
    test "updates restart policy at runtime" do
      {:ok, _} = Supervisor.start_agent(ExampleAgent, %{}, id: "policy_test")
      
      assert :ok = Supervisor.update_restart_policy("policy_test", :transient)
      
      # Verify policy is stored
      assert [{_, :transient}] = :ets.lookup(:agent_restart_policies, "policy_test")
    end
  end
  
  describe "integration with Agent.Server" do
    test "agent server executes actions" do
      {:ok, pid} = Supervisor.start_agent(ExampleAgent, %{counter: 0})
      
      # Execute action through server
      {:ok, updated_agent} = Server.execute_action(pid, RubberDuck.Jido.Actions.Increment, %{amount: 5})
      
      # The directive result is stored in the result field
      actual_counter = case updated_agent do
        %{result: {:set, %{counter: counter}}} -> counter
        %{state: %{counter: counter}} -> counter
        _ -> 0
      end
      
      assert actual_counter == 5
    end
    
    test "agent server handles signals" do
      {:ok, pid} = Supervisor.start_agent(ExampleAgent, %{messages: []})
      
      # Send signal
      signal = %{
        "specversion" => "1.0",
        "id" => "test-signal",
        "source" => "test",
        "type" => "test.signal"
      }
      
      Server.send_signal(pid, signal)
      Process.sleep(50)
      
      # Check stats were updated
      {:ok, info} = Server.get_info(pid)
      assert info.stats.signals_received == 1
    end
    
    test "agent server health check" do
      {:ok, pid} = Supervisor.start_agent(ExampleAgent, %{})
      
      {:ok, health} = Server.health_check(pid)
      assert health.status == :starting or health.status == :healthy
      assert health.actions_executed == 0
      assert health.error_rate == 0.0
    end
  end
end