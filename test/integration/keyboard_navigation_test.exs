defmodule RubberDuckWeb.Integration.KeyboardNavigationTest do
  @moduledoc """
  Integration tests for keyboard navigation flow.

  Tests comprehensive keyboard shortcuts, navigation patterns,
  and accessibility features for power users.
  """

  use RubberDuckWeb.ConnCase

  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures

  @moduletag :integration

  setup do
    user = user_fixture()

    project = %{
      id: "keyboard-test-#{System.unique_integer()}",
      name: "Keyboard Test Project"
    }

    %{user: user, project: project}
  end

  describe "global keyboard shortcuts" do
    test "command palette activation", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Cmd/Ctrl + K opens command palette
      view
      |> element("body")
      |> render_keydown(%{"key" => "k", "ctrlKey" => true})

      html = render(view)
      assert html =~ "command-palette" or html =~ "Command Palette"
      assert has_element?(view, "input[placeholder*=command]")

      # Escape closes it
      view
      |> element("input.command-palette")
      |> render_keydown(%{"key" => "Escape"})

      refute render(view) =~ "command-palette-open"
    end

    test "quick file switching", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Add some files to history
      files = ["app.ex", "server.ex", "test.exs"]

      for file <- files do
        send(view.pid, {:file_selected, %{path: "lib/#{file}", content: "# #{file}"}})
        :timer.sleep(50)
      end

      # Ctrl+P for quick open
      view
      |> element("body")
      |> render_keydown(%{"key" => "p", "ctrlKey" => true})

      html = render(view)
      assert html =~ "quick-open" or html =~ "Go to File"

      # Should show recent files
      for file <- files do
        assert html =~ file
      end

      # Type to filter
      view
      |> element("input.quick-open")
      |> render_change(%{"value" => "ser"})

      html = render(view)
      assert html =~ "server.ex"
      # Filtered out
      refute html =~ "app.ex"

      # Enter to select
      view
      |> element("input.quick-open")
      |> render_keydown(%{"key" => "Enter"})

      assert view.assigns.current_file.path =~ "server.ex"
    end

    test "panel navigation shortcuts", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      shortcuts = [
        {"f", "file_tree", "Files"},
        {"e", "editor", "editor"},
        {"/", "chat", "chat-input"}
      ]

      for {key, panel, indicator} <- shortcuts do
        initial_state = view.assigns.layout[String.to_atom("show_#{panel}")]

        view
        |> element("body")
        |> render_keydown(%{"key" => key, "ctrlKey" => true})

        new_state = view.assigns.layout[String.to_atom("show_#{panel}")]
        assert new_state != initial_state

        html = render(view)

        if new_state do
          assert html =~ indicator
        else
          refute html =~ indicator
        end
      end
    end
  end

  describe "editor keyboard navigation" do
    test "code navigation shortcuts", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Load a file with code
      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/example.ex",
           content: """
           defmodule Example do
             def function_one do
               :one
             end
             
             def function_two do
               :two
             end
             
             def function_three do
               :three
             end
           end
           """
         }}
      )

      # Go to definition (F12)
      view
      |> element(".editor")
      |> render_keydown(%{"key" => "F12"})

      # Go to line (Ctrl+G)
      view
      |> element("body")
      |> render_keydown(%{"key" => "g", "ctrlKey" => true})

      html = render(view)
      assert html =~ "Go to line" or html =~ "line-number"

      # Type line number
      view
      |> element("input.goto-line")
      |> render_change(%{"value" => "6"})

      view
      |> element("input.goto-line")
      |> render_keydown(%{"key" => "Enter"})

      assert view.assigns.editor_state.cursor.line == 6
    end

    test "multi-cursor editing", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      send(
        view.pid,
        {:file_selected,
         %{
           path: "test.ex",
           content: "line one\nline two\nline three"
         }}
      )

      # Add cursor with Ctrl+Alt+Down
      view
      |> element(".editor")
      |> render_keydown(%{"key" => "ArrowDown", "ctrlKey" => true, "altKey" => true})

      assert length(view.assigns.editor_state.cursors) == 2

      # Type affects all cursors
      view
      |> element(".editor")
      |> render_keypress(%{"key" => "x"})

      lines = String.split(view.assigns.current_file.content, "\n")
      assert Enum.at(lines, 0) =~ "x"
      assert Enum.at(lines, 1) =~ "x"
    end

    test "code folding shortcuts", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      send(
        view.pid,
        {:file_selected,
         %{
           path: "nested.ex",
           content: """
           defmodule Nested do
             def outer do
               inner_one()
               inner_two()
             end
             
             defp inner_one do
               :one
             end
             
             defp inner_two do
               :two
             end
           end
           """
         }}
      )

      # Fold at cursor (Ctrl+Shift+[)
      send(view.pid, {:cursor_position, %{line: 2, column: 1}})

      view
      |> element(".editor")
      |> render_keydown(%{"key" => "[", "ctrlKey" => true, "shiftKey" => true})

      assert view.assigns.editor_state.folded_regions[{2, 5}] == true

      # Unfold (Ctrl+Shift+])
      view
      |> element(".editor")
      |> render_keydown(%{"key" => "]", "ctrlKey" => true, "shiftKey" => true})

      assert view.assigns.editor_state.folded_regions[{2, 5}] == false
    end
  end

  describe "chat and AI keyboard shortcuts" do
    test "quick AI commands", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Alt+Enter for AI assist on selection
      send(view.pid, {:text_selected, "def calculate(a, b)"})

      view
      |> element(".editor")
      |> render_keydown(%{"key" => "Enter", "altKey" => true})

      html = render(view)
      assert html =~ "AI Assist" or html =~ "suggestions"

      # Ctrl+Shift+A for explain code
      view
      |> element("body")
      |> render_keydown(%{"key" => "a", "ctrlKey" => true, "shiftKey" => true})

      assert render(view) =~ "Explain" or render(view) =~ "What does this code do?"
    end

    test "chat message navigation", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Send multiple messages
      messages = ["First", "Second", "Third"]

      for msg <- messages do
        view
        |> form("form[phx-submit=\"send_message\"]", %{message: msg})
        |> render_submit()

        :timer.sleep(50)
      end

      # Focus chat
      view
      |> element("body")
      |> render_keydown(%{"key" => "/", "ctrlKey" => true})

      # Navigate history with up/down
      view
      |> element("input.chat-input")
      |> render_keydown(%{"key" => "ArrowUp"})

      assert view.assigns.chat_input == "Third"

      view
      |> element("input.chat-input")
      |> render_keydown(%{"key" => "ArrowUp"})

      assert view.assigns.chat_input == "Second"
    end
  end

  describe "file tree keyboard navigation" do
    test "navigates files with arrow keys", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Focus file tree
      view
      |> element("body")
      |> render_keydown(%{"key" => "f", "ctrlKey" => true})

      # Navigate with arrows
      view
      |> element(".file-tree")
      |> render_keydown(%{"key" => "ArrowDown"})

      assert view.assigns.file_tree_selection == 1

      view
      |> element(".file-tree")
      |> render_keydown(%{"key" => "ArrowDown"})

      assert view.assigns.file_tree_selection == 2

      # Expand folder with right arrow
      view
      |> element(".file-tree")
      |> render_keydown(%{"key" => "ArrowRight"})

      assert view.assigns.expanded_folders != []

      # Open file with Enter
      view
      |> element(".file-tree")
      |> render_keydown(%{"key" => "Enter"})

      assert view.assigns.current_file != nil
    end

    test "file operations shortcuts", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # New file (Ctrl+N in file tree)
      view
      |> element(".file-tree")
      |> render_keydown(%{"key" => "n", "ctrlKey" => true})

      html = render(view)
      assert html =~ "New file" or html =~ "Enter filename"

      # Rename (F2)
      view
      |> element(".file-tree")
      |> render_keydown(%{"key" => "F2"})

      assert render(view) =~ "Rename" or render(view) =~ "rename-input"

      # Delete (Delete key)
      view
      |> element(".file-tree")
      |> render_keydown(%{"key" => "Delete"})

      assert render(view) =~ "confirm" or render(view) =~ "Delete"
    end
  end

  describe "vim mode navigation" do
    test "basic vim movements", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Enable vim mode
      view
      |> element("button[phx-click=\"toggle_vim_mode\"]")
      |> render_click()

      assert view.assigns.vim_mode_enabled == true

      send(
        view.pid,
        {:file_selected,
         %{
           path: "vim_test.ex",
           content: "line one\nline two\nline three\nline four"
         }}
      )

      # Normal mode movements
      movements = [
        # Down
        {"j", %{line: 2, column: 1}},
        # Up
        {"k", %{line: 1, column: 1}},
        # Right
        {"l", %{line: 1, column: 2}},
        # Left
        {"h", %{line: 1, column: 1}},
        # Word forward
        {"w", %{line: 1, column: 5}},
        # Word back
        {"b", %{line: 1, column: 1}},
        # End of line
        {"$", %{line: 1, column: 8}},
        # Start of line
        {"0", %{line: 1, column: 1}}
      ]

      for {key, expected_pos} <- movements do
        view
        |> element(".editor")
        |> render_keypress(%{"key" => key})

        assert view.assigns.editor_state.cursor == expected_pos
      end
    end

    test "vim mode operations", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      view
      |> element("button[phx-click=\"toggle_vim_mode\"]")
      |> render_click()

      send(
        view.pid,
        {:file_selected,
         %{
           path: "vim_ops.ex",
           content: "delete this line\nkeep this\nchange this"
         }}
      )

      # Delete line (dd)
      view
      |> element(".editor")
      |> render_keypress(%{"key" => "d"})

      view
      |> element(".editor")
      |> render_keypress(%{"key" => "d"})

      refute view.assigns.current_file.content =~ "delete this line"

      # Change word (cw)
      view
      |> element(".editor")
      |> render_keypress(%{"key" => "c"})

      view
      |> element(".editor")
      |> render_keypress(%{"key" => "w"})

      assert view.assigns.vim_mode == :insert
    end
  end

  describe "accessibility keyboard support" do
    test "tab navigation through interface", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Tab through major sections
      tab_stops = [
        "file-tree",
        "editor",
        "chat-input",
        "toolbar"
      ]

      for i <- 0..(length(tab_stops) - 1) do
        view
        |> element("body")
        |> render_keydown(%{"key" => "Tab"})

        assert view.assigns.focus_index == i
        html = render(view)
        assert html =~ "focus" or html =~ "focused"
        assert html =~ Enum.at(tab_stops, i)
      end

      # Shift+Tab backwards
      view
      |> element("body")
      |> render_keydown(%{"key" => "Tab", "shiftKey" => true})

      assert view.assigns.focus_index == length(tab_stops) - 2
    end

    test "skip link navigation", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session")

      # Should have skip links
      assert html =~ "Skip to main content"
      assert html =~ "Skip to chat"

      # Tab to skip link
      view
      |> element("body")
      |> render_keydown(%{"key" => "Tab"})

      # Enter to activate
      view
      |> element("a.skip-link")
      |> render_click()

      assert view.assigns.focus_area == "main-content"
    end
  end

  describe "custom keyboard shortcuts" do
    test "allows custom shortcut configuration", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Open shortcuts configuration
      view
      |> element("body")
      |> render_keydown(%{"key" => ",", "ctrlKey" => true})

      html = render(view)
      assert html =~ "Keyboard Shortcuts" or html =~ "Customize shortcuts"

      # Change a shortcut
      view
      |> form("form[phx-submit=\"update_shortcut\"]", %{
        shortcut: %{
          action: "toggle_file_tree",
          old_key: "ctrl+f",
          new_key: "ctrl+b"
        }
      })
      |> render_submit()

      # New shortcut should work
      view
      |> element("body")
      |> render_keydown(%{"key" => "b", "ctrlKey" => true})

      # File tree should toggle
      initial = view.assigns.layout.show_file_tree

      view
      |> element("body")
      |> render_keydown(%{"key" => "b", "ctrlKey" => true})

      assert view.assigns.layout.show_file_tree != initial
    end

    test "shortcut conflict detection", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Try to assign conflicting shortcut
      view
      |> form("form[phx-submit=\"update_shortcut\"]", %{
        shortcut: %{
          action: "save_file",
          # Already used for focus chat
          new_key: "ctrl+/"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "conflict" or html =~ "already assigned"
      # Shows what it conflicts with
      assert html =~ "focus chat"
    end
  end

  describe "keyboard shortcut help" do
    test "shows contextual shortcuts", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # ? or F1 for help
      view
      |> element("body")
      |> render_keydown(%{"key" => "?"})

      html = render(view)
      assert html =~ "Keyboard Shortcuts"
      # Command palette
      assert html =~ "Ctrl+K"
      # Quick open
      assert html =~ "Ctrl+P"

      # Context-specific help in editor
      view
      |> element(".editor")
      |> render_keydown(%{"key" => "F1"})

      html = render(view)
      assert html =~ "Editor shortcuts"
      assert html =~ "Go to definition"
      assert html =~ "Multi-cursor"
    end
  end
end
