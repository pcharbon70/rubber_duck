defmodule RubberDuck.Engine.SupervisorTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Engine.Supervisor
  alias RubberDuck.EngineSystem.Engine, as: EngineConfig
  
  # Use test engine from server test
  alias RubberDuck.Engine.ServerTest.TestEngine
  
  setup do
    # Supervisor is started by application, but let's ensure it's clean
    engines = Supervisor.list_engines()
    Enum.each(engines, fn {name, _pid} ->
      Supervisor.stop_engine(name)
    end)
    
    engine_config = %EngineConfig{
      name: :sup_test_engine,
      module: TestEngine,
      description: "Supervisor test engine",
      priority: 50,
      timeout: 1000,
      config: []
    }
    
    {:ok, engine_config: engine_config}
  end
  
  describe "start_engine/2" do
    test "starts engine under supervision", %{engine_config: config} do
      assert {:ok, pid} = Supervisor.start_engine(config)
      assert Process.alive?(pid)
      
      # Verify it's in the supervisor
      engines = Supervisor.list_engines()
      assert {config.name, pid} in engines
      
      Supervisor.stop_engine(config.name)
    end
    
    test "prevents duplicate engines", %{engine_config: config} do
      assert {:ok, _pid} = Supervisor.start_engine(config)
      assert {:error, :already_started} = Supervisor.start_engine(config)
      
      Supervisor.stop_engine(config.name)
    end
  end
  
  describe "stop_engine/1" do
    test "stops engine by name", %{engine_config: config} do
      {:ok, pid} = Supervisor.start_engine(config)
      assert :ok = Supervisor.stop_engine(config.name)
      
      refute Process.alive?(pid)
      assert Supervisor.list_engines() == []
    end
    
    test "stops engine by pid", %{engine_config: config} do
      {:ok, pid} = Supervisor.start_engine(config)
      assert :ok = Supervisor.stop_engine(pid)
      
      refute Process.alive?(pid)
    end
    
    test "returns error for non-existent engine" do
      assert {:error, :not_found} = Supervisor.stop_engine(:nonexistent)
    end
  end
  
  describe "restart_engine/2" do
    test "restarts engine with new pid", %{engine_config: config} do
      {:ok, old_pid} = Supervisor.start_engine(config)
      
      assert {:ok, new_pid} = Supervisor.restart_engine(config.name, config)
      assert new_pid != old_pid
      refute Process.alive?(old_pid)
      assert Process.alive?(new_pid)
      
      Supervisor.stop_engine(config.name)
    end
  end
  
  describe "list_engines/0" do
    test "lists all running engines", %{engine_config: config} do
      assert Supervisor.list_engines() == []
      
      {:ok, pid1} = Supervisor.start_engine(config)
      
      config2 = %{config | name: :another_test_engine}
      {:ok, pid2} = Supervisor.start_engine(config2)
      
      engines = Supervisor.list_engines()
      assert length(engines) == 2
      assert {config.name, pid1} in engines
      assert {config2.name, pid2} in engines
      
      Supervisor.stop_engine(config.name)
      Supervisor.stop_engine(config2.name)
    end
  end
  
  describe "count_engines/0" do
    test "counts running engines", %{engine_config: config} do
      counts = Supervisor.count_engines()
      initial_active = counts.active
      
      {:ok, _} = Supervisor.start_engine(config)
      
      new_counts = Supervisor.count_engines()
      assert new_counts.active == initial_active + 1
      
      Supervisor.stop_engine(config.name)
    end
  end
  
  describe "fault tolerance" do
    test "restarts crashed engines", %{engine_config: config} do
      {:ok, pid} = Supervisor.start_engine(config)
      
      # Simulate crash
      Process.exit(pid, :kill)
      
      # Give supervisor time to restart
      Process.sleep(100)
      
      # Engine should be restarted with new pid
      engines = Supervisor.list_engines()
      assert length(engines) == 1
      
      {name, new_pid} = hd(engines)
      assert name == config.name
      assert new_pid != pid
      assert Process.alive?(new_pid)
      
      Supervisor.stop_engine(config.name)
    end
  end
end