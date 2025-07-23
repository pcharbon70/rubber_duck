defmodule RubberDuckWeb.Integration.StatePersistenceTest do
  @moduledoc """
  Integration tests for state persistence across sessions.

  Tests the LiveView's ability to save and restore user state,
  preferences, and work progress across sessions.
  """

  use RubberDuckWeb.ConnCase

  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures
  alias Phoenix.PubSub

  @moduletag :integration

  setup do
    user = user_fixture()

    project = %{
      id: "persist-test-#{System.unique_integer()}",
      name: "Persistence Test Project"
    }

    %{user: user, project: project}
  end

  describe "session state persistence" do
    test "saves and restores basic session state", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)

      # First session - set up state
      {:ok, view1, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Open files
      send(
        view1.pid,
        {:file_selected,
         %{
           path: "lib/main.ex",
           content: "defmodule Main do\nend"
         }}
      )

      # Send messages
      view1
      |> form("form[phx-submit=\"send_message\"]", %{message: "Hello AI"})
      |> render_submit()

      view1
      |> form("form[phx-submit=\"send_message\"]", %{message: "Help with GenServer"})
      |> render_submit()

      # Toggle panels
      view1
      |> element("button[phx-value-panel=\"file_tree\"]")
      |> render_click()

      :timer.sleep(100)

      # Store state before leaving
      state_before = %{
        current_file: view1.assigns.current_file,
        chat_messages: view1.assigns.chat_messages,
        layout: view1.assigns.layout
      }

      # Leave session
      GenServer.stop(view1.pid, :normal)
      :timer.sleep(100)

      # New session - should restore state
      {:ok, view2, html} = live(conn, ~p"/projects/#{project.id}/session")
      :timer.sleep(100)

      # Verify state restored
      assert view2.assigns.current_file == state_before.current_file
      assert length(view2.assigns.chat_messages) == length(state_before.chat_messages)
      # Was toggled off
      assert view2.assigns.layout.show_file_tree == false

      # Verify UI reflects restored state
      assert html =~ "lib/main.ex"
      assert html =~ "Hello AI"
      assert html =~ "Help with GenServer"
    end

    test "persists editor cursor and scroll position", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view1, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Set editor state
      send(
        view1.pid,
        {:file_selected,
         %{
           path: "lib/long_file.ex",
           content: Enum.join(for i <- 1..100, do: "# Line #{i}\n")
         }}
      )

      send(
        view1.pid,
        {:editor_state_changed,
         %{
           cursor: %{line: 50, column: 10},
           scroll: %{top: 1200, left: 0},
           selection: %{
             start: %{line: 48, column: 0},
             end: %{line: 52, column: 15}
           }
         }}
      )

      :timer.sleep(100)

      # Close and reopen
      GenServer.stop(view1.pid, :normal)
      :timer.sleep(100)

      {:ok, view2, _html} = live(conn, ~p"/projects/#{project.id}/session")
      :timer.sleep(100)

      # Verify editor state restored
      assert view2.assigns.editor_state.cursor.line == 50
      assert view2.assigns.editor_state.cursor.column == 10
      assert view2.assigns.editor_state.scroll.top == 1200
      assert view2.assigns.editor_state.selection != nil
    end

    test "persists open files and tabs", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view1, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Open multiple files
      files = [
        %{path: "lib/app.ex", content: "defmodule App do\nend"},
        %{path: "lib/server.ex", content: "defmodule Server do\nend"},
        %{path: "test/app_test.exs", content: "defmodule AppTest do\nend"}
      ]

      for file <- files do
        send(view1.pid, {:file_selected, file})
        :timer.sleep(50)
      end

      # Set active tab
      send(view1.pid, {:tab_selected, "lib/server.ex"})

      # Close and reopen
      GenServer.stop(view1.pid, :normal)
      :timer.sleep(100)

      {:ok, view2, html} = live(conn, ~p"/projects/#{project.id}/session")
      :timer.sleep(100)

      # All tabs should be restored
      assert length(view2.assigns.open_files) == 3
      assert view2.assigns.active_tab == "lib/server.ex"

      # UI should show all tabs
      for file <- files do
        assert html =~ file.path
      end
    end
  end

  describe "user preferences persistence" do
    test "saves and restores user preferences", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view1, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Set preferences
      preferences = %{
        theme: "dark",
        font_size: 16,
        tab_size: 2,
        word_wrap: true,
        show_line_numbers: true,
        auto_save: true,
        ai_suggestions: true
      }

      for {key, value} <- preferences do
        view1
        |> element("button[phx-click=\"update_preference\"][phx-value-key=\"#{key}\"]")
        |> render_click(%{"value" => value})

        :timer.sleep(20)
      end

      # Close and reopen
      GenServer.stop(view1.pid, :normal)
      :timer.sleep(100)

      {:ok, view2, html} = live(conn, ~p"/projects/#{project.id}/session")

      # Verify preferences restored
      assert view2.assigns.preferences.theme == "dark"
      assert view2.assigns.preferences.font_size == 16
      assert view2.assigns.preferences.auto_save == true

      # UI should reflect preferences
      assert html =~ "dark-theme" or html =~ "theme-dark"
      assert html =~ "font-size-16" or html =~ "text-base"
    end

    test "persists panel layouts and sizes", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view1, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Resize panels
      send(
        view1.pid,
        {:panel_resized,
         %{
           panel: "file_tree",
           width: 300
         }}
      )

      send(
        view1.pid,
        {:panel_resized,
         %{
           panel: "chat",
           width: 400
         }}
      )

      send(
        view1.pid,
        {:panel_resized,
         %{
           panel: "terminal",
           height: 200
         }}
      )

      # Custom layout
      send(
        view1.pid,
        {:layout_changed,
         %{
           mode: "custom",
           panels: %{
             file_tree: %{visible: true, position: "left", size: 300},
             editor: %{visible: true, position: "center", size: "flex"},
             chat: %{visible: true, position: "right", size: 400},
             terminal: %{visible: true, position: "bottom", size: 200}
           }
         }}
      )

      :timer.sleep(100)

      # Close and reopen
      GenServer.stop(view1.pid, :normal)
      :timer.sleep(100)

      {:ok, view2, html} = live(conn, ~p"/projects/#{project.id}/session")

      # Verify layout restored
      assert view2.assigns.layout_mode == "custom"
      assert view2.assigns.panel_sizes.file_tree == 300
      assert view2.assigns.panel_sizes.chat == 400
      assert view2.assigns.panel_sizes.terminal == 200

      # UI should reflect custom layout
      assert html =~ "style=\"width: 300px\"" or html =~ "w-\\[300px\\]"
    end
  end

  describe "work progress persistence" do
    test "saves unsaved file changes", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view1, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Make unsaved changes
      send(
        view1.pid,
        {:file_selected,
         %{
           path: "lib/work.ex",
           content: "defmodule Work do\nend"
         }}
      )

      send(
        view1.pid,
        {:editor_content_changed,
         %{
           path: "lib/work.ex",
           content: "defmodule Work do\n  # TODO: Important work\n  def process do\n    :in_progress\n  end\nend",
           dirty: true
         }}
      )

      :timer.sleep(100)

      # Close without saving
      GenServer.stop(view1.pid, :normal)
      :timer.sleep(100)

      # Reopen
      {:ok, view2, html} = live(conn, ~p"/projects/#{project.id}/session")
      :timer.sleep(100)

      # Should restore unsaved changes
      assert view2.assigns.unsaved_files["lib/work.ex"] != nil
      assert html =~ "Unsaved changes" or html =~ "modified"
      assert html =~ "TODO: Important work"

      # Should prompt to restore
      assert html =~ "Restore unsaved changes?" or html =~ "recover"
    end

    test "persists debug session state", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view1, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Start debugging
      view1
      |> element("button[phx-click=\"start_debug\"]")
      |> render_click()

      # Set breakpoints
      breakpoints = [
        %{file: "lib/app.ex", line: 10},
        %{file: "lib/app.ex", line: 25},
        %{file: "lib/server.ex", line: 5}
      ]

      for bp <- breakpoints do
        send(view1.pid, {:breakpoint_set, bp})
        :timer.sleep(20)
      end

      # Add watch expressions
      send(view1.pid, {:watch_added, "state"})
      send(view1.pid, {:watch_added, "user_id"})

      # Debug state
      send(
        view1.pid,
        {:debug_paused,
         %{
           file: "lib/app.ex",
           line: 10,
           call_stack: ["App.process/1", "App.handle_call/3"],
           variables: %{"state" => "%{users: []}", "user_id" => "123"}
         }}
      )

      :timer.sleep(100)

      # Close session
      GenServer.stop(view1.pid, :normal)
      :timer.sleep(100)

      # Reopen
      {:ok, view2, html} = live(conn, ~p"/projects/#{project.id}/session")
      :timer.sleep(100)

      # Debug state should be restored
      assert length(view2.assigns.breakpoints) == 3
      assert view2.assigns.watch_expressions == ["state", "user_id"]
      assert view2.assigns.debug_session_active == true

      # UI should show debug state
      assert html =~ "Debugging" or html =~ "debug-mode"
      assert html =~ "Breakpoints (3)" or html =~ "3 breakpoints"
    end

    test "persists terminal history and state", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view1, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Execute terminal commands
      commands = [
        "mix compile",
        "mix test",
        "iex -S mix",
        "h Enum.map"
      ]

      for cmd <- commands do
        view1
        |> form("form[phx-submit=\"terminal_command\"]", %{command: cmd})
        |> render_submit()

        :timer.sleep(50)
      end

      # Set terminal state
      send(
        view1.pid,
        {:terminal_state,
         %{
           working_directory: "/home/user/project",
           environment: %{"MIX_ENV" => "test"},
           running_process: "iex"
         }}
      )

      :timer.sleep(100)

      # Close and reopen
      GenServer.stop(view1.pid, :normal)
      :timer.sleep(100)

      {:ok, view2, html} = live(conn, ~p"/projects/#{project.id}/session")

      # Terminal history should be restored
      assert length(view2.assigns.terminal_history) >= 4
      assert view2.assigns.terminal_state.working_directory == "/home/user/project"
      assert view2.assigns.terminal_state.running_process == "iex"

      # Can access history
      view2
      |> element("input[phx-keydown=\"terminal_key\"]")
      |> render_keydown(%{"key" => "ArrowUp"})

      assert view2.assigns.terminal_input == "h Enum.map"
    end
  end

  describe "collaboration state persistence" do
    test "persists collaboration session state", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view1, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Start collaboration
      view1
      |> element("button[phx-click=\"start_collaboration\"]")
      |> render_click()

      :timer.sleep(100)

      # Collaboration state
      collab_state = %{
        session_id: view1.assigns.collaboration_session.id,
        active_users: ["user1", "user2"],
        shared_cursors: %{
          "user2" => %{file: "lib/app.ex", line: 10, column: 5}
        },
        voice_enabled: true
      }

      # Close and reopen
      GenServer.stop(view1.pid, :normal)
      :timer.sleep(100)

      {:ok, view2, html} = live(conn, ~p"/projects/#{project.id}/session")
      :timer.sleep(100)

      # Should offer to rejoin collaboration
      assert html =~ "Rejoin collaboration?" or html =~ "Active collaboration session"
      assert has_element?(view2, "button", "Rejoin")

      # Rejoin
      view2
      |> element("button[phx-click=\"rejoin_collaboration\"]")
      |> render_click()

      :timer.sleep(100)

      # Should restore collaboration state
      assert view2.assigns.is_collaborative == true
      assert view2.assigns.collaboration_session != nil
    end
  end

  describe "persistence across devices" do
    test "syncs state across multiple devices", %{conn: conn, user: user, project: project} do
      # Device 1
      conn1 = log_in_user(conn, user)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session?device=desktop")

      # Set state on device 1
      view1
      |> form("form[phx-submit=\"send_message\"]", %{message: "Working on desktop"})
      |> render_submit()

      send(
        view1.pid,
        {:file_selected,
         %{
           path: "lib/shared.ex",
           content: "defmodule Shared do\nend"
         }}
      )

      :timer.sleep(200)

      # Device 2 (mobile)
      conn2 = log_in_user(conn, user)
      {:ok, view2, html2} = live(conn2, ~p"/projects/#{project.id}/session?device=mobile")

      :timer.sleep(100)

      # Should see synced state
      assert html2 =~ "Working on desktop"
      assert html2 =~ "lib/shared.ex"

      # Make change on device 2
      view2
      |> form("form[phx-submit=\"send_message\"]", %{message: "Now on mobile"})
      |> render_submit()

      :timer.sleep(100)

      # Device 1 should see update
      assert render(view1) =~ "Now on mobile"
    end

    test "handles conflicts in multi-device scenarios", %{conn: conn, user: user, project: project} do
      # Two devices
      conn1 = log_in_user(conn, user)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session?device=1")

      conn2 = log_in_user(conn, user)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session?device=2")

      # Both edit preferences simultaneously
      view1
      |> element("button[phx-click=\"update_preference\"][phx-value-key=\"theme\"]")
      |> render_click(%{"value" => "dark"})

      view2
      |> element("button[phx-click=\"update_preference\"][phx-value-key=\"theme\"]")
      |> render_click(%{"value" => "light"})

      :timer.sleep(200)

      # Should resolve conflict (last write wins or merge)
      assert view1.assigns.preferences.theme == view2.assigns.preferences.theme

      # Should notify about sync
      html1 = render(view1)
      assert html1 =~ "synced" or html1 =~ "updated from another device"
    end
  end

  describe "persistence storage management" do
    test "limits storage size per user", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Fill up storage with large data
      # 1MB
      large_content = String.duplicate("x", 1_000_000)

      for i <- 1..10 do
        send(
          view.pid,
          {:file_selected,
           %{
             path: "large#{i}.txt",
             content: large_content
           }}
        )

        :timer.sleep(50)
      end

      # Check storage usage
      send(view.pid, :get_storage_info)
      assert_receive {:storage_info, info}

      assert info.used_bytes > 0
      assert info.limit_bytes > info.used_bytes
      assert info.percentage < 100

      # Should show warning if near limit
      if info.percentage > 80 do
        html = render(view)
        assert html =~ "storage" and (html =~ "warning" or html =~ "limit")
      end
    end

    test "cleans up old session data", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      # Create multiple old sessions
      for i <- 1..5 do
        project = %{id: "old-project-#{i}", name: "Old Project #{i}"}
        {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

        # Add some data
        view
        |> form("form[phx-submit=\"send_message\"]", %{message: "Old message #{i}"})
        |> render_submit()

        GenServer.stop(view.pid, :normal)
        :timer.sleep(50)
      end

      # Trigger cleanup (usually happens periodically)
      send(self(), :cleanup_old_sessions)
      :timer.sleep(200)

      # New session
      current_project = %{id: "current-project", name: "Current Project"}
      {:ok, view, _html} = live(conn, ~p"/projects/#{current_project.id}/session")

      # Check storage - old sessions should be cleaned
      send(view.pid, :get_session_count)
      assert_receive {:session_count, count}
      # Keep only recent sessions
      assert count <= 3
    end
  end
end
