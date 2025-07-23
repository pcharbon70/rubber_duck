defmodule RubberDuckWeb.Integration.PerformanceLargeFilesTest do
  @moduledoc """
  Integration tests for performance with large files.

  Tests the LiveView's ability to handle large codebases,
  big files, and maintain responsiveness under load.
  """

  use RubberDuckWeb.ConnCase

  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures

  @moduletag :integration
  @moduletag :performance

  setup do
    user = user_fixture()

    project = %{
      id: "perf-test-#{System.unique_integer()}",
      name: "Performance Test Project"
    }

    %{user: user, project: project}
  end

  describe "large file handling" do
    test "loads large files efficiently", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Generate a large file (1MB)
      large_content = generate_large_file(1_000_000)

      start_time = System.monotonic_time(:millisecond)

      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/large_file.ex",
           content: large_content
         }}
      )

      :timer.sleep(100)

      end_time = System.monotonic_time(:millisecond)
      load_time = end_time - start_time

      # Should load within reasonable time
      # Less than 2 seconds
      assert load_time < 2000

      # Should virtualize rendering
      html = render(view)
      assert html =~ "virtual-scroll" or html =~ "viewport"

      # Not all content should be in DOM
      refute String.length(html) > String.length(large_content)
    end

    test "implements syntax highlighting efficiently", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Large file with complex syntax
      # 10k lines
      large_code = generate_complex_code(10_000)

      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/complex.ex",
           content: large_code
         }}
      )

      :timer.sleep(200)

      # Should use incremental highlighting
      assert view.assigns.highlighting_mode == :incremental

      # Only visible portion should be highlighted initially
      html = render(view)
      highlighted_lines = Regex.scan(~r/class="syntax-/, html) |> length()
      # Only viewport is highlighted
      assert highlighted_lines < 100

      # Scroll triggers more highlighting
      send(view.pid, {:viewport_scroll, %{top: 5000, bottom: 5100}})
      :timer.sleep(100)

      assert view.assigns.highlighted_ranges[{5000, 5100}] == true
    end

    test "handles multiple large files", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Open several large files
      for i <- 1..5 do
        # 500KB each
        content = generate_large_file(500_000)

        send(
          view.pid,
          {:file_selected,
           %{
             path: "lib/file_#{i}.ex",
             content: content
           }}
        )

        :timer.sleep(100)
      end

      # Check memory usage
      memory_info = view.assigns.memory_usage
      # Should not exceed 100MB
      assert memory_info.total_mb < 100

      # Should implement tab limits
      assert length(view.assigns.open_files) <= 10

      # LRU eviction for unopened tabs
      if length(view.assigns.open_files) == 10 do
        assert view.assigns.evicted_files != []
      end
    end
  end

  describe "search and navigation performance" do
    test "searches large files quickly", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Large file with patterns
      content = generate_searchable_content(50_000)

      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/searchable.ex",
           content: content
         }}
      )

      :timer.sleep(100)

      # Search performance
      start_time = System.monotonic_time(:millisecond)

      view
      |> element("input.search")
      |> render_change(%{"query" => "pattern_42"})

      :timer.sleep(50)

      end_time = System.monotonic_time(:millisecond)
      search_time = end_time - start_time

      # Should be fast
      # Less than 500ms
      assert search_time < 500

      # Should find results
      assert length(view.assigns.search_results) > 0
      assert view.assigns.search_results |> hd() |> Map.get(:line) == 4200
    end

    test "go to line performance", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Very large file
      content = generate_numbered_lines(100_000)

      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/huge.ex",
           content: content
         }}
      )

      # Go to line near end
      start_time = System.monotonic_time(:millisecond)

      view
      |> element("body")
      |> render_keydown(%{"key" => "g", "ctrlKey" => true})

      view
      |> element("input.goto-line")
      |> render_change(%{"value" => "95000"})

      view
      |> element("input.goto-line")
      |> render_keydown(%{"key" => "Enter"})

      end_time = System.monotonic_time(:millisecond)
      jump_time = end_time - start_time

      # Should jump instantly
      # Less than 200ms
      assert jump_time < 200
      assert view.assigns.editor_state.viewport.top_line >= 94950
      assert view.assigns.editor_state.viewport.top_line <= 95050
    end
  end

  describe "editing performance" do
    test "handles rapid typing in large files", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Large file
      content = generate_large_file(500_000)

      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/editable.ex",
           content: content
         }}
      )

      # Simulate rapid typing
      typing_events = for char <- String.codepoints("Hello world this is a test"), do: char

      start_time = System.monotonic_time(:millisecond)

      for char <- typing_events do
        send(view.pid, {:editor_keypress, %{key: char}})
        # 100 WPM typing speed
        :timer.sleep(10)
      end

      end_time = System.monotonic_time(:millisecond)

      # Should not lag
      assert view.assigns.pending_keystrokes == []

      # Debounced updates
      assert view.assigns.update_scheduled == true
      # Wait for debounce
      :timer.sleep(300)

      # Content should be updated
      assert view.assigns.current_file.content =~ "Hello world this is a test"
    end

    test "efficient undo/redo for large changes", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      original_content = generate_large_file(100_000)

      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/undo_test.ex",
           content: original_content
         }}
      )

      # Make large change (select all and delete)
      send(view.pid, {:select_all})
      send(view.pid, {:delete_selection})

      # Should use efficient diff storage
      undo_entry = hd(view.assigns.undo_stack)
      assert undo_entry.type == :delete_range
      # Stores range, not content
      assert undo_entry.size < 1000

      # Undo performance
      start_time = System.monotonic_time(:millisecond)

      view
      |> element("body")
      |> render_keydown(%{"key" => "z", "ctrlKey" => true})

      end_time = System.monotonic_time(:millisecond)
      undo_time = end_time - start_time

      # Near instant
      assert undo_time < 100
      assert view.assigns.current_file.content == original_content
    end
  end

  describe "collaborative editing performance" do
    test "handles multiple users editing large files", %{conn: conn, project: project} do
      # Create multiple users
      users = for i <- 1..5, do: user_fixture(%{username: "user#{i}"})

      # Large shared file
      content = generate_large_file(200_000)

      # All users connect
      views =
        for user <- users do
          conn = log_in_user(conn, user)
          {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

          send(
            view.pid,
            {:file_selected,
             %{
               path: "lib/shared.ex",
               content: content
             }}
          )

          view
        end

      # Start collaboration
      for view <- views do
        view
        |> element("button[phx-click=\"start_collaboration\"]")
        |> render_click()
      end

      :timer.sleep(200)

      # Concurrent edits at different positions
      for {view, i} <- Enum.with_index(views) do
        # Spread out edits
        position = i * 10000

        send(
          view.pid,
          {:editor_operation,
           %{
             type: :insert,
             position: position,
             content: "/* User #{i} edit */\n"
           }}
        )
      end

      :timer.sleep(500)

      # All edits should be applied
      for view <- views do
        content = view.assigns.current_file.content

        for i <- 0..4 do
          assert content =~ "User #{i} edit"
        end
      end

      # Should not have performance degradation
      for view <- views do
        # ms
        assert view.assigns.collaboration_lag < 100
      end
    end
  end

  describe "file tree performance" do
    test "handles large directory structures", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Generate large file tree
      # 10k files
      file_tree = generate_file_tree(10_000)

      send(view.pid, {:file_tree_loaded, file_tree})
      :timer.sleep(200)

      # Should virtualize tree rendering
      html = render(view)
      visible_nodes = Regex.scan(~r/class="tree-node"/, html) |> length()
      # Only visible portion rendered
      assert visible_nodes < 100

      # Expand performance
      start_time = System.monotonic_time(:millisecond)

      view
      |> element(".tree-node[data-path=\"lib\"] .expand-icon")
      |> render_click()

      end_time = System.monotonic_time(:millisecond)
      expand_time = end_time - start_time

      # Fast expansion
      assert expand_time < 200

      # Search in file tree
      view
      |> element("input.tree-search")
      |> render_change(%{"value" => "specific_file"})

      :timer.sleep(100)

      # Should filter efficiently
      assert length(view.assigns.filtered_tree_nodes) < 50
    end
  end

  describe "memory management" do
    test "implements memory limits and cleanup", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Track initial memory
      initial_memory = :erlang.memory(:total)

      # Open many large files
      for i <- 1..20 do
        # 1MB each
        content = generate_large_file(1_000_000)

        send(
          view.pid,
          {:file_selected,
           %{
             path: "lib/memory_test_#{i}.ex",
             content: content
           }}
        )

        :timer.sleep(50)
      end

      # Check memory growth
      current_memory = :erlang.memory(:total)
      memory_growth_mb = (current_memory - initial_memory) / 1_024 / 1_024

      # Should not grow linearly with file size
      # Less than 50MB for 20MB of files
      assert memory_growth_mb < 50

      # Should trigger cleanup
      assert view.assigns.memory_cleanup_triggered == true
      assert length(view.assigns.cached_files) < 10

      # Force garbage collection
      send(view.pid, :force_cleanup)
      :timer.sleep(100)

      # Memory should be reclaimed
      after_gc_memory = :erlang.memory(:total)
      assert after_gc_memory < current_memory
    end

    test "warns about memory pressure", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Simulate high memory usage
      send(
        view.pid,
        {:memory_stats,
         %{
           used_mb: 450,
           limit_mb: 500,
           percentage: 90
         }}
      )

      html = render(view)
      assert html =~ "High memory usage" or html =~ "90%"
      assert html =~ "Some features may be limited"

      # Should disable memory-intensive features
      assert view.assigns.features_limited == true
      assert view.assigns.syntax_highlighting_enabled == false
      # Reduced from default
      assert view.assigns.max_file_size_mb == 5
    end
  end

  describe "rendering optimizations" do
    test "uses efficient diff updates", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Large file with many elements
      content = generate_html_heavy_content(1000)

      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/heavy.ex",
           content: content
         }}
      )

      :timer.sleep(100)

      # Make small change
      initial_render = render(view)

      send(
        view.pid,
        {:editor_operation,
         %{
           type: :insert,
           position: 100,
           content: "X"
         }}
      )

      :timer.sleep(50)

      # Track diff size
      send(view.pid, :get_last_diff_stats)
      assert_receive {:diff_stats, stats}

      # Diff should be small
      assert stats.changed_elements < 10
      assert stats.diff_size_bytes < 1000
    end

    test "throttles updates during heavy activity", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Rapid updates
      for i <- 1..100 do
        send(view.pid, {:cursor_position, %{line: i, column: 1}})
        :timer.sleep(5)
      end

      # Should batch updates
      assert view.assigns.update_queue != []
      assert view.assigns.throttle_active == true

      # Wait for throttle period
      :timer.sleep(100)

      # Should have processed in batches
      assert view.assigns.updates_processed < 100
      assert view.assigns.updates_batched > 50
    end
  end

  # Helper functions

  defp generate_large_file(size_bytes) do
    # Approximately 80 chars per line
    lines = div(size_bytes, 80)

    for i <- 1..lines do
      "defmodule Module#{i} do\n  def function#{i}, do: :ok\nend\n"
    end
    |> Enum.join("\n")
  end

  defp generate_complex_code(lines) do
    for i <- 1..lines do
      case rem(i, 10) do
        0 -> "defmodule Module#{i} do"
        1 -> "  @moduledoc \"Documentation for module #{i}\""
        2 -> "  use GenServer"
        3 -> "  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)"
        4 -> "  @impl true"
        5 -> "  def init(state), do: {:ok, state}"
        6 -> "  def handle_call(:get, _from, state), do: {:reply, state, state}"
        7 -> "  def handle_cast({:set, value}, _state), do: {:noreply, value}"
        8 -> "  defp private_function(x), do: x * 2"
        9 -> "end\n"
      end
    end
    |> Enum.join("\n")
  end

  defp generate_searchable_content(lines) do
    for i <- 1..lines do
      "# Line #{i}: pattern_#{div(i, 100)} - searchable content here\n"
    end
    |> Enum.join()
  end

  defp generate_numbered_lines(count) do
    for i <- 1..count do
      "#{String.pad_leading("#{i}", 6, "0")}: This is line number #{i}\n"
    end
    |> Enum.join()
  end

  defp generate_file_tree(file_count) do
    %{
      "lib" => %{
        type: :directory,
        children: generate_tree_structure(file_count, 4)
      },
      "test" => %{
        type: :directory,
        children: generate_tree_structure(div(file_count, 2), 3)
      },
      "config" => %{
        type: :directory,
        children: %{
          "config.exs" => %{type: :file},
          "dev.exs" => %{type: :file},
          "test.exs" => %{type: :file}
        }
      }
    }
  end

  defp generate_tree_structure(remaining, depth) when depth <= 0 or remaining <= 0 do
    %{}
  end

  defp generate_tree_structure(remaining, depth) do
    files_here = min(remaining, 10)
    subdirs = min(div(remaining - files_here, 10), 5)

    files =
      for i <- 1..files_here, into: %{} do
        {"file_#{i}.ex", %{type: :file}}
      end

    dirs =
      for i <- 1..subdirs, into: %{} do
        remaining_per_dir = div(remaining - files_here, subdirs)

        {"subdir_#{i}",
         %{
           type: :directory,
           children: generate_tree_structure(remaining_per_dir, depth - 1)
         }}
      end

    Map.merge(files, dirs)
  end

  defp generate_html_heavy_content(elements) do
    for i <- 1..elements do
      """
      <div class="line line-#{i}">
        <span class="line-number">#{i}</span>
        <span class="syntax-keyword">def</span>
        <span class="syntax-function">function_#{i}</span>
        <span class="syntax-punct">(</span>
        <span class="syntax-variable">arg</span>
        <span class="syntax-punct">)</span>
        <span class="syntax-keyword">do</span>
      </div>
      """
    end
    |> Enum.join("\n")
  end
end
