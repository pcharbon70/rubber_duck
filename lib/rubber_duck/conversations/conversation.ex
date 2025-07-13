defmodule RubberDuck.Conversations.Conversation do
  @moduledoc """
  Represents a conversation session with an AI assistant.
  
  A conversation contains multiple messages and maintains metadata about
  the conversation such as the title, associated project, and conversation settings.
  """
  
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Conversations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "conversations"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
    
    read :list_by_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
      description "ID of the user who owns this conversation"
    end

    attribute :project_id, :uuid do
      allow_nil? true
      public? true
      description "Optional project this conversation is associated with"
    end

    attribute :title, :string do
      allow_nil? true
      public? true
      description "Human-readable title for the conversation"
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :archived, :deleted]
      description "Current status of the conversation"
    end

    attribute :metadata, :map do
      allow_nil? true
      default %{}
      public? true
      description "Additional conversation metadata (LLM preferences, etc.)"
    end

    attribute :message_count, :integer do
      allow_nil? false
      default 0
      public? true
      description "Cached count of messages in this conversation"
    end

    attribute :last_activity_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "Timestamp of the last message or activity in this conversation"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :messages, RubberDuck.Conversations.Message do
      destination_attribute :conversation_id
      sort :inserted_at
    end
    
    has_one :context, RubberDuck.Conversations.ConversationContext do
      destination_attribute :conversation_id
    end
    
    belongs_to :project, RubberDuck.Workspace.Project do
      attribute_writable? true
      allow_nil? true
    end
  end


end