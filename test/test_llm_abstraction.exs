defmodule TestLLMAbstraction do
  @moduledoc """
  Simple test to verify LLM abstraction components work.
  """

  alias RubberDuck.LLMAbstraction.{
    Capability,
    CapabilityMatcher,
    Provider,
    ProviderRegistry
  }
  
  alias RubberDuck.LLMAbstraction.Message
  alias RubberDuck.LLMAbstraction.Providers.MockProvider

  def test_capability_system do
    IO.puts("=== Testing Capability System ===")
    
    # Test capability creation
    chat_cap = Capability.chat_completion(constraints: [max_tokens: 4096])
    IO.puts("Created chat capability: #{inspect(chat_cap.name)}")
    
    # Test capability matching
    requirements = [:chat_completion, {:max_tokens, 2048}]
    capabilities = [chat_cap, Capability.streaming(), Capability.function_calling()]
    
    satisfied = CapabilityMatcher.provider_satisfies?(capabilities, requirements)
    IO.puts("Requirements satisfied: #{satisfied}")
    
    :ok
  end

  def test_message_protocol do
    IO.puts("=== Testing Message Protocol ===")
    
    # Test message creation
    user_msg = Message.Factory.user("Hello, how are you?")
    assistant_msg = Message.Factory.assistant("I'm doing well, thank you!")
    system_msg = Message.Factory.system("You are a helpful assistant.")
    
    IO.puts("Created user message: #{Message.role(user_msg)} - #{Message.content(user_msg)}")
    IO.puts("Created assistant message: #{Message.role(assistant_msg)} - #{Message.content(assistant_msg)}")
    IO.puts("Created system message: #{Message.role(system_msg)} - #{Message.content(system_msg)}")
    
    # Test provider format conversion
    openai_format = Message.to_provider_format(user_msg, :openai)
    IO.puts("OpenAI format: #{inspect(openai_format)}")
    
    :ok
  end

  def test_provider_registry do
    IO.puts("=== Testing Provider Registry ===")
    
    # Test mock provider registration
    config = %{
      responses: %{"Hello" => "Hi there!"},
      default_response: "I understand.",
      latency_ms: 100,
      error_rate: 0.0
    }
    
    case ProviderRegistry.register_provider(:mock_test, MockProvider, config) do
      :ok ->
        IO.puts("Successfully registered mock provider")
        
        # Test provider listing
        providers = ProviderRegistry.list_providers()
        IO.puts("Registered providers: #{inspect(Map.keys(providers))}")
        
        # Test capability discovery
        requirements = [:chat_completion]
        matching = ProviderRegistry.find_providers(requirements)
        IO.puts("Providers with chat capability: #{inspect(matching)}")
        
      {:error, reason} ->
        IO.puts("Failed to register provider: #{inspect(reason)}")
    end
    
    :ok
  end

  def test_mock_provider do
    IO.puts("=== Testing Mock Provider ===")
    
    config = %{
      responses: %{"test" => "mock response"},
      default_response: "default mock response",
      latency_ms: 50
    }
    
    case MockProvider.init(config) do
      {:ok, state} ->
        IO.puts("Mock provider initialized successfully")
        
        # Test capabilities
        capabilities = MockProvider.capabilities(state)
        IO.puts("Mock provider capabilities: #{length(capabilities)} capabilities")
        
        # Test health check
        health = MockProvider.health_check(state)
        IO.puts("Mock provider health: #{health}")
        
        # Test metadata
        metadata = MockProvider.metadata()
        IO.puts("Mock provider info: #{metadata.name} v#{metadata.version}")
        
      {:error, reason} ->
        IO.puts("Failed to initialize mock provider: #{inspect(reason)}")
    end
    
    :ok
  end

  def run_all_tests do
    IO.puts("=== Testing LLM Abstraction Layer ===")
    
    test_capability_system()
    test_message_protocol()
    test_mock_provider()
    test_provider_registry()
    
    IO.puts("=== All tests completed ===")
  end
end

# Run the tests
TestLLMAbstraction.run_all_tests()