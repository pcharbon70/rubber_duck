defmodule RubberDuck.LLMAbstraction.MessageTest do
  use ExUnit.Case, async: true

  alias RubberDuck.LLMAbstraction.Message
  alias RubberDuck.LLMAbstraction.Message.{Text, Function, Multimodal, Factory}

  describe "Text message" do
    test "implements Message protocol correctly" do
      message = %Text{role: :user, content: "Hello, AI!", name: "test_user"}
      
      assert Message.role(message) == :user
      assert Message.content(message) == "Hello, AI!"
      assert Message.multimodal?(message) == false
      assert Message.metadata(message) == %{}
    end

    test "converts to OpenAI format" do
      message = %Text{role: :system, content: "You are helpful."}
      result = Message.to_provider_format(message, :openai)
      
      assert result == %{
        "role" => "system",
        "content" => "You are helpful."
      }
    end

    test "converts to OpenAI format with name" do
      message = %Text{role: :user, content: "Hi", name: "alice"}
      result = Message.to_provider_format(message, :openai)
      
      assert result == %{
        "role" => "user",
        "content" => "Hi",
        "name" => "alice"
      }
    end

    test "converts to Anthropic format" do
      message = %Text{role: :assistant, content: "I can help!"}
      result = Message.to_provider_format(message, :anthropic)
      
      assert result == %{
        "role" => "assistant",
        "content" => "I can help!"
      }
    end

    test "converts to generic format" do
      message = %Text{role: :user, content: "Test", metadata: %{id: 123}}
      result = Message.to_provider_format(message, :unknown)
      
      assert result == %{
        "role" => "user",
        "content" => "Test",
        "metadata" => %{id: 123}
      }
    end
  end

  describe "Function message" do
    test "implements Message protocol for function calls" do
      message = %Function{
        name: "get_weather",
        arguments: %{location: "NYC"},
        result: nil
      }
      
      assert Message.role(message) == :function
      assert Message.content(message) == %{location: "NYC"}
      assert Message.multimodal?(message) == false
    end

    test "converts function call to OpenAI format" do
      message = %Function{
        name: "search",
        arguments: %{query: "Elixir"},
        result: nil
      }
      
      result = Message.to_provider_format(message, :openai)
      
      assert result == %{
        "role" => "assistant",
        "content" => nil,
        "function_call" => %{
          "name" => "search",
          "arguments" => ~s({"query":"Elixir"})
        }
      }
    end

    test "converts function result to OpenAI format" do
      message = %Function{
        name: "search",
        arguments: nil,
        result: %{results: ["item1", "item2"]}
      }
      
      result = Message.to_provider_format(message, :openai)
      
      assert result["role"] == "function"
      assert result["name"] == "search"
      assert result["content"] == ~s({"results":["item1","item2"]})
    end

    test "converts to Anthropic tool use format" do
      message = %Function{
        name: "calculator",
        arguments: %{expression: "2+2"}
      }
      
      result = Message.to_provider_format(message, :anthropic)
      
      assert result["role"] == "assistant"
      assert [tool_use] = result["content"]
      assert tool_use["type"] == "tool_use"
      assert tool_use["name"] == "calculator"
      assert tool_use["input"] == %{expression: "2+2"}
      assert is_binary(tool_use["id"])
    end
  end

  describe "Multimodal message" do
    test "implements Message protocol" do
      message = %Multimodal{
        role: :user,
        parts: [
          {:text, "What's in this image?"},
          {:image_url, "https://example.com/cat.jpg"}
        ]
      }
      
      assert Message.role(message) == :user
      assert Message.content(message) == "What's in this image?"
      assert Message.multimodal?(message) == true
    end

    test "converts to OpenAI vision format" do
      message = %Multimodal{
        role: :user,
        parts: [
          {:text, "Describe this"},
          {:image_base64, "abc123", "image/jpeg"}
        ]
      }
      
      result = Message.to_provider_format(message, :openai)
      
      assert result["role"] == "user"
      assert length(result["content"]) == 2
      
      [text_part, image_part] = result["content"]
      assert text_part == %{"type" => "text", "text" => "Describe this"}
      assert image_part == %{
        "type" => "image_url",
        "image_url" => %{"url" => "data:image/jpeg;base64,abc123"}
      }
    end

    test "converts to Anthropic format" do
      message = %Multimodal{
        role: :user,
        parts: [
          {:text, "What do you see?"},
          {:image_base64, "xyz789", "image/png"}
        ]
      }
      
      result = Message.to_provider_format(message, :anthropic)
      
      assert result["role"] == "user"
      assert length(result["content"]) == 2
      
      [text_part, image_part] = result["content"]
      assert text_part == %{"type" => "text", "text" => "What do you see?"}
      assert image_part == %{
        "type" => "image",
        "source" => %{
          "type" => "base64",
          "media_type" => "image/png",
          "data" => "xyz789"
        }
      }
    end

    test "extracts only text content" do
      message = %Multimodal{
        role: :user,
        parts: [
          {:text, "First part"},
          {:image_url, "https://example.com/img.jpg"},
          {:text, "Second part"}
        ]
      }
      
      assert Message.content(message) == "First part\nSecond part"
    end
  end

  describe "Message.Factory" do
    test "creates system message" do
      message = Factory.system("You are helpful", metadata: %{version: 1})
      
      assert message.role == :system
      assert message.content == "You are helpful"
      assert message.metadata == %{version: 1}
    end

    test "creates user message" do
      message = Factory.user("Hello", name: "alice")
      
      assert message.role == :user
      assert message.content == "Hello"
      assert message.name == "alice"
    end

    test "creates assistant message" do
      message = Factory.assistant("I can help with that")
      
      assert message.role == :assistant
      assert message.content == "I can help with that"
    end

    test "creates function call message" do
      message = Factory.function_call("search", %{q: "test"})
      
      assert message.name == "search"
      assert message.arguments == %{q: "test"}
      assert message.result == nil
    end

    test "creates function result message" do
      message = Factory.function_result("search", %{items: [1, 2, 3]})
      
      assert message.name == "search"
      assert message.result == %{items: [1, 2, 3]}
      assert message.arguments == nil
    end

    test "creates multimodal message" do
      parts = [
        {:text, "Check this out"},
        {:image_url, "https://example.com/img.png"}
      ]
      
      message = Factory.multimodal(:user, parts)
      
      assert message.role == :user
      assert message.parts == parts
    end
  end
end