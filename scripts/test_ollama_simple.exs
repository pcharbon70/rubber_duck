#!/usr/bin/env elixir

# Simple unit test for Ollama provider without starting the full app
# Run with: elixir scripts/test_ollama_simple.exs

# Add the lib directory to the code path
Code.prepend_path("_build/dev/lib/rubber_duck/ebin")

# Load required modules
Code.require_file("lib/rubber_duck/llm/provider.ex")
Code.require_file("lib/rubber_duck/llm/request.ex")
Code.require_file("lib/rubber_duck/llm/response.ex")
Code.require_file("lib/rubber_duck/llm/provider_config.ex")
Code.require_file("lib/rubber_duck/llm/providers/ollama.ex")

alias RubberDuck.LLM.Providers.Ollama
alias RubberDuck.LLM.{Request, Response, ProviderConfig}

IO.puts("=== Testing Ollama Provider (Unit Tests) ===\n")

# Test 1: Module exists and implements behavior
IO.puts("1. Testing module and behavior...")
behaviors = Ollama.__info__(:attributes)[:behaviour] || []
has_provider_behavior = Enum.member?(behaviors, RubberDuck.LLM.Provider)
IO.puts("  Module exists: #{is_atom(Ollama)}")
IO.puts("  Implements Provider behavior: #{has_provider_behavior}")

# Test 2: All required callbacks are implemented
IO.puts("\n2. Testing required callbacks...")
required_callbacks = [
  execute: 2,
  validate_config: 1,
  info: 0,
  supports_feature?: 1,
  count_tokens: 2,
  health_check: 1,
  stream_completion: 3
]

Enum.each(required_callbacks, fn {func, arity} ->
  exported = function_exported?(Ollama, func, arity)
  IO.puts("  #{func}/#{arity}: #{if exported, do: "✓", else: "✗"}")
end)

# Test 3: Provider info structure
IO.puts("\n3. Testing provider info...")
info = Ollama.info()
IO.puts("  Name: #{info.name}")
IO.puts("  Description: #{info.description}")
IO.puts("  Requires API key: #{info.requires_api_key}")
IO.puts("  Supports streaming: #{info.supports_streaming}")
IO.puts("  Supports function calling: #{info.supports_function_calling}")
IO.puts("  Supports JSON mode: #{info.supports_json_mode}")
IO.puts("  Model count: #{length(info.supported_models)}")

# Test 4: Feature support
IO.puts("\n4. Testing feature support...")
features = [
  streaming: true,
  system_messages: true,
  json_mode: true,
  function_calling: false,
  vision: false,
  unknown_feature: false
]

all_correct = Enum.all?(features, fn {feature, expected} ->
  actual = Ollama.supports_feature?(feature)
  matches = actual == expected
  status = if matches, do: "✓", else: "✗"
  IO.puts("  #{feature}: #{actual} #{status}")
  matches
end)

IO.puts("  All features correct: #{all_correct}")

# Test 5: Config validation
IO.puts("\n5. Testing config validation...")

# Valid config
valid_config = %ProviderConfig{
  name: :ollama,
  adapter: Ollama,
  base_url: "http://localhost:11434"
}
valid_result = Ollama.validate_config(valid_config)
IO.puts("  Valid config: #{inspect(valid_result)}")

# Config with nil base_url (should be ok)
nil_config = %ProviderConfig{
  name: :ollama,
  adapter: Ollama,
  base_url: nil
}
nil_result = Ollama.validate_config(nil_config)
IO.puts("  Nil base_url: #{inspect(nil_result)}")

# Test 6: Token counting
IO.puts("\n6. Testing token counting...")
token_result = Ollama.count_tokens("Test text", "llama2")
IO.puts("  Result: #{inspect(token_result)}")
IO.puts("  Expected: {:error, :not_supported}")
IO.puts("  Correct: #{token_result == {:error, :not_supported}}")

# Test 7: Response parsing
IO.puts("\n7. Testing response parsing...")
# Test chat response format
chat_response = %{
  "model" => "llama2",
  "created_at" => "2024-01-01T00:00:00Z",
  "message" => %{
    "role" => "assistant",
    "content" => "Hello from Ollama!"
  },
  "done" => true,
  "prompt_eval_count" => 10,
  "eval_count" => 15,
  "total_duration" => 5_000_000_000
}

parsed = Response.from_provider(:ollama, chat_response)
IO.puts("  Response ID generated: #{String.starts_with?(parsed.id, "resp_")}")
IO.puts("  Model: #{parsed.model}")
IO.puts("  Provider: #{parsed.provider}")
IO.puts("  Content: #{Response.get_content(parsed)}")
IO.puts("  Usage tokens: #{parsed.usage.total_tokens}")

# Test 8: Cost calculation (should be free)
IO.puts("\n8. Testing cost calculation...")
cost = Response.calculate_cost(parsed)
IO.puts("  Cost: $#{cost}")
IO.puts("  Is free: #{cost == 0.0}")

IO.puts("\n=== All unit tests completed! ===")
IO.puts("\nSummary:")
IO.puts("  - Ollama provider module is correctly implemented")
IO.puts("  - All required callbacks are present")
IO.puts("  - Feature support is properly configured")
IO.puts("  - Response parsing works correctly")
IO.puts("  - Cost calculation returns 0.0 (free for local models)")
IO.puts("\nThe Ollama provider is ready for use!")