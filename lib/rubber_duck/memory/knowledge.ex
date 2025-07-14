defmodule RubberDuck.Memory.Knowledge do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Memory,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  @moduledoc """
  Long-term memory storage for project knowledge and documentation.
  Uses PostgreSQL with pgvector for semantic search capabilities.
  """

  postgres do
    table "memory_knowledge"
    repo RubberDuck.Repo
  end

  postgres do
    custom_indexes do
      index [:user_id, :project_id]
      index [:knowledge_type]
      index [:tags], using: "gin"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :project_id, :knowledge_type, :title, :content, :tags, :metadata]

      # Generate embedding after creation
      change after_action(fn changeset, record, _context ->
               # TODO: Generate embedding using LLM service
               {:ok, record}
             end)
    end

    update :update do
      primary? true
      accept [:title, :content, :tags, :relevance_score, :metadata]

      change set_attribute(:last_accessed_at, &DateTime.utc_now/0)
    end

    update :increment_usage do
      require_atomic? false
      
      accept []

      change increment(:usage_count)
      change set_attribute(:last_accessed_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        # Update relevance score based on usage
        usage_count = Ash.Changeset.get_attribute(changeset, :usage_count)
        created_at = Ash.Changeset.get_data(changeset, :created_at)
        relevance_score = calculate_relevance_score(usage_count, created_at)

        Ash.Changeset.change_attribute(changeset, :relevance_score, relevance_score)
      end
    end

    read :by_project do
      argument :user_id, :string, allow_nil?: false
      argument :project_id, :string, allow_nil?: false

      filter expr(user_id == ^arg(:user_id) and project_id == ^arg(:project_id))
      prepare build(sort: [relevance_score: :desc, last_accessed_at: :desc])
    end

    read :by_type do
      argument :user_id, :string, allow_nil?: false
      argument :project_id, :string, allow_nil?: false
      argument :knowledge_type, :atom, allow_nil?: false

      filter expr(
               user_id == ^arg(:user_id) and
                 project_id == ^arg(:project_id) and
                 knowledge_type == ^arg(:knowledge_type)
             )

      prepare build(sort: [relevance_score: :desc])
    end

    read :search_semantic do
      argument :user_id, :string, allow_nil?: false
      argument :project_id, :string, allow_nil?: false
      argument :query_embedding, {:array, :float}, allow_nil?: false
      argument :limit, :integer, default: 10

      filter expr(user_id == ^arg(:user_id) and project_id == ^arg(:project_id))

      prepare fn query, context ->
        embedding = context.arguments.query_embedding

        # TODO: Implement pgvector similarity search
        # For now, return regular results
        query
        |> Ash.Query.sort(relevance_score: :desc)
        |> Ash.Query.limit(context.arguments.limit)
      end
    end

    read :search_keyword do
      argument :user_id, :string, allow_nil?: false
      argument :project_id, :string, allow_nil?: false
      argument :query, :string, allow_nil?: false
      argument :tags, {:array, :string}
      argument :limit, :integer, default: 10

      filter expr(user_id == ^arg(:user_id) and project_id == ^arg(:project_id))

      prepare fn query, context ->
        search_term = String.downcase(context.arguments.query)
        pattern = "%#{search_term}%"

        query =
          Ash.Query.filter(
            query,
            expr(
              fragment("LOWER(?) LIKE ?", title, ^pattern) or
                fragment("LOWER(?) LIKE ?", content, ^pattern)
            )
          )

        query =
          if context.arguments[:tags] && context.arguments.tags != [] do
            # Filter for any matching tags
            Ash.Query.filter(query, expr(fragment("? && ?", tags, ^context.arguments.tags)))
          else
            query
          end

        query
        |> Ash.Query.sort(relevance_score: :desc)
        |> Ash.Query.limit(context.arguments.limit)
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :string do
      allow_nil? false
      public? true
    end

    attribute :project_id, :string do
      allow_nil? false
      public? true
    end

    attribute :knowledge_type, :atom do
      allow_nil? false
      constraints one_of: [:architecture, :api, :business_logic, :dependency, :configuration, :documentation]
      public? true
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    attribute :tags, {:array, :string} do
      allow_nil? true
      default []
      public? true
    end

    attribute :relevance_score, :float do
      allow_nil? false
      default 1.0
      public? true
    end

    attribute :usage_count, :integer do
      allow_nil? false
      default 0
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
    update_timestamp :last_accessed_at
  end

  # Private helper functions
  defp calculate_relevance_score(usage_count, created_at) do
    # Relevance score based on usage and age
    # Score = log(usage_count + 1) * recency_factor

    days_old = DateTime.diff(DateTime.utc_now(), created_at, :day)
    # Slower decay for knowledge
    recency_factor = :math.exp(-days_old / 90)

    :math.log(usage_count + 1) * recency_factor
  end
end
