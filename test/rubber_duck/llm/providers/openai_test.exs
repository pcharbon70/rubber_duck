defmodule RubberDuck.LLM.Providers.OpenAITest do
  use ExUnit.Case, async: true

  alias RubberDuck.LLM.Providers.OpenAI
  alias RubberDuck.LLM.{Request, Response, ProviderConfig}

  describe "validate_config/1" do
    test "validates API key is present" do
      config = %ProviderConfig{
        name: :openai,
        adapter: OpenAI,
        api_key: "test-key"
      }

      assert :ok = OpenAI.validate_config(config)
    end

    test "returns error when API key is missing" do
      config = %ProviderConfig{
        name: :openai,
        adapter: OpenAI,
        api_key: nil
      }

      assert {:error, :api_key_required} = OpenAI.validate_config(config)
    end

    test "returns error when API key is empty" do
      config = %ProviderConfig{
        name: :openai,
        adapter: OpenAI,
        api_key: ""
      }

      assert {:error, :api_key_required} = OpenAI.validate_config(config)
    end
  end

  describe "info/0" do
    test "returns provider information" do
      info = OpenAI.info()

      assert info.name == "OpenAI"
      assert is_list(info.models)
      assert length(info.models) > 0
      assert is_list(info.features)
      assert :streaming in info.features
      assert :function_calling in info.features
    end

    test "includes model details" do
      info = OpenAI.info()
      model = hd(info.models)

      assert Map.has_key?(model, :id)
      assert Map.has_key?(model, :context_window)
      assert Map.has_key?(model, :max_output)
      assert Map.has_key?(model, :supports_functions)
    end
  end

  describe "supports_feature?/1" do
    test "supports expected features" do
      assert OpenAI.supports_feature?(:streaming)
      assert OpenAI.supports_feature?(:function_calling)
      assert OpenAI.supports_feature?(:system_messages)
      assert OpenAI.supports_feature?(:json_mode)
    end

    test "does not support unknown features" do
      refute OpenAI.supports_feature?(:unknown_feature)
    end
  end

  describe "count_tokens/2" do
    test "estimates tokens for text" do
      text = "Hello, this is a test message for token counting."

      assert {:ok, count} = OpenAI.count_tokens(text, "gpt-4")
      assert is_integer(count)
      assert count > 0
    end

    test "estimates tokens for messages" do
      messages = [
        %{"role" => "system", "content" => "You are a helpful assistant."},
        %{"role" => "user", "content" => "Hello, how are you?"}
      ]

      assert {:ok, count} = OpenAI.count_tokens(messages, "gpt-4")
      assert is_integer(count)
      # Should include message structure overhead
      assert count > 10
    end

    test "handles empty text" do
      assert {:ok, 0} = OpenAI.count_tokens("", "gpt-4")
    end
  end

  # Note: execute/2 would require mocking HTTP requests
  # We'll test that through integration tests instead
end
