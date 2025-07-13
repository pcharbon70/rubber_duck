defmodule RubberDuck.Conversations.ConversationContext do
  @moduledoc """
  Manages the context state for a conversation including memory, preferences,
  and conversation-specific settings.
  
  This resource stores the conversational state that helps maintain context
  across multiple message exchanges and provides memory for the AI assistant.
  """
  
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Conversations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "conversation_contexts"
    repo RubberDuck.Repo
    
    references do
      reference :conversation, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
    
    read :get_by_conversation do
      argument :conversation_id, :uuid, allow_nil?: false
      filter expr(conversation_id == ^arg(:conversation_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :conversation_id, :uuid do
      allow_nil? false
      public? true
      description "ID of the conversation this context belongs to"
    end

    attribute :system_prompt, :string do
      allow_nil? true
      public? true
      description "System prompt/instructions for this conversation"
    end

    attribute :context_window_size, :integer do
      allow_nil? false
      default 4000
      public? true
      description "Maximum context window size for this conversation"
    end

    attribute :memory_summary, :string do
      allow_nil? true
      public? true
      description "Summarized memory of conversation for context management"
    end

    attribute :conversation_summary, :string do
      allow_nil? true
      public? true
      description "High-level summary of the conversation for context"
    end

    attribute :active_topics, {:array, :string} do
      allow_nil? true
      default []
      public? true
      description "List of currently active topics in the conversation"
    end

    attribute :mentioned_files, {:array, :string} do
      allow_nil? true
      default []
      public? true
      description "List of files mentioned or worked on in this conversation"
    end

    attribute :mentioned_functions, {:array, :string} do
      allow_nil? true
      default []
      public? true
      description "List of functions mentioned or worked on in this conversation"
    end

    attribute :conversation_type, :atom do
      allow_nil? false
      default :general
      public? true
      constraints one_of: [:general, :coding, :debugging, :planning, :review]
      description "Type/category of this conversation"
    end

    attribute :llm_preferences, :map do
      allow_nil? true
      default %{}
      public? true
      description "LLM preferences for this conversation (temperature, model, etc.)"
    end

    attribute :context_metadata, :map do
      allow_nil? true
      default %{}
      public? true
      description "Additional context metadata for conversation management"
    end

    attribute :last_summarized_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When the conversation was last summarized for context management"
    end

    attribute :total_tokens_used, :integer do
      allow_nil? false
      default 0
      public? true
      description "Total tokens used in this conversation across all messages"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :conversation, RubberDuck.Conversations.Conversation do
      attribute_writable? true
      allow_nil? false
    end
  end


end