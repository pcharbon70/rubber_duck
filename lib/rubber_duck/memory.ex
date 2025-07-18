defmodule RubberDuck.Memory do
  use Ash.Domain,
    otp_app: :rubber_duck

  @moduledoc """
  Domain for managing the hierarchical memory system.

  This domain provides a three-tier memory architecture:
  - Short-term: Recent interactions (ETS, FIFO eviction after 20 items)
  - Mid-term: Summarized patterns (ETS, heat score-based eviction after 100 items)
  - Long-term: Persistent knowledge and patterns (PostgreSQL with pgvector)
  """

  resources do
    resource RubberDuck.Memory.Interaction do
      define :store_interaction, action: :create
      define :get_recent_interactions, action: :by_session, args: [:user_id, :session_id]
      define :get_user_interactions, action: :by_user, args: [:user_id]
    end

    resource RubberDuck.Memory.Summary do
      define :create_summary, action: :create
      define :update_summary, action: :update
      define :increment_pattern_frequency, action: :increment_frequency
      define :get_user_summaries, action: :by_user, args: [:user_id]
      define :get_summary_by_topic, action: :by_topic, args: [:user_id, :topic]
      define :search_summaries, action: :search, args: [:user_id, :query]
    end

    resource RubberDuck.Memory.UserProfile do
      define :create_or_update_profile, action: :create
      define :update_profile, action: :update
      define :add_learned_pattern, action: :add_learned_pattern, args: [:pattern_key, :pattern_data]
      define :set_llm_preference, action: :set_llm_preference, args: [:provider, :model, :is_default]
      define :add_llm_model, action: :add_llm_model, args: [:provider, :model]
      define :clear_llm_preferences, action: :clear_llm_preferences
      define :get_user_profile, action: :get_by_user, args: [:user_id]
    end

    resource RubberDuck.Memory.UserLLMConfig do
      define :create_config, action: :create
      define :update_config, action: :update
      define :increment_usage, action: :increment_usage
      define :set_user_default, action: :set_user_default, args: [:user_id, :provider, :model]
      define :get_user_configs, action: :get_by_user, args: [:user_id]
      define :get_user_default, action: :get_user_default, args: [:user_id]
      define :get_provider_configs, action: :get_by_user_and_provider, args: [:user_id, :provider]
      define :get_provider_default, action: :get_user_provider_default, args: [:user_id, :provider]
    end

    resource RubberDuck.Memory.CodePattern do
      define :store_pattern, action: :create
      define :update_pattern, action: :update
      define :increment_pattern_usage, action: :increment_usage
      define :get_patterns_by_language, action: :by_user_and_language, args: [:user_id, :language]
      define :search_patterns_semantic, action: :search_semantic, args: [:user_id, :query_embedding]
      define :search_patterns_keyword, action: :search_keyword, args: [:user_id, :query]
    end

    resource RubberDuck.Memory.Knowledge do
      define :store_knowledge, action: :create
      define :update_knowledge, action: :update
      define :increment_knowledge_usage, action: :increment_usage
      define :get_project_knowledge, action: :by_project, args: [:user_id, :project_id]
      define :get_knowledge_by_type, action: :by_type, args: [:user_id, :project_id, :knowledge_type]
      define :search_knowledge_semantic, action: :search_semantic, args: [:user_id, :project_id, :query_embedding]
      define :search_knowledge_keyword, action: :search_keyword, args: [:user_id, :project_id, :query]
    end
  end
end
