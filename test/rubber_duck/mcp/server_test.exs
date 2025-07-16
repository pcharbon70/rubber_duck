defmodule RubberDuck.MCP.ServerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.MCP.Server
  alias RubberDuck.MCP.Server.State
  alias Hermes.Server.Frame
  
  @moduletag :mcp_server
  
  describe "server lifecycle" do
    test "initializes with default configuration" do
      opts = []
      frame = Hermes.Server.Frame.new()
      
      assert {:ok, frame} = Server.init(opts, frame)
      
      state = frame.assigns[:server_state]
      assert %State{} = state
      assert state.transport == :stdio
      assert state.request_count == 0
      assert MapSet.size(state.active_sessions) == 0
    end
    
    test "initializes with custom configuration" do
      opts = [
        transport: :streamable_http,
        tool_filter: fn name -> String.starts_with?(name, "allowed_") end,
        resource_filter: fn uri -> not String.contains?(uri, "secret") end
      ]
      frame = Hermes.Server.Frame.new()
      
      assert {:ok, frame} = Server.init(opts, frame)
      
      state = frame.assigns[:server_state]
      assert state.transport == :streamable_http
      assert is_function(state.tool_filter, 1)
      assert is_function(state.resource_filter, 1)
    end
  end
  
  describe "notification handling" do
    setup do
      frame = Hermes.Server.Frame.new()
      {:ok, frame} = Server.init([], frame)
      {:ok, frame: frame}
    end
    
    test "handles cancellation notifications", %{frame: frame} do
      notification = %{
        "method" => "notifications/cancelled",
        "params" => %{"requestId" => "req_123"}
      }
      
      assert {:noreply, _frame} = Server.handle_notification(notification, frame)
    end
    
    test "handles log level notifications", %{frame: frame} do
      notification = %{
        "method" => "logging/setLevel",
        "params" => %{"level" => "debug"}
      }
      
      assert {:noreply, updated_frame} = Server.handle_notification(notification, frame)
      # Verify log level was updated in frame
    end
    
    test "handles unknown notifications gracefully", %{frame: frame} do
      notification = %{
        "method" => "unknown/method",
        "params" => %{}
      }
      
      assert {:noreply, _frame} = Server.handle_notification(notification, frame)
    end
  end
  
  describe "server_info/0" do
    test "returns correct server information" do
      info = Server.server_info()
      
      assert info["name"] == "RubberDuck AI Assistant"
      assert info["version"] == "0.1.0"
    end
  end
  
  describe "server_capabilities/0" do
    test "returns all enabled capabilities" do
      capabilities = Server.server_capabilities()
      
      assert Map.has_key?(capabilities, "tools")
      assert Map.has_key?(capabilities, "resources")
      assert Map.has_key?(capabilities, "prompts")
      assert Map.has_key?(capabilities, "logging")
    end
  end
  
  describe "state management" do
    setup do
      frame = Hermes.Server.Frame.new()
      {:ok, frame} = Server.init([], frame)
      state = frame.assigns[:server_state]
      {:ok, state: state, frame: frame}
    end
    
    test "records requests", %{state: state} do
      updated_state = State.record_request(state)
      
      assert updated_state.request_count == 1
      assert updated_state.last_activity != nil
    end
    
    test "manages sessions", %{state: state} do
      state = State.add_session(state, "session_123")
      assert MapSet.member?(state.active_sessions, "session_123")
      
      state = State.remove_session(state, "session_123")
      refute MapSet.member?(state.active_sessions, "session_123")
    end
    
    test "calculates uptime", %{state: state} do
      # Create a state with a start time in the past
      state_with_start = %{state | start_time: System.monotonic_time(:second) - 1}
      
      uptime = State.uptime(state_with_start)
      assert uptime >= 1
    end
    
    test "applies tool filters", %{state: state} do
      # Without filter
      assert State.tool_allowed?(state, "any_tool")
      
      # With filter
      filter = fn name -> String.starts_with?(name, "allowed_") end
      state = %{state | tool_filter: filter}
      
      assert State.tool_allowed?(state, "allowed_tool")
      refute State.tool_allowed?(state, "forbidden_tool")
    end
    
    test "applies resource filters", %{state: state} do
      # Without filter
      assert State.resource_allowed?(state, "any://resource")
      
      # With filter
      filter = fn uri -> not String.contains?(uri, "secret") end
      state = %{state | resource_filter: filter}
      
      assert State.resource_allowed?(state, "public://data")
      refute State.resource_allowed?(state, "secret://data")
    end
  end
  
  describe "transport configuration" do
    setup do
      # Ensure Hermes.Server.Registry is started
      start_supervised!(Hermes.Server.Registry)
      :ok
    end
    
    test "starts with STDIO transport" do
      assert {:ok, _pid} = Server.start_link(transport: :stdio)
    end
    
    @tag :skip
    test "starts with StreamableHTTP transport" do
      assert {:ok, _pid} = Server.start_link(
        transport: :streamable_http,
        port: 8081
      )
    end
  end
end