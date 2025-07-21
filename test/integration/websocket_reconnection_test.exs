defmodule RubberDuckWeb.Integration.WebSocketReconnectionTest do
  @moduledoc """
  Integration tests for WebSocket reconnection handling.
  
  Tests the LiveView's ability to handle connection issues,
  reconnect gracefully, and maintain state consistency.
  """
  
  use RubberDuckWeb.ConnCase
  
  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures
  alias Phoenix.PubSub
  
  @moduletag :integration
  
  setup do
    user = user_fixture()
    project = %{
      id: "ws-test-#{System.unique_integer()}",
      name: "WebSocket Test Project"
    }
    
    %{user: user, project: project}
  end
  
  describe "connection state management" do
    test "tracks connection status accurately", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Initial connection should be established
      assert html =~ "Connected"
      assert view.assigns.connection_status == :connected
      
      # Simulate connection loss
      send(view.pid, {:websocket_event, :connection_lost})
      :timer.sleep(50)
      
      html = render(view)
      assert html =~ "Disconnected" or html =~ "Reconnecting"
      assert view.assigns.connection_status in [:disconnected, :reconnecting]
      
      # Show reconnection attempts
      assert html =~ "attempt" or html =~ "retry"
    end
    
    test "displays reconnection progress", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Start reconnection
      send(view.pid, {:websocket_event, :connection_lost})
      :timer.sleep(50)
      
      # Multiple reconnection attempts
      for attempt <- 1..3 do
        send(view.pid, {:reconnection_attempt, attempt})
        :timer.sleep(100)
        
        html = render(view)
        assert html =~ "Attempt #{attempt}" or html =~ "retry"
        assert html =~ "Reconnecting"
      end
      
      # Successful reconnection
      send(view.pid, {:websocket_event, :connection_restored})
      :timer.sleep(50)
      
      html = render(view)
      assert html =~ "Connected"
      assert view.assigns.connection_status == :connected
    end
  end
  
  describe "message queuing during disconnection" do
    test "queues chat messages while disconnected", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Disconnect
      send(view.pid, {:websocket_event, :connection_lost})
      :timer.sleep(50)
      
      # Try to send messages while disconnected
      messages = ["First message", "Second message", "Third message"]
      
      for msg <- messages do
        view
        |> form("form[phx-submit=\"send_message\"]", %{message: msg})
        |> render_submit()
        :timer.sleep(20)
      end
      
      # Messages should be queued
      assert length(view.assigns.message_queue) == 3
      html = render(view)
      assert html =~ "queued" or html =~ "pending"
      assert html =~ "3 messages" or html =~ "3 pending"
      
      # Reconnect
      send(view.pid, {:websocket_event, :connection_restored})
      :timer.sleep(100)
      
      # Messages should be sent
      assert view.assigns.message_queue == []
      assert length(view.assigns.chat_messages) >= 3
    end
    
    test "queues file operations while disconnected", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Select a file
      send(view.pid, {:file_selected, %{path: "test.ex", content: "defmodule Test do\nend"}})
      :timer.sleep(50)
      
      # Disconnect
      send(view.pid, {:websocket_event, :connection_lost})
      :timer.sleep(50)
      
      # Make edits while disconnected
      send(view.pid, {:editor_operation, %{
        type: :insert,
        position: 18,
        content: "\n  def hello, do: :world\n"
      }})
      
      # Try to save
      view
      |> element("button[phx-click=\"save_file\"]")
      |> render_click()
      
      # Should show pending save
      html = render(view)
      assert html =~ "pending save" or html =~ "will save when connected"
      assert view.assigns.pending_operations != []
      
      # Reconnect
      send(view.pid, {:websocket_event, :connection_restored})
      :timer.sleep(100)
      
      # Save should complete
      assert view.assigns.pending_operations == []
      html = render(view)
      assert html =~ "saved" or html =~ "✓"
    end
  end
  
  describe "state synchronization after reconnection" do
    test "synchronizes presence information", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Simulate other users
      initial_users = ["user2", "user3"]
      send(view.pid, {:presence_update, %{users: initial_users}})
      :timer.sleep(50)
      
      assert view.assigns.active_users == [user.id | initial_users]
      
      # Disconnect
      send(view.pid, {:websocket_event, :connection_lost})
      :timer.sleep(50)
      
      # Presence changes while disconnected (not received)
      # User3 leaves, User4 joins
      
      # Reconnect
      send(view.pid, {:websocket_event, :connection_restored})
      :timer.sleep(50)
      
      # Trigger presence sync
      updated_users = ["user2", "user4"]
      send(view.pid, {:presence_sync, %{users: updated_users}})
      :timer.sleep(50)
      
      # Should have updated presence
      assert view.assigns.active_users == [user.id | updated_users]
      assert "user3" not in view.assigns.active_users
      assert "user4" in view.assigns.active_users
    end
    
    test "synchronizes file changes", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Open a file
      original_content = "defmodule Original do\nend"
      send(view.pid, {:file_selected, %{path: "test.ex", content: original_content}})
      :timer.sleep(50)
      
      # Disconnect
      send(view.pid, {:websocket_event, :connection_lost})
      :timer.sleep(50)
      
      # File changed by another user while disconnected
      
      # Reconnect
      send(view.pid, {:websocket_event, :connection_restored})
      :timer.sleep(50)
      
      # Receive file update
      updated_content = "defmodule Updated do\n  # Changed by another user\nend"
      send(view.pid, {:file_sync, %{
        path: "test.ex",
        content: updated_content,
        version: 2
      }})
      :timer.sleep(50)
      
      # Should prompt about external changes
      html = render(view)
      assert html =~ "external changes" or html =~ "file modified"
      assert html =~ "reload" or html =~ "merge"
    end
    
    test "handles collaborative editing sync", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Start collaborative session
      view
      |> element("button[phx-click=\"start_collaboration\"]")
      |> render_click()
      :timer.sleep(50)
      
      # Make some edits
      send(view.pid, {:editor_operation, %{
        type: :insert,
        position: 0,
        content: "Hello ",
        version: 1
      }})
      
      # Disconnect
      send(view.pid, {:websocket_event, :connection_lost})
      :timer.sleep(50)
      
      # Make offline edit
      send(view.pid, {:editor_operation, %{
        type: :insert,
        position: 6,
        content: "World",
        version: 2
      }})
      
      # Reconnect
      send(view.pid, {:websocket_event, :connection_restored})
      :timer.sleep(50)
      
      # Sync with server
      send(view.pid, {:collaboration_sync, %{
        server_version: 5,
        missed_operations: [
          %{type: :insert, position: 0, content: "Hi ", version: 3, user_id: "other"},
          %{type: :delete, position: 3, length: 2, version: 4, user_id: "other"}
        ]
      }})
      :timer.sleep(100)
      
      # Should merge changes
      assert view.assigns.collaboration_version >= 5
      html = render(view)
      assert html =~ "merged" or html =~ "synchronized"
    end
  end
  
  describe "reconnection strategies" do
    test "implements exponential backoff", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Track reconnection delays
      reconnect_delays = []
      
      # Disconnect
      send(view.pid, {:websocket_event, :connection_lost})
      
      # Simulate multiple failed reconnection attempts
      for attempt <- 1..5 do
        send(view.pid, {:reconnection_attempt, attempt})
        
        # Get delay for next attempt
        send(view.pid, :get_reconnection_delay)
        assert_receive {:reconnection_delay, delay}
        reconnect_delays = reconnect_delays ++ [delay]
        
        # Fail the attempt
        send(view.pid, {:reconnection_failed, attempt})
        :timer.sleep(50)
      end
      
      # Verify exponential backoff
      assert length(reconnect_delays) == 5
      assert Enum.at(reconnect_delays, 0) < Enum.at(reconnect_delays, 1)
      assert Enum.at(reconnect_delays, 1) < Enum.at(reconnect_delays, 2)
      
      # Should have maximum delay cap
      assert Enum.max(reconnect_delays) <= 30_000  # 30 seconds max
    end
    
    test "provides manual reconnection option", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Disconnect
      send(view.pid, {:websocket_event, :connection_lost})
      :timer.sleep(50)
      
      # Should show manual reconnect button
      html = render(view)
      assert html =~ "Reconnect" or html =~ "Try again"
      
      # Click manual reconnect
      view
      |> element("button[phx-click=\"manual_reconnect\"]")
      |> render_click()
      
      # Should attempt immediate reconnection
      assert_receive {:reconnection_attempt, _}
    end
    
    test "handles network type changes", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Simulate network change (e.g., WiFi to cellular)
      send(view.pid, {:network_change, %{
        from: "wifi",
        to: "cellular",
        quality: "good"
      }})
      :timer.sleep(50)
      
      # Should adapt behavior
      html = render(view)
      assert html =~ "cellular" or html =~ "mobile data"
      
      # May reduce data usage
      assert view.assigns.data_saver_mode == true or
             view.assigns.reduced_updates == true
    end
  end
  
  describe "offline mode support" do
    test "enables offline mode during extended disconnection", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Disconnect
      send(view.pid, {:websocket_event, :connection_lost})
      
      # Wait for offline mode to activate
      :timer.sleep(5000)  # 5 seconds
      
      # Should enter offline mode
      html = render(view)
      assert html =~ "Offline mode" or html =~ "Working offline"
      assert view.assigns.offline_mode == true
      
      # Should still allow local operations
      assert has_element?(view, "form[phx-submit=\"send_message\"]")
      assert has_element?(view, "button[phx-click=\"save_file\"]")
    end
    
    test "syncs offline changes when reconnected", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Enter offline mode
      send(view.pid, {:websocket_event, :connection_lost})
      :timer.sleep(5000)
      
      # Make changes offline
      offline_changes = [
        {:message, "Offline message 1"},
        {:message, "Offline message 2"},
        {:file_edit, %{path: "test.ex", content: "# Edited offline"}},
        {:file_create, %{path: "new.ex", content: "# Created offline"}}
      ]
      
      for {type, data} <- offline_changes do
        case type do
          :message ->
            view
            |> form("form[phx-submit=\"send_message\"]", %{message: data})
            |> render_submit()
          :file_edit ->
            send(view.pid, {:file_operation, Map.put(data, :type, :edit)})
          :file_create ->
            send(view.pid, {:file_operation, Map.put(data, :type, :create)})
        end
        :timer.sleep(50)
      end
      
      # Verify changes are tracked
      assert length(view.assigns.offline_changes) == 4
      
      # Reconnect
      send(view.pid, {:websocket_event, :connection_restored})
      :timer.sleep(200)
      
      # Should sync all changes
      html = render(view)
      assert html =~ "Syncing" or html =~ "Uploading changes"
      
      # After sync
      :timer.sleep(500)
      assert view.assigns.offline_changes == []
      assert view.assigns.offline_mode == false
    end
  end
  
  describe "connection quality indicators" do
    test "shows connection quality metrics", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Send connection metrics
      send(view.pid, {:connection_metrics, %{
        latency: 150,  # ms
        packet_loss: 0.02,  # 2%
        bandwidth: "good"
      }})
      :timer.sleep(50)
      
      html = render(view)
      assert html =~ "150ms" or html =~ "latency"
      assert html =~ "Good connection" or html =~ "connection-good"
      
      # Poor connection
      send(view.pid, {:connection_metrics, %{
        latency: 500,
        packet_loss: 0.15,  # 15%
        bandwidth: "poor"
      }})
      :timer.sleep(50)
      
      html = render(view)
      assert html =~ "Poor connection" or html =~ "connection-poor"
      assert html =~ "High latency" or html =~ "500ms"
    end
    
    test "adapts UI based on connection quality", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Poor connection
      send(view.pid, {:connection_metrics, %{
        latency: 1000,
        packet_loss: 0.20,
        bandwidth: "very_poor"
      }})
      :timer.sleep(50)
      
      # Should reduce real-time features
      assert view.assigns.reduced_updates == true
      assert view.assigns.disable_animations == true
      
      # May disable some features
      html = render(view)
      assert html =~ "Limited functionality" or 
             html =~ "Some features disabled"
    end
  end
  
  describe "error recovery" do
    test "handles authentication errors during reconnection", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Disconnect
      send(view.pid, {:websocket_event, :connection_lost})
      :timer.sleep(50)
      
      # Session expired during disconnection
      send(view.pid, {:reconnection_error, :authentication_failed})
      :timer.sleep(50)
      
      html = render(view)
      assert html =~ "Session expired" or html =~ "Please sign in"
      assert html =~ "sign-in" or html =~ "login"
    end
    
    test "handles server errors gracefully", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Server error during operation
      send(view.pid, {:server_error, %{
        code: 503,
        message: "Service temporarily unavailable"
      }})
      :timer.sleep(50)
      
      html = render(view)
      assert html =~ "temporarily unavailable" or html =~ "Server error"
      assert html =~ "retry" or html =~ "Try again"
      
      # Should not crash the session
      assert Process.alive?(view.pid)
    end
  end
end