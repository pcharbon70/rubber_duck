defmodule RubberDuckWeb.CodingSessionLiveTest do
  use RubberDuckWeb.ConnCase

  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures

  alias Phoenix.PubSub

  setup do
    user = user_fixture()
    # TODO: Create project fixture when Projects domain is implemented
    project = %{id: "test-project-123", name: "Test Project"}

    %{user: user, project: project}
  end

  describe "mount and authentication" do
    test "redirects if user is not logged in", %{conn: conn, project: project} do
      result =
        conn
        |> live(~p"/projects/#{project.id}/session")

      assert {:error, {:redirect, %{to: "/sign-in", flash: _}}} = result
    end

    test "mounts successfully when authenticated", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      assert has_element?(view, "div.coding-session")
      assert has_element?(view, "header")
      assert has_element?(view, "main")
    end

    test "assigns initial state correctly", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      assert view.assigns.project_id == project.id
      assert view.assigns.user.id == user.id
      assert view.assigns.chat_messages == []
      assert view.assigns.chat_input == ""
      assert view.assigns.current_file == nil
      assert view.assigns.layout.show_file_tree == true
      assert view.assigns.layout.show_editor == true
    end
  end

  describe "panel toggling" do
    setup %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      %{view: view}
    end

    test "toggles file tree panel", %{view: view} do
      assert has_element?(view, "aside", "Files")

      view
      |> element("button[phx-value-panel=\"file_tree\"]")
      |> render_click()

      refute has_element?(view, "aside", "Files")

      view
      |> element("button[phx-value-panel=\"file_tree\"]")
      |> render_click()

      assert has_element?(view, "aside", "Files")
    end

    test "toggles editor panel", %{view: view} do
      assert has_element?(view, "aside", "No file selected")

      view
      |> element("button[phx-value-panel=\"editor\"]")
      |> render_click()

      refute has_element?(view, "aside", "No file selected")

      view
      |> element("button[phx-value-panel=\"editor\"]")
      |> render_click()

      assert has_element?(view, "aside", "No file selected")
    end
  end

  describe "chat functionality" do
    setup %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      %{view: view}
    end

    test "sends chat message", %{view: view, project: project} do
      # Subscribe to PubSub to verify broadcast
      PubSub.subscribe(RubberDuck.PubSub, "chat:#{project.id}")

      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Hello, world!"})
      |> render_submit()

      # Verify PubSub broadcast
      assert_receive {:chat_message, message}
      assert message.content == "Hello, world!"
      assert message.type == :user

      # Verify message appears in view
      assert has_element?(view, "div", "Hello, world!")
    end

    test "updates chat input as user types", %{view: view} do
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Test input"})
      |> render_change()

      assert view.assigns.chat_input == "Test input"
    end

    test "clears chat input after sending", %{view: view, project: project} do
      PubSub.subscribe(RubberDuck.PubSub, "chat:#{project.id}")

      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Test message"})
      |> render_submit()

      assert view.assigns.chat_input == ""
    end

    test "identifies command messages", %{view: view, project: project} do
      PubSub.subscribe(RubberDuck.PubSub, "chat:#{project.id}")

      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "/help"})
      |> render_submit()

      assert_receive {:chat_message, message}
      assert message.type == :command
    end
  end

  describe "keyboard shortcuts" do
    setup %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      %{view: view}
    end

    test "Ctrl+F toggles file tree", %{view: view} do
      assert view.assigns.layout.show_file_tree == true

      view
      |> element("div.coding-session")
      |> render_keydown(%{"key" => "f", "ctrlKey" => true})

      assert view.assigns.layout.show_file_tree == false
    end

    test "Ctrl+E toggles editor", %{view: view} do
      assert view.assigns.layout.show_editor == true

      view
      |> element("div.coding-session")
      |> render_keydown(%{"key" => "e", "ctrlKey" => true})

      assert view.assigns.layout.show_editor == false
    end

    test "Ctrl+/ focuses chat input", %{view: view} do
      view
      |> element("div.coding-session")
      |> render_keydown(%{"key" => "/", "ctrlKey" => true})

      # This would push a focus_chat event to the client
      # In a real test, we'd verify the JavaScript hook behavior
    end
  end

  describe "PubSub message handling" do
    setup %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      %{view: view, project: project}
    end

    test "receives and displays chat messages from other users", %{view: view} do
      other_user_message = %{
        id: Ecto.UUID.generate(),
        user_id: "other-user-123",
        username: "other_user",
        content: "Hello from another user!",
        timestamp: DateTime.utc_now(),
        type: :user
      }

      send(view.pid, {:chat_message, other_user_message})

      # Give the view time to process the message
      :timer.sleep(50)

      assert render(view) =~ "Hello from another user!"
      assert render(view) =~ "other_user"
    end

    test "handles presence updates", %{view: view} do
      presence_diff = %{
        joins: %{
          "user-123" => %{
            metas: [%{username: "new_user", online_at: System.system_time(:second)}]
          }
        },
        leaves: %{}
      }

      send(view.pid, {:presence_diff, presence_diff})

      :timer.sleep(50)

      assert view.assigns.presence_users["user-123"]
    end
  end

  describe "connection status" do
    setup %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      %{view: view}
    end

    test "displays connection status", %{view: view} do
      assert has_element?(view, "div", "Connected")
      assert view.assigns.connection_status == :connected
    end
  end

  describe "streaming messages" do
    setup %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      %{view: view}
    end

    test "displays streaming message with animation", %{view: view} do
      streaming_msg = %{
        content: "I'm thinking about your request..."
      }

      # Simulate streaming message update
      send(view.pid, {:streaming_update, streaming_msg})

      :timer.sleep(50)

      # Would verify streaming message display
      # This requires implementing the streaming message handler
    end
  end
end
