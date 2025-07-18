defmodule RubberDuck.MCP.ProtocolTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.MCP.Protocol
  
  describe "parse_message/1" do
    test "parses valid request from JSON string" do
      json = ~s({"jsonrpc":"2.0","id":1,"method":"test","params":{"key":"value"}})
      
      assert {:ok, message} = Protocol.parse_message(json)
      assert message["jsonrpc"] == "2.0"
      assert message["id"] == 1
      assert message["method"] == "test"
      assert message["params"]["key"] == "value"
    end
    
    test "parses valid request from map" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "test-id",
        "method" => "tools/list"
      }
      
      assert {:ok, ^message} = Protocol.parse_message(message)
    end
    
    test "parses valid response" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{"status" => "ok"}
      }
      
      assert {:ok, ^message} = Protocol.parse_message(message)
    end
    
    test "parses valid error response" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "error" => %{
          "code" => -32601,
          "message" => "Method not found"
        }
      }
      
      assert {:ok, ^message} = Protocol.parse_message(message)
    end
    
    test "parses valid notification" do
      message = %{
        "jsonrpc" => "2.0",
        "method" => "notification/test",
        "params" => %{"data" => "value"}
      }
      
      assert {:ok, ^message} = Protocol.parse_message(message)
    end
    
    test "rejects invalid JSON" do
      assert {:error, "Invalid JSON"} = Protocol.parse_message("{invalid json}")
    end
    
    test "rejects missing jsonrpc version" do
      message = %{"id" => 1, "method" => "test"}
      assert {:error, "Invalid or missing jsonrpc version"} = Protocol.parse_message(message)
    end
    
    test "rejects invalid jsonrpc version" do
      message = %{"jsonrpc" => "1.0", "id" => 1, "method" => "test"}
      assert {:error, "Invalid or missing jsonrpc version"} = Protocol.parse_message(message)
    end
    
    test "rejects response with both result and error" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => "ok",
        "error" => %{"code" => -1, "message" => "error"}
      }
      
      assert {:error, "Response cannot have both result and error"} = Protocol.parse_message(message)
    end
  end
  
  describe "build_request/3" do
    test "builds request with params" do
      request = Protocol.build_request(1, "test", %{"key" => "value"})
      
      assert request == %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "test",
        "params" => %{"key" => "value"}
      }
    end
    
    test "builds request without params" do
      request = Protocol.build_request("test-id", "ping")
      
      assert request == %{
        "jsonrpc" => "2.0",
        "id" => "test-id",
        "method" => "ping"
      }
    end
  end
  
  describe "build_response/2" do
    test "builds response with result" do
      response = Protocol.build_response(1, %{"status" => "ok"})
      
      assert response == %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{"status" => "ok"}
      }
    end
  end
  
  describe "build_error/4" do
    test "builds error with atom code" do
      error = Protocol.build_error(1, :method_not_found, "Unknown method")
      
      assert error == %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "error" => %{
          "code" => -32601,
          "message" => "Unknown method"
        }
      }
    end
    
    test "builds error with integer code" do
      error = Protocol.build_error(1, -32000, "Custom error")
      
      assert error == %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "error" => %{
          "code" => -32000,
          "message" => "Custom error"
        }
      }
    end
    
    test "builds error with data" do
      error = Protocol.build_error(1, :invalid_params, "Invalid", %{"field" => "name"})
      
      assert error == %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "error" => %{
          "code" => -32602,
          "message" => "Invalid",
          "data" => %{"field" => "name"}
        }
      }
    end
  end
  
  describe "build_notification/2" do
    test "builds notification with params" do
      notification = Protocol.build_notification("test", %{"key" => "value"})
      
      assert notification == %{
        "jsonrpc" => "2.0",
        "method" => "test",
        "params" => %{"key" => "value"}
      }
    end
    
    test "builds notification without params" do
      notification = Protocol.build_notification("ping")
      
      assert notification == %{
        "jsonrpc" => "2.0",
        "method" => "ping"
      }
    end
  end
  
  describe "message type detection" do
    test "request?/1 correctly identifies requests" do
      assert Protocol.request?(%{"jsonrpc" => "2.0", "id" => 1, "method" => "test"})
      refute Protocol.request?(%{"jsonrpc" => "2.0", "method" => "test"})
      refute Protocol.request?(%{"jsonrpc" => "2.0", "id" => 1, "result" => "ok"})
    end
    
    test "response?/1 correctly identifies responses" do
      assert Protocol.response?(%{"jsonrpc" => "2.0", "id" => 1, "result" => "ok"})
      assert Protocol.response?(%{"jsonrpc" => "2.0", "id" => 1, "error" => %{"code" => -1, "message" => "error"}})
      refute Protocol.response?(%{"jsonrpc" => "2.0", "id" => 1, "method" => "test"})
    end
    
    test "notification?/1 correctly identifies notifications" do
      assert Protocol.notification?(%{"jsonrpc" => "2.0", "method" => "test"})
      refute Protocol.notification?(%{"jsonrpc" => "2.0", "id" => 1, "method" => "test"})
    end
  end
  
  describe "parse_batch/1" do
    test "parses valid batch" do
      batch = [
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "test1"},
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "test2"}
      ]
      
      assert {:ok, parsed} = Protocol.parse_batch(batch)
      assert length(parsed) == 2
    end
    
    test "rejects empty batch" do
      assert {:error, "Batch cannot be empty"} = Protocol.parse_batch([])
    end
    
    test "rejects batch with invalid message" do
      batch = [
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "test1"},
        %{"id" => 2, "method" => "test2"}  # Missing jsonrpc
      ]
      
      assert {:error, _} = Protocol.parse_batch(batch)
    end
  end
end