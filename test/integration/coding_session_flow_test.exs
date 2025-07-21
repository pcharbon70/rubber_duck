defmodule RubberDuckWeb.Integration.CodingSessionFlowTest do
  @moduledoc """
  Integration tests for complete coding session flow.
  
  Tests the entire user journey from login to project creation,
  file editing, AI assistance, and collaboration.
  """
  
  use RubberDuckWeb.ConnCase
  
  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures
  alias Phoenix.PubSub
  
  @moduletag :integration
  
  setup do
    user = user_fixture()
    project = %{
      id: "flow-test-#{System.unique_integer()}",
      name: "Flow Test Project",
      description: "Testing complete coding flow"
    }
    
    %{user: user, project: project}
  end
  
  describe "complete coding session flow" do
    test "user can navigate through full coding workflow", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      
      # Step 1: Navigate to coding session
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      assert html =~ "Flow Test Project"
      assert has_element?(view, "div.coding-session")
      
      # Step 2: Verify initial layout
      assert has_element?(view, "aside", "Files")  # File tree panel
      assert has_element?(view, "main")  # Editor area
      assert has_element?(view, "section", "AI Assistant")  # Chat panel
      
      # Step 3: Open a file (simulate file selection)
      send(view.pid, {:file_selected, %{
        path: "lib/example.ex",
        content: "defmodule Example do\n  def hello, do: :world\nend"
      }})
      
      :timer.sleep(50)
      
      assert render(view) =~ "lib/example.ex"
      assert render(view) =~ "defmodule Example"
      
      # Step 4: Send chat message to AI
      PubSub.subscribe(RubberDuck.PubSub, "chat:#{project.id}")
      
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Explain this module"})
      |> render_submit()
      
      assert_receive {:chat_message, message}
      assert message.content == "Explain this module"
      assert message.type == :user
      
      # Step 5: Simulate AI response
      ai_response = %{
        id: Ecto.UUID.generate(),
        user_id: "ai-assistant",
        username: "AI Assistant",
        content: "This is a simple Elixir module that defines a function `hello/0` which returns the atom `:world`.",
        timestamp: DateTime.utc_now(),
        type: :assistant
      }
      
      send(view.pid, {:chat_message, ai_response})
      :timer.sleep(50)
      
      assert render(view) =~ "simple Elixir module"
      
      # Step 6: Use command palette
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "/help"})
      |> render_submit()
      
      assert_receive {:chat_message, help_message}
      assert help_message.type == :command
      
      # Step 7: Toggle panels
      initial_file_tree_state = view.assigns.layout.show_file_tree
      
      view
      |> element("button[phx-value-panel=\"file_tree\"]")
      |> render_click()
      
      assert view.assigns.layout.show_file_tree == !initial_file_tree_state
      
      # Step 8: Test keyboard shortcuts
      view
      |> element("div.coding-session")
      |> render_keydown(%{"key" => "f", "ctrlKey" => true})
      
      assert view.assigns.layout.show_file_tree == initial_file_tree_state
      
      # Step 9: Update context panel
      send(view.pid, {:context_update, %{
        current_function: "hello/0",
        related_files: ["test/example_test.exs"],
        suggestions: ["Add documentation", "Add type specs"]
      }})
      
      :timer.sleep(50)
      
      assert render(view) =~ "Current Function"
      assert render(view) =~ "hello/0"
      
      # Step 10: Check status indicators
      assert render(view) =~ "Connected"
      assert view.assigns.connection_status == :connected
      
      # Verify session state is complete
      assert length(view.assigns.chat_messages) >= 2
      assert view.assigns.current_file != nil
      assert view.assigns.context != %{}
    end
    
    test "handles file operations in sequence", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Create new file
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "/new lib/new_module.ex"})
      |> render_submit()
      
      # Edit file
      send(view.pid, {:file_content_changed, %{
        path: "lib/new_module.ex",
        content: "defmodule NewModule do\n  # New code here\nend"
      }})
      
      :timer.sleep(50)
      
      # Save file
      view
      |> element("button[phx-click=\"save_file\"]")
      |> render_click()
      
      # Run tests
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "/test"})
      |> render_submit()
      
      # Verify file operations completed
      assert render(view) =~ "lib/new_module.ex"
      assert render(view) =~ "NewModule"
    end
    
    test "maintains state across panel reconfigurations", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Add some chat messages
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "First message"})
      |> render_submit()
      
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Second message"})
      |> render_submit()
      
      # Select a file
      send(view.pid, {:file_selected, %{
        path: "lib/test.ex",
        content: "defmodule Test do\nend"
      }})
      
      :timer.sleep(50)
      
      # Store initial state
      initial_messages = view.assigns.chat_messages
      initial_file = view.assigns.current_file
      
      # Toggle all panels
      view |> element("button[phx-value-panel=\"file_tree\"]") |> render_click()
      view |> element("button[phx-value-panel=\"editor\"]") |> render_click()
      view |> element("button[phx-value-panel=\"chat\"]") |> render_click()
      
      # Toggle them back
      view |> element("button[phx-value-panel=\"file_tree\"]") |> render_click()
      view |> element("button[phx-value-panel=\"editor\"]") |> render_click()
      view |> element("button[phx-value-panel=\"chat\"]") |> render_click()
      
      # Verify state is preserved
      assert view.assigns.chat_messages == initial_messages
      assert view.assigns.current_file == initial_file
    end
  end
  
  describe "error handling in coding flow" do
    test "gracefully handles disconnection during session", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Simulate disconnection
      send(view.pid, {:connection_status, :disconnected})
      :timer.sleep(50)
      
      assert render(view) =~ "Disconnected"
      assert view.assigns.connection_status == :disconnected
      
      # Try to send message while disconnected
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Test message"})
      |> render_submit()
      
      # Should queue message or show error
      assert render(view) =~ "offline" or render(view) =~ "queued"
      
      # Simulate reconnection
      send(view.pid, {:connection_status, :connected})
      :timer.sleep(50)
      
      assert render(view) =~ "Connected"
      assert view.assigns.connection_status == :connected
    end
    
    test "handles invalid file operations", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Try to open non-existent file
      send(view.pid, {:file_error, %{
        path: "non/existent.ex",
        error: "File not found"
      }})
      
      :timer.sleep(50)
      
      assert render(view) =~ "File not found" or render(view) =~ "Error"
      
      # Verify session continues to work
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Still working?"})
      |> render_submit()
      
      assert length(view.assigns.chat_messages) > 0
    end
  end
end