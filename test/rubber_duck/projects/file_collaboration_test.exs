defmodule RubberDuck.Projects.FileCollaborationTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.Projects.{FileCollaboration, CollaborationSupervisor, FileManager}
  alias RubberDuck.AccountsFixtures
  alias RubberDuck.WorkspaceFixtures
  
  setup do
    user1 = AccountsFixtures.user_fixture()
    user2 = AccountsFixtures.user_fixture()
    project = WorkspaceFixtures.project_fixture(%{owner: user1})
    
    # Create a test project directory
    project_dir = Path.join(System.tmp_dir!(), "collab_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(project_dir)
    
    # Update project with test directory
    {:ok, project} = Ash.update(project, %{root_path: project_dir}, action: :update, actor: user1)
    
    # Create FileManager instances
    fm1 = FileManager.new(project, user1)
    fm2 = FileManager.new(project, user2)
    
    # Start collaboration
    {:ok, _pid} = CollaborationSupervisor.start_collaboration(project.id)
    
    on_exit(fn -> 
      File.rm_rf!(project_dir)
      CollaborationSupervisor.stop_collaboration(project.id)
    end)
    
    %{
      project: project,
      user1: user1,
      user2: user2,
      fm1: fm1,
      fm2: fm2,
      project_dir: project_dir
    }
  end
  
  describe "file locking" do
    test "acquires exclusive lock on file", %{project: project, fm1: fm1} do
      assert {:ok, lock_id} = FileCollaboration.acquire_lock(project.id, fm1, "test.txt")
      assert is_binary(lock_id)
      assert String.starts_with?(lock_id, "lock_")
    end
    
    test "prevents multiple exclusive locks on same file", %{project: project, fm1: fm1, fm2: fm2} do
      assert {:ok, _lock_id} = FileCollaboration.acquire_lock(project.id, fm1, "test.txt")
      assert {:error, :locked} = FileCollaboration.acquire_lock(project.id, fm2, "test.txt")
    end
    
    test "allows multiple shared locks on same file", %{project: project, fm1: fm1, fm2: fm2} do
      opts = [type: :shared]
      assert {:ok, _lock_id1} = FileCollaboration.acquire_lock(project.id, fm1, "test.txt", opts)
      assert {:ok, _lock_id2} = FileCollaboration.acquire_lock(project.id, fm2, "test.txt", opts)
    end
    
    test "releases lock", %{project: project, fm1: fm1, fm2: fm2} do
      assert {:ok, lock_id} = FileCollaboration.acquire_lock(project.id, fm1, "test.txt")
      assert :ok = FileCollaboration.release_lock(project.id, lock_id)
      
      # Now another user can acquire the lock
      assert {:ok, _lock_id2} = FileCollaboration.acquire_lock(project.id, fm2, "test.txt")
    end
    
    test "checks if file is locked", %{project: project, fm1: fm1} do
      assert not FileCollaboration.locked?(project.id, "test.txt")
      
      assert {:ok, _lock_id} = FileCollaboration.acquire_lock(project.id, fm1, "test.txt")
      assert FileCollaboration.locked?(project.id, "test.txt")
    end
    
    test "gets lock information", %{project: project, fm1: fm1, user1: user1} do
      assert {:ok, lock_id} = FileCollaboration.acquire_lock(project.id, fm1, "test.txt")
      
      assert {:ok, lock} = FileCollaboration.get_lock(project.id, "test.txt")
      assert lock.id == lock_id
      assert lock.file_path == "test.txt"
      assert lock.user_id == user1.id
      assert lock.type == :exclusive
    end
    
    test "lists all active locks", %{project: project, fm1: fm1} do
      assert {:ok, []} = FileCollaboration.list_locks(project.id)
      
      assert {:ok, _lock1} = FileCollaboration.acquire_lock(project.id, fm1, "file1.txt")
      assert {:ok, _lock2} = FileCollaboration.acquire_lock(project.id, fm1, "file2.txt")
      
      assert {:ok, locks} = FileCollaboration.list_locks(project.id)
      assert length(locks) == 2
      
      file_paths = Enum.map(locks, & &1.file_path) |> Enum.sort()
      assert file_paths == ["file1.txt", "file2.txt"]
    end
    
    test "lock expires after timeout", %{project: project, fm1: fm1} do
      # Acquire lock with very short timeout
      assert {:ok, _lock_id} = FileCollaboration.acquire_lock(
        project.id, fm1, "test.txt", timeout: 100
      )
      
      assert FileCollaboration.locked?(project.id, "test.txt")
      
      # Wait for expiration and cleanup
      Process.sleep(150)
      # Get the process via Registry lookup
      [{pid, _}] = Registry.lookup(RubberDuck.CollaborationRegistry, project.id)
      send(pid, :cleanup_expired)
      
      # Lock should be expired now
      assert not FileCollaboration.locked?(project.id, "test.txt")
    end
  end
  
  describe "presence tracking" do
    test "tracks user presence on file", %{project: project, fm1: fm1, user1: user1} do
      metadata = %{cursor_position: {10, 5}, selection: nil}
      assert :ok = FileCollaboration.track_presence(project.id, fm1, "test.txt", metadata)
      
      assert {:ok, presence_list} = FileCollaboration.get_file_presence(project.id, "test.txt")
      assert length(presence_list) == 1
      
      [presence] = presence_list
      assert presence.user_id == user1.id
      assert presence.file_path == "test.txt"
      assert presence.cursor_position == {10, 5}
    end
    
    test "tracks multiple users on same file", %{project: project, fm1: fm1, fm2: fm2} do
      assert :ok = FileCollaboration.track_presence(project.id, fm1, "test.txt", %{})
      assert :ok = FileCollaboration.track_presence(project.id, fm2, "test.txt", %{})
      
      assert {:ok, presence_list} = FileCollaboration.get_file_presence(project.id, "test.txt")
      assert length(presence_list) == 2
    end
    
    test "updates presence for same user", %{project: project, fm1: fm1} do
      # First position
      assert :ok = FileCollaboration.track_presence(
        project.id, fm1, "test.txt", %{cursor_position: {1, 1}}
      )
      
      # Update position
      assert :ok = FileCollaboration.track_presence(
        project.id, fm1, "test.txt", %{cursor_position: {5, 10}}
      )
      
      assert {:ok, [presence]} = FileCollaboration.get_file_presence(project.id, "test.txt")
      assert presence.cursor_position == {5, 10}
    end
  end
  
  describe "change broadcasting" do
    test "broadcasts file changes", %{project: project, fm1: fm1} do
      # Subscribe to file events
      assert :ok = FileCollaboration.subscribe_to_file(project.id, "test.txt")
      
      # Broadcast a change
      change_data = %{
        type: :content_update,
        line: 5,
        content: "Updated line"
      }
      
      FileCollaboration.broadcast_change(project.id, fm1, "test.txt", change_data)
      
      # Should receive the event
      assert_receive {:file_event, event}
      assert event.type == :file_changed
      assert event.file_path == "test.txt"
      assert event.change == change_data
    end
    
    test "broadcasts lock events", %{project: project, fm1: fm1} do
      # Subscribe to file events
      assert :ok = FileCollaboration.subscribe_to_file(project.id, "test.txt")
      
      # Acquire lock
      assert {:ok, lock_id} = FileCollaboration.acquire_lock(project.id, fm1, "test.txt")
      
      # Should receive lock acquired event
      assert_receive {:lock_event, %{type: :lock_acquired}}
      
      # Release lock
      assert :ok = FileCollaboration.release_lock(project.id, lock_id)
      
      # Should receive lock released event
      assert_receive {:lock_event, %{type: :lock_released}}
    end
  end
  
  describe "activity recording" do
    test "records collaborative activities", %{project: project, fm1: fm1} do
      # Subscribe to project events
      assert :ok = FileCollaboration.subscribe_to_project(project.id)
      
      # Record an activity
      FileCollaboration.record_activity(
        project.id, fm1, "test.txt", :edit_started, %{line: 10}
      )
      
      # Should receive activity event
      assert_receive {:activity, activity}
      assert activity.action == :edit_started
      assert activity.file_path == "test.txt"
      assert activity.metadata.line == 10
    end
  end
  
  describe "FileManager integration" do
    setup %{fm1: fm1} do
      # Create a test file
      assert {:ok, _} = FileManager.write_file(fm1, "test.txt", "Initial content")
      :ok
    end
    
    test "acquire_lock through FileManager", %{fm1: fm1} do
      assert {:ok, lock_id} = FileManager.acquire_lock(fm1, "test.txt")
      assert is_binary(lock_id)
      
      assert :ok = FileManager.release_lock(fm1, lock_id)
    end
    
    test "track_presence through FileManager", %{fm1: fm1} do
      assert :ok = FileManager.track_presence(fm1, "test.txt", %{cursor_position: {1, 1}})
      
      assert {:ok, collaborators} = FileManager.get_collaborators(fm1, "test.txt")
      assert length(collaborators) == 1
    end
  end
  
  describe "collaboration lifecycle" do
    test "starts and stops collaboration sessions", %{project: project} do
      # First verify it's running from setup
      assert CollaborationSupervisor.collaboration_running?(project.id)
      
      # Stop existing collaboration
      CollaborationSupervisor.stop_collaboration(project.id)
      
      # Small delay to ensure process cleanup
      Process.sleep(100)
      
      assert not CollaborationSupervisor.collaboration_running?(project.id)
      
      # Start collaboration
      assert {:ok, _pid} = CollaborationSupervisor.start_collaboration(project.id)
      assert CollaborationSupervisor.collaboration_running?(project.id)
      
      # Stop collaboration
      assert :ok = CollaborationSupervisor.stop_collaboration(project.id)
      
      # Small delay to ensure process cleanup
      Process.sleep(100)
      
      assert not CollaborationSupervisor.collaboration_running?(project.id)
    end
    
    test "lists active collaboration sessions" do
      sessions = CollaborationSupervisor.list_active_sessions()
      assert is_list(sessions)
      
      # Should have at least one active session
      assert length(sessions) > 0
    end
  end
end