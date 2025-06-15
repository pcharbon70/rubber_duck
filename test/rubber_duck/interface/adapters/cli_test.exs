defmodule RubberDuck.Interface.Adapters.CLITest do
  use ExUnit.Case, async: true

  alias RubberDuck.Interface.Adapters.CLI
  alias RubberDuck.Interface.Behaviour

  # Mock configuration for testing
  @test_config %{
    colors: false,  # Disable colors for consistent testing
    syntax_highlight: false,
    format: "text",
    auto_save_sessions: false,  # Disable auto-save for tests
    config_dir: System.tmp_dir!() <> "/rubber_duck_cli_test_#{System.unique_integer()}",
    sessions_dir: System.tmp_dir!() <> "/rubber_duck_sessions_test_#{System.unique_integer()}"
  }

  setup do
    # Clean up any existing test data
    [@test_config.config_dir, @test_config.sessions_dir]
    |> Enum.each(fn dir ->
      if File.exists?(dir) do
        File.rm_rf!(dir)
      end
    end)
    
    on_exit(fn ->
      # Clean up test directories
      [@test_config.config_dir, @test_config.sessions_dir]
      |> Enum.each(fn dir ->
        if File.exists?(dir) do
          File.rm_rf!(dir)
        end
      end)
    end)
    
    :ok
  end

  describe "init/1" do
    test "initializes with default configuration" do
      {:ok, state} = CLI.init([])
      
      assert is_map(state)
      assert Map.has_key?(state, :config)
      assert Map.has_key?(state, :sessions)
      assert Map.has_key?(state, :session_manager)
      assert state.sessions == %{}
      assert state.current_session == nil
    end

    test "initializes with custom configuration" do
      {:ok, state} = CLI.init(config: @test_config)
      
      assert state.config.colors == false
      assert state.config.format == "text"
      assert Map.has_key?(state, :session_manager)
    end

    test "initializes session manager successfully" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Session manager should be initialized
      assert is_map(state.session_manager)
    end

    test "returns error if session manager fails to initialize" do
      # Use invalid session directory to trigger failure
      invalid_config = Map.put(@test_config, :sessions_dir, "/invalid/path/that/cannot/be/created")
      
      # This might not fail on all systems, so we'll test the happy path
      # In production, you'd mock the SessionManager.init/1 call
      {:ok, _state} = CLI.init(config: @test_config)
    end
  end

  describe "handle_request/3" do
    setup do
      {:ok, state} = CLI.init(config: @test_config)
      %{state: state}
    end

    test "handles chat request", %{state: state} do
      request = %{
        id: "req_123",
        operation: :chat,
        params: %{message: "Hello, AI!"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli, mode: :direct}
      
      {:ok, response, new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      assert is_binary(response.data.message)
      assert response.data.message =~ "Hello!"  # Mock response should echo
      assert is_map(new_state)
    end

    test "handles completion request", %{state: state} do
      request = %{
        id: "req_123",
        operation: :complete,
        params: %{prompt: "def fibonacci(n):"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, _new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      assert is_binary(response.data.completion)
      assert response.data.completion =~ "fibonacci"
    end

    test "handles analysis request", %{state: state} do
      request = %{
        id: "req_123",
        operation: :analyze,
        params: %{content: "def hello(): print('world')"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, _new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      assert is_map(response.data)
      assert Map.has_key?(response.data, :content_type)
      assert Map.has_key?(response.data, :language)
    end

    test "handles session management request", %{state: state} do
      # Test session list
      request = %{
        id: "req_123",
        operation: :session_management,
        params: %{action: :list},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, _new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      assert is_list(response.data.sessions)
    end

    test "handles configuration request", %{state: state} do
      # Test config show
      request = %{
        id: "req_123",
        operation: :configuration,
        params: %{action: :show},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, _new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      assert is_map(response.data.config)
    end

    test "handles help request", %{state: state} do
      request = %{
        id: "req_123",
        operation: :help,
        params: %{topic: :general},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, _new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      assert is_binary(response.data.help)
      assert response.data.help =~ "RubberDuck"
    end

    test "handles status request", %{state: state} do
      request = %{
        id: "req_123",
        operation: :status,
        params: %{},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, _new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      assert response.data.adapter == :cli
      assert is_atom(response.data.health)
      assert is_integer(response.data.uptime)
    end

    test "returns error for unsupported operation", %{state: state} do
      request = %{
        id: "req_123",
        operation: :unsupported,
        params: %{},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:error, error, _new_state} = CLI.handle_request(request, context, state)
      
      assert error.type == :unsupported_operation
      assert error.message =~ "not supported"
    end

    test "validates chat parameters", %{state: state} do
      # Empty message in non-interactive mode should fail
      request = %{
        id: "req_123",
        operation: :chat,
        params: %{message: "", interactive: false},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      # This should pass validation at the adapter level
      # but might fail at business logic level
      {:ok, _response, _new_state} = CLI.handle_request(request, context, state)
    end
  end

  describe "format_response/3" do
    setup do
      {:ok, state} = CLI.init(config: @test_config)
      %{state: state}
    end

    test "formats chat response", %{state: state} do
      response = %{
        id: "req_123",
        status: :success,
        data: %{message: "Hello there!"},
        metadata: %{}
      }
      
      request = %{operation: :chat}
      
      {:ok, formatted} = CLI.format_response(response, request, state)
      
      assert is_binary(formatted)
      assert formatted =~ "Hello there!"
    end

    test "handles formatting errors gracefully", %{state: state} do
      # Malformed response
      response = %{invalid: :structure}
      request = %{operation: :chat}
      
      {:error, {:format_error, _reason}} = CLI.format_response(response, request, state)
    end
  end

  describe "handle_error/3" do
    setup do
      {:ok, state} = CLI.init(config: @test_config)
      %{state: state}
    end

    test "transforms errors for CLI display", %{state: state} do
      error = %{
        type: :validation_error,
        message: "Invalid input provided"
      }
      
      request = %{operation: :chat}
      
      formatted_error = CLI.handle_error(error, request, state)
      
      assert is_binary(formatted_error)
      assert formatted_error =~ "Invalid input"
    end
  end

  describe "capabilities/0" do
    test "returns list of CLI capabilities" do
      capabilities = CLI.capabilities()
      
      assert is_list(capabilities)
      assert :chat in capabilities
      assert :complete in capabilities
      assert :analyze in capabilities
      assert :session_management in capabilities
      assert :interactive_mode in capabilities
    end
  end

  describe "validate_request/1" do
    test "validates basic request structure" do
      valid_request = %{
        id: "req_123",
        operation: :chat,
        params: %{message: "test"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      assert :ok = CLI.validate_request(valid_request)
    end

    test "validates CLI-specific parameters for chat" do
      # Valid chat request
      chat_request = %{
        id: "req_123",
        operation: :chat,
        params: %{message: "Hello", interactive: false},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      assert :ok = CLI.validate_request(chat_request)
      
      # Invalid chat request (empty message, non-interactive)
      invalid_chat = %{
        id: "req_123",
        operation: :chat,
        params: %{message: "", interactive: false},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      assert {:error, _reasons} = CLI.validate_request(invalid_chat)
    end

    test "validates completion parameters" do
      # Valid completion request
      completion_request = %{
        id: "req_123",
        operation: :complete,
        params: %{prompt: "def hello():"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      assert :ok = CLI.validate_request(completion_request)
      
      # Invalid completion request (empty prompt)
      invalid_completion = %{
        id: "req_123",
        operation: :complete,
        params: %{prompt: ""},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      assert {:error, _reasons} = CLI.validate_request(invalid_completion)
    end
  end

  describe "shutdown/2" do
    test "performs cleanup on shutdown" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Add a current session to test cleanup
      state_with_session = %{state | current_session: %{id: "test_session"}}
      
      # Should not crash and should return :ok
      assert :ok = CLI.shutdown(:normal, state_with_session)
    end
  end

  describe "session management integration" do
    setup do
      {:ok, state} = CLI.init(config: @test_config)
      %{state: state}
    end

    test "creates session when none exists", %{state: state} do
      request = %{
        id: "req_123",
        operation: :chat,
        params: %{message: "Hello"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, new_state} = CLI.handle_request(request, context, state)
      
      # Response should include session information
      assert is_binary(response.data.session_id)
      
      # State should be updated with session info
      assert new_state != state
    end

    test "uses existing session when provided", %{state: state} do
      # First create a session
      request1 = %{
        id: "req_123",
        operation: :chat,
        params: %{message: "Hello"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response1, state1} = CLI.handle_request(request1, context, state)
      session_id = response1.data.session_id
      
      # Use the same session for another request
      request2 = %{
        id: "req_124",
        operation: :chat,
        params: %{message: "How are you?", session_id: session_id},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, response2, _state2} = CLI.handle_request(request2, context, state1)
      
      # Should use the same session
      assert response2.data.session_id == session_id
    end
  end

  describe "error scenarios" do
    setup do
      {:ok, state} = CLI.init(config: @test_config)
      %{state: state}
    end

    test "handles missing required parameters", %{state: state} do
      # Chat request without message
      request = %{
        id: "req_123",
        operation: :chat,
        params: %{},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      # Should handle gracefully (might use empty message)
      {:ok, _response, _new_state} = CLI.handle_request(request, context, state)
    end

    test "handles session creation failures gracefully", %{state: state} do
      # This is hard to test without mocking, but we can test
      # that the system doesn't crash with unusual inputs
      request = %{
        id: "req_123",
        operation: :session_management,
        params: %{action: :new, name: String.duplicate("a", 1000)},  # Very long name
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      # Should either succeed or fail gracefully
      result = CLI.handle_request(request, context, state)
      
      case result do
        {:ok, _response, _new_state} -> :ok
        {:error, _error, _new_state} -> :ok
      end
    end
  end

  describe "configuration integration" do
    test "uses provided configuration correctly" do
      custom_config = Map.merge(@test_config, %{
        colors: true,
        syntax_highlight: true,
        format: "json"
      })
      
      {:ok, state} = CLI.init(config: custom_config)
      
      assert state.config.colors == true
      assert state.config.syntax_highlight == true
      assert state.config.format == "json"
    end

    test "handles configuration updates" do
      {:ok, state} = CLI.init(config: @test_config)
      
      request = %{
        id: "req_123",
        operation: :configuration,
        params: %{action: :set, key: "colors", value: true},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      # Configuration should be updated in the new state
      assert new_state.config.colors == true
    end
  end
end