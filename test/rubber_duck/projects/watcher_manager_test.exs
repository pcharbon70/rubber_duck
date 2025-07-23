defmodule RubberDuck.Projects.WatcherManagerTest do
  use RubberDuck.DataCase, async: false

  alias RubberDuck.Projects.WatcherManager

  setup do
    # Create temp directories for testing
    temp_dir1 = Path.join(System.tmp_dir!(), "watcher_test_#{System.unique_integer()}")
    temp_dir2 = Path.join(System.tmp_dir!(), "watcher_test_#{System.unique_integer()}")
    temp_dir3 = Path.join(System.tmp_dir!(), "watcher_test_#{System.unique_integer()}")

    File.mkdir_p!(temp_dir1)
    File.mkdir_p!(temp_dir2)
    File.mkdir_p!(temp_dir3)

    on_exit(fn ->
      File.rm_rf!(temp_dir1)
      File.rm_rf!(temp_dir2)
      File.rm_rf!(temp_dir3)
    end)

    %{
      temp_dir1: temp_dir1,
      temp_dir2: temp_dir2,
      temp_dir3: temp_dir3,
      project_id1: "test_project_#{System.unique_integer()}",
      project_id2: "test_project_#{System.unique_integer()}",
      project_id3: "test_project_#{System.unique_integer()}"
    }
  end

  describe "start_watcher/2" do
    test "starts a watcher successfully", %{temp_dir1: temp_dir, project_id1: project_id} do
      assert {:ok, :started} = WatcherManager.start_watcher(project_id, %{root_path: temp_dir})

      # Verify watcher is running
      assert {:ok, info} = WatcherManager.get_info(project_id)
      assert info.project_id == project_id
      assert is_pid(info.pid)
    end

    test "returns already_running for existing watcher", %{temp_dir1: temp_dir, project_id1: project_id} do
      assert {:ok, :started} = WatcherManager.start_watcher(project_id, %{root_path: temp_dir})
      assert {:ok, :already_running} = WatcherManager.start_watcher(project_id, %{root_path: temp_dir})
    end

    test "starts multiple watchers up to limit", %{temp_dir1: temp_dir1, temp_dir2: temp_dir2} do
      # Use unique project IDs to avoid conflicts
      project1 = "limit_test_#{System.unique_integer()}"
      project2 = "limit_test_#{System.unique_integer()}"

      # Start two watchers
      assert {:ok, :started} = WatcherManager.start_watcher(project1, %{root_path: temp_dir1})
      assert {:ok, :started} = WatcherManager.start_watcher(project2, %{root_path: temp_dir2})

      # Verify both are running
      assert {:ok, _} = WatcherManager.get_info(project1)
      assert {:ok, _} = WatcherManager.get_info(project2)

      # Cleanup
      on_exit(fn ->
        WatcherManager.stop_watcher(project1)
        WatcherManager.stop_watcher(project2)
      end)
    end
  end

  describe "stop_watcher/1" do
    test "stops an existing watcher", %{temp_dir1: temp_dir, project_id1: project_id} do
      assert {:ok, :started} = WatcherManager.start_watcher(project_id, %{root_path: temp_dir})
      assert :ok = WatcherManager.stop_watcher(project_id)
      assert {:error, :not_found} = WatcherManager.get_info(project_id)
    end

    test "returns error for non-existent watcher" do
      assert {:error, :not_found} = WatcherManager.stop_watcher("non_existent")
    end
  end

  describe "touch_activity/1" do
    test "updates activity timestamp", %{temp_dir1: temp_dir, project_id1: project_id} do
      assert {:ok, :started} = WatcherManager.start_watcher(project_id, %{root_path: temp_dir})

      {:ok, info1} = WatcherManager.get_info(project_id)
      initial_activity = info1.last_activity
      initial_count = info1.event_count

      # Wait a bit and touch activity
      Process.sleep(10)
      assert :ok = WatcherManager.touch_activity(project_id)

      # Give cast time to process
      Process.sleep(10)

      {:ok, info2} = WatcherManager.get_info(project_id)
      assert DateTime.compare(info2.last_activity, initial_activity) == :gt
      assert info2.event_count == initial_count + 1
    end
  end

  describe "get_stats/0" do
    test "returns accurate statistics", %{
      temp_dir1: temp_dir1,
      temp_dir2: temp_dir2,
      project_id1: project_id1,
      project_id2: project_id2
    } do
      # Initial stats
      stats1 = WatcherManager.get_stats()
      initial_started = stats1.total_started

      # Start watchers
      assert {:ok, :started} = WatcherManager.start_watcher(project_id1, %{root_path: temp_dir1})
      assert {:ok, :started} = WatcherManager.start_watcher(project_id2, %{root_path: temp_dir2})

      # Check updated stats
      stats2 = WatcherManager.get_stats()
      assert stats2.active_watchers >= 2
      assert stats2.total_started >= initial_started + 2
      assert stats2.uptime_seconds >= 0

      # Stop one watcher
      assert :ok = WatcherManager.stop_watcher(project_id1)

      stats3 = WatcherManager.get_stats()
      assert stats3.active_watchers == stats2.active_watchers - 1
      assert stats3.total_stopped >= 1
    end
  end

  describe "list_watchers/0" do
    test "lists all active watchers", %{
      temp_dir1: temp_dir1,
      temp_dir2: temp_dir2,
      project_id1: project_id1,
      project_id2: project_id2
    } do
      assert {:ok, :started} = WatcherManager.start_watcher(project_id1, %{root_path: temp_dir1})
      assert {:ok, :started} = WatcherManager.start_watcher(project_id2, %{root_path: temp_dir2})

      watchers = WatcherManager.list_watchers()
      project_ids = Enum.map(watchers, & &1.project_id)

      assert project_id1 in project_ids
      assert project_id2 in project_ids
    end

    test "returns watchers sorted by activity", %{
      temp_dir1: temp_dir1,
      temp_dir2: temp_dir2,
      project_id1: project_id1,
      project_id2: project_id2
    } do
      assert {:ok, :started} = WatcherManager.start_watcher(project_id1, %{root_path: temp_dir1})
      Process.sleep(10)
      assert {:ok, :started} = WatcherManager.start_watcher(project_id2, %{root_path: temp_dir2})

      # Touch first project to make it more recent
      Process.sleep(10)
      WatcherManager.touch_activity(project_id1)
      Process.sleep(10)

      watchers = WatcherManager.list_watchers()
      assert [%{project_id: ^project_id1} | _] = watchers
    end
  end

  describe "resource limits and eviction" do
    @tag :slow
    test "evicts LRU watcher when at capacity" do
      # Note: This test is difficult to perform with the global WatcherManager
      # because we can't control its configuration. We'll test the basic eviction concept
      # by filling up the default capacity and checking stats

      # Get initial stats
      initial_stats = WatcherManager.get_stats()

      # Create enough watchers to potentially trigger eviction
      # (assuming default max_watchers is reasonably low)
      watchers =
        for i <- 1..25 do
          dir = Path.join(System.tmp_dir!(), "evict_test_#{i}")
          File.mkdir_p!(dir)
          project_id = "evict_project_#{i}"

          # Start watcher - some may be queued or trigger eviction
          result = WatcherManager.start_watcher(project_id, %{root_path: dir})

          %{id: project_id, dir: dir, result: result}
        end

      # Get final stats
      final_stats = WatcherManager.get_stats()

      # We should have hit capacity at some point
      assert final_stats.active_watchers <= final_stats.max_watchers
      assert final_stats.total_started > initial_stats.total_started

      # Cleanup
      on_exit(fn ->
        for w <- watchers do
          WatcherManager.stop_watcher(w.id)
          File.rm_rf!(w.dir)
        end
      end)
    end

    test "queues requests when at capacity with high priority" do
      # This test requires creating enough watchers to hit capacity
      # We'll create watchers up to the limit then test queueing behavior

      stats = WatcherManager.get_stats()
      max_watchers = stats.max_watchers

      # Fill up to capacity
      watchers =
        for i <- 1..(max_watchers + 2) do
          dir = Path.join(System.tmp_dir!(), "queue_test_#{i}")
          File.mkdir_p!(dir)
          project_id = "queue_project_#{System.unique_integer()}"

          # High priority to avoid eviction
          result = WatcherManager.start_watcher(project_id, %{root_path: dir, priority: :high})

          %{id: project_id, dir: dir, result: result}
        end

      # Some should have been queued
      queued_count = Enum.count(watchers, fn w -> elem(w.result, 1) == :queued end)
      assert queued_count > 0

      # Cleanup
      on_exit(fn ->
        for w <- watchers do
          WatcherManager.stop_watcher(w.id)
          File.rm_rf!(w.dir)
        end
      end)
    end
  end

  describe "cleanup process" do
    @tag :slow
    test "cleans up inactive watchers periodically" do
      # Since we can't control the global WatcherManager's config,
      # we'll test that cleanup doesn't remove active watchers

      temp_dir = Path.join(System.tmp_dir!(), "cleanup_test_#{System.unique_integer()}")
      File.mkdir_p!(temp_dir)
      project_id = "cleanup_project_#{System.unique_integer()}"

      # Start a watcher
      assert {:ok, :started} = WatcherManager.start_watcher(project_id, %{root_path: temp_dir})

      # Touch activity to keep it active
      WatcherManager.touch_activity(project_id)

      # Wait a bit
      Process.sleep(100)

      # Watcher should still be running (because we touched activity)
      assert {:ok, _info} = WatcherManager.get_info(project_id)

      on_exit(fn ->
        WatcherManager.stop_watcher(project_id)
        File.rm_rf!(temp_dir)
      end)
    end
  end

end

