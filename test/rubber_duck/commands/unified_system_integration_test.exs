defmodule RubberDuck.Commands.UnifiedSystemIntegrationTest do
  @moduledoc """
  Integration tests for the unified command system.
  
  These tests verify that all commands work correctly end-to-end through
  the unified abstraction layer, including parsing, processing, handling,
  and formatting.
  """
  
  use RubberDuck.DataCase, async: false
  
  alias RubberDuck.Commands.{Processor, Parser, Context}
  alias RubberDuck.Commands.Adapters.{CLI, WebSocket, LiveView, TUI}
  alias RubberDuck.LLM.ConnectionManager
  
  setup do
    # Ensure processor is started
    case Process.whereis(Processor) do
      nil -> start_supervised!(Processor)
      _pid -> :ok
    end
    
    # Ensure mock provider is connected
    case ConnectionManager.connect(:mock) do
      :ok -> :ok
      {:ok, :already_connected} -> :ok
    end
    
    # Create test files
    test_dir = Path.join(System.tmp_dir!(), "rubber_duck_test_#{System.unique_integer()}")
    File.mkdir_p!(test_dir)
    
    test_file = Path.join(test_dir, "test.ex")
    test_content = """
    defmodule Test do
      def hello(name) do
        "Hello, \#{name}!"
      end
      
      def unused_function do
        :not_used
      end
    end
    """
    File.write!(test_file, test_content)
    
    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)
    
    # Create a standard context for testing
    {:ok, context} = Context.new(%{
      user_id: "test_user",
      project_id: "test_project",
      session_id: "test_session",
      permissions: [:read, :write, :execute],
      metadata: %{}
    })
    
    %{
      test_dir: test_dir,
      test_file: test_file,
      test_content: test_content,
      context: context,
      config: %{
        user_id: "test_user",
        project_id: "test_project",
        permissions: [:read, :write, :execute]
      }
    }
  end
  
  describe "CLI adapter integration" do
    test "executes analyze command through CLI adapter", %{test_file: test_file, config: config} do
      args = ["analyze", "--path", test_file, "--type", "all", "--recursive"]
      
      assert {:ok, result} = CLI.execute(args, config)
      assert is_binary(result)  # Result is formatted
    end
    
    test "executes generate command through CLI adapter", %{config: config} do
      args = ["generate", "--prompt", "Create a function that adds two numbers", "--language", "elixir"]
      
      assert {:ok, result} = CLI.execute(args, config)
      assert is_binary(result)  # Result is formatted
    end
    
    test "executes health command through CLI adapter", %{config: config} do
      args = ["health"]
      
      assert {:ok, result} = CLI.execute(args, config)
      assert is_binary(result)  # Result is formatted
    end
    
    test "handles async execution through CLI adapter", %{test_file: test_file, config: config} do
      args = ["analyze", "--path", test_file, "--recursive"]
      
      assert {:ok, %{request_id: request_id}} = CLI.execute_async(args, config)
      assert is_binary(request_id)
      
      # Wait a bit for processing
      Process.sleep(100)
      
      # Check status
      assert {:ok, status} = CLI.get_status(request_id)
      assert status.status in [:completed, :running, :pending]
    end
  end
  
  describe "WebSocket adapter integration" do
    test "handles analyze command through WebSocket adapter", %{test_file: test_file} do
      socket = %{
        assigns: %{user_id: "ws_user", permissions: [:read, :write]},
        id: "socket_123",
        topic: "cli:commands"
      }
      
      payload = %{
        "command" => "analyze",
        "params" => %{
          "path" => test_file,
          "type" => "all"
        }
      }
      
      assert {:ok, result} = WebSocket.handle_message("cli:commands", payload, socket)
      assert is_binary(result)  # Result is formatted
    end
    
    test "handles async command through WebSocket adapter", %{test_file: test_file} do
      socket = %{
        assigns: %{user_id: "ws_user", permissions: [:read, :write]},
        id: "socket_123",
        topic: "cli:commands"
      }
      
      payload = %{
        "command" => "generate",
        "params" => %{
          "prompt" => "Create a GenServer",
          "language" => "elixir"
        }
      }
      
      assert {:ok, %{request_id: request_id}} = WebSocket.handle_async_message("cli:commands", payload, socket)
      assert is_binary(request_id)
    end
    
    test "builds proper response format", %{test_file: test_file} do
      result = {:ok, %{status: "healthy", uptime: 1234}}
      response = WebSocket.build_response(result, "req_123")
      
      assert response["status"] == "ok"
      assert response["request_id"] == "req_123"
      assert response["data"] == %{status: "healthy", uptime: 1234}
      assert Map.has_key?(response, "timestamp")
    end
  end
  
  describe "LiveView adapter integration" do
    test "handles event through LiveView adapter", %{test_file: test_file} do
      socket = %{
        assigns: %{
          current_user: %{id: "lv_user"},
          project_id: "test_project"
        },
        id: "liveview_123",
        view: TestLiveView
      }
      
      event = "analyze"
      params = %{
        "path" => test_file,
        "type" => "all"
      }
      
      assert {:ok, result} = LiveView.handle_event(event, params, socket)
      assert is_binary(result)  # Result is formatted
    end
    
    test "builds assigns for LiveView", %{} do
      result = {:ok, %{message: "Command completed"}}
      assigns = LiveView.build_assigns(result)
      
      assert assigns.command_status == :success
      assert assigns.command_result == %{message: "Command completed"}
      assert is_nil(assigns.command_error)
      assert Map.has_key?(assigns, :last_command_timestamp)
    end
    
    test "builds flash messages", %{} do
      assert {:info, message} = LiveView.build_flash({:ok, %{message: "Success!"}})
      assert message == "Success!"
      
      assert {:error, message} = LiveView.build_flash({:error, "Failed"})
      assert message == "Command failed: Failed"
    end
  end
  
  describe "TUI adapter integration" do
    test "executes command through TUI adapter", %{test_file: test_file} do
      session = %{
        user_id: "tui_user",
        project_id: "test_project",
        terminal_width: 80,
        terminal_height: 24,
        colors_supported: true
      }
      
      input = "analyze #{test_file}"
      
      assert {:ok, result} = TUI.execute(input, session)
      assert is_binary(result)  # Result is formatted
    end
    
    test "formats output for terminal display", %{} do
      result = {:ok, %{status: "healthy", uptime: 12345}}
      formatted = TUI.format_for_terminal(result, colors: false)
      
      assert is_binary(formatted)
      assert formatted =~ "status:"
      assert formatted =~ "healthy"
    end
    
    test "provides command autocompletion", %{} do
      session = %{user_id: "tui_user"}
      
      suggestions = TUI.autocomplete("ana", session)
      assert "analyze" in suggestions
      
      suggestions = TUI.autocomplete("gen", session)
      assert "generate" in suggestions
      
      suggestions = TUI.autocomplete("", session)
      assert length(suggestions) > 5  # Should list all commands
    end
  end
  
  describe "cross-adapter consistency" do
    test "all adapters produce consistent results for health command", %{config: config} do
      # CLI adapter
      {:ok, cli_result} = CLI.execute(["health"], config)
      
      # WebSocket adapter
      socket = %{
        assigns: %{user_id: "test_user", permissions: [:read]},
        id: "socket_123",
        topic: "cli:commands"
      }
      {:ok, ws_result} = WebSocket.handle_message("cli:commands", %{"command" => "health", "params" => %{}}, socket)
      
      # TUI adapter
      session = %{user_id: "test_user"}
      {:ok, tui_result} = TUI.execute("health", session)
      
      # All should return formatted strings containing health info
      assert is_binary(cli_result)
      assert is_binary(ws_result)
      assert is_binary(tui_result)
      
      # All should contain key health indicators
      for result <- [cli_result, ws_result, tui_result] do
        assert result =~ "healthy" or result =~ "status"
      end
    end
  end
  
  describe "error handling" do
    test "all adapters handle parsing errors gracefully", %{config: config} do
      # CLI with invalid syntax
      assert {:error, reason} = CLI.execute(["--invalid-command"], config)
      assert is_binary(reason)
      
      # WebSocket with missing command
      socket = %{assigns: %{user_id: "test"}, id: "123", topic: "cli:commands"}
      assert {:error, reason} = WebSocket.handle_message("cli:commands", %{}, socket)
      assert is_binary(reason)
      
      # TUI with empty input
      session = %{user_id: "test"}
      assert {:error, reason} = TUI.execute("", session)
      assert is_binary(reason)
    end
    
    test "handles permission errors", %{test_file: test_file} do
      # Create a restricted context
      restricted_config = %{
        user_id: "restricted_user",
        permissions: [:read]  # No write permission
      }
      
      # Try to execute a write command
      args = ["generate", "--prompt", "test"]
      assert {:error, reason} = CLI.execute(args, restricted_config)
      assert reason =~ "Unauthorized" or reason =~ "permission"
    end
    
    test "handles handler errors gracefully", %{} do
      config = %{user_id: "test", permissions: [:read, :write, :execute]}
      
      # Try to analyze a non-existent file
      args = ["analyze", "--path", "/non/existent/file.ex"]
      assert {:error, reason} = CLI.execute(args, config)
      assert is_binary(reason)
    end
  end
  
  describe "async command execution" do
    test "tracks async command lifecycle", %{test_file: test_file, config: config} do
      args = ["analyze", "--path", test_file, "--recursive"]
      
      # Start async execution
      assert {:ok, %{request_id: request_id}} = CLI.execute_async(args, config)
      
      # Should start in pending or running state
      assert {:ok, status1} = CLI.get_status(request_id)
      assert status1.status in [:pending, :running]
      
      # Wait for completion
      Process.sleep(200)
      
      # Should be completed
      assert {:ok, status2} = CLI.get_status(request_id)
      assert status2.status == :completed
      assert not is_nil(status2.result)
    end
    
    test "can cancel async commands", %{test_file: test_file, config: config} do
      # Use a command that might take longer
      args = ["analyze", "--path", Path.dirname(test_file), "--recursive"]
      
      assert {:ok, %{request_id: request_id}} = CLI.execute_async(args, config)
      
      # Cancel immediately
      assert :ok = CLI.cancel(request_id)
      
      # Status should reflect cancellation (or completion if it was too fast)
      Process.sleep(50)
      {:ok, status} = CLI.get_status(request_id)
      assert status.status in [:cancelled, :completed]
    end
  end
  
  describe "formatting" do
    test "respects format preferences across client types", %{test_file: test_file, context: context} do
      # Parse the same command with different formats
      {:ok, json_cmd} = Parser.parse(
        %{"command" => "health", "params" => %{}},
        :websocket,
        context
      )
      
      {:ok, text_cmd} = Parser.parse(
        "health",
        :tui,
        context
      )
      
      # Execute both
      {:ok, json_result} = Processor.execute(json_cmd)
      {:ok, text_result} = Processor.execute(text_cmd)
      
      # JSON result should be a JSON string
      assert is_binary(json_result)
      assert {:ok, _} = Jason.decode(json_result)
      
      # Text result should be human-readable
      assert is_binary(text_result)
      assert text_result =~ "Health Status:" or text_result =~ "healthy"
    end
  end
end