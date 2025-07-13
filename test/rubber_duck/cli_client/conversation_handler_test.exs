defmodule RubberDuck.CLIClient.ConversationHandlerTest do
  use ExUnit.Case, async: false

  alias RubberDuck.CLIClient.ConversationHandler

  describe "conversation handler utilities" do
    test "extracts conversation ID from response" do
      response = """
      Conversation created successfully!
      
      ID: 123e4567-e89b-12d3-a456-426614174000
      Title: Test Conversation
      Type: general
      """
      
      assert {:ok, "123e4567-e89b-12d3-a456-426614174000"} = 
        ConversationHandler.extract_conversation_id(response)
    end

    test "handles missing conversation ID" do
      response = "Some response without an ID"
      
      assert {:error, "Could not extract conversation ID"} = 
        ConversationHandler.extract_conversation_id(response)
    end
  end
end