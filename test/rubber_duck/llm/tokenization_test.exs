defmodule RubberDuck.LLM.TokenizationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.LLM.Tokenization

  describe "count_tokens/2 with text" do
    test "counts tokens for GPT-4 model" do
      text = "Hello, world!"

      {:ok, count} = Tokenization.count_tokens(text, "gpt-4")

      # Should be around 3-4 tokens for this simple text
      assert count > 0
      assert count < 10
    end

    test "counts tokens for GPT-3.5-turbo model" do
      text = "The quick brown fox jumps over the lazy dog"

      {:ok, count} = Tokenization.count_tokens(text, "gpt-3.5-turbo")

      # Should be around 9-12 tokens
      assert count > 5
      assert count < 20
    end

    test "counts tokens for Claude model" do
      text = "Hello, world!"

      {:ok, count} = Tokenization.count_tokens(text, "claude-3-sonnet")

      # Should use character-based approximation
      assert count > 0
      assert count < 10
    end

    test "handles empty text" do
      {:ok, count} = Tokenization.count_tokens("", "gpt-4")
      assert count == 0
    end

    test "handles unknown model with fallback" do
      text = "Hello, world!"

      {:ok, count} = Tokenization.count_tokens(text, "unknown-model")

      assert count > 0
    end

    test "handles very long text" do
      text = String.duplicate("word ", 1000)

      {:ok, count} = Tokenization.count_tokens(text, "gpt-4")

      # Should be approximately 1000-1300 tokens
      assert count > 800
      assert count < 1500
    end
  end

  describe "count_tokens/2 with messages" do
    test "counts tokens for GPT-4 message list" do
      messages = [
        %{"role" => "system", "content" => "You are a helpful assistant."},
        %{"role" => "user", "content" => "Hello!"},
        %{"role" => "assistant", "content" => "Hi there! How can I help you today?"}
      ]

      {:ok, count} = Tokenization.count_tokens(messages, "gpt-4")

      # Should include content tokens plus message overhead
      assert count > 10
      assert count < 50
    end

    test "counts tokens for Claude message list" do
      messages = [
        %{"role" => "user", "content" => "What is 2+2?"},
        %{"role" => "assistant", "content" => "2+2 equals 4."}
      ]

      {:ok, count} = Tokenization.count_tokens(messages, "claude-3-sonnet")

      assert count > 5
      assert count < 20
    end

    test "handles empty message list" do
      {:ok, count} = Tokenization.count_tokens([], "gpt-4")
      assert count >= 0
    end

    test "handles messages with missing content" do
      messages = [
        %{"role" => "user"},
        %{"role" => "assistant", "content" => "Hello"}
      ]

      {:ok, count} = Tokenization.count_tokens(messages, "gpt-4")
      assert count > 0
    end
  end

  describe "get_encoding_for_model/1" do
    test "returns correct encoding for GPT-4" do
      assert Tokenization.get_encoding_for_model("gpt-4") == "cl100k_base"
    end

    test "returns correct encoding for GPT-4o" do
      assert Tokenization.get_encoding_for_model("gpt-4o") == "o200k_base"
    end

    test "returns correct encoding for GPT-3.5-turbo" do
      assert Tokenization.get_encoding_for_model("gpt-3.5-turbo") == "cl100k_base"
    end

    test "returns encoding for Claude models" do
      assert Tokenization.get_encoding_for_model("claude-3-sonnet") == "claude"
    end

    test "returns unknown for unrecognized models" do
      assert Tokenization.get_encoding_for_model("unknown-model") == "unknown"
    end
  end

  describe "supported_models/0" do
    test "returns map with OpenAI and Anthropic models" do
      models = Tokenization.supported_models()

      assert Map.has_key?(models, :openai)
      assert Map.has_key?(models, :anthropic)

      # Check that GPT-4 is listed
      openai_models = get_in(models, [:openai, :models])
      assert Enum.any?(openai_models, fn model -> model.model == "gpt-4" end)

      # Check that Claude is listed
      anthropic_models = get_in(models, [:anthropic, :models])
      assert Enum.any?(anthropic_models, fn model -> model.model == "claude-3-sonnet" end)
    end

    test "includes tiktoken support information" do
      models = Tokenization.supported_models()

      openai_models = get_in(models, [:openai, :models])
      gpt4_model = Enum.find(openai_models, fn model -> model.model == "gpt-4" end)

      assert gpt4_model.tiktoken == true
      assert gpt4_model.encoding == "cl100k_base"
    end
  end

  describe "tokenization accuracy" do
    test "OpenAI tokenization is more accurate than approximation" do
      text = "The quick brown fox jumps over the lazy dog."

      {:ok, tiktoken_count} = Tokenization.count_tokens(text, "gpt-4")

      # Compare with simple word-based approximation
      words = String.split(text, ~r/\s+/) |> length()
      word_approximation = round(words * 1.3)

      # Tiktoken should be different from simple approximation for most texts
      # (This test might occasionally fail due to coincidence, but generally holds)
      assert tiktoken_count != word_approximation
    end

    test "consistent results for same input" do
      text = "Consistency is key in tokenization."

      {:ok, count1} = Tokenization.count_tokens(text, "gpt-4")
      {:ok, count2} = Tokenization.count_tokens(text, "gpt-4")

      assert count1 == count2
    end
  end

  describe "error handling" do
    test "gracefully handles tiktoken failures" do
      # This test ensures we don't crash if tiktoken fails
      text = "Test text"

      # Should succeed or gracefully fall back
      assert {:ok, _count} = Tokenization.count_tokens(text, "gpt-4")
    end
  end
end
