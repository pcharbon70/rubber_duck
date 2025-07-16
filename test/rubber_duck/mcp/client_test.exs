defmodule RubberDuck.MCP.ClientTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.MCP.Client
  alias RubberDuck.MCP.ClientSupervisor
  
  @moduletag :mcp

  setup do
    # ClientSupervisor is started in application
    :ok
  end

  describe "client lifecycle" do
    test "starts and stops client successfully" do
      opts = [
        name: :test_client,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      assert {:ok, pid} = Client.start_link(opts)
      assert is_pid(pid)
      assert Process.alive?(pid)
      
      assert :ok = Client.stop(:test_client)
      refute Process.alive?(pid)
    end

    test "registers client in registry" do
      opts = [
        name: :registry_test_client,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      assert {:ok, _pid} = Client.start_link(opts)
      assert RubberDuck.MCP.Client.Registry.registered?(:registry_test_client)
      
      Client.stop(:registry_test_client)
      refute RubberDuck.MCP.Client.Registry.registered?(:registry_test_client)
    end

    test "handles initialization errors gracefully" do
      opts = [
        name: :error_client,
        transport: {:stdio, command: "nonexistent_command", args: []},
        capabilities: [:tools],
        auto_reconnect: false
      ]
      
      assert {:ok, pid} = Client.start_link(opts)
      
      # Give it time to fail
      Process.sleep(100)
      
      # Should have stopped due to connection failure
      refute Process.alive?(pid)
    end
  end

  describe "transport configuration" do
    test "accepts STDIO transport configuration" do
      opts = [
        name: :stdio_client,
        transport: {:stdio, command: "echo", args: ["hello"]},
        capabilities: [:tools]
      ]
      
      assert {:ok, pid} = Client.start_link(opts)
      assert is_pid(pid)
      Client.stop(:stdio_client)
    end

    test "accepts HTTP/SSE transport configuration" do
      opts = [
        name: :http_sse_client,
        transport: {:http_sse, url: "http://localhost:8080/mcp", headers: %{"Authorization" => "Bearer token"}},
        capabilities: [:tools, :resources]
      ]
      
      assert {:ok, pid} = Client.start_link(opts)
      assert is_pid(pid)
      Client.stop(:http_sse_client)
    end

    test "accepts WebSocket transport configuration" do
      opts = [
        name: :websocket_client,
        transport: {:websocket, url: "ws://localhost:8080/mcp", headers: %{"Authorization" => "Bearer token"}},
        capabilities: [:tools, :resources, :prompts]
      ]
      
      assert {:ok, pid} = Client.start_link(opts)
      assert is_pid(pid)
      Client.stop(:websocket_client)
    end
  end

  describe "capability negotiation" do
    setup do
      # Create a mock MCP server for testing
      # In real tests, we'd use a proper mock server
      opts = [
        name: :capability_client,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools, :resources, :prompts]
      ]
      
      {:ok, _pid} = Client.start_link(opts)
      
      on_exit(fn ->
        Client.stop(:capability_client)
      end)
      
      :ok
    end

    @tag :skip
    test "negotiates capabilities with server" do
      # This would require a real MCP server or mock
      # Skipping for now as it needs integration setup
    end
  end

  describe "tool discovery and invocation" do
    setup do
      # For real tests, we'd need a mock MCP server
      opts = [
        name: :tool_client,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      {:ok, _pid} = Client.start_link(opts)
      
      on_exit(fn ->
        Client.stop(:tool_client)
      end)
      
      :ok
    end

    @tag :skip
    test "lists available tools" do
      # Requires mock server
      {:ok, tools} = Client.list_tools(:tool_client)
      assert is_list(tools)
    end

    @tag :skip
    test "calls tool with arguments" do
      # Requires mock server
      {:ok, result} = Client.call_tool(:tool_client, "test_tool", %{arg: "value"})
      assert is_map(result)
    end

    test "returns error when not connected" do
      # Stop the client to simulate disconnection
      Client.stop(:tool_client)
      
      # Start a new one that won't connect
      opts = [
        name: :disconnected_client,
        transport: {:stdio, command: "false", args: []},
        capabilities: [:tools],
        auto_reconnect: false
      ]
      
      {:ok, _pid} = Client.start_link(opts)
      Process.sleep(100)  # Let it fail to connect
      
      assert {:error, :not_connected} = Client.list_tools(:disconnected_client)
      assert {:error, :not_connected} = Client.call_tool(:disconnected_client, "test", %{})
      
      Client.stop(:disconnected_client)
    end
  end

  describe "authentication" do
    test "supports OAuth2 authentication" do
      opts = [
        name: :oauth_client,
        transport: {:http_sse, url: "http://localhost:8080/mcp", headers: %{}},
        auth: {:oauth2, 
          client_id: "test_client",
          client_secret: "test_secret",
          token_url: "http://localhost:8080/oauth/token"
        },
        capabilities: [:tools]
      ]
      
      assert {:ok, _pid} = Client.start_link(opts)
      Client.stop(:oauth_client)
    end

    test "supports API key authentication" do
      opts = [
        name: :api_key_client,
        transport: {:http_sse, url: "http://localhost:8080/mcp", headers: %{}},
        auth: {:api_key, key: "test_api_key"},
        capabilities: [:tools]
      ]
      
      assert {:ok, _pid} = Client.start_link(opts)
      Client.stop(:api_key_client)
    end

    test "supports certificate authentication" do
      opts = [
        name: :cert_client,
        transport: {:http_sse, url: "https://localhost:8443/mcp", headers: %{}},
        auth: {:certificate, cert: "cert.pem", key: "key.pem"},
        capabilities: [:tools]
      ]
      
      assert {:ok, _pid} = Client.start_link(opts)
      Client.stop(:cert_client)
    end
  end

  describe "health monitoring" do
    setup do
      opts = [
        name: :health_client,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      {:ok, _pid} = Client.start_link(opts)
      
      on_exit(fn ->
        Client.stop(:health_client)
      end)
      
      :ok
    end

    test "reports health status" do
      {:ok, health} = Client.health_check(:health_client)
      
      assert is_map(health)
      assert health.status in [:initializing, :connecting, :connected, :disconnected, :error]
      assert is_boolean(health.connected)
      assert is_integer(health.uptime)
    end

    @tag :skip
    test "heartbeat keeps connection alive" do
      # Would need to observe heartbeat messages
      # Requires integration with mock server
    end

    @tag :skip
    test "auto-reconnects on disconnect" do
      # Would need to simulate disconnect and observe reconnection
      # Requires integration with mock server
    end
  end

  describe "concurrent operations" do
    setup do
      opts = [
        name: :concurrent_client,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools],
        timeout: 5000
      ]
      
      {:ok, _pid} = Client.start_link(opts)
      
      on_exit(fn ->
        Client.stop(:concurrent_client)
      end)
      
      :ok
    end

    @tag :skip
    test "handles concurrent tool calls" do
      # Would need mock server that can handle concurrent requests
      tasks = for i <- 1..10 do
        Task.async(fn ->
          Client.call_tool(:concurrent_client, "test_tool", %{id: i})
        end)
      end
      
      results = Task.await_many(tasks)
      assert length(results) == 10
    end
  end

  describe "error handling" do
    test "handles timeout errors" do
      opts = [
        name: :timeout_client,
        transport: {:stdio, command: "sleep", args: ["10"]},
        capabilities: [:tools],
        timeout: 100
      ]
      
      assert {:ok, _pid} = Client.start_link(opts)
      
      # This should timeout
      assert {:error, :timeout} = Client.list_tools(:timeout_client, timeout: 100)
      
      Client.stop(:timeout_client)
    end

    test "handles invalid transport configuration" do
      opts = [
        name: :invalid_transport_client,
        transport: {:unsupported, some: "config"},
        capabilities: [:tools],
        auto_reconnect: false
      ]
      
      assert {:ok, pid} = Client.start_link(opts)
      
      # Should fail to connect and stop
      Process.sleep(100)
      refute Process.alive?(pid)
    end
  end

  describe "telemetry" do
    setup do
      :telemetry.attach_many(
        "test-mcp-client",
        [
          [:rubber_duck, :mcp, :client, :connected],
          [:rubber_duck, :mcp, :client, :disconnected]
        ],
        &__MODULE__.handle_telemetry_event/4,
        nil
      )
      
      on_exit(fn ->
        :telemetry.detach("test-mcp-client")
      end)
      
      :ok
    end

    test "emits telemetry events" do
      # Store events in process dictionary for testing
      Process.put(:telemetry_events, [])
      
      opts = [
        name: :telemetry_client,
        transport: {:stdio, command: "echo", args: ["test"]},
        capabilities: [:tools]
      ]
      
      {:ok, _pid} = Client.start_link(opts)
      
      # Give it time to connect
      Process.sleep(100)
      
      events = Process.get(:telemetry_events)
      assert Enum.any?(events, fn {event, _, _} -> 
        event == [:rubber_duck, :mcp, :client, :connected]
      end)
      
      Client.stop(:telemetry_client)
    end
  end

  # Helper function for telemetry testing
  def handle_telemetry_event(event, measurements, metadata, _config) do
    events = Process.get(:telemetry_events, [])
    Process.put(:telemetry_events, [{event, measurements, metadata} | events])
  end
end