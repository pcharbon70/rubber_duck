defmodule RubberDuck.Repo.Migrations.CreateConversationsDomain do
  @moduledoc "Create tables for the Conversations domain"
  
  use Ecto.Migration

  def up do
    # Create conversations table
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :binary_id, null: false
      add :project_id, references(:projects, type: :binary_id, on_delete: :nilify_all), null: true
      add :title, :text, null: true
      add :status, :text, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}
      add :message_count, :integer, null: false, default: 0
      add :last_activity_at, :utc_datetime_usec, null: true

      timestamps(type: :utc_datetime_usec)
    end

    # Create conversation_messages table
    create table(:conversation_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :text, null: false
      add :content, :text, null: false
      add :sequence_number, :integer, null: false
      add :parent_message_id, references(:conversation_messages, type: :binary_id, on_delete: :nilify_all), null: true
      add :metadata, :map, null: false, default: %{}
      add :tokens_used, :integer, null: true
      add :generation_time_ms, :integer, null: true
      add :model_used, :text, null: true
      add :provider_used, :text, null: true

      timestamps(type: :utc_datetime_usec)
    end

    # Create conversation_contexts table
    create table(:conversation_contexts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all), null: false
      add :system_prompt, :text, null: true
      add :context_window_size, :integer, null: false, default: 4000
      add :memory_summary, :text, null: true
      add :conversation_summary, :text, null: true
      add :active_topics, {:array, :text}, null: false, default: []
      add :mentioned_files, {:array, :text}, null: false, default: []
      add :mentioned_functions, {:array, :text}, null: false, default: []
      add :conversation_type, :text, null: false, default: "general"
      add :llm_preferences, :map, null: false, default: %{}
      add :context_metadata, :map, null: false, default: %{}
      add :last_summarized_at, :utc_datetime_usec, null: true
      add :total_tokens_used, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    # Create indexes for performance
    create index(:conversations, [:user_id])
    create index(:conversations, [:project_id])
    create index(:conversations, [:status])
    create index(:conversations, [:last_activity_at])
    
    create index(:conversation_messages, [:conversation_id])
    create index(:conversation_messages, [:conversation_id, :sequence_number])
    create index(:conversation_messages, [:role])
    create index(:conversation_messages, [:parent_message_id])
    create index(:conversation_messages, [:inserted_at])
    
    create unique_index(:conversation_contexts, [:conversation_id])
    create index(:conversation_contexts, [:conversation_type])
    create index(:conversation_contexts, [:last_summarized_at])

    # Add constraints
    create constraint(:conversations, :valid_status, check: "status IN ('active', 'archived', 'deleted')")
    create constraint(:conversation_messages, :valid_role, check: "role IN ('user', 'assistant', 'system', 'tool')")
    create constraint(:conversation_messages, :positive_sequence_number, check: "sequence_number > 0")
    create constraint(:conversation_contexts, :valid_conversation_type, 
      check: "conversation_type IN ('general', 'coding', 'debugging', 'planning', 'review')")
    create constraint(:conversation_contexts, :valid_context_window, 
      check: "context_window_size >= 100 AND context_window_size <= 128000")
  end

  def down do
    drop table(:conversation_contexts)
    drop table(:conversation_messages)
    drop table(:conversations)
  end
end