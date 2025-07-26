defmodule RubberDuck.Conversations.Conversation do
  @moduledoc """
  Represents a conversation session with an AI assistant.

  A conversation contains multiple messages and maintains metadata about
  the conversation such as the title, associated project, and conversation settings.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Conversations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "conversations"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy, update: :*]

    create :create do
      accept [:title, :user_id, :project_id, :metadata, :status]
      primary? true

      # Allow setting the ID during creation
      argument :id, :uuid do
        allow_nil? true
      end

      change fn changeset, _ ->
        case Ash.Changeset.get_argument(changeset, :id) do
          nil -> changeset
          id -> Ash.Changeset.force_change_attribute(changeset, :id, id)
        end
      end

      # Ensure users can only create conversations for themselves
      change fn changeset, context ->
        case context.actor do
          nil -> changeset
          actor -> Ash.Changeset.force_change_attribute(changeset, :user_id, actor.id)
        end
      end
    end

    read :list_by_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
    end
    
    read :get_latest_by_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [updated_at: :desc], limit: 1)
      get? true
    end
  end

  policies do
    # Allow system operations to bypass authorization
    bypass actor_attribute_equals(:system, true) do
      description "System operations can bypass authorization"
      authorize_if always()
    end

    # Create policies - authenticated users can create conversations
    policy action_type(:create) do
      description "Authenticated users can create conversations"
      authorize_if actor_present()
    end

    # Read policies - users can only read their own conversations
    policy action_type(:read) do
      description "Users can read their own conversations"
      authorize_if relates_to_actor_via(:user)
    end

    # Update policies - only owner can update
    policy action_type(:update) do
      description "Users can update their own conversations"
      authorize_if relates_to_actor_via(:user)
    end

    # Delete policies - only owner can delete
    policy action_type(:destroy) do
      description "Users can delete their own conversations"
      authorize_if relates_to_actor_via(:user)
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

    attribute :processing_status, :atom do
      allow_nil? false
      default :idle
      public? true
      constraints one_of: [:idle, :processing, :cancelling, :cancelled, :completed, :failed]
      description "Current processing status of the conversation"
    end

    attribute :processing_started_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When the current processing started"
    end

    attribute :processing_metadata, :map do
      allow_nil? true
      default %{}
      public? true
      description "Metadata about the current processing (task_id, engine, etc.)"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, RubberDuck.Accounts.User do
      allow_nil? false
      attribute_writable? true
    end

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
