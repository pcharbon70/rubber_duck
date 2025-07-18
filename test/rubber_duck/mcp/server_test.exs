defmodule RubberDuck.MCP.ServerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.MCP.{Server, Protocol}
  
  defmodule MockTransport do
    use GenServer
    
    @behaviour RubberDuck.MCP.Transport
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end
    
    def init(opts) do
      parent = Keyword.fetch!(opts, :parent)
      {:ok, %{parent: parent, messages: [], connections: %{}}}
    end
    
    @impl RubberDuck.MCP.Transport
    def subscribe(_transport), do: :ok
    
    @impl RubberDuck.MCP.Transport
    def send_message(transport, connection_id, message) do
      GenServer.call(transport, {:send_message, connection_id, message})
    end
    
    @impl RubberDuck.MCP.Transport
    def close_connection(transport, connection_id) do
      GenServer.call(transport, {:close_connection, connection_id})
    end
    
    @impl RubberDuck.MCP.Transport
    def stop(transport) do
      GenServer.stop(transport)
    end
    
    @impl RubberDuck.MCP.Transport
    def list_connections(transport) do
      GenServer.call(transport, :list_connections)
    end
    
    # Test helpers
    def simulate_connection(transport, connection_id \\ nil) do
      GenServer.call(transport, {:simulate_connection, connection_id})
    end
    
    def simulate_message(transport, connection_id, message) do
      GenServer.call(transport, {:simulate_message, connection_id, message})
    end
    
    def get_sent_messages(transport) do
      GenServer.call(transport, :get_sent_messages)
    end
    
    # GenServer callbacks
    def handle_call({:send_message, connection_id, message}, _from, state) do
      messages = [{connection_id, message} | state.messages]
      {:reply, :ok, %{state | messages: messages}}
    end
    
    def handle_call({:close_connection, connection_id}, _from, state) do
      connections = Map.delete(state.connections, connection_id)
      {:reply, :ok, %{state | connections: connections}}
    end
    
    def handle_call(:list_connections, _from, state) do
      connections = Map.values(state.connections)
      {:reply, {:ok, connections}, state}
    end
    
    def handle_call({:simulate_connection, connection_id}, _from, state) do
      id = connection_id || RubberDuck.MCP.Transport.generate_connection_id()
      connection_info = %{
        id: id,
        remote_info: %{type: "test"},
        connected_at: DateTime.utc_now()
      }
      
      send(state.parent, {:transport_connected, connection_info})
      connections = Map.put(state.connections, id, connection_info)
      
      {:reply, {:ok, id}, %{state | connections: connections}}
    end
    
    def handle_call({:simulate_message, connection_id, message}, _from, state) do
      send(state.parent, {:transport_message, connection_id, message})
      {:reply, :ok, state}
    end
    
    def handle_call(:get_sent_messages, _from, state) do
      {:reply, Enum.reverse(state.messages), state}
    end
  end
  
  setup do
    {:ok, server} = Server.start_link(
      transport: MockTransport,
      transport_opts: [],
      name: nil
    )
    
    transport = :sys.get_state(server).transport
    
    {:ok, server: server, transport: transport}
  end
  
  describe "connection lifecycle" do
    test "accepts new connections", %{server: server, transport: transport} do
      # Simulate a new connection
      {:ok, conn_id} = MockTransport.simulate_connection(transport)
      
      # Connection should be accepted
      assert {:ok, status} = Server.status(server)
      assert status.active_sessions == 0  # Not yet initialized
    end
    
    test "requires initialization before other messages", %{transport: transport} do
      # Simulate connection
      {:ok, conn_id} = MockTransport.simulate_connection(transport)
      
      # Send non-initialization message
      request = Protocol.build_request(1, "tools/list")
      MockTransport.simulate_message(transport, conn_id, request)
      
      # Should receive error response
      Process.sleep(50)  # Give time to process
      messages = MockTransport.get_sent_messages(transport)
      
      assert [{^conn_id, response}] = messages
      assert response["error"]["code"] == -32600  # Invalid request
      assert response["error"]["message"] =~ "Must initialize"
    end
    
    test "handles initialization correctly", %{server: server, transport: transport} do
      # Simulate connection
      {:ok, conn_id} = MockTransport.simulate_connection(transport)
      
      # Send initialization
      init_request = Protocol.build_request(1, "initialize", %{
        "protocolVersion" => "2024-11-05",
        "clientInfo" => %{
          "name" => "Test Client",
          "version" => "1.0.0"
        }
      })
      
      MockTransport.simulate_message(transport, conn_id, init_request)
      
      # Should receive initialization response
      Process.sleep(50)
      messages = MockTransport.get_sent_messages(transport)
      
      assert [{^conn_id, response}] = messages
      assert response["id"] == 1
      assert response["result"]["protocolVersion"] == "2024-11-05"
      assert response["result"]["capabilities"]
      assert response["result"]["serverInfo"]["name"] == "RubberDuck MCP Server"
      
      # Now we should have an active session
      assert {:ok, status} = Server.status(server)
      assert status.active_sessions == 1
    end
    
    test "rejects incompatible protocol versions", %{transport: transport} do
      # Simulate connection
      {:ok, conn_id} = MockTransport.simulate_connection(transport)
      
      # Send initialization with wrong version
      init_request = Protocol.build_request(1, "initialize", %{
        "protocolVersion" => "1.0.0",
        "clientInfo" => %{"name" => "Test Client"}
      })
      
      MockTransport.simulate_message(transport, conn_id, init_request)
      
      # Should receive error
      Process.sleep(50)
      messages = MockTransport.get_sent_messages(transport)
      
      assert [{^conn_id, response}] = messages
      assert response["error"]["code"] == -32602  # Invalid params
      assert response["error"]["message"] =~ "Incompatible protocol version"
    end
  end
  
  describe "session management" do
    test "lists active sessions", %{server: server, transport: transport} do
      # Create multiple sessions
      {:ok, conn1} = MockTransport.simulate_connection(transport)
      {:ok, conn2} = MockTransport.simulate_connection(transport)
      
      # Initialize both
      init_request = Protocol.build_request(1, "initialize", %{
        "protocolVersion" => "2024-11-05"
      })
      
      MockTransport.simulate_message(transport, conn1, init_request)
      MockTransport.simulate_message(transport, conn2, init_request)
      
      Process.sleep(50)
      
      # List sessions
      assert {:ok, sessions} = Server.list_sessions(server)
      assert length(sessions) == 2
      assert Enum.all?(sessions, fn s -> s.id in [conn1, conn2] end)
    end
    
    test "handles session disconnection", %{server: server, transport: transport} do
      # Create and initialize session
      {:ok, conn_id} = MockTransport.simulate_connection(transport)
      
      init_request = Protocol.build_request(1, "initialize", %{
        "protocolVersion" => "2024-11-05"
      })
      
      MockTransport.simulate_message(transport, conn_id, init_request)
      Process.sleep(50)
      
      # Verify session exists
      assert {:ok, status} = Server.status(server)
      assert status.active_sessions == 1
      
      # Simulate disconnect
      send(server, {:transport_disconnected, conn_id, :closed})
      Process.sleep(50)
      
      # Session should be removed
      assert {:ok, status} = Server.status(server)
      assert status.active_sessions == 0
    end
  end
  
  describe "graceful shutdown" do
    test "handles shutdown request", %{server: server} do
      # Request shutdown
      assert :ok = Server.shutdown(server)
      
      # Server should be marked as shutting down
      assert {:ok, status} = Server.status(server)
      assert status.shutdown_requested == true
    end
  end
end