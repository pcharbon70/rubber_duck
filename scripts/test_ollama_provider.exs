#!/usr/bin/env elixir

# Test script for RubberDuck Ollama Provider
# Run with: mix run scripts/test_ollama_provider.exs

alias RubberDuck.LLM.Providers.Ollama
alias RubberDuck.LLM.{Request, Response, ProviderConfig}

IO.puts("=== Testing RubberDuck Ollama Provider ===\n")

# Test 1: Provider Info
IO.puts("1. Testing provider info...")
info = Ollama.info()
IO.inspect(info, label: "Provider info")

# Test 2: Feature Support
IO.puts("\n2. Testing feature support...")
features = [:streaming, :system_messages, :json_mode, :function_calling, :vision]
Enum.each(features, fn feature ->
  supports = Ollama.supports_feature?(feature)
  IO.puts("  #{feature}: #{supports}")
end)

# Test 3: Config Validation
IO.puts("\n3. Testing config validation...")
valid_config = %ProviderConfig{
  name: :ollama,
  adapter: Ollama,
  base_url: "http://localhost:11434"
}

invalid_config = %ProviderConfig{
  name: :ollama,
  adapter: Ollama,
  base_url: nil
}

IO.inspect(Ollama.validate_config(valid_config), label: "Valid config")
IO.inspect(Ollama.validate_config(invalid_config), label: "Invalid config")

# Test 4: Health Check
IO.puts("\n4. Testing health check...")
case Ollama.health_check(valid_config) do
  {:ok, health} ->
    IO.puts("✓ Health check passed!")
    IO.inspect(health, label: "Health status")
    
  {:error, reason} ->
    IO.puts("✗ Health check failed: #{inspect(reason)}")
end

# Test 5: Token Counting
IO.puts("\n5. Testing token counting...")
result = Ollama.count_tokens("Test text", "llama2")
IO.inspect(result, label: "Token count result")

# Test 6: Mock Execution (without actual model)
IO.puts("\n6. Testing request building (dry run)...")
request = %Request{
  model: "llama2",
  messages: [
    %{"role" => "system", "content" => "You are helpful."},
    %{"role" => "user", "content" => "Hello"}
  ],
  options: %{
    temperature: 0.7,
    max_tokens: 100,
    json_mode: true
  }
}

IO.puts("Request would be sent to Ollama with:")
IO.puts("  Model: #{request.model}")
IO.puts("  Messages: #{length(request.messages)}")
IO.puts("  Options: #{inspect(request.options)}")

# Test 7: Response Parsing
IO.puts("\n7. Testing response parsing...")
# Simulate Ollama response
mock_response = %{
  "model" => "llama2",
  "created_at" => "2024-01-01T00:00:00Z",
  "message" => %{
    "role" => "assistant",
    "content" => "Hello! How can I help you?"
  },
  "done" => true,
  "prompt_eval_count" => 10,
  "eval_count" => 15,
  "total_duration" => 5_000_000_000,
  "eval_duration" => 3_500_000_000
}

response = Response.from_provider(:ollama, mock_response)
IO.inspect(response, label: "Parsed response", limit: :infinity)

# Test 8: Cost Calculation
IO.puts("\n8. Testing cost calculation...")
cost = Response.calculate_cost(response)
IO.puts("Cost for Ollama (should be 0.0): $#{cost}")

IO.puts("\n=== All tests completed! ===")
IO.puts("\nTo test with real models:")
IO.puts("1. Install Ollama: curl -fsSL https://ollama.ai/install.sh | sh")
IO.puts("2. Pull a model: ollama pull llama2")
IO.puts("3. Run: mix run scripts/test_ollama_live.exs")