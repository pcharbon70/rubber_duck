defmodule RubberDuck.LLMAbstraction.Providers.MockProviderTest do
  use ExUnit.Case, async: true

  alias RubberDuck.LLMAbstraction.Providers.MockProvider
  alias RubberDuck.LLMAbstraction.Message

  describe "init/1" do
    test "initializes with default configuration" do
      {:ok, state} = MockProvider.init(%{})
      
      assert state.default_response == "This is a mock response."
      assert state.latency_ms == 0
      assert state.error_rate == 0.0
      assert state.call_count == 0
      assert state.health == :healthy
    end

    test "initializes with custom configuration" do
      config = %{
        responses: %{"test" => "custom response"},
        default_response: "fallback",
        latency_ms: 100,
        error_rate: 0.5
      }
      
      {:ok, state} = MockProvider.init(config)
      
      assert state.responses == %{"test" => "custom response"}
      assert state.default_response == "fallback"
      assert state.latency_ms == 100
      assert state.error_rate == 0.5
    end
  end

  describe "chat/3" do
    setup do
      {:ok, state} = MockProvider.init(%{
        responses: %{
          "Hello" => "Hi there!",
          "What's 2+2?" => "4"
        },
        default_response: "I don't know"
      })
      
      {:ok, state: state}
    end

    test "returns configured response for matching input", %{state: state} do
      messages = [
        Message.Factory.system("You are helpful"),
        Message.Factory.user("Hello")
      ]
      
      {:ok, response, new_state} = MockProvider.chat(messages, state, [])
      
      assert response.content == "Hi there!"
      assert response.provider == :mock
      assert response.role == :assistant
      assert response.finish_reason == :stop
      assert new_state.call_count == 1
    end

    test "returns default response for non-matching input", %{state: state} do
      messages = [Message.Factory.user("Unknown question")]
      
      {:ok, response, _} = MockProvider.chat(messages, state, [])
      
      assert response.content == "I don't know"
    end

    test "calculates token usage", %{state: state} do
      messages = [
        Message.Factory.user("Hello"),
        Message.Factory.assistant("Hi!"),
        Message.Factory.user("What's 2+2?")
      ]
      
      {:ok, response, _} = MockProvider.chat(messages, state, [])
      
      assert response.usage.prompt_tokens > 0
      assert response.usage.completion_tokens >= 0  # Token count varies by response
      assert response.usage.total_tokens > 0
    end

    test "simulates latency", %{state: state} do
      state = %{state | latency_ms: 50}
      messages = [Message.Factory.user("Test")]
      
      start_time = System.monotonic_time(:millisecond)
      {:ok, response, _} = MockProvider.chat(messages, state, [])
      elapsed = System.monotonic_time(:millisecond) - start_time
      
      assert elapsed >= 50
      assert response.latency_ms == 50
    end

    test "simulates errors based on error rate" do
      {:ok, state} = MockProvider.init(%{error_rate: 1.0})
      messages = [Message.Factory.user("Test")]
      
      assert {:error, :simulated_error, new_state} = MockProvider.chat(messages, state, [])
      assert new_state.call_count == 1
    end

    test "uses custom model from options", %{state: state} do
      messages = [Message.Factory.user("Test")]
      opts = [model: "custom-mock-model"]
      
      {:ok, response, _} = MockProvider.chat(messages, state, opts)
      
      assert response.model == "custom-mock-model"
    end
  end

  describe "complete/3" do
    setup do
      {:ok, state} = MockProvider.init(%{
        responses: %{
          "Once upon a time" => "there was a mock provider"
        }
      })
      
      {:ok, state: state}
    end

    test "completes prompts with configured responses", %{state: state} do
      {:ok, response, new_state} = MockProvider.complete("Once upon a time", state, [])
      
      assert response.content == "there was a mock provider"
      assert response.provider == :mock
      assert new_state.call_count == 1
    end

    test "calculates tokens for single prompt", %{state: state} do
      {:ok, response, _} = MockProvider.complete("Test prompt here", state, [])
      
      assert response.usage.prompt_tokens >= 3  # At least 3 tokens
      assert response.usage.completion_tokens > 0
    end
  end

  describe "embed/3" do
    test "generates embeddings for single text" do
      {:ok, state} = MockProvider.init(%{})
      
      {:ok, embeddings, new_state} = MockProvider.embed("test text", state, [])
      
      assert length(embeddings) == 1
      [embedding] = embeddings
      assert length(embedding) == 48  # SHA384 = 48 bytes
      assert Enum.all?(embedding, &(&1 >= -1.0 and &1 <= 1.0))
      assert new_state.call_count == 1
    end

    test "generates embeddings for multiple texts" do
      {:ok, state} = MockProvider.init(%{})
      texts = ["first", "second", "third"]
      
      {:ok, embeddings, _} = MockProvider.embed(texts, state, [])
      
      assert length(embeddings) == 3
      
      # Each text should produce a different embedding
      unique_embeddings = Enum.uniq(embeddings)
      assert length(unique_embeddings) == 3
    end

    test "generates deterministic embeddings" do
      {:ok, state} = MockProvider.init(%{})
      
      {:ok, [embedding1], state} = MockProvider.embed("same text", state, [])
      {:ok, [embedding2], _} = MockProvider.embed("same text", state, [])
      
      assert embedding1 == embedding2
    end
  end

  describe "stream_chat/3" do
    test "creates a stream of response chunks" do
      {:ok, state} = MockProvider.init(%{
        responses: %{"Stream test" => "This is a streaming response"}
      })
      
      messages = [Message.Factory.user("Stream test")]
      
      {:ok, stream, new_state} = MockProvider.stream_chat(messages, state, [])
      
      # Collect stream chunks
      chunks = Enum.to_list(stream)
      
      assert length(chunks) > 1
      assert new_state.call_count == 1
      
      # Verify chunk format
      first_chunk = hd(chunks)
      assert %{"choices" => [choice]} = first_chunk
      assert Map.has_key?(choice, "delta")
      assert Map.has_key?(choice["delta"], "content")
      
      # Reconstruct full content
      full_content = chunks
      |> Enum.map(fn %{"choices" => [%{"delta" => %{"content" => content}}]} -> content end)
      |> Enum.join()
      
      assert full_content == "This is a streaming response"
    end
  end

  describe "capabilities/1" do
    test "returns comprehensive capability list" do
      {:ok, state} = MockProvider.init(%{})
      capabilities = MockProvider.capabilities(state)
      
      capability_names = Enum.map(capabilities, & &1.name)
      
      assert :chat_completion in capability_names
      assert :text_completion in capability_names
      assert :embeddings in capability_names
      assert :streaming in capability_names
      assert :function_calling in capability_names
      
      # Check specific constraints
      chat_cap = Enum.find(capabilities, & &1.name == :chat_completion)
      assert {:max_tokens, 4096} in chat_cap.constraints
    end
  end

  describe "health_check/1" do
    test "returns health status" do
      {:ok, state} = MockProvider.init(%{})
      assert MockProvider.health_check(state) == :healthy
      
      # Can modify health in state
      unhealthy_state = %{state | health: :degraded}
      assert MockProvider.health_check(unhealthy_state) == :degraded
    end
  end

  describe "metadata/0" do
    test "returns provider metadata" do
      metadata = MockProvider.metadata()
      
      assert metadata.name == "Mock Provider"
      assert metadata.version == "1.0.0"
      assert is_binary(metadata.description)
      assert metadata.author == "RubberDuck Team"
    end
  end

  describe "validate_config/1" do
    test "accepts any configuration" do
      assert :ok = MockProvider.validate_config(%{})
      assert :ok = MockProvider.validate_config(%{anything: "goes"})
    end
  end

  describe "terminate/1" do
    test "cleans up successfully" do
      {:ok, state} = MockProvider.init(%{})
      assert :ok = MockProvider.terminate(state)
    end
  end
end