defmodule RubberDuckWeb.CLIChannelTest do
  use RubberDuckWeb.ChannelCase

  alias RubberDuckWeb.CLIChannel

  setup do
    # Create a test API key (must be at least 32 bytes)
    api_key = "test_api_key_1234567890123456789012345678901234"

    # Connect and authenticate socket
    {:ok, socket} =
      connect(RubberDuckWeb.UserSocket, %{"api_key" => api_key})

    # Join the CLI channel
    {:ok, _, socket} = subscribe_and_join(socket, CLIChannel, "cli:commands")

    %{socket: socket, api_key: api_key}
  end

  describe "channel join" do
    test "successfully joins with valid authentication", %{socket: socket} do
      assert socket.assigns.user_id == "api_user_test_api_key_1234567890123456789012345678901234"
    end

    test "returns connected status on join" do
      api_key = "another_test_key_12345678901234567890123456789012"
      {:ok, socket} = connect(RubberDuckWeb.UserSocket, %{"api_key" => api_key})

      {:ok, reply, _socket} = subscribe_and_join(socket, CLIChannel, "cli:commands")

      assert reply.status == "connected"
      assert reply.server_time
    end
  end

  describe "ping command" do
    test "responds to ping with pong", %{socket: socket} do
      ref = push(socket, "ping", %{})
      assert_reply(ref, :ok, %{pong: timestamp})
      assert is_integer(timestamp)
    end
  end

  describe "stats command" do
    test "returns connection statistics", %{socket: socket} do
      ref = push(socket, "stats", %{})
      assert_reply(ref, :ok, stats)

      assert stats.request_count == 0
      assert stats.connected_at
      assert stats.uptime_seconds >= 0
    end

    test "increments request count", %{socket: socket} do
      # Make a request that goes through the unified command system
      ref1 = push(socket, "health", %{})
      assert_reply(ref1, :ok, _)

      # Check stats
      ref2 = push(socket, "stats", %{})
      assert_reply(ref2, :ok, stats)

      assert stats.request_count == 1
    end
  end

  describe "analyze command" do
    test "accepts analyze request and returns processing status", %{socket: socket} do
      ref = push(socket, "analyze", %{"path" => "mix.exs"})
      assert_reply(ref, :ok, %{status: "processing"})

      # Should receive result via push with longer timeout
      assert_push("analyze:result", %{status: "success", result: _}, 5000)
    end

    test "handles analyze errors", %{socket: socket} do
      ref = push(socket, "analyze", %{"path" => "/invalid/path"})
      assert_reply(ref, :ok, %{status: "processing"})

      # Should receive error via push with longer timeout
      assert_push("analyze:error", %{status: "error", reason: _}, 5000)
    end
  end

  describe "generate command" do
    test "accepts generate request", %{socket: socket} do
      ref = push(socket, "generate", %{"prompt" => "Create a hello world function"})
      assert_reply(ref, :ok, %{status: "processing"})

      assert_push("generate:result", %{status: "success", result: _}, 5000)
    end
  end

  describe "llm commands" do
    test "returns LLM status", %{socket: socket} do
      ref = push(socket, "llm", %{"subcommand" => "status"})
      assert_reply(ref, :ok, response)

      assert response["status"] == "ok"
      assert response["data"]
      
      # Parse the JSON response
      {:ok, llm_data} = Jason.decode(response["data"])
      assert llm_data["type"] == "llm_status"
      assert is_list(llm_data["providers"])
    end

    test "connects to LLM provider", %{socket: socket} do
      ref = push(socket, "llm", %{"subcommand" => "connect", "provider" => "mock"})
      assert_reply(ref, :ok, response)

      assert response["status"] == "ok"
      {:ok, llm_data} = Jason.decode(response["data"])
      assert llm_data["message"] =~ "connected"
    end

    test "handles unknown provider", %{socket: socket} do
      ref = push(socket, "llm", %{"subcommand" => "connect", "provider" => "unknown"})
      assert_reply(ref, :error, response)

      assert response["error"] =~ "provider_not_configured"
    end

    test "disconnects from LLM provider", %{socket: socket} do
      # First connect
      ref1 = push(socket, "llm", %{"subcommand" => "connect", "provider" => "mock"})
      assert_reply(ref1, :ok, _)

      # Then disconnect
      ref2 = push(socket, "llm", %{"subcommand" => "disconnect", "provider" => "mock"})
      assert_reply(ref2, :ok, response)

      assert response["status"] == "ok"
      {:ok, llm_data} = Jason.decode(response["data"])
      assert llm_data["message"] =~ "Disconnected"
    end

    test "enables LLM provider", %{socket: socket} do
      ref = push(socket, "llm", %{"subcommand" => "enable", "provider" => "mock"})
      assert_reply(ref, :ok, response)

      assert response["status"] == "ok"
      {:ok, llm_data} = Jason.decode(response["data"])
      assert llm_data["message"] =~ "Enabled"
    end

    test "disables LLM provider", %{socket: socket} do
      ref = push(socket, "llm", %{"subcommand" => "disable", "provider" => "mock"})
      assert_reply(ref, :ok, response)

      assert response["status"] == "ok"
      {:ok, llm_data} = Jason.decode(response["data"])
      assert llm_data["message"] =~ "Disabled"
    end

    test "handles unknown LLM subcommand", %{socket: socket} do
      ref = push(socket, "llm", %{"subcommand" => "invalid"})
      assert_reply(ref, :error, response)

      assert response["error"] =~ "Invalid LLM subcommand"
    end
  end

  describe "streaming commands" do
    test "initiates streaming with stream ID", %{socket: socket} do
      ref = push(socket, "stream:generate", %{"prompt" => "Stream test"})
      assert_reply(ref, :ok, %{stream_id: stream_id})

      assert stream_id

      # Should receive stream events
      assert_push("stream:start", %{stream_id: ^stream_id}, 1000)
      assert_push("stream:data", %{stream_id: ^stream_id, chunk: _}, 3000)
      assert_push("stream:end", %{stream_id: ^stream_id, status: "completed"}, 3000)
    end
  end

  describe "health command" do
    test "returns server health information", %{socket: socket} do
      ref = push(socket, "health", %{})
      assert_reply(ref, :ok, response)

      # The response is wrapped in the unified command format
      assert response["status"] == "ok"
      assert response["data"]
      
      # Parse the JSON data
      {:ok, health_data} = Jason.decode(response["data"])
      
      assert health_data["status"] == "healthy"
      assert health_data["timestamp"]
      assert is_map(health_data["uptime"])
      assert health_data["uptime"]["seconds"] >= 0
      assert is_map(health_data["memory"])
      assert health_data["memory"]["total"] > 0
      assert is_map(health_data["services"])
    end
  end
end
