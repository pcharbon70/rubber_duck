defmodule RubberDuck.MnesiaManagerTest do
  use ExUnit.Case, async: false

  alias RubberDuck.MnesiaManager

  setup do
    # Stop the application to control Mnesia lifecycle in tests
    Application.stop(:rubber_duck)
    
    # Clean up any existing Mnesia schema
    :mnesia.delete_schema([node()])
    
    on_exit(fn -> 
      :mnesia.stop()
      :mnesia.delete_schema([node()])
      Application.start(:rubber_duck) 
    end)
    :ok
  end

  describe "start_link/1" do
    test "starts the MnesiaManager GenServer" do
      assert {:ok, pid} = MnesiaManager.start_link([])
      assert Process.alive?(pid)
    end

    test "registers the process with its module name" do
      assert {:ok, _pid} = MnesiaManager.start_link([])
      assert Process.whereis(MnesiaManager) != nil
    end

    test "accepts configuration options" do
      config = %{timeout: 30_000, nodes: [node()]}
      assert {:ok, pid} = MnesiaManager.start_link(config: config)
      assert Process.alive?(pid)
    end
  end

  describe "schema initialization" do
    setup do
      {:ok, pid} = MnesiaManager.start_link([])
      %{pid: pid}
    end

    test "initializes Mnesia schema", %{pid: pid} do
      assert :ok = MnesiaManager.initialize_schema(pid)
      
      # Mnesia should be running
      assert :mnesia.system_info(:is_running) == :yes
    end

    test "creates required tables", %{pid: pid} do
      MnesiaManager.initialize_schema(pid)
      
      # Check that all required tables exist
      tables = MnesiaManager.get_tables(pid)
      
      assert :sessions in tables
      assert :models in tables
      assert :model_stats in tables
      assert :cluster_nodes in tables
    end

    test "handles schema already exists", %{pid: pid} do
      # Initialize once
      assert :ok = MnesiaManager.initialize_schema(pid)
      
      # Initialize again should succeed (idempotent)
      assert :ok = MnesiaManager.initialize_schema(pid)
    end

    test "sets up proper table attributes", %{pid: pid} do
      MnesiaManager.initialize_schema(pid)
      
      # Check sessions table attributes
      sessions_info = :mnesia.table_info(:sessions, :attributes)
      assert sessions_info == [:session_id, :messages, :metadata, :created_at, :updated_at, :node]
      
      # Check models table attributes
      models_info = :mnesia.table_info(:models, :attributes)
      assert models_info == [:name, :type, :endpoint, :capabilities, :health_status, :health_reason, :registered_at, :node]
    end
  end

  describe "table operations" do
    setup do
      {:ok, pid} = MnesiaManager.start_link([])
      MnesiaManager.initialize_schema(pid)
      %{pid: pid}
    end

    test "lists all tables", %{pid: pid} do
      tables = MnesiaManager.get_tables(pid)
      
      assert is_list(tables)
      assert :sessions in tables
      assert :models in tables
      assert :model_stats in tables
      assert :cluster_nodes in tables
    end

    test "gets table info", %{pid: pid} do
      info = MnesiaManager.get_table_info(pid, :sessions)
      
      assert is_map(info)
      assert Map.has_key?(info, :type)
      assert Map.has_key?(info, :size)
      assert Map.has_key?(info, :memory)
      assert Map.has_key?(info, :storage_type)
    end

    test "checks table exists", %{pid: pid} do
      assert MnesiaManager.table_exists?(pid, :sessions) == true
      assert MnesiaManager.table_exists?(pid, :non_existent) == false
    end
  end

  describe "replication management" do
    setup do
      {:ok, pid} = MnesiaManager.start_link([])
      MnesiaManager.initialize_schema(pid)
      %{pid: pid}
    end

    test "gets table storage type", %{pid: pid} do
      # Sessions should be ram_copies for fast access
      storage = MnesiaManager.get_storage_type(pid, :sessions)
      assert storage in [:ram_copies, :disc_copies, :disc_only_copies]
    end

    test "lists nodes for table", %{pid: pid} do
      nodes = MnesiaManager.get_table_nodes(pid, :sessions)
      assert is_list(nodes)
      assert node() in nodes
    end
  end

  describe "backup and recovery" do
    setup do
      {:ok, pid} = MnesiaManager.start_link([])
      MnesiaManager.initialize_schema(pid)
      %{pid: pid}
    end

    test "creates backup", %{pid: pid} do
      backup_path = "/tmp/rubber_duck_test_backup.bak"
      
      # Clean up any existing backup
      File.rm(backup_path)
      
      assert :ok = MnesiaManager.create_backup(pid, backup_path)
      assert File.exists?(backup_path)
      
      # Clean up
      File.rm(backup_path)
    end

    test "restores backup", %{pid: pid} do
      backup_path = "/tmp/rubber_duck_test_backup.bak"
      
      # Create a backup first
      MnesiaManager.create_backup(pid, backup_path)
      
      # Restore should work
      assert :ok = MnesiaManager.restore_backup(pid, backup_path)
      
      # Clean up
      File.rm(backup_path)
    end
  end

  describe "health monitoring" do
    setup do
      {:ok, pid} = MnesiaManager.start_link([])
      %{pid: pid}
    end

    test "responds to health check", %{pid: pid} do
      assert :ok = MnesiaManager.health_check(pid)
    end

    test "returns manager info", %{pid: pid} do
      info = MnesiaManager.get_info(pid)
      
      assert %{
        status: _,
        mnesia_running: _,
        tables: _,
        memory: _,
        uptime: _
      } = info
      
      assert info.status in [:initializing, :running, :stopped]
      assert is_boolean(info.mnesia_running)
      assert is_list(info.tables)
    end

    test "gets cluster status", %{pid: pid} do
      MnesiaManager.initialize_schema(pid)
      
      status = MnesiaManager.get_cluster_status(pid)
      
      assert %{
        running_nodes: _,
        stopped_nodes: _,
        master_node: _,
        schema_location: _
      } = status
      
      assert is_list(status.running_nodes)
      assert is_list(status.stopped_nodes)
      assert node() in status.running_nodes
    end
  end

  describe "graceful shutdown" do
    test "handles normal shutdown gracefully" do
      {:ok, pid} = MnesiaManager.start_link([])
      MnesiaManager.initialize_schema(pid)
      
      # Shutdown should complete without error
      assert :ok = GenServer.stop(pid, :normal)
      refute Process.alive?(pid)
    end
  end
end