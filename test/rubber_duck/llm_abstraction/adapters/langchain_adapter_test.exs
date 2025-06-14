defmodule RubberDuck.LLMAbstraction.Adapters.LangChainAdapterTest do
  use ExUnit.Case, async: true

  alias RubberDuck.LLMAbstraction.Adapters.{LangChainAdapter, LangChainRegistry}
  alias RubberDuck.LLMAbstraction.Message

  # Mock LangChain module for testing
  defmodule MockLangChainProvider do
    def init(_config), do: {:ok, %{client: :mock}}
    
    def chat(messages, _opts \\ []) do
      content = case length(messages) do
        0 -> "Empty conversation"
        1 -> "Single message response"
        _ -> "Multi-turn response"
      end
      
      %{
        id: "langchain-123",
        model: "langchain-test",
        content: content,
        role: :assistant,
        finish_reason: :stop,
        usage: %{
          prompt_tokens: 10,
          completion_tokens: 5,
          total_tokens: 15
        },
        metadata: %{source: "langchain"}
      }
    end
    
    def complete(prompt, _opts \\ []) do
      %{
        content: "Completed: #{prompt}",
        finish_reason: :stop,
        usage: %{prompt_tokens: 5, completion_tokens: 3, total_tokens: 8}
      }
    end
    
    def embed(input, opts \\ [])
    
    def embed(input, _opts) when is_binary(input) do
      [1, 2, 3, 4, 5]  # Simple mock embedding
    end
    
    def embed(inputs, _opts) when is_list(inputs) do
      Enum.map(inputs, fn _ -> [1, 2, 3, 4, 5] end)
    end
    
    def stream_chat(messages, _opts \\ []) do
      content = "Streaming response for #{length(messages)} messages"
      chunks = String.graphemes(content)
      
      Stream.map(chunks, fn char ->
        %{content: char}
      end)
    end
    
    def capabilities do
      [
        %{name: :chat_completion, constraints: []},
        %{name: :text_completion, constraints: []},
        %{name: :embeddings, constraints: []}
      ]
    end
    
    def health_check, do: :healthy
    def terminate(_client), do: :ok
  end

  # Minimal LangChain module without optional functions
  defmodule MinimalLangChainProvider do
    def chat(_messages, _opts \\ []) do
      %{content: "Minimal response", role: :assistant}
    end
    
    def complete(prompt, _opts \\ []) do
      %{content: "Completed: #{prompt}"}
    end
  end

  describe "validation" do
    test "validates complete LangChain module" do
      result = LangChainRegistry.validate_langchain_module(MockLangChainProvider)
      
      assert {:ok, info} = result
      assert length(info.required) == 2
      assert {:chat, 2} in info.required
      assert {:complete, 2} in info.required
      assert Enum.empty?(info.missing_required)
    end

    test "validates minimal LangChain module" do
      result = LangChainRegistry.validate_langchain_module(MinimalLangChainProvider)
      
      assert {:ok, info} = result
      assert Enum.empty?(info.missing_required)
      # Should have some missing optional functions
      assert length(info.missing_optional) > 0
    end

    test "rejects non-existent module" do
      result = LangChainRegistry.validate_langchain_module(NonExistentModule)
      assert {:error, {:module_not_found, _}} = result
    end

    test "rejects module without required functions" do
      result = LangChainRegistry.validate_langchain_module(String)
      assert {:error, {:missing_required_functions, missing}} = result
      assert {:chat, 2} in missing
      assert {:complete, 2} in missing
    end
  end

  describe "LangChainAdapter with MockLangChainProvider" do
    setup do
      config = %{
        provider_name: :test_langchain,
        langchain_module: MockLangChainProvider,
        api_key: "test-key"
      }
      
      {:ok, state} = LangChainAdapter.init(config)
      {:ok, state: state}
    end

    test "validates configuration", %{state: state} do
      assert state.provider_name == :test_langchain
      assert state.langchain_module == MockLangChainProvider
      assert state.call_count == 0
    end

    test "executes chat through LangChain module", %{state: state} do
      messages = [
        Message.Factory.user("Hello"),
        Message.Factory.assistant("Hi there!")
      ]
      
      {:ok, response, new_state} = LangChainAdapter.chat(messages, state, [])
      
      assert response.content == "Multi-turn response"
      assert response.provider == :test_langchain
      assert response.model == "langchain-test"
      assert response.usage.total_tokens == 15
      assert new_state.call_count == 1
    end

    test "executes completion through LangChain module", %{state: state} do
      {:ok, response, new_state} = LangChainAdapter.complete("Test prompt", state, [])
      
      assert response.content == "Completed: Test prompt"
      assert new_state.call_count == 1
    end

    test "executes embeddings through LangChain module", %{state: state} do
      {:ok, embeddings, new_state} = LangChainAdapter.embed("test text", state, [])
      
      assert embeddings == [1, 2, 3, 4, 5]
      assert new_state.call_count == 1
    end

    test "executes embeddings for multiple inputs", %{state: state} do
      inputs = ["text1", "text2", "text3"]
      {:ok, embeddings, _} = LangChainAdapter.embed(inputs, state, [])
      
      assert length(embeddings) == 3
      assert Enum.all?(embeddings, &(&1 == [1, 2, 3, 4, 5]))
    end

    test "executes streaming chat", %{state: state} do
      messages = [Message.Factory.user("Stream test")]
      
      {:ok, stream, new_state} = LangChainAdapter.stream_chat(messages, state, [])
      
      chunks = Enum.take(stream, 5)
      assert length(chunks) == 5
      
      # Verify chunk format is OpenAI-compatible
      first_chunk = hd(chunks)
      assert %{"choices" => [choice]} = first_chunk
      assert Map.has_key?(choice["delta"], "content")
      assert new_state.call_count == 1
    end

    test "retrieves capabilities from LangChain module", %{state: state} do
      capabilities = LangChainAdapter.capabilities(state)
      
      capability_names = Enum.map(capabilities, & &1.name)
      assert :chat_completion in capability_names
      assert :text_completion in capability_names
      assert :embeddings in capability_names
    end

    test "checks health through LangChain module", %{state: state} do
      assert LangChainAdapter.health_check(state) == :healthy
    end

    test "terminates cleanly", %{state: state} do
      assert LangChainAdapter.terminate(state) == :ok
    end
  end

  describe "LangChainAdapter with minimal provider" do
    setup do
      config = %{
        provider_name: :minimal_langchain,
        langchain_module: MinimalLangChainProvider
      }
      
      {:ok, state} = LangChainAdapter.init(config)
      {:ok, state: state}
    end

    test "falls back to default capabilities when not supported", %{state: state} do
      capabilities = LangChainAdapter.capabilities(state)
      
      # Should return default capabilities
      capability_names = Enum.map(capabilities, & &1.name)
      assert :chat_completion in capability_names
      assert :text_completion in capability_names
    end

    test "handles missing optional functions gracefully", %{state: state} do
      # embed function doesn't exist
      assert {:error, {:function_not_supported, :embed}, _} = 
        LangChainAdapter.embed("test", state, [])
      
      # health_check function doesn't exist
      assert LangChainAdapter.health_check(state) == :degraded
    end
  end

  describe "configuration validation" do
    test "validates valid configuration" do
      config = %{
        langchain_module: MockLangChainProvider,
        api_key: "test"
      }
      
      assert :ok = LangChainAdapter.validate_config(config)
    end

    test "rejects configuration without langchain_module" do
      config = %{api_key: "test"}
      
      assert {:error, {:missing_required_keys, [:langchain_module]}} = 
        LangChainAdapter.validate_config(config)
    end

    test "rejects configuration with invalid langchain_module" do
      config = %{langchain_module: String}
      
      assert {:error, {:invalid_langchain_module, String}} = 
        LangChainAdapter.validate_config(config)
    end
  end

  describe "LangChainRegistry" do
    test "registers LangChain provider successfully" do
      # This test requires the ProviderRegistry to be running
      # We'll just test that the function exists and accepts the right params
      assert function_exported?(LangChainRegistry, :register_langchain_provider, 3)
    end

    test "discovers no LangChain modules by default" do
      modules = LangChainRegistry.discover_langchain_modules()
      assert modules == []
    end
  end

  describe "metadata" do
    test "returns adapter metadata" do
      metadata = LangChainAdapter.metadata()
      
      assert metadata.name == "LangChain Adapter"
      assert metadata.version == "1.0.0"
      assert metadata.adapter == true
      assert is_binary(metadata.description)
    end
  end

  describe "error handling" do
    test "handles LangChain module errors" do
      defmodule ErrorLangChainProvider do
        def chat(_messages, _opts), do: raise("Simulated error")
        def complete(_prompt, _opts), do: raise("Simulated error")
      end
      
      config = %{
        langchain_module: ErrorLangChainProvider,
        provider_name: :error_test
      }
      
      {:ok, state} = LangChainAdapter.init(config)
      
      assert {:error, {:langchain_error, _}, _} = 
        LangChainAdapter.chat([], state, [])
      
      assert {:error, {:langchain_error, _}, _} = 
        LangChainAdapter.complete("test", state, [])
    end
  end
end