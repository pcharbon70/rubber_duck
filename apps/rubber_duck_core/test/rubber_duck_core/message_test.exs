defmodule RubberDuckCore.MessageTest do
  use ExUnit.Case, async: true

  alias RubberDuckCore.Message

  describe "new/1" do
    test "creates a message with default values" do
      message = Message.new()

      assert message.id != nil
      assert message.role == :user
      assert message.content == ""
      assert message.content_type == :text
      assert message.metadata == %{}
      assert %DateTime{} = message.timestamp
    end

    test "creates a message with provided attributes" do
      attrs = [
        id: "msg-123",
        role: :assistant,
        content: "Hello!",
        content_type: :code,
        metadata: %{language: "elixir"}
      ]

      message = Message.new(attrs)

      assert message.id == "msg-123"
      assert message.role == :assistant
      assert message.content == "Hello!"
      assert message.content_type == :code
      assert message.metadata == %{language: "elixir"}
    end
  end

  describe "convenience constructors" do
    test "user/2 creates a user message" do
      message = Message.user("Hello world")

      assert message.role == :user
      assert message.content == "Hello world"
    end

    test "assistant/2 creates an assistant message" do
      message = Message.assistant("Hi there", content_type: :text)

      assert message.role == :assistant
      assert message.content == "Hi there"
      assert message.content_type == :text
    end

    test "system/2 creates a system message" do
      message = Message.system("System initialized")

      assert message.role == :system
      assert message.content == "System initialized"
    end
  end
end
