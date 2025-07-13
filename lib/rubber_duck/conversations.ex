defmodule RubberDuck.Conversations do
  @moduledoc """
  Domain for managing conversational AI interactions including conversations,
  messages, and conversation context state.
  
  This domain provides the foundation for multi-turn conversations with
  context awareness, history management, and integration with the LLM system.
  """
  
  use Ash.Domain,
    otp_app: :rubber_duck

  resources do
    resource RubberDuck.Conversations.Conversation do
      define :create_conversation, action: :create
      define :list_conversations, action: :read
      define :get_conversation, action: :read, get_by: [:id]
      define :update_conversation, action: :update
      define :delete_conversation, action: :destroy
      define :list_user_conversations, action: :list_by_user
    end

    resource RubberDuck.Conversations.Message do
      define :create_message, action: :create
      define :list_messages, action: :read
      define :get_message, action: :read, get_by: [:id]
      define :update_message, action: :update
      define :delete_message, action: :destroy
      define :list_conversation_messages, action: :list_by_conversation
      define :get_conversation_history, action: :get_history
    end

    resource RubberDuck.Conversations.ConversationContext do
      define :create_context, action: :create
      define :get_context, action: :read, get_by: [:id]
      define :update_context, action: :update
      define :delete_context, action: :destroy
      define :get_conversation_context, action: :get_by_conversation
    end
  end
end