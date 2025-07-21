defmodule RubberDuckWeb.Components.MonacoEditorComponentTest do
  use RubberDuckWeb.ConnCase, async: true
  
  import Phoenix.LiveViewTest
  
  alias RubberDuckWeb.Components.MonacoEditorComponent
  
  # Test LiveView wrapper for the component
  defmodule TestLive do
    use Phoenix.LiveView
    
    def render(assigns) do
      ~H"""
      <div>
        <.live_component
          module={MonacoEditorComponent}
          id="test-editor"
          project_id={@project_id}
          file_path={@file_path}
          current_user_id={@current_user_id}
        />
      </div>
      """
    end
    
    def mount(_params, _session, socket) do
      {:ok,
       socket
       |> assign(:project_id, "test-project")
       |> assign(:file_path, nil)
       |> assign(:current_user_id, "test-user")
       |> assign(:content_loaded, false)}
    end
    
    def handle_info({:load_file_content, component_id, file_path}, socket) do
      # Simulate file loading
      content = 
        case file_path do
          "test.ex" -> "defmodule Test do\n  def hello, do: :world\nend"
          "test.js" -> "console.log('Hello, world!');"
          _ -> "# Unknown file"
        end
      
      language = 
        case Path.extname(file_path) do
          ".ex" -> "elixir"
          ".js" -> "javascript"
          _ -> "plaintext"
        end
      
      MonacoEditorComponent.update_content(component_id, content, language)
      
      {:noreply, assign(socket, :content_loaded, true)}
    end
    
    def handle_info({:auto_save, _component_id}, socket) do
      # Track auto-save for testing
      {:noreply, assign(socket, :auto_saved, true)}
    end
  end
  
  describe "rendering" do
    test "renders editor with header and status bar", %{conn: conn} do
      {:ok, view, html} = live_isolated(conn, TestLive)
      
      assert html =~ "monaco-editor-component"
      assert html =~ "editor-header"
      assert html =~ "editor-status-bar"
    end
    
    test "shows loading state initially", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, TestLive)
      
      assert html =~ "animate-spin"
    end
    
    test "displays file path when provided", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Update with file path
      send_update(MonacoEditorComponent, 
        id: "test-editor",
        file_path: "lib/test.ex"
      )
      
      assert render(view) =~ ".../lib/test.ex"
    end
  end
  
  describe "language detection" do
    test "detects Elixir from .ex extension", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      send_update(MonacoEditorComponent, 
        id: "test-editor",
        file_path: "test.ex"
      )
      
      assert render(view) =~ "elixir"
    end
    
    test "detects JavaScript from .js extension", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      send_update(MonacoEditorComponent, 
        id: "test-editor",
        file_path: "test.js"
      )
      
      assert render(view) =~ "javascript"
    end
    
    test "defaults to plaintext for unknown extensions", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      send_update(MonacoEditorComponent, 
        id: "test-editor",
        file_path: "test.unknown"
      )
      
      assert render(view) =~ "plaintext"
    end
  end
  
  describe "editor actions" do
    test "format document button is present", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      assert element(view, "[phx-click=\"format_document\"]")
             |> render() =~ "Format Document"
    end
    
    test "AI assistant toggle is present", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      assert element(view, "[phx-click=\"toggle_ai_assistant\"]")
             |> render() =~ "Toggle AI Assistant"
    end
    
    test "settings button is present", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      assert element(view, "[phx-click=\"open_settings\"]")
             |> render() =~ "Editor Settings"
    end
  end
  
  describe "file operations" do
    test "loads file content when file path is set", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Update with file path
      send_update(MonacoEditorComponent, 
        id: "test-editor",
        file_path: "test.ex"
      )
      
      # Should request file load
      assert_receive {:load_file_content, "test-editor", "test.ex"}
    end
  end
  
  describe "editor state" do
    test "shows modified indicator when content changes", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Mark as modified
      send_update(MonacoEditorComponent, 
        id: "test-editor",
        modified: true
      )
      
      assert render(view) =~ "●"
    end
    
    test "displays cursor position when available", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Update cursor position
      send_update(MonacoEditorComponent, 
        id: "test-editor",
        cursor_position: %{line: 10, column: 5}
      )
      
      assert render(view) =~ "Line 10"
      assert render(view) =~ "Column 5"
    end
  end
  
  describe "collaboration features" do
    test "displays collaborators when present", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Add collaborators
      send_update(MonacoEditorComponent, 
        id: "test-editor",
        collaborators: %{
          "user1" => %{name: "Alice", color: "#ff0000"},
          "user2" => %{name: "Bob", color: "#00ff00"}
        }
      )
      
      html = render(view)
      assert html =~ "A" # First letter of Alice
      assert html =~ "B" # First letter of Bob
    end
  end
  
  describe "AI features" do
    test "toggles AI suggestions panel", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      
      # Initially hidden
      refute render(view) =~ "AI Suggestions"
      
      # Toggle on
      view
      |> element("[phx-click=\"toggle_ai_assistant\"]")
      |> render_click()
      
      # Update component to show panel
      send_update(MonacoEditorComponent, 
        id: "test-editor",
        show_ai_suggestions: true
      )
      
      assert render(view) =~ "AI Suggestions"
    end
  end
end