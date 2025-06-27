defmodule RubberDuckWeb.EndpointTest do
  use ExUnit.Case, async: true

  test "endpoint module exists and has proper configuration" do
    # Test that the endpoint module exists and is properly configured
    assert function_exported?(RubberDuckWeb.Endpoint, :config, 1)
    assert function_exported?(RubberDuckWeb.Endpoint, :static_paths, 0)
  end

  test "endpoint supports websocket connections" do
    # Test that WebSocket connections are configured
    sockets = RubberDuckWeb.Endpoint.__sockets__()
    assert is_list(sockets)
    assert length(sockets) > 0

    # Check for our UserSocket
    socket_paths = Enum.map(sockets, fn {path, _socket, _opts} -> path end)
    assert "/socket" in socket_paths
  end
end
