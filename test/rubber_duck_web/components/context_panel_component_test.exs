defmodule RubberDuckWeb.Components.ContextPanelComponentTest do
  use RubberDuckWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  
  alias RubberDuckWeb.Components.ContextPanelComponent
  alias RubberDuck.Analysis.{CodeAnalyzer, MetricsCollector}
  
  describe "mount/1" do
    test "initializes with default state" do
      {:ok, socket} = ContextPanelComponent.mount(%{})
      
      assert socket.assigns.current_file == nil
      assert socket.assigns.file_analysis == nil
      assert socket.assigns.symbol_outline == []
      assert socket.assigns.related_files == []
      assert socket.assigns.active_tab == :context
      assert socket.assigns.show_search == false
      assert socket.assigns.loading == false
    end
  end
  
  describe "update/2" do
    setup do
      {:ok, socket} = ContextPanelComponent.mount(%{})
      {:ok, socket: socket}
    end
    
    test "updates assigns", %{socket: socket} do
      assigns = %{
        id: "context-panel",
        project_id: "test-project",
        current_file: "lib/example.ex"
      }
      
      {:ok, updated_socket} = ContextPanelComponent.update(assigns, socket)
      
      assert updated_socket.assigns.id == "context-panel"
      assert updated_socket.assigns.project_id == "test-project"
      assert updated_socket.assigns.current_file == "lib/example.ex"
    end
  end
  
  describe "tab switching" do
    setup do
      {:ok, view, _html} = live_isolated(RubberDuckWeb.ConnCase.build_conn(), ContextPanelComponent, 
        id: "context-panel",
        project_id: "test-project"
      )
      {:ok, view: view}
    end
    
    test "switches between tabs", %{view: view} do
      # Start on context tab
      assert view |> element("[phx-value-tab=\"context\"]") |> has_element?()
      
      # Switch to metrics tab
      view |> element("[phx-value-tab=\"metrics\"]") |> render_click()
      assert has_element?(view, ".metrics-content")
      
      # Switch to status tab
      view |> element("[phx-value-tab=\"status\"]") |> render_click()
      assert has_element?(view, ".status-content")
      
      # Switch to actions tab
      view |> element("[phx-value-tab=\"actions\"]") |> render_click()
      assert has_element?(view, ".actions-content")
    end
  end
  
  describe "search functionality" do
    setup do
      {:ok, view, _html} = live_isolated(RubberDuckWeb.ConnCase.build_conn(), ContextPanelComponent,
        id: "context-panel",
        project_id: "test-project"
      )
      {:ok, view: view}
    end
    
    test "toggles search", %{view: view} do
      # Initially hidden
      refute has_element?(view, "input[name=\"search\"]")
      
      # Toggle search on
      view |> element("button[phx-click=\"toggle_search\"]") |> render_click()
      assert has_element?(view, "input[name=\"search\"]")
      
      # Toggle search off
      view |> element("button[phx-click=\"toggle_search\"]") |> render_click()
      refute has_element?(view, "input[name=\"search\"]")
    end
    
    test "performs search", %{view: view} do
      # Enable search
      view |> element("button[phx-click=\"toggle_search\"]") |> render_click()
      
      # Type search query
      view
      |> element("input[name=\"search\"]")
      |> render_change(%{"search" => "test_function"})
      
      # Should trigger search (mocked in component)
      # In real implementation, would show search results
    end
    
    test "clears search", %{view: view} do
      # Enable search and type query
      view |> element("button[phx-click=\"toggle_search\"]") |> render_click()
      view
      |> element("input[name=\"search\"]")
      |> render_change(%{"search" => "test_query"})
      
      # Clear search
      view |> element("button[phx-click=\"clear_search\"]") |> render_click()
      
      # Search input should be empty
      assert view |> element("input[name=\"search\"]") |> render() =~ "value=\"\""
    end
  end
  
  describe "context tab" do
    setup do
      {:ok, view, _html} = live_isolated(RubberDuckWeb.ConnCase.build_conn(), ContextPanelComponent,
        id: "context-panel",
        project_id: "test-project",
        current_file: "lib/example.ex",
        file_analysis: %{
          lines: 100,
          function_count: 5,
          complexity: 10,
          symbols: [
            %{type: :module, name: "Example", line: 1},
            %{type: :function, name: "hello", line: 5}
          ]
        },
        symbol_outline: [
          %{type: :module, name: "Example", line: 1},
          %{type: :function, name: "hello", line: 5}
        ],
        related_files: [
          %{path: "test/example_test.exs", relationship: :test},
          %{path: "lib/example_helper.ex", relationship: :similar}
        ]
      )
      {:ok, view: view}
    end
    
    test "displays current file info", %{view: view} do
      html = render(view)
      
      assert html =~ "example.ex"
      assert html =~ "Lines: 100"
      assert html =~ "Functions: 5"
      assert html =~ "Complexity: 10"
    end
    
    test "displays symbol outline", %{view: view} do
      html = render(view)
      
      assert html =~ "Example"
      assert html =~ "hello"
    end
    
    test "clicking symbol triggers goto", %{view: view} do
      view |> element("button[phx-click=\"goto_symbol\"][phx-value-line=\"5\"]") |> render_click()
      
      # This would send a message to parent LiveView
      # Test by checking if message was sent
    end
    
    test "displays related files", %{view: view} do
      html = render(view)
      
      assert html =~ "example_test.exs"
      assert html =~ "(test)"
      assert html =~ "example_helper.ex"
      assert html =~ "(similar)"
    end
  end
  
  describe "metrics tab" do
    setup do
      {:ok, view, _html} = live_isolated(RubberDuckWeb.ConnCase.build_conn(), ContextPanelComponent,
        id: "context-panel",
        project_id: "test-project",
        code_metrics: %{
          complexity: %{
            cyclomatic: 8,
            cognitive: 12
          },
          test_coverage: %{
            lines: 85,
            functions: 90,
            branches: 75,
            uncovered_lines: 20
          },
          performance: %{
            avg_response_time: 45,
            memory_usage: 52_428_800,
            query_count: 5
          },
          security_score: 88,
          security_issues: %{
            critical: 0,
            high: 1,
            medium: 3,
            low: 5
          }
        }
      )
      
      # Switch to metrics tab
      view |> element("[phx-value-tab=\"metrics\"]") |> render_click()
      
      {:ok, view: view}
    end
    
    test "displays complexity metrics", %{view: view} do
      html = render(view)
      
      assert html =~ "Cyclomatic"
      assert html =~ "8"
      assert html =~ "Cognitive"
      assert html =~ "12"
      assert html =~ "Good complexity levels"
    end
    
    test "displays test coverage", %{view: view} do
      html = render(view)
      
      assert html =~ "Line Coverage"
      assert html =~ "85%"
      assert html =~ "Function Coverage"
      assert html =~ "90%"
      assert html =~ "20 uncovered lines"
    end
    
    test "displays performance metrics", %{view: view} do
      html = render(view)
      
      assert html =~ "Avg Response Time"
      assert html =~ "45ms"
      assert html =~ "Memory Usage"
      assert html =~ "50.0 MB"
      assert html =~ "SQL Queries"
      assert html =~ "5"
    end
    
    test "displays security score", %{view: view} do
      html = render(view)
      
      assert html =~ "B"  # Security grade for score 88
      assert html =~ "88/100"
      assert html =~ "0 critical"
      assert html =~ "1 high"
      assert html =~ "3 medium"
    end
  end
  
  describe "status tab" do
    setup do
      {:ok, view, _html} = live_isolated(RubberDuckWeb.ConnCase.build_conn(), ContextPanelComponent,
        id: "context-panel",
        project_id: "test-project",
        llm_status: %{
          provider: "openai",
          model: "gpt-4",
          available: true,
          tokens_used: 50_000,
          tokens_limit: 100_000
        },
        analysis_queue: %{
          pending: 3,
          processing: 1,
          completed: 10
        },
        system_resources: %{
          cpu_usage: 45,
          memory_usage: 62,
          disk_usage: 78
        },
        error_count: 2,
        warning_count: 5
      )
      
      # Switch to status tab
      view |> element("[phx-value-tab=\"status\"]") |> render_click()
      
      {:ok, view: view}
    end
    
    test "displays LLM status", %{view: view} do
      html = render(view)
      
      assert html =~ "openai"
      assert html =~ "gpt-4"
      assert html =~ "✅ Available"
      assert html =~ "50K / 100K"
    end
    
    test "displays analysis queue", %{view: view} do
      html = render(view)
      
      assert html =~ "🔄 Processing"
      assert html =~ "1"
      assert html =~ "⏳ Pending"
      assert html =~ "3"
      assert html =~ "✅ Completed"
      assert html =~ "10"
    end
    
    test "displays system resources", %{view: view} do
      html = render(view)
      
      assert html =~ "CPU Usage"
      assert html =~ "45%"
      assert html =~ "Memory"
      assert html =~ "62%"
      assert html =~ "Disk"
      assert html =~ "78%"
    end
    
    test "displays error and warning counts", %{view: view} do
      html = render(view)
      
      assert html =~ "2"  # Error count
      assert html =~ "5"  # Warning count
      assert html =~ "Errors"
      assert html =~ "Warnings"
    end
  end
  
  describe "actions tab" do
    setup do
      {:ok, view, _html} = live_isolated(RubberDuckWeb.ConnCase.build_conn(), ContextPanelComponent,
        id: "context-panel",
        project_id: "test-project",
        current_file: "lib/example.ex"
      )
      
      # Switch to actions tab
      view |> element("[phx-value-tab=\"actions\"]") |> render_click()
      
      {:ok, view: view}
    end
    
    test "displays all action buttons", %{view: view} do
      html = render(view)
      
      assert html =~ "Run Full Analysis"
      assert html =~ "Generate Tests"
      assert html =~ "Suggest Refactoring"
      assert html =~ "Generate Documentation"
      assert html =~ "Security Scan"
      assert html =~ "Optimize Performance"
    end
    
    test "action buttons enabled when file selected", %{view: view} do
      # Buttons should not be disabled since current_file is set
      refute view |> element("button[phx-click=\"run_analysis\"][disabled]") |> has_element?()
      refute view |> element("button[phx-click=\"generate_tests\"][disabled]") |> has_element?()
    end
    
    test "clicking action triggers event", %{view: view} do
      view |> element("button[phx-click=\"run_analysis\"]") |> render_click()
      
      # This would send a message to parent LiveView
      # In real test, would verify message sent
    end
    
    test "displays export options", %{view: view} do
      html = render(view)
      
      assert html =~ "Export Metrics Report"
      assert html =~ "Export Analysis Results"
    end
  end
  
  describe "notifications" do
    setup do
      {:ok, view, _html} = live_isolated(RubberDuckWeb.ConnCase.build_conn(), ContextPanelComponent,
        id: "context-panel",
        project_id: "test-project"
      )
      {:ok, view: view}
    end
    
    test "displays notifications", %{view: view} do
      # Add notification via public function
      ContextPanelComponent.add_notification("context-panel", :info, "Test notification")
      
      html = render(view)
      assert html =~ "Test notification"
    end
    
    test "dismisses notifications", %{view: view} do
      # Add notification
      ContextPanelComponent.add_notification("context-panel", :error, "Error message")
      
      # Find and dismiss notification
      view 
      |> element("button[phx-click=\"dismiss_notification\"]")
      |> render_click()
      
      # Notification should be gone
      refute render(view) =~ "Error message"
    end
  end
  
  describe "public functions" do
    test "update_current_file/2" do
      # This tests the public API
      assert :ok = ContextPanelComponent.update_current_file("context-panel", "lib/new_file.ex")
    end
    
    test "update_metrics/2" do
      metrics = %{
        complexity: %{cyclomatic: 5, cognitive: 8},
        test_coverage: %{lines: 90, functions: 95}
      }
      
      assert :ok = ContextPanelComponent.update_metrics("context-panel", metrics)
    end
    
    test "update_llm_status/2" do
      status = %{
        provider: "anthropic",
        model: "claude-3",
        available: true
      }
      
      assert :ok = ContextPanelComponent.update_llm_status("context-panel", status)
    end
    
    test "add_notification/3" do
      assert :ok = ContextPanelComponent.add_notification("context-panel", :success, "Success!")
    end
  end
  
  describe "UI helpers" do
    test "formats numbers correctly" do
      {:ok, view, _html} = live_isolated(RubberDuckWeb.ConnCase.build_conn(), ContextPanelComponent,
        id: "context-panel",
        llm_status: %{
          provider: "test",
          model: "test",
          available: true,
          tokens_used: 1_500_000,
          tokens_limit: 10_000_000
        }
      )
      
      view |> element("[phx-value-tab=\"status\"]") |> render_click()
      html = render(view)
      
      assert html =~ "1.5M"  # Formatted tokens_used
      assert html =~ "10.0M" # Formatted tokens_limit
    end
    
    test "formats bytes correctly" do
      {:ok, view, _html} = live_isolated(RubberDuckWeb.ConnCase.build_conn(), ContextPanelComponent,
        id: "context-panel",
        code_metrics: %{
          performance: %{
            avg_response_time: 100,
            memory_usage: 1_073_741_824,  # 1 GB
            query_count: 10
          }
        }
      )
      
      view |> element("[phx-value-tab=\"metrics\"]") |> render_click()
      html = render(view)
      
      assert html =~ "1.0 GB"
    end
  end
end