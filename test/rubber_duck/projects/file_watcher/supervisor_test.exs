defmodule RubberDuck.Projects.FileWatcher.SupervisorTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Projects.FileWatcher.Supervisor, as: FWSupervisor
  
  @test_project_id "test_project_#{System.unique_integer()}"
  @test_root System.tmp_dir!()
  
  setup do
    # Supervisor is already started by the application
    # Just ensure no watchers are running
    on_exit(fn ->
      FWSupervisor.list_watchers()
      |> Enum.each(fn {project_id, _pid} ->
        FWSupervisor.stop_watcher(project_id)
      end)
    end)
    
    :ok
  end
  
  describe "start_watcher/2" do
    test "starts a file watcher for a project" do
      opts = %{root_path: @test_root}
      
      assert {:ok, pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end
    
    test "returns error when root_path is missing" do
      opts = %{}
      
      assert {:error, :invalid_root_path} = FWSupervisor.start_watcher(@test_project_id, opts)
    end
    
    test "returns error when root_path is not a directory" do
      opts = %{root_path: "/non/existent/path"}
      
      assert {:error, :root_path_not_directory} = FWSupervisor.start_watcher(@test_project_id, opts)
    end
    
    test "returns error when watcher already running" do
      opts = %{root_path: @test_root}
      
      assert {:ok, _pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      assert {:error, :already_running} = FWSupervisor.start_watcher(@test_project_id, opts)
    end
    
    test "accepts optional configuration" do
      opts = %{
        root_path: @test_root,
        debounce_ms: 200,
        batch_size: 100,
        recursive: false
      }
      
      assert {:ok, pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      assert is_pid(pid)
    end
  end
  
  describe "stop_watcher/1" do
    test "stops a running watcher" do
      opts = %{root_path: @test_root}
      assert {:ok, pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      assert :ok = FWSupervisor.stop_watcher(@test_project_id)
      refute Process.alive?(pid)
    end
    
    test "returns error when watcher not found" do
      assert {:error, :not_found} = FWSupervisor.stop_watcher("non_existent_project")
    end
  end
  
  describe "list_watchers/0" do
    test "returns empty list when no watchers running" do
      assert [] = FWSupervisor.list_watchers()
    end
    
    test "returns list of running watchers" do
      project1 = "#{@test_project_id}_1"
      project2 = "#{@test_project_id}_2"
      
      opts = %{root_path: @test_root}
      assert {:ok, pid1} = FWSupervisor.start_watcher(project1, opts)
      assert {:ok, pid2} = FWSupervisor.start_watcher(project2, opts)
      
      watchers = FWSupervisor.list_watchers()
      assert length(watchers) == 2
      
      assert {^project1, ^pid1} = Enum.find(watchers, fn {id, _} -> id == project1 end)
      assert {^project2, ^pid2} = Enum.find(watchers, fn {id, _} -> id == project2 end)
    end
  end
  
  describe "watcher_running?/1" do
    test "returns false when watcher not running" do
      refute FWSupervisor.watcher_running?(@test_project_id)
    end
    
    test "returns true when watcher is running" do
      opts = %{root_path: @test_root}
      assert {:ok, _pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      assert FWSupervisor.watcher_running?(@test_project_id)
    end
  end
  
  describe "get_watcher/1" do
    test "returns pid when watcher exists" do
      opts = %{root_path: @test_root}
      assert {:ok, pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      assert {:ok, ^pid} = FWSupervisor.get_watcher(@test_project_id)
    end
    
    test "returns error when watcher not found" do
      assert {:error, :not_found} = FWSupervisor.get_watcher("non_existent_project")
    end
  end
  
  describe "supervision" do
    test "restarts watcher on crash" do
      opts = %{root_path: @test_root}
      assert {:ok, pid1} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      # Force crash
      Process.exit(pid1, :kill)
      
      # Give supervisor time to restart
      Process.sleep(100)
      
      # Should have a new pid
      assert {:ok, pid2} = FWSupervisor.get_watcher(@test_project_id)
      assert pid1 != pid2
      assert Process.alive?(pid2)
    end
    
    test "respects max restart limits" do
      opts = %{root_path: @test_root}
      project_id = "#{@test_project_id}_restart_test"
      
      assert {:ok, _pid} = FWSupervisor.start_watcher(project_id, opts)
      
      # Force multiple crashes
      for _ <- 1..5 do
        case FWSupervisor.get_watcher(project_id) do
          {:ok, pid} -> Process.exit(pid, :kill)
          _ -> :ok
        end
        Process.sleep(50)
      end
      
      # After max restarts, watcher should not be running
      Process.sleep(200)
      refute FWSupervisor.watcher_running?(project_id)
    end
  end
end