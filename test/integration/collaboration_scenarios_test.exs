defmodule RubberDuckWeb.Integration.CollaborationScenariosTest do
  @moduledoc """
  Integration tests for multi-user collaboration scenarios.
  
  Tests real-time collaboration features including presence tracking,
  collaborative editing, shared selections, and communication.
  """
  
  use RubberDuckWeb.ConnCase
  
  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures
  alias Phoenix.PubSub
  alias RubberDuckWeb.Collaboration.{CollaborativeEditor, PresenceTracker, SessionManager}
  
  @moduletag :integration
  
  setup do
    # Create multiple users
    user1 = user_fixture(%{username: "alice", email: "alice@example.com"})
    user2 = user_fixture(%{username: "bob", email: "bob@example.com"})
    user3 = user_fixture(%{username: "charlie", email: "charlie@example.com"})
    
    project = %{
      id: "collab-test-#{System.unique_integer()}",
      name: "Collaboration Test Project",
      description: "Testing multi-user collaboration"
    }
    
    %{
      user1: user1,
      user2: user2,
      user3: user3,
      project: project
    }
  end
  
  describe "multi-user presence tracking" do
    test "tracks multiple users joining and leaving", %{conn: conn, user1: user1, user2: user2, project: project} do
      # User 1 joins
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      # Verify user 1 is alone
      assert view1.assigns.active_users == [user1.id]
      
      # User 2 joins
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session")
      
      # Give presence time to sync
      :timer.sleep(100)
      
      # Both users should see each other
      assert length(view1.assigns.active_users) == 2
      assert length(view2.assigns.active_users) == 2
      assert user1.id in view1.assigns.active_users
      assert user2.id in view1.assigns.active_users
      
      # User 2 leaves
      GenServer.stop(view2.pid, :normal)
      :timer.sleep(100)
      
      # User 1 should see user 2 left
      assert view1.assigns.active_users == [user1.id]
    end
    
    test "displays user avatars and colors", %{conn: conn, user1: user1, user2: user2, project: project} do
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session")
      
      :timer.sleep(100)
      
      # Check presence display
      html1 = render(view1)
      assert html1 =~ "alice"
      assert html1 =~ "bob"
      assert html1 =~ "avatar" or html1 =~ "gravatar"
      
      # Verify each user has a unique color
      assert view1.assigns.user_colors[user1.id] != view1.assigns.user_colors[user2.id]
    end
    
    test "tracks user activity status", %{conn: conn, user1: user1, user2: user2, project: project} do
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session")
      
      # User 2 starts typing
      send(view2.pid, {:activity_update, :typing})
      :timer.sleep(50)
      
      # User 1 should see user 2 is typing
      assert render(view1) =~ "typing" or render(view1) =~ "active"
      
      # User 2 goes idle
      send(view2.pid, {:activity_update, :idle})
      :timer.sleep(50)
      
      assert render(view1) =~ "idle" or render(view1) =~ "away"
    end
  end
  
  describe "collaborative editing" do
    test "synchronizes edits between multiple users", %{conn: conn, user1: user1, user2: user2, project: project} do
      # Both users join
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session")
      
      # Start collaborative editing session
      view1
      |> element("button[phx-click=\"start_collaboration\"]")
      |> render_click()
      
      :timer.sleep(100)
      
      # Both open the same file
      file_content = "defmodule Example do\n  def hello, do: :world\nend"
      
      send(view1.pid, {:file_selected, %{path: "lib/example.ex", content: file_content}})
      send(view2.pid, {:file_selected, %{path: "lib/example.ex", content: file_content}})
      
      :timer.sleep(50)
      
      # User 1 makes an edit
      send(view1.pid, {:editor_operation, %{
        type: :insert,
        position: 21,  # After "Example do\n"
        content: "  # This is a comment\n"
      }})
      
      :timer.sleep(100)
      
      # User 2 should see the edit
      assert render(view2) =~ "This is a comment"
      
      # User 2 makes a concurrent edit
      send(view2.pid, {:editor_operation, %{
        type: :insert,
        position: 50,  # In the function
        content: " # Returns :world"
      }})
      
      :timer.sleep(100)
      
      # Both users should see both edits
      assert render(view1) =~ "This is a comment"
      assert render(view1) =~ "Returns :world"
      assert render(view2) =~ "This is a comment"
      assert render(view2) =~ "Returns :world"
    end
    
    test "handles conflicting edits with operational transformation", %{conn: conn, user1: user1, user2: user2, project: project} do
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session")
      
      # Start collaboration
      view1 |> element("button[phx-click=\"start_collaboration\"]") |> render_click()
      :timer.sleep(100)
      
      # Open same file
      file_content = "Hello world"
      send(view1.pid, {:file_selected, %{path: "test.txt", content: file_content}})
      send(view2.pid, {:file_selected, %{path: "test.txt", content: file_content}})
      
      # Simulate concurrent edits at the same position
      send(view1.pid, {:editor_operation, %{
        type: :insert,
        position: 5,  # After "Hello"
        content: " beautiful"
      }})
      
      send(view2.pid, {:editor_operation, %{
        type: :insert,
        position: 5,  # Same position
        content: " wonderful"
      }})
      
      :timer.sleep(200)
      
      # Both edits should be preserved without conflicts
      content1 = render(view1)
      content2 = render(view2)
      
      # The exact order depends on OT resolution, but both words should appear
      assert (content1 =~ "beautiful" and content1 =~ "wonderful") or
             (content1 =~ "Hello beautiful wonderful world") or
             (content1 =~ "Hello wonderful beautiful world")
      
      assert content1 == content2  # Both users see the same result
    end
  end
  
  describe "shared selections and cursors" do
    test "shows other users' cursors in real-time", %{conn: conn, user1: user1, user2: user2, project: project} do
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session")
      
      # Open same file
      send(view1.pid, {:file_selected, %{path: "lib/test.ex", content: "defmodule Test do\nend"}})
      send(view2.pid, {:file_selected, %{path: "lib/test.ex", content: "defmodule Test do\nend"}})
      
      # User 2 moves cursor
      send(view2.pid, {:cursor_position, %{line: 2, column: 1}})
      :timer.sleep(50)
      
      # User 1 should see user 2's cursor
      html1 = render(view1)
      assert html1 =~ "cursor" or html1 =~ "bob"
      assert html1 =~ "line-2" or html1 =~ "2:1"
    end
    
    test "highlights shared selections", %{conn: conn, user1: user1, user2: user2, project: project} do
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session")
      
      # User 2 selects text
      send(view2.pid, {:text_selection, %{
        start_line: 1,
        start_column: 1,
        end_line: 1,
        end_column: 10
      }})
      
      :timer.sleep(50)
      
      # User 1 should see the selection
      html1 = render(view1)
      assert html1 =~ "selection" or html1 =~ "highlight"
      assert html1 =~ view1.assigns.user_colors[user2.id]  # Selection in user's color
    end
    
    test "supports annotations on selections", %{conn: conn, user1: user1, user2: user2, project: project} do
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session")
      
      # User 1 adds annotation
      view1
      |> element("button[phx-click=\"add_annotation\"]")
      |> render_click()
      
      view1
      |> form("form[phx-submit=\"save_annotation\"]", %{
        annotation: %{
          text: "Consider refactoring this",
          line: 5,
          type: "suggestion"
        }
      })
      |> render_submit()
      
      :timer.sleep(100)
      
      # User 2 should see the annotation
      assert render(view2) =~ "Consider refactoring"
      assert render(view2) =~ "suggestion"
      assert render(view2) =~ "alice"  # Author
    end
  end
  
  describe "communication features" do
    test "voice chat indicator and controls", %{conn: conn, user1: user1, user2: user2, project: project} do
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session")
      
      # User 1 starts voice chat
      view1
      |> element("button[phx-click=\"toggle_voice\"]")
      |> render_click()
      
      :timer.sleep(50)
      
      # Both users should see voice indicators
      assert render(view1) =~ "voice" or render(view1) =~ "🎤"
      assert render(view2) =~ "alice" and (render(view2) =~ "speaking" or render(view2) =~ "voice")
    end
    
    test "emoji reactions on code", %{conn: conn, user1: user1, user2: user2, project: project} do
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session")
      
      # User 1 adds reaction
      view1
      |> element("button[phx-click=\"add_reaction\"][phx-value-line=\"10\"][phx-value-emoji=\"👍\"]")
      |> render_click()
      
      :timer.sleep(50)
      
      # Both users should see the reaction
      assert render(view1) =~ "👍"
      assert render(view2) =~ "👍"
      
      # User 2 adds different reaction to same line
      view2
      |> element("button[phx-click=\"add_reaction\"][phx-value-line=\"10\"][phx-value-emoji=\"🎉\"]")
      |> render_click()
      
      :timer.sleep(50)
      
      # Should see both reactions
      assert render(view1) =~ "👍" and render(view1) =~ "🎉"
    end
    
    test "shared pointer for attention direction", %{conn: conn, user1: user1, user2: user2, project: project} do
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session")
      
      # User 1 shares pointer
      send(view1.pid, {:share_pointer, %{x: 100, y: 200, active: true}})
      :timer.sleep(50)
      
      # User 2 should see the pointer
      assert render(view2) =~ "pointer" or render(view2) =~ "alice"
      
      # User 1 stops sharing
      send(view1.pid, {:share_pointer, %{active: false}})
      :timer.sleep(50)
      
      # Pointer should disappear
      refute render(view2) =~ "pointer-active"
    end
  end
  
  describe "session management" do
    test "owner can manage session permissions", %{conn: conn, user1: user1, user2: user2, user3: user3, project: project} do
      # User 1 creates session as owner
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      view1
      |> element("button[phx-click=\"start_collaboration\"]")
      |> render_click()
      
      :timer.sleep(100)
      
      # User 2 joins
      conn2 = log_in_user(conn, user2)
      {:ok, view2, _html} = live(conn2, ~p"/projects/#{project.id}/session?join=true")
      
      # User 3 joins
      conn3 = log_in_user(conn, user3)
      {:ok, view3, _html} = live(conn3, ~p"/projects/#{project.id}/session?join=true")
      
      :timer.sleep(100)
      
      # Owner changes user 3 to viewer only
      view1
      |> form("form[phx-submit=\"update_permissions\"]", %{
        permissions: %{
          user_id: user3.id,
          role: "viewer"
        }
      })
      |> render_submit()
      
      :timer.sleep(50)
      
      # User 3 should not be able to edit
      assert render(view3) =~ "read-only" or render(view3) =~ "viewer"
      refute has_element?(view3, "button[phx-click=\"save_file\"]")
    end
    
    test "handles session recording and playback", %{conn: conn, user1: user1, user2: user2, project: project} do
      conn1 = log_in_user(conn, user1)
      {:ok, view1, _html} = live(conn1, ~p"/projects/#{project.id}/session")
      
      # Start recording
      view1
      |> element("button[phx-click=\"toggle_recording\"]")
      |> render_click()
      
      assert render(view1) =~ "Recording" or render(view1) =~ "🔴"
      
      # Perform some actions
      view1
      |> form("form[phx-submit=\"send_message\"]", %{message: "Recording test"})
      |> render_submit()
      
      send(view1.pid, {:file_selected, %{path: "test.ex", content: "# Test"}})
      
      :timer.sleep(100)
      
      # Stop recording
      view1
      |> element("button[phx-click=\"toggle_recording\"]")
      |> render_click()
      
      # Should show recording saved
      assert render(view1) =~ "saved" or render(view1) =~ "Recording stopped"
    end
  end
  
  describe "performance with multiple users" do
    test "handles many concurrent users efficiently", %{conn: conn, project: project} do
      # Create 10 users
      users = for i <- 1..10 do
        user_fixture(%{username: "user#{i}", email: "user#{i}@example.com"})
      end
      
      # All users join
      views = for user <- users do
        conn = log_in_user(conn, user)
        {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
        view
      end
      
      :timer.sleep(200)
      
      # Verify all users see each other
      first_view = hd(views)
      assert length(first_view.assigns.active_users) == 10
      
      # Each user sends a message
      for {view, i} <- Enum.with_index(views) do
        view
        |> form("form[phx-submit=\"send_message\"]", %{message: "Message #{i}"})
        |> render_submit()
        :timer.sleep(10)  # Small delay to prevent overwhelming
      end
      
      :timer.sleep(500)
      
      # Verify all messages received
      for view <- views do
        html = render(view)
        for i <- 0..9 do
          assert html =~ "Message #{i}"
        end
      end
    end
  end
end