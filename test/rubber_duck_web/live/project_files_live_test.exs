defmodule RubberDuckWeb.Live.ProjectFilesLiveTest do
  use RubberDuckWeb.ConnCase
  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures
  
  alias RubberDuck.Workspace
  alias RubberDuck.Projects.WatcherManager
  
  setup do
    user = user_fixture()
    
    # Create a test project
    {:ok, project} = Workspace.create_project(%{
      name: "Test Project",
      description: "Test project for LiveView",
      file_access_enabled: true,
      root_path: System.tmp_dir!() |> Path.join("test_live_#{System.unique_integer([:positive])}"),
      max_file_size: 1_048_576,
      allowed_extensions: []
    }, actor: user)
    
    # Create the project directory and some test files
    File.mkdir_p!(project.root_path)
    File.mkdir_p!(Path.join(project.root_path, "lib"))
    File.write!(Path.join(project.root_path, "README.md"), "# Test Project")
    File.write!(Path.join(project.root_path, "lib/module.ex"), "defmodule Test do\nend")
    
    on_exit(fn ->
      # Stop watcher if running
      WatcherManager.stop_watcher(project.id)
      # Cleanup
      File.rm_rf(project.root_path)
    end)
    
    {:ok, user: user, project: project}
  end
  
  describe "mount/3" do
    test "redirects if user is not logged in", %{conn: conn, project: project} do
      result = live(conn, ~p"/projects/#{project.id}/files")
      assert {:error, {:redirect, %{to: "/sign-in", flash: _}}} = result
    end
    
    test "loads project files on mount", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/files")
      
      assert html =~ project.name
      assert html =~ "README.md"
      assert has_element?(view, "[phx-click=toggle_folder]")
    end
    
    test "redirects when project not found", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      invalid_id = Ecto.UUID.generate()
      
      assert {:error, {:redirect, %{to: "/", flash: %{"error" => _}}}} = 
        live(conn, ~p"/projects/#{invalid_id}/files")
    end
    
    test "tracks user presence", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Check that user is present
      assert has_element?(view, "[title=\"#{user.username}\"]")
    end
  end
  
  describe "folder operations" do
    test "toggles folder expansion", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Initially lib folder should be collapsed
      refute render(view) =~ "module.ex"
      
      # Expand lib folder
      view
      |> element("[phx-click=toggle_folder][phx-value-path=\"lib\"]")
      |> render_click()
      
      # Now module.ex should be visible
      assert render(view) =~ "module.ex"
    end
  end
  
  describe "file selection" do
    test "selects a file on click", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Click on README.md
      view
      |> element("[phx-click=select_file][phx-value-path=\"README.md\"]")
      |> render_click()
      
      # File should be highlighted
      assert has_element?(view, ".bg-blue-50")
    end
    
    test "opens file on double click", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Double click on README.md
      view
      |> element("[phx-dblclick=open_file][phx-value-path=\"README.md\"]")
      |> render_click()
      
      # Should show flash message
      assert render(view) =~ "Opening README.md..."
    end
  end
  
  describe "file operations" do
    test "shows create file modal", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Click create file button
      view
      |> element("[phx-click=create_file][phx-value-type=file]")
      |> render_click()
      
      # Modal should appear
      assert has_element?(view, "#create-modal")
      assert has_element?(view, "input[name=\"create[name]\"]")
    end
    
    test "creates a new file", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Open create file modal
      view
      |> element("[phx-click=create_file][phx-value-type=file][phx-value-parent=\"/\"]")
      |> render_click()
      
      # Submit form
      view
      |> form("form[phx-submit=confirm_create]", %{"create" => %{"name" => "new_file.ex"}})
      |> render_submit()
      
      # File should be created
      assert File.exists?(Path.join(project.root_path, "new_file.ex"))
      
      # Flash message should appear
      assert render(view) =~ "File created successfully"
    end
    
    test "shows rename file modal", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Click rename button
      view
      |> element("[phx-click=rename_file][phx-value-path=\"README.md\"]")
      |> render_click()
      
      # Modal should appear
      assert has_element?(view, "#rename-modal")
      assert has_element?(view, "input[name=\"rename[name]\"]")
    end
    
    test "shows delete confirmation modal", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Click delete button
      view
      |> element("[phx-click=delete_file][phx-value-path=\"README.md\"]")
      |> render_click()
      
      # Modal should appear
      assert has_element?(view, "#delete-modal")
      assert render(view) =~ "Are you sure you want to delete"
    end
  end
  
  describe "search functionality" do
    test "filters files based on search query", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Search for "module"
      view
      |> form("form[phx-change=search]", %{"query" => "module"})
      |> render_change()
      
      # Should show module.ex but not README.md
      refute render(view) =~ "README.md"
      assert render(view) =~ "module.ex"
    end
    
    test "highlights search matches", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Search for "READ"
      view
      |> form("form[phx-change=search]", %{"query" => "READ"})
      |> render_change()
      
      # Should highlight the match
      assert has_element?(view, "mark", "READ")
    end
  end
  
  describe "keyboard shortcuts" do
    test "creates new file with Ctrl+N", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Select a file first
      view
      |> element("[phx-click=select_file][phx-value-path=\"/\"]")
      |> render_click()
      
      # Press Ctrl+N
      view
      |> element("div[phx-window-keydown]")
      |> render_keydown(%{"key" => "n", "ctrlKey" => true, "metaKey" => false})
      
      # Create modal should appear
      assert has_element?(view, "#create-modal")
    end
  end
  
  describe "real-time updates" do
    test "updates file tree when files change", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Simulate file change event
      send(view.pid, %{
        event: :file_changed,
        changes: [%{type: :created, path: "new_from_event.txt"}]
      })
      
      # Force re-render
      render(view)
      
      # New file should appear in the tree
      assert render(view) =~ "new_from_event.txt"
    end
    
    test "handles presence updates", %{conn: conn, project: project, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files")
      
      # Simulate presence diff
      send(view.pid, %Phoenix.Socket.Broadcast{
        event: "presence_diff",
        payload: %{
          joins: %{
            "user123" => %{metas: [%{username: "another_user", joined_at: DateTime.utc_now()}]}
          },
          leaves: %{}
        }
      })
      
      # Force re-render
      render(view)
      
      # Another user should be shown as present
      assert has_element?(view, "[title=\"another_user\"]")
    end
  end
  
  describe "performance mode" do
    test "enables performance mode for large trees", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      
      # Create project with many files
      {:ok, large_project} = Workspace.create_project(%{
        name: "Large Project",
        file_access_enabled: true,
        root_path: System.tmp_dir!() |> Path.join("large_#{System.unique_integer([:positive])}"),
        allowed_extensions: []
      }, actor: user)
      
      File.mkdir_p!(large_project.root_path)
      
      # Create many files
      for i <- 1..1100 do
        File.write!(Path.join(large_project.root_path, "file#{i}.txt"), "content")
      end
      
      {:ok, _view, html} = live(conn, ~p"/projects/#{large_project.id}/files")
      
      # Should show performance mode warning
      assert html =~ "Performance mode enabled"
      
      # Cleanup
      File.rm_rf(large_project.root_path)
    end
  end
end