defmodule RubberDuckWeb.Integration.ErrorRecoveryTest do
  @moduledoc """
  Integration tests for error recovery mechanisms.

  Tests the LiveView's ability to handle errors gracefully,
  recover from failures, and maintain a stable user experience.
  """

  use RubberDuckWeb.ConnCase

  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures
  alias Phoenix.PubSub

  @moduletag :integration

  setup do
    user = user_fixture()

    project = %{
      id: "error-test-#{System.unique_integer()}",
      name: "Error Recovery Test Project"
    }

    %{user: user, project: project}
  end

  describe "network error recovery" do
    test "handles API request failures gracefully", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Simulate API failure for file save
      send(view.pid, {:mock_api_error, :file_save})

      # Try to save file
      send(
        view.pid,
        {:file_selected,
         %{
           path: "test.ex",
           content: "defmodule Test do\nend"
         }}
      )

      view
      |> element("button[phx-click=\"save_file\"]")
      |> render_click()

      :timer.sleep(100)

      html = render(view)
      # Should show error message
      assert html =~ "Failed to save" or html =~ "Error saving file"
      assert html =~ "Retry" or html =~ "Try again"

      # File should be marked as unsaved
      assert view.assigns.current_file.dirty == true
      assert html =~ "unsaved changes" or html =~ "modified"

      # Retry mechanism
      view
      |> element("button[phx-click=\"retry_save\"]")
      |> render_click()

      :timer.sleep(100)

      # Should attempt again
      assert view.assigns.retry_count == 1
    end

    test "implements exponential backoff for retries", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Persistent failure
      send(view.pid, {:mock_api_error, :persistent})

      # Trigger operation that will fail
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Test"})
      |> render_submit()

      # Track retry attempts
      retry_delays = []

      for i <- 1..4 do
        :timer.sleep(100)
        send(view.pid, :get_retry_info)
        assert_receive {:retry_info, info}
        retry_delays = retry_delays ++ [info.next_retry_in]

        # Manually trigger retry
        send(view.pid, :retry_now)
      end

      # Verify exponential backoff
      assert Enum.at(retry_delays, 0) < Enum.at(retry_delays, 1)
      assert Enum.at(retry_delays, 1) < Enum.at(retry_delays, 2)
      assert Enum.at(retry_delays, 2) < Enum.at(retry_delays, 3)

      # Should eventually give up
      assert view.assigns.retry_count <= 5
      assert view.assigns.retry_status == :max_retries_reached
    end

    test "handles timeout errors", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Simulate slow response
      # 10 second delay
      send(view.pid, {:mock_delay, :ai_response, 10_000})

      # Send AI request
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Explain this code"})
      |> render_submit()

      # Should show loading state
      html = render(view)
      assert html =~ "Thinking" or html =~ "Loading" or html =~ "spinner"

      # Wait for timeout (assuming 5 second timeout)
      :timer.sleep(6000)

      html = render(view)
      # Should show timeout error
      assert html =~ "Request timed out" or html =~ "took too long"
      assert html =~ "Try again" or html =~ "Retry"

      # Should not block other operations
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Quick test"})
      |> render_submit()

      assert length(view.assigns.chat_messages) > 0
    end
  end

  describe "file system error recovery" do
    test "handles file read errors", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Try to open file that becomes unreadable
      send(
        view.pid,
        {:file_error,
         %{
           path: "lib/corrupted.ex",
           error: :permission_denied
         }}
      )

      html = render(view)
      assert html =~ "Permission denied" or html =~ "Cannot read file"
      assert html =~ "lib/corrupted.ex"

      # Should offer alternatives
      assert html =~ "Check file permissions" or html =~ "Contact administrator"

      # Should not crash the session
      assert Process.alive?(view.pid)

      # Can still use other files
      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/working.ex",
           content: "# This works"
         }}
      )

      assert view.assigns.current_file.path == "lib/working.ex"
    end

    test "handles file write conflicts", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Edit a file
      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/conflict.ex",
           content: "original content",
           version: 1
         }}
      )

      send(
        view.pid,
        {:editor_content_changed,
         %{
           content: "my changes"
         }}
      )

      # Simulate external change
      send(
        view.pid,
        {:file_external_change,
         %{
           path: "lib/conflict.ex",
           content: "someone else's changes",
           version: 2
         }}
      )

      # Try to save
      view
      |> element("button[phx-click=\"save_file\"]")
      |> render_click()

      html = render(view)
      # Should detect conflict
      assert html =~ "File has been modified" or html =~ "Conflict detected"

      # Should offer resolution options
      assert has_element?(view, "button", "Keep mine")
      assert has_element?(view, "button", "Use theirs")
      assert has_element?(view, "button", "Merge")

      # Choose merge
      view
      |> element("button[phx-click=\"merge_changes\"]")
      |> render_click()

      # Should show merge UI
      assert render(view) =~ "Resolving conflicts"
    end

    test "handles disk space errors", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Simulate disk full
      send(view.pid, {:system_error,
       %{
         type: :disk_full,
         # 1KB left
         available_bytes: 1024,
         # 1MB needed
         required_bytes: 1_048_576
       }})

      # Try to save large file
      large_content = String.duplicate("x", 1_000_000)

      send(
        view.pid,
        {:file_selected,
         %{
           path: "large.txt",
           content: large_content
         }}
      )

      view
      |> element("button[phx-click=\"save_file\"]")
      |> render_click()

      html = render(view)
      assert html =~ "Insufficient disk space" or html =~ "disk full"
      assert html =~ "1 MB required" or html =~ "Free up space"

      # Should prevent data loss
      assert view.assigns.unsaved_files["large.txt"] != nil
    end
  end

  describe "process crash recovery" do
    test "recovers from GenServer crashes", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Store some state
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Important work"})
      |> render_submit()

      initial_messages = view.assigns.chat_messages

      # Simulate process crash
      send(view.pid, {:simulate_crash, :gen_server})

      # Process should restart
      :timer.sleep(200)

      # Verify process is alive
      assert Process.alive?(view.pid)

      # State should be recovered
      assert view.assigns.chat_messages == initial_messages

      html = render(view)
      assert html =~ "Important work"

      # Should show recovery notice
      assert html =~ "Session recovered" or html =~ "Restored"
    end

    test "handles supervisor restarts", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Start collaboration
      view
      |> element("button[phx-click=\"start_collaboration\"]")
      |> render_click()

      collab_session_id = view.assigns.collaboration_session.id

      # Crash collaboration supervisor
      send(view.pid, {:crash_subsystem, :collaboration})

      :timer.sleep(500)

      # Should detect and recover
      html = render(view)

      assert html =~ "Reconnecting to collaboration" or
               html =~ "Collaboration interrupted"

      # Should attempt to restore session
      :timer.sleep(1000)

      if view.assigns.collaboration_session do
        assert view.assigns.collaboration_session.id == collab_session_id
        assert render(view) =~ "Collaboration restored"
      else
        # Or offer to restart
        assert has_element?(view, "button", "Restart collaboration")
      end
    end
  end

  describe "data corruption recovery" do
    test "handles corrupted state data", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Corrupt internal state
      send(view.pid, {:corrupt_state, :chat_messages})

      # Try to use corrupted feature
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Test"})
      |> render_submit()

      # Should handle gracefully
      html = render(view)
      assert html =~ "reset" or html =~ "cleared"

      # Feature should still work
      assert Process.alive?(view.pid)
      # Reset to empty
      assert view.assigns.chat_messages == []

      # Can add new messages
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "New message"})
      |> render_submit()

      assert length(view.assigns.chat_messages) == 1
    end

    test "validates and sanitizes incoming data", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Send malformed data
      malformed_updates = [
        {:file_selected, %{path: nil, content: "test"}},
        {:file_selected, %{path: "../../../etc/passwd", content: "hacked"}},
        {:chat_message, %{content: String.duplicate("x", 1_000_000)}},
        {:editor_operation, %{type: :invalid, position: -1}}
      ]

      for update <- malformed_updates do
        {event, data} = update
        send(view.pid, {event, data})
        :timer.sleep(50)

        # Should not crash
        assert Process.alive?(view.pid)
      end

      # Should show validation errors
      html = render(view)
      assert html =~ "Invalid" or html =~ "rejected"

      # Should sanitize paths
      refute Enum.any?(view.assigns.recent_errors, fn err ->
               err =~ "etc/passwd"
             end)
    end
  end

  describe "AI service failures" do
    test "handles AI service unavailability", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Disable AI service
      send(view.pid, {:service_status, :ai, :unavailable})

      # Try to use AI features
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Explain this"})
      |> render_submit()

      html = render(view)
      # Should show service status
      assert html =~ "AI service unavailable" or
               html =~ "AI features temporarily disabled"

      # Should offer alternatives
      assert html =~ "Try again later" or html =~ "Use search instead"

      # Basic features should still work
      send(
        view.pid,
        {:file_selected,
         %{
           path: "test.ex",
           content: "# Works without AI"
         }}
      )

      assert view.assigns.current_file.path == "test.ex"
    end

    test "falls back to simpler AI models", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Primary model fails
      send(view.pid, {:ai_model_error, :primary, "Rate limit exceeded"})

      # Make AI request
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Generate code"})
      |> render_submit()

      :timer.sleep(200)

      # Should fall back
      assert view.assigns.ai_model == :fallback
      html = render(view)
      assert html =~ "Using simplified AI" or html =~ "Limited AI mode"

      # Should still provide response
      assert length(view.assigns.chat_messages) >= 2
      last_message = List.last(view.assigns.chat_messages)
      assert last_message.type == :assistant
    end
  end

  describe "browser-specific error handling" do
    test "handles local storage errors", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/session",
          connect_params: %{"local_storage_error" => "QuotaExceededError"}
        )

      # Should detect storage issue
      assert view.assigns.local_storage_available == false

      html = render(view)
      # Should warn user
      assert html =~ "Local storage unavailable" or
               html =~ "Settings will not persist"

      # Should use alternative storage
      assert view.assigns.storage_backend == :server

      # Features should still work
      view
      |> element("button[phx-click=\"update_preference\"][phx-value-key=\"theme\"]")
      |> render_click(%{"value" => "dark"})

      assert view.assigns.preferences.theme == "dark"
    end

    test "handles memory pressure in browser", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Simulate browser memory warning
      send(
        view.pid,
        {:browser_event,
         %{
           type: "memory_pressure",
           level: "critical",
           available_mb: 50
         }}
      )

      # Should reduce memory usage
      assert view.assigns.reduced_functionality == true

      html = render(view)
      assert html =~ "Low memory" or html =~ "Performance mode"

      # Should disable heavy features
      assert view.assigns.syntax_highlighting_enabled == false
      # Reduced from default
      assert view.assigns.max_open_files == 3
      assert view.assigns.file_preview_enabled == false
    end
  end

  describe "error reporting and diagnostics" do
    test "collects error context for debugging", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Trigger various errors
      send(view.pid, {:error, :file_not_found, %{path: "missing.ex"}})
      send(view.pid, {:error, :syntax_error, %{line: 10, message: "Unexpected token"}})
      send(view.pid, {:error, :network_timeout, %{endpoint: "/api/complete"}})

      # Check error log
      send(view.pid, :get_error_log)
      assert_receive {:error_log, log}

      assert length(log) >= 3

      # Each error should have context
      for error <- log do
        assert error.timestamp != nil
        assert error.type != nil
        assert error.context != nil
        assert error.stack_trace != nil or error.user_actions != nil
      end
    end

    test "provides error recovery suggestions", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Various error scenarios
      error_scenarios = [
        {:websocket_failed, ["Check internet connection", "Disable firewall", "Try refreshing"]},
        {:file_locked, ["Close other programs", "Check file permissions", "Save with new name"]},
        {:out_of_memory, ["Close unused tabs", "Restart browser", "Reduce file size"]},
        {:ai_error, ["Try simpler query", "Check AI service status", "Use alternative features"]}
      ]

      for {error_type, expected_suggestions} <- error_scenarios do
        send(view.pid, {:error_with_suggestions, error_type})

        html = render(view)

        # Should show relevant suggestions
        assert Enum.any?(expected_suggestions, fn suggestion ->
                 html =~ suggestion
               end)
      end
    end

    test "allows error report submission", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Trigger error
      send(view.pid, {:critical_error, "Unexpected system error"})

      html = render(view)
      assert html =~ "Send error report" or html =~ "Report issue"

      # Fill error report
      view
      |> form("form[phx-submit=\"submit_error_report\"]", %{
        report: %{
          description: "Was editing when it crashed",
          include_logs: true,
          contact_email: user.email
        }
      })
      |> render_submit()

      # Should acknowledge submission
      assert render(view) =~ "Report sent" or render(view) =~ "Thank you"

      # Should include diagnostic data
      assert view.assigns.last_error_report.logs != nil
      assert view.assigns.last_error_report.system_info != nil
      assert view.assigns.last_error_report.session_data != nil
    end
  end
end
