defmodule RubberDuck.Projects.FileWatcherIntegrationTest do
  use RubberDuck.DataCase, async: false

  alias RubberDuck.Projects.{WatcherManager, FileWatcher}
  alias Phoenix.PubSub

  @pubsub RubberDuck.PubSub

  setup do
    # Create temp directory for testing
    temp_dir = Path.join(System.tmp_dir!(), "integration_test_#{System.unique_integer()}")
    File.mkdir_p!(temp_dir)

    project_id = "integration_project_#{System.unique_integer()}"

    on_exit(fn ->
      File.rm_rf!(temp_dir)
      WatcherManager.stop_watcher(project_id)
    end)

    %{temp_dir: temp_dir, project_id: project_id}
  end

  describe "file watcher through manager" do
    @tag :integration
    test "receives file change events through PubSub", %{temp_dir: temp_dir, project_id: project_id} do
      # Subscribe to file watcher topic
      topic = "file_watcher:#{project_id}"
      PubSub.subscribe(@pubsub, topic)

      # Start watcher through manager
      assert {:ok, :started} =
               WatcherManager.start_watcher(project_id, %{
                 root_path: temp_dir,
                 debounce_ms: 50,
                 batch_size: 10
               })

      # Create a file
      test_file = Path.join(temp_dir, "test.txt")
      File.write!(test_file, "Hello World")

      # Should receive file change event
      assert_receive %{
                       event: :file_changed,
                       project_id: ^project_id,
                       changes: changes,
                       batch_size: _
                     },
                     1000

      assert length(changes) > 0
      change = hd(changes)
      assert change.path == test_file
      assert change.event in [:created, :modified]
    end

    @tag :integration
    test "activity tracking updates on file events", %{temp_dir: temp_dir, project_id: project_id} do
      # Start watcher
      assert {:ok, :started} =
               WatcherManager.start_watcher(project_id, %{
                 root_path: temp_dir,
                 debounce_ms: 50
               })

      # Get initial info
      {:ok, initial_info} = WatcherManager.get_info(project_id)

      # Subscribe to events
      topic = "file_watcher:#{project_id}"
      PubSub.subscribe(@pubsub, topic)

      # Create multiple files
      for i <- 1..3 do
        File.write!(Path.join(temp_dir, "file_#{i}.txt"), "Content #{i}")
        # Ensure debounce
        Process.sleep(60)
      end

      # Wait for events
      Process.sleep(200)

      # Check activity was updated
      {:ok, updated_info} = WatcherManager.get_info(project_id)
      assert DateTime.compare(updated_info.last_activity, initial_info.last_activity) == :gt
      assert updated_info.event_count > initial_info.event_count
    end

    @tag :integration
    test "multiple projects can be watched simultaneously", %{temp_dir: _} do
      # Create multiple project directories
      projects =
        for i <- 1..3 do
          dir = Path.join(System.tmp_dir!(), "multi_project_#{i}")
          File.mkdir_p!(dir)

          project_id = "multi_project_#{i}"

          # Start watcher
          assert {:ok, :started} =
                   WatcherManager.start_watcher(project_id, %{
                     root_path: dir,
                     debounce_ms: 50
                   })

          # Subscribe to events
          PubSub.subscribe(@pubsub, "file_watcher:#{project_id}")

          %{id: project_id, dir: dir}
        end

      # Create files in each project
      for project <- projects do
        File.write!(Path.join(project.dir, "test.txt"), "Project #{project.id}")
      end

      # Should receive events for each project
      for project <- projects do
        assert_receive %{
                         event: :file_changed,
                         project_id: project_id,
                         changes: _
                       },
                       1000

        assert project_id == project.id
      end

      # Cleanup
      on_exit(fn ->
        for project <- projects do
          WatcherManager.stop_watcher(project.id)
          File.rm_rf!(project.dir)
        end
      end)
    end

    @tag :integration
    test "handles watcher crashes gracefully", %{temp_dir: temp_dir, project_id: project_id} do
      # Start watcher
      assert {:ok, :started} =
               WatcherManager.start_watcher(project_id, %{
                 root_path: temp_dir
               })

      # Get watcher pid
      {:ok, info} = WatcherManager.get_info(project_id)
      watcher_pid = info.pid

      # Kill the watcher process
      Process.exit(watcher_pid, :kill)

      # Wait for supervisor to notice
      Process.sleep(100)

      # Watcher should be removed from manager
      assert {:error, :not_found} = WatcherManager.get_info(project_id)

      # Should be able to start new watcher
      assert {:ok, :started} =
               WatcherManager.start_watcher(project_id, %{
                 root_path: temp_dir
               })
    end
  end

  describe "resource limit scenarios" do
    @tag :integration
    @tag :slow
    test "handles resource exhaustion gracefully" do
      # Create manager with very low limits
      {:ok, manager} =
        WatcherManager.start_link(
          max_watchers: 2,
          queue_timeout_ms: 500
        )

      # Create directories
      dirs =
        for i <- 1..4 do
          dir = Path.join(System.tmp_dir!(), "resource_test_#{i}")
          File.mkdir_p!(dir)
          {i, dir}
        end

      # Start watchers up to limit
      assert {:ok, :started} =
               GenServer.call(manager, {:start_watcher, "resource_1", %{root_path: elem(Enum.at(dirs, 0), 1)}})

      assert {:ok, :started} =
               GenServer.call(manager, {:start_watcher, "resource_2", %{root_path: elem(Enum.at(dirs, 1), 1)}})

      # Next ones should queue or evict
      task3 =
        Task.async(fn ->
          GenServer.call(manager, {:start_watcher, "resource_3", %{root_path: elem(Enum.at(dirs, 2), 1)}}, 1000)
        end)

      task4 =
        Task.async(fn ->
          GenServer.call(
            manager,
            {:start_watcher, "resource_4", %{root_path: elem(Enum.at(dirs, 3), 1), priority: :high}},
            1000
          )
        end)

      # Let them queue
      Process.sleep(100)

      # Check queue length
      stats = GenServer.call(manager, :get_stats)
      assert stats.queued_requests > 0

      # Stop one to allow queued to start
      GenServer.call(manager, {:stop_watcher, "resource_1"})

      # One of the tasks should complete
      results = [Task.await(task3, 1000), Task.await(task4, 1000)]
      assert Enum.any?(results, &match?({:ok, :started}, &1))

      on_exit(fn ->
        for {_, dir} <- dirs, do: File.rm_rf!(dir)
        GenServer.stop(manager)
      end)
    end
  end

  describe "telemetry events" do
    @tag :integration
    test "emits telemetry events for watcher lifecycle", %{temp_dir: temp_dir, project_id: project_id} do
      # Attach telemetry handler
      handler_id = "test_handler_#{System.unique_integer()}"
      test_pid = self()

      :telemetry.attach_many(
        handler_id,
        [
          [:rubber_duck, :watcher_manager, :watcher_started],
          [:rubber_duck, :watcher_manager, :watcher_stopped],
          [:rubber_duck, :watcher_manager, :request_queued]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      # Start watcher
      assert {:ok, :started} = WatcherManager.start_watcher(project_id, %{root_path: temp_dir})

      # Should receive start event
      assert_receive {:telemetry_event, [:rubber_duck, :watcher_manager, :watcher_started], %{count: 1},
                      %{project_id: ^project_id}},
                     500

      # Stop watcher
      assert :ok = WatcherManager.stop_watcher(project_id)

      # Should receive stop event
      assert_receive {:telemetry_event, [:rubber_duck, :watcher_manager, :watcher_stopped], %{count: 1},
                      %{project_id: ^project_id, reason: :manual}},
                     500

      # Cleanup
      :telemetry.detach(handler_id)
    end
  end
end

