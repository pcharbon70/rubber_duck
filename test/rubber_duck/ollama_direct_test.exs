defmodule RubberDuck.OllamaDirectTest do
  use ExUnit.Case
  require Logger
  
  test "test direct Ollama API call" do
    # Test direct HTTP call to Ollama
    IO.puts("\n=== Testing Direct Ollama API ===")
    
    url = "http://localhost:11434/api/generate"
    body = %{
      model: "codellama",
      prompt: "What is 2+2? Answer with just the number.",
      stream: false
    }
    
    IO.puts("Request URL: #{url}")
    IO.puts("Request body: #{inspect(body)}")
    
    start_time = System.monotonic_time(:millisecond)
    
    result = Req.post(url, 
      json: body,
      receive_timeout: 10_000,
      retry: false
    )
    
    end_time = System.monotonic_time(:millisecond)
    time_taken = end_time - start_time
    
    IO.puts("Time taken: #{time_taken}ms")
    IO.inspect(result, label: "Result", pretty: true)
    
    case result do
      {:ok, %{status: 200, body: response}} ->
        IO.puts("\nSuccess! Response:")
        IO.inspect(response, pretty: true)
        
      {:ok, %{status: status}} ->
        IO.puts("\nHTTP Error: #{status}")
        
      {:error, reason} ->
        IO.puts("\nError: #{inspect(reason)}")
    end
    
    # Also test chat endpoint
    IO.puts("\n=== Testing Ollama Chat API ===")
    
    chat_url = "http://localhost:11434/api/chat"
    chat_body = %{
      model: "codellama",
      messages: [
        %{role: "user", content: "What is 2+2? Answer with just the number."}
      ],
      stream: false
    }
    
    IO.puts("Chat URL: #{chat_url}")
    IO.puts("Chat body: #{inspect(chat_body)}")
    
    start_time = System.monotonic_time(:millisecond)
    
    chat_result = Req.post(chat_url, 
      json: chat_body,
      receive_timeout: 10_000,
      retry: false
    )
    
    end_time = System.monotonic_time(:millisecond)
    time_taken = end_time - start_time
    
    IO.puts("Time taken: #{time_taken}ms")
    IO.inspect(chat_result, label: "Chat Result", pretty: true)
    
    # Test through our Ollama provider
    IO.puts("\n=== Testing Through Ollama Provider ===")
    
    config = %RubberDuck.LLM.ProviderConfig{
      name: :ollama,
      adapter: RubberDuck.LLM.Providers.Ollama,
      base_url: "http://localhost:11434",
      models: ["codellama"],
      timeout: 10_000
    }
    
    request = %RubberDuck.LLM.Request{
      model: "codellama",
      messages: [
        %{role: "user", content: "What is 2+2?"}
      ],
      options: %{
        temperature: 0.5,
        max_tokens: 100,
        timeout: 10_000
      }
    }
    
    start_time = System.monotonic_time(:millisecond)
    
    provider_result = RubberDuck.LLM.Providers.Ollama.execute(request, config)
    
    end_time = System.monotonic_time(:millisecond)
    time_taken = end_time - start_time
    
    IO.puts("Time taken: #{time_taken}ms")
    IO.inspect(provider_result, label: "Provider Result", pretty: true)
    
    assert true
  end
end