defmodule RubberDuckWeb.Components.FileTreeComponentTest do
  use RubberDuckWeb.ConnCase, async: true
  
  import Phoenix.LiveViewTest
  
  alias RubberDuckWeb.Components.FileTreeComponent
  
  # Since LiveComponents can't be tested with live_isolated,
  # we need to test through a parent LiveView
  defmodule TestLive do
    use Phoenix.LiveView
    
    def render(assigns) do
      ~H"""
      <div>
        <.live_component
          module={FileTreeComponent}
          id="test-file-tree"
          project_id={@project_id}
          current_file={@current_file}
        />
      </div>
      """
    end
    
    def mount(_params, _session, socket) do
      {:ok,
       socket
       |> assign(:project_id, "test-project")
       |> assign(:current_file, nil)}
    end
    
    def handle_info({:file_selected, file_path}, socket) do
      {:noreply, assign(socket, :selected_file, file_path)}
    end
    
    def handle_info({:load_file_tree, component_id, _show_hidden}, socket) do
      # Return mock data for testing
      mock_tree = [
        %{
          path: "lib",
          name: "lib",
          type: :directory,
          children: [
            %{
              path: "lib/test.ex",
              name: "test.ex",
              type: :file,
              size: 1234,
              modified: DateTime.utc_now()
            }
          ]
        },
        %{
          path: "README.md",
          name: "README.md",
          type: :file,
          size: 2048,
          modified: DateTime.utc_now()
        }
      ]
      
      FileTreeComponent.update_tree_data(component_id, mock_tree, %{})
      
      {:noreply, socket}
    end
  end
  
  describe "rendering" do
    test "renders file tree structure", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Wait for tree to load
      assert render(view) =~ "Files"
      
      # Should show directories and files
      assert render(view) =~ "lib"
      assert render(view) =~ "README.md"
    end
    
    test "shows loading state initially", %{conn: conn} do
      {:ok, view, html} = live_isolated(conn, TestLive)
      
      # Should show loading spinner initially
      assert html =~ "animate-spin"
    end
  end
  
  describe "file operations" do
    test "expands and collapses directories", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Click on directory to expand
      view
      |> element("[phx-click=\"toggle_node\"][phx-value-path=\"lib\"]")
      |> render_click()
      
      # Should show children
      assert render(view) =~ "test.ex"
      
      # Click again to collapse
      view
      |> element("[phx-click=\"toggle_node\"][phx-value-path=\"lib\"]")
      |> render_click()
      
      # Children should be hidden (but lib should still be visible)
      refute render(view) =~ "test.ex"
      assert render(view) =~ "lib"
    end
    
    test "selects files on click", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Select a file
      view
      |> element("[phx-click=\"select_file\"][phx-value-path=\"README.md\"]")
      |> render_click()
      
      # Should have selection styling
      assert render(view) =~ "bg-blue-100"
    end
  end
  
  describe "search functionality" do
    test "toggles search input", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Initially no search input
      refute render(view) =~ "Search files..."
      
      # Click search button
      view
      |> element("[phx-click=\"toggle_search\"]")
      |> render_click()
      
      # Should show search input
      assert render(view) =~ "Search files..."
    end
    
    test "filters files based on search query", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Toggle search
      view
      |> element("[phx-click=\"toggle_search\"]")
      |> render_click()
      
      # Search for "test"
      view
      |> form("[phx-change=\"search_files\"]", %{search: "test"})
      |> render_change()
      
      # Should show matching files
      assert render(view) =~ "test.ex"
      # Should hide non-matching files
      refute render(view) =~ "README.md"
    end
  end
  
  describe "keyboard navigation" do
    test "handles arrow key navigation", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Simulate arrow key press
      view
      |> element("[phx-keydown=\"tree_keydown\"]")
      |> render_keydown(%{key: "ArrowDown"})
      
      # Should handle without error
      assert render(view)
    end
  end
  
  describe "hidden files" do
    test "toggles hidden file visibility", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Click toggle hidden button
      view
      |> element("[phx-click=\"toggle_hidden\"]")
      |> render_click()
      
      # Should update the button title
      assert render(view) =~ "Hide hidden files"
    end
  end
end