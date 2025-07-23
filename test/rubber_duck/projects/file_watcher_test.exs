defmodule RubberDuck.Projects.FileWatcherTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Projects.FileWatcher
  alias RubberDuck.Projects.FileWatcher.Supervisor, as: FWSupervisor
  alias Phoenix.PubSub
  
  @test_project_id "test_project_#{System.unique_integer()}"
  @pubsub RubberDuck.PubSub
  
  setup do
    # Create a temporary directory for testing
    test_dir = Path.join([System.tmp_dir!(), "file_watcher_test", "#{System.unique_integer()}"])
    File.mkdir_p!(test_dir)
    
    # Supervisor is already started by the application
    
    on_exit(fn ->
      # Stop any running watchers
      FWSupervisor.stop_watcher(@test_project_id)
      
      # Clean up test directory
      File.rm_rf!(test_dir)
    end)
    
    {:ok, test_dir: test_dir}
  end
  
  describe "file watching" do
    test "detects file creation", %{test_dir: test_dir} do
      # Subscribe to events
      FileWatcher.subscribe(@test_project_id)
      
      # Start watcher
      opts = %{root_path: test_dir, debounce_ms: 50}
      assert {:ok, _pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      # Create a file
      test_file = Path.join(test_dir, "test.txt")
      File.write!(test_file, "test content")
      
      # Wait for debounce and check for event
      assert_receive %{
        event: :file_changed,
        project_id: @test_project_id,
        changes: changes
      }, 200
      
      assert length(changes) == 1
      [change] = changes
      assert change.path == "test.txt"
      assert change.type == :created
    end
    
    test "detects file modification", %{test_dir: test_dir} do
      # Create file first
      test_file = Path.join(test_dir, "modify.txt")
      File.write!(test_file, "initial content")
      
      # Subscribe and start watcher
      FileWatcher.subscribe(@test_project_id)
      opts = %{root_path: test_dir, debounce_ms: 50}
      assert {:ok, _pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      # Wait a bit to ensure watcher is ready
      Process.sleep(100)
      
      # Modify the file
      File.write!(test_file, "modified content")
      
      # Wait for event
      assert_receive %{
        event: :file_changed,
        changes: changes
      }, 200
      
      assert Enum.any?(changes, fn c -> 
        c.path == "modify.txt" and c.type == :modified
      end)
    end
    
    test "detects file deletion", %{test_dir: test_dir} do
      # Create file first
      test_file = Path.join(test_dir, "delete.txt")
      File.write!(test_file, "to be deleted")
      
      # Subscribe and start watcher
      FileWatcher.subscribe(@test_project_id)
      opts = %{root_path: test_dir, debounce_ms: 50}
      assert {:ok, _pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      # Wait a bit
      Process.sleep(100)
      
      # Delete the file
      File.rm!(test_file)
      
      # Wait for event
      assert_receive %{
        event: :file_changed,
        changes: changes
      }, 200
      
      assert Enum.any?(changes, fn c -> 
        c.path == "delete.txt" and c.type == :deleted
      end)
    end
    
    test "batches multiple events", %{test_dir: test_dir} do
      # Subscribe and start watcher
      FileWatcher.subscribe(@test_project_id)
      opts = %{root_path: test_dir, debounce_ms: 100}
      assert {:ok, _pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      # Create multiple files quickly
      for i <- 1..5 do
        file = Path.join(test_dir, "batch_#{i}.txt")
        File.write!(file, "content #{i}")
      end
      
      # Should receive one batched event
      assert_receive %{
        event: :file_changed,
        changes: changes,
        batch_size: batch_size
      }, 300
      
      assert batch_size >= 5
      assert length(changes) >= 5
    end
    
    test "respects debounce timing", %{test_dir: test_dir} do
      # Subscribe and start watcher with longer debounce
      FileWatcher.subscribe(@test_project_id)
      opts = %{root_path: test_dir, debounce_ms: 200}
      assert {:ok, _pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      # Create first file
      File.write!(Path.join(test_dir, "debounce_1.txt"), "content")
      
      # Wait less than debounce time
      Process.sleep(100)
      
      # Create second file
      File.write!(Path.join(test_dir, "debounce_2.txt"), "content")
      
      # Should not receive event yet
      refute_receive %{event: :file_changed}, 50
      
      # Should receive after full debounce
      assert_receive %{
        event: :file_changed,
        changes: changes
      }, 200
      
      # Both files should be in the same batch
      assert length(changes) == 2
    end
  end
  
  describe "security" do
    test "ignores events outside project root", %{test_dir: test_dir} do
      # Subscribe and start watcher
      FileWatcher.subscribe(@test_project_id)
      opts = %{root_path: test_dir}
      assert {:ok, _pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      # Try to create a file outside the watched directory
      outside_file = Path.join(System.tmp_dir!(), "outside_file.txt")
      File.write!(outside_file, "outside content")
      
      # Should not receive any events
      refute_receive %{event: :file_changed}, 200
      
      # Clean up
      File.rm(outside_file)
    end
    
    test "handles symlinks safely", %{test_dir: test_dir} do
      # Subscribe and start watcher
      FileWatcher.subscribe(@test_project_id)
      opts = %{root_path: test_dir}
      assert {:ok, _pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      # Create a file outside the project
      outside_file = Path.join(System.tmp_dir!(), "linked_file.txt")
      File.write!(outside_file, "linked content")
      
      # Create a symlink inside the project
      symlink = Path.join(test_dir, "symlink.txt")
      File.ln_s!(outside_file, symlink)
      
      # Modify the outside file through the symlink
      File.write!(symlink, "modified through symlink")
      
      # Should not receive events for symlink modifications
      refute_receive %{event: :file_changed}, 200
      
      # Clean up
      File.rm(symlink)
      File.rm(outside_file)
    end
  end
  
  describe "get_status/1" do
    test "returns watcher status", %{test_dir: test_dir} do
      opts = %{root_path: test_dir}
      assert {:ok, _pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      assert {:ok, status} = FileWatcher.get_status(@test_project_id)
      
      assert status.project_id == @test_project_id
      assert status.root_path == test_dir
      assert status.watching == true
      assert status.buffer_size == 0
      assert status.subscriber_count >= 0
    end
    
    test "returns error when watcher not found" do
      assert {:error, :not_found} = FileWatcher.get_status("non_existent")
    end
  end
  
  describe "subscription" do
    test "can subscribe and unsubscribe", %{test_dir: test_dir} do
      # Start watcher
      opts = %{root_path: test_dir}
      assert {:ok, _pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      # Subscribe
      assert :ok = FileWatcher.subscribe(@test_project_id)
      
      # Create a file
      File.write!(Path.join(test_dir, "sub_test.txt"), "content")
      
      # Should receive event
      assert_receive %{event: :file_changed}, 200
      
      # Unsubscribe
      assert :ok = FileWatcher.unsubscribe(@test_project_id)
      
      # Create another file
      File.write!(Path.join(test_dir, "sub_test_2.txt"), "content")
      
      # Should not receive event
      refute_receive %{event: :file_changed}, 200
    end
  end
  
  describe "error handling" do
    test "handles file system watcher crash", %{test_dir: test_dir} do
      # Start watcher
      opts = %{root_path: test_dir}
      assert {:ok, watcher_pid} = FWSupervisor.start_watcher(@test_project_id, opts)
      
      # Get the file system watcher pid
      {:ok, %{watcher_pid: fs_pid}} = :sys.get_state(watcher_pid)
      
      # Subscribe
      FileWatcher.subscribe(@test_project_id)
      
      # Kill the file system watcher
      Process.exit(fs_pid, :kill)
      
      # Give it time to restart
      Process.sleep(100)
      
      # Should still be able to detect events
      File.write!(Path.join(test_dir, "after_crash.txt"), "content")
      
      assert_receive %{event: :file_changed}, 200
    end
  end
end