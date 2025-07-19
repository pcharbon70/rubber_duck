defmodule RubberDuck.Conversations.Message do
  @moduledoc """
  Represents a single message within a conversation.

  Messages have a role (user, assistant, system), content, and metadata
  about the message generation including token usage and model information.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Conversations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "conversation_messages"
    repo RubberDuck.Repo

    migration_types tokens_used: :bigint

    references do
      reference :conversation, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    read :list_by_conversation do
      argument :conversation_id, :uuid, allow_nil?: false
      filter expr(conversation_id == ^arg(:conversation_id))
      pagination offset?: true, default_limit: 50, max_page_size: 100
    end

    read :get_history do
      argument :conversation_id, :uuid, allow_nil?: false
      argument :limit, :integer, allow_nil?: true, default: 50

      filter expr(conversation_id == ^arg(:conversation_id))
      pagination offset?: false, keyset?: true, default_limit: 50
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :conversation_id, :uuid do
      allow_nil? false
      public? true
      description "ID of the conversation this message belongs to"
    end

    attribute :role, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:user, :assistant, :system, :tool]
      description "Role of the message sender (user, assistant, system, tool)"
    end

    attribute :content, :string do
      allow_nil? false
      public? true
      description "The actual content/text of the message"
    end

    attribute :sequence_number, :integer do
      allow_nil? false
      public? true
      description "Sequential number of this message in the conversation"
    end

    attribute :parent_message_id, :uuid do
      allow_nil? true
      public? true
      description "ID of the parent message for threaded conversations"
    end

    attribute :metadata, :map do
      allow_nil? true
      default %{}
      public? true
      description "Message metadata (model used, token usage, generation time, etc.)"
    end

    attribute :tokens_used, :integer do
      allow_nil? true
      public? true
      description "Number of tokens used to generate this message"
      constraints min: 0
    end

    attribute :generation_time_ms, :integer do
      allow_nil? true
      public? true
      description "Time taken to generate this message in milliseconds"
    end

    attribute :model_used, :string do
      allow_nil? true
      public? true
      description "Model that generated this message (for assistant messages)"
    end

    attribute :provider_used, :string do
      allow_nil? true
      public? true
      description "Provider that generated this message (for assistant messages)"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :conversation, RubberDuck.Conversations.Conversation do
      attribute_writable? true
      allow_nil? false
    end

    belongs_to :parent_message, __MODULE__ do
      attribute_writable? true
      allow_nil? true
      source_attribute :parent_message_id
      destination_attribute :id
    end

    has_many :child_messages, __MODULE__ do
      destination_attribute :parent_message_id
      sort :sequence_number
    end
  end
end
