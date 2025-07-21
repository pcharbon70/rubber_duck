defmodule RubberDuckWeb.Integration.ResponsiveDesignTest do
  @moduledoc """
  Integration tests for responsive design breakpoints.
  
  Tests the LiveView interface's adaptability across different
  screen sizes and device types.
  """
  
  use RubberDuckWeb.ConnCase
  
  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures
  
  @moduletag :integration
  
  # Define common breakpoints
  @breakpoints %{
    mobile: %{width: 375, height: 812, name: "iPhone X"},
    tablet: %{width: 768, height: 1024, name: "iPad"},
    laptop: %{width: 1366, height: 768, name: "Laptop"},
    desktop: %{width: 1920, height: 1080, name: "Desktop"},
    ultrawide: %{width: 3440, height: 1440, name: "Ultrawide"}
  }
  
  setup do
    user = user_fixture()
    project = %{
      id: "responsive-test-#{System.unique_integer()}",
      name: "Responsive Test Project"
    }
    
    %{user: user, project: project}
  end
  
  describe "mobile layout (< 768px)" do
    test "shows single panel layout on mobile", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      
      # Simulate mobile viewport
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session", 
        connect_params: %{"viewport" => @breakpoints.mobile})
      
      # Should show mobile menu button
      assert html =~ "mobile-menu" or html =~ "hamburger"
      
      # Panels should be hidden by default except main
      refute html =~ "file-tree-visible"
      assert html =~ "editor" or html =~ "main"
      refute html =~ "chat-panel-visible"
      
      # Should have bottom navigation
      assert html =~ "bottom-nav" or html =~ "mobile-nav"
    end
    
    test "mobile panel switching", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.mobile})
      
      # Open file tree
      view
      |> element("button[phx-click=\"mobile_panel\"][phx-value-panel=\"files\"]")
      |> render_click()
      
      assert render(view) =~ "Files"
      refute render(view) =~ "editor-visible"
      
      # Switch to chat
      view
      |> element("button[phx-click=\"mobile_panel\"][phx-value-panel=\"chat\"]")
      |> render_click()
      
      assert render(view) =~ "AI Assistant"
      refute render(view) =~ "Files"
      
      # Return to editor
      view
      |> element("button[phx-click=\"mobile_panel\"][phx-value-panel=\"editor\"]")
      |> render_click()
      
      assert render(view) =~ "editor"
      refute render(view) =~ "AI Assistant"
    end
    
    test "mobile gestures support", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.mobile})
      
      # Swipe right to show file tree
      send(view.pid, {:gesture, %{type: "swipe", direction: "right", from: "edge"}})
      :timer.sleep(50)
      
      assert render(view) =~ "Files"
      
      # Swipe left to hide
      send(view.pid, {:gesture, %{type: "swipe", direction: "left"}})
      :timer.sleep(50)
      
      refute render(view) =~ "file-tree-visible"
    end
    
    test "mobile-optimized chat interface", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.mobile})
      
      # Open chat
      view
      |> element("button[phx-click=\"mobile_panel\"][phx-value-panel=\"chat\"]")
      |> render_click()
      
      html = render(view)
      
      # Chat should be full screen
      assert html =~ "chat-fullscreen" or html =~ "mobile-chat"
      
      # Input should be at bottom with mobile keyboard consideration
      assert html =~ "chat-input-mobile" or html =~ "bottom-input"
      
      # Should have quick actions
      assert html =~ "quick-action" or html =~ "suggestion-chip"
    end
  end
  
  describe "tablet layout (768px - 1024px)" do
    test "shows split layout on tablet", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.tablet})
      
      # Should show two panels side by side
      assert html =~ "tablet-layout" or html =~ "split-view"
      
      # File tree should be collapsible sidebar
      assert html =~ "sidebar-collapsible"
      
      # Editor and chat can share space
      assert html =~ "main-content"
    end
    
    test "tablet portrait vs landscape", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      
      # Portrait orientation
      {:ok, view_portrait, html_portrait} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => %{width: 768, height: 1024}})
      
      # Should prioritize vertical space
      assert html_portrait =~ "portrait" or html_portrait =~ "vertical-layout"
      
      # Landscape orientation
      {:ok, view_landscape, html_landscape} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => %{width: 1024, height: 768}})
      
      # Should use horizontal space better
      assert html_landscape =~ "landscape" or html_landscape =~ "horizontal-layout"
    end
    
    test "touch-optimized controls on tablet", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.tablet, "touch" => true})
      
      # Larger touch targets
      assert html =~ "touch-target" or html =~ "touch-optimized"
      
      # Touch-friendly spacing
      assert html =~ "spacing-touch" or html =~ "pad-touch"
      
      # Context menus on long press
      send(view.pid, {:gesture, %{type: "longpress", target: "file-item"}})
      :timer.sleep(50)
      
      assert render(view) =~ "context-menu" or render(view) =~ "actions"
    end
  end
  
  describe "desktop layouts" do
    test "shows full multi-panel layout on desktop", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.desktop})
      
      # All panels visible by default
      assert html =~ "Files"
      assert html =~ "editor" or html =~ "main"
      assert html =~ "AI Assistant"
      
      # Should have resizable panels
      assert html =~ "resize-handle" or html =~ "splitter"
    end
    
    test "supports multiple editor splits on large screens", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.desktop})
      
      # Open multiple files
      send(view.pid, {:file_selected, %{path: "file1.ex", content: "content1"}})
      
      # Split editor
      view
      |> element("button[phx-click=\"split_editor\"][phx-value-direction=\"vertical\"]")
      |> render_click()
      
      send(view.pid, {:file_selected, %{path: "file2.ex", content: "content2", pane: 2}})
      
      html = render(view)
      assert html =~ "file1.ex"
      assert html =~ "file2.ex"
      assert html =~ "editor-split" or html =~ "split-pane"
    end
    
    test "ultrawide optimizations", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.ultrawide})
      
      # Should use additional space wisely
      assert html =~ "ultrawide" or html =~ "wide-layout"
      
      # May show additional panels
      assert html =~ "outline" or html =~ "minimap"
      assert html =~ "terminal" or html =~ "console"
      
      # Multiple editor columns
      assert html =~ "three-column" or html =~ "multi-editor"
    end
  end
  
  describe "dynamic layout adjustments" do
    test "responds to window resize", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.desktop})
      
      # Start with desktop layout
      assert render(view) =~ "Files"
      assert render(view) =~ "AI Assistant"
      
      # Resize to tablet
      send(view.pid, {:viewport_changed, @breakpoints.tablet})
      :timer.sleep(50)
      
      html = render(view)
      assert html =~ "tablet-layout" or html =~ "medium-screen"
      
      # Resize to mobile
      send(view.pid, {:viewport_changed, @breakpoints.mobile})
      :timer.sleep(50)
      
      html = render(view)
      assert html =~ "mobile" or html =~ "small-screen"
      refute html =~ "three-panel"  # Should not show all panels
    end
    
    test "preserves state during layout changes", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.desktop})
      
      # Add some state
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Test message"})
      |> render_submit()
      
      send(view.pid, {:file_selected, %{path: "test.ex", content: "content"}})
      
      # Store state
      messages_before = view.assigns.chat_messages
      file_before = view.assigns.current_file
      
      # Change layout multiple times
      send(view.pid, {:viewport_changed, @breakpoints.mobile})
      :timer.sleep(50)
      send(view.pid, {:viewport_changed, @breakpoints.desktop})
      :timer.sleep(50)
      
      # Verify state preserved
      assert view.assigns.chat_messages == messages_before
      assert view.assigns.current_file == file_before
    end
  end
  
  describe "responsive typography and spacing" do
    test "adjusts font sizes for different screens", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      
      # Mobile
      {:ok, view_mobile, html_mobile} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.mobile})
      
      assert html_mobile =~ "text-sm" or html_mobile =~ "mobile-text"
      
      # Desktop
      {:ok, view_desktop, html_desktop} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.desktop})
      
      assert html_desktop =~ "text-base" or html_desktop =~ "desktop-text"
    end
    
    test "responsive spacing and padding", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      
      # Mobile - tighter spacing
      {:ok, view_mobile, html_mobile} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.mobile})
      
      assert html_mobile =~ "p-2" or html_mobile =~ "compact"
      
      # Desktop - more generous spacing
      {:ok, view_desktop, html_desktop} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.desktop})
      
      assert html_desktop =~ "p-4" or html_desktop =~ "spacious"
    end
  end
  
  describe "responsive performance" do
    test "lazy loads panels on mobile", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.mobile})
      
      # Initially only editor loaded
      assert html =~ "editor"
      refute html =~ "file-tree-loaded"
      
      # Open file tree - should load dynamically
      view
      |> element("button[phx-click=\"mobile_panel\"][phx-value-panel=\"files\"]")
      |> render_click()
      
      :timer.sleep(100)
      
      assert render(view) =~ "file-tree-loaded"
    end
    
    test "reduces updates on smaller screens", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"viewport" => @breakpoints.mobile})
      
      # Track updates
      send(view.pid, {:start_tracking_updates})
      
      # Simulate activity that would cause updates
      for i <- 1..10 do
        send(view.pid, {:cursor_position, %{line: i, column: 1, user_id: "other"}})
        :timer.sleep(10)
      end
      
      # Mobile should throttle/batch updates
      send(view.pid, {:get_update_count})
      assert_receive {:update_count, count}
      assert count < 10  # Should batch updates
    end
  end
end