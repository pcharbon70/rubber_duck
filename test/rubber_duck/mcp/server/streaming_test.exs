defmodule RubberDuck.MCP.Server.StreamingTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.MCP.Server.Streaming
  alias Hermes.Server.Frame
  
  @moduletag :mcp_server
  
  describe "start_stream/2" do
    test "creates a new streaming context" do
      frame = Hermes.Server.Frame.new()
      
      assert {:ok, token, frame} = Streaming.start_stream(frame, "test_operation")
      
      assert is_binary(token)
      assert String.starts_with?(token, "prog_")
      
      # Verify context is stored
      context = Hermes.Server.Frame.get_private(frame, {:streaming, token})
      assert context.token == token
      assert context.operation == "test_operation"
      assert context.progress == 0
    end
  end
  
  describe "send_progress/3" do
    setup do
      frame = Hermes.Server.Frame.new()
      {:ok, token, frame} = Streaming.start_stream(frame, "test")
      {:ok, token: token, frame: frame}
    end
    
    test "sends valid progress update", %{token: token, frame: frame} do
      progress_info = %{progress: 0.5, message: "Half way there"}
      
      assert {:ok, updated_frame} = Streaming.send_progress(frame, token, progress_info)
      
      # Verify context was updated
      context = Hermes.Server.Frame.get_private(updated_frame, {:streaming, token})
      assert context.progress == 0.5
    end
    
    test "validates progress is between 0 and 1", %{token: token, frame: frame} do
      assert {:error, _} = Streaming.send_progress(frame, token, %{progress: -0.1})
      assert {:error, _} = Streaming.send_progress(frame, token, %{progress: 1.5})
      assert {:ok, _} = Streaming.send_progress(frame, token, %{progress: 0.0})
      assert {:ok, _} = Streaming.send_progress(frame, token, %{progress: 1.0})
    end
    
    test "validates total if provided", %{token: token, frame: frame} do
      assert {:error, _} = Streaming.send_progress(frame, token, %{progress: 0.5, total: -1})
      assert {:error, _} = Streaming.send_progress(frame, token, %{progress: 0.5, total: 0})
      assert {:ok, _} = Streaming.send_progress(frame, token, %{progress: 0.5, total: 100})
    end
    
    test "rejects invalid token", %{frame: frame} do
      assert {:error, :invalid_token} = Streaming.send_progress(frame, "bad_token", %{progress: 0.5})
    end
  end
  
  describe "stream_chunk/3" do
    setup do
      frame = Hermes.Server.Frame.new()
      {:ok, token, frame} = Streaming.start_stream(frame, "test")
      {:ok, token: token, frame: frame}
    end
    
    test "streams content chunks", %{token: token, frame: frame} do
      assert {:ok, frame} = Streaming.stream_chunk(frame, token, "First chunk")
      assert {:ok, frame} = Streaming.stream_chunk(frame, token, "Second chunk")
    end
    
    test "rejects invalid token", %{frame: frame} do
      assert {:error, :invalid_token} = Streaming.stream_chunk(frame, "bad_token", "chunk")
    end
  end
  
  describe "complete_stream/3" do
    setup do
      frame = Hermes.Server.Frame.new()
      {:ok, token, frame} = Streaming.start_stream(frame, "test")
      {:ok, token: token, frame: frame}
    end
    
    test "completes stream successfully", %{token: token, frame: frame} do
      final_result = %{"status" => "completed", "data" => "result"}
      
      assert {:ok, frame} = Streaming.complete_stream(frame, token, final_result)
      
      # Verify context was cleaned up
      assert Hermes.Server.Frame.get_private(frame, {:streaming, token}) == nil
    end
    
    test "completes stream without result", %{token: token, frame: frame} do
      assert {:ok, frame} = Streaming.complete_stream(frame, token)
      
      # Verify context was cleaned up
      assert Hermes.Server.Frame.get_private(frame, {:streaming, token}) == nil
    end
    
    test "rejects invalid token", %{frame: frame} do
      assert {:error, :invalid_token} = Streaming.complete_stream(frame, "bad_token")
    end
  end
  
  describe "streaming_response/2" do
    test "creates proper streaming response structure" do
      response = Streaming.streaming_response("initial content", "prog_123")
      
      assert response["content"] == "initial content"
      assert response["isPartial"] == true
      assert response["progressToken"] == "prog_123"
    end
  end
  
  describe "with_stream/3" do
    test "executes function with automatic stream management" do
      frame = Hermes.Server.Frame.new()
      
      result = Streaming.with_stream(frame, "test_op", fn frame, token ->
        # Simulate some work
        {:ok, frame} = Streaming.send_progress(frame, token, %{progress: 0.5})
        {:ok, frame} = Streaming.stream_chunk(frame, token, "Working...")
        
        {:ok, "final result", frame}
      end)
      
      assert {:ok, response, _frame} = result
      assert response["content"] == "final result"
      assert response["isPartial"] == true
      assert String.starts_with?(response["progressToken"], "prog_")
    end
    
    test "cleans up on error" do
      frame = Hermes.Server.Frame.new()
      
      result = Streaming.with_stream(frame, "test_op", fn _frame, _token ->
        {:error, "something went wrong"}
      end)
      
      assert {:error, "something went wrong"} = result
    end
    
    test "cleans up on exception" do
      frame = Hermes.Server.Frame.new()
      
      assert_raise RuntimeError, fn ->
        Streaming.with_stream(frame, "test_op", fn _frame, _token ->
          raise "boom!"
        end)
      end
    end
  end
end