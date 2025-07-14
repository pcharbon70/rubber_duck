defmodule RubberDuck.ReqOllamaTest do
  use ExUnit.Case
  require Logger
  
  test "test Req directly with Ollama" do
    url = "http://localhost:11434/api/chat"
    body = %{
      "model" => "codellama",
      "messages" => [%{"role" => "user", "content" => "What is the capital of france?"}],
      "stream" => false,
      "options" => %{"temperature" => 0.6, "num_predict" => 100}
    }
    
    IO.puts("\n=== Testing Req with different configurations ===")
    
    # Test 1: Basic Req.post
    IO.puts("\n1. Basic Req.post")
    start_time = System.monotonic_time(:millisecond)
    
    result1 = Req.post(url, json: body)
    
    end_time = System.monotonic_time(:millisecond)
    IO.puts("Time: #{end_time - start_time}ms")
    IO.inspect(result1, label: "Result", pretty: true)
    
    # Test 2: With timeout options like in Ollama provider
    IO.puts("\n2. With timeout options")
    start_time = System.monotonic_time(:millisecond)
    
    result2 = Req.post(url, 
      json: body,
      receive_timeout: 120_000,
      connect_options: [timeout: 120_000],
      pool_timeout: 120_000,
      retry: false
    )
    
    end_time = System.monotonic_time(:millisecond)
    IO.puts("Time: #{end_time - start_time}ms")
    IO.inspect(result2, label: "Result", pretty: true)
    
    # Test 3: With headers
    IO.puts("\n3. With headers")
    start_time = System.monotonic_time(:millisecond)
    
    result3 = Req.post(url, 
      json: body,
      headers: [{"content-type", "application/json"}],
      receive_timeout: 120_000
    )
    
    end_time = System.monotonic_time(:millisecond)
    IO.puts("Time: #{end_time - start_time}ms")
    IO.inspect(result3, label: "Result", pretty: true)
    
    assert true
  end
end