defmodule RubberDuck.Memory.CodePattern do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Memory,
    data_layer: AshPostgres.DataLayer
  
  require Ash.Query

  @moduledoc """
  Long-term memory storage for code patterns and style preferences.
  Uses PostgreSQL with pgvector for semantic similarity search.
  """

  postgres do
    table "memory_code_patterns"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :string do
      allow_nil? false
      public? true
    end

    attribute :language, :string do
      allow_nil? false
      public? true
    end

    attribute :pattern_name, :string do
      allow_nil? false
      public? true
    end

    attribute :pattern_code, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? true
      public? true
    end

    attribute :pattern_type, :atom do
      allow_nil? false
      constraints one_of: [:function, :module, :test, :config, :error_handling, :data_structure]
      public? true
    end

    attribute :usage_count, :integer do
      allow_nil? false
      default 1
      public? true
    end

    attribute :embedding, {:array, :float} do
      allow_nil? true
      public? false
    end

    attribute :metadata, :map do
      allow_nil? true
      default %{}
      public? true
    end

    create_timestamp :created_at
    update_timestamp :last_used_at
  end

  postgres do
    custom_indexes do
      index [:user_id, :language]
      index [:pattern_type]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :language, :pattern_name, :pattern_code, :description, :pattern_type, :metadata]
      
      # Generate embedding after creation
      change after_action(fn changeset, record, _context ->
        # TODO: Generate embedding using LLM service
        {:ok, record}
      end)
    end

    update :update do
      primary? true
      accept [:pattern_name, :pattern_code, :description, :metadata]
      
      change set_attribute(:last_used_at, &DateTime.utc_now/0)
    end

    update :increment_usage do
      accept []
      
      change increment(:usage_count)
      change set_attribute(:last_used_at, &DateTime.utc_now/0)
    end

    read :by_user_and_language do
      argument :user_id, :string, allow_nil?: false
      argument :language, :string, allow_nil?: false
      
      filter expr(user_id == ^arg(:user_id) and language == ^arg(:language))
      prepare build(sort: [usage_count: :desc, last_used_at: :desc])
    end

    read :search_semantic do
      argument :user_id, :string, allow_nil?: false
      argument :query_embedding, {:array, :float}, allow_nil?: false
      argument :limit, :integer, default: 10
      
      filter expr(user_id == ^arg(:user_id))
      
      prepare fn query, context ->
        embedding = context.arguments.query_embedding
        
        # TODO: Implement pgvector similarity search
        # For now, return regular results
        query
        |> Ash.Query.sort(usage_count: :desc)
        |> Ash.Query.limit(context.arguments.limit)
      end
    end

    read :search_keyword do
      argument :user_id, :string, allow_nil?: false
      argument :query, :string, allow_nil?: false
      argument :language, :string
      argument :limit, :integer, default: 10
      
      filter expr(user_id == ^arg(:user_id))
      
      prepare fn query, context ->
        search_term = String.downcase(context.arguments.query)
        pattern = "%#{search_term}%"
        
        query = Ash.Query.filter(query, expr(
          fragment("LOWER(?) LIKE ?", pattern_name, ^pattern) or
          fragment("LOWER(?) LIKE ?", description, ^pattern) or
          fragment("LOWER(?) LIKE ?", pattern_code, ^pattern)
        ))
        
        query = if context.arguments[:language] do
          Ash.Query.filter(query, expr(language == ^context.arguments.language))
        else
          query
        end
        
        query
        |> Ash.Query.sort(usage_count: :desc)
        |> Ash.Query.limit(context.arguments.limit)
      end
    end
  end
end