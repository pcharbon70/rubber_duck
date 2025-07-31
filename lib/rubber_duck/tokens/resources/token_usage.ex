defmodule RubberDuck.Tokens.Resources.TokenUsage do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Tokens,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  @moduledoc """
  Persistent storage for token usage records.
  
  Tracks every LLM request's token consumption with full attribution
  and cost information for analytics and billing.
  """

  postgres do
    table "token_usages"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [
        :provider,
        :model,
        :prompt_tokens,
        :completion_tokens,
        :total_tokens,
        :cost,
        :currency,
        :user_id,
        :project_id,
        :team_id,
        :feature,
        :request_id,
        :metadata
      ]

      change fn changeset, _context ->
        # Ensure total_tokens matches sum
        prompt = Ash.Changeset.get_attribute(changeset, :prompt_tokens)
        completion = Ash.Changeset.get_attribute(changeset, :completion_tokens)
        
        if prompt && completion do
          Ash.Changeset.change_attribute(changeset, :total_tokens, prompt + completion)
        else
          changeset
        end
      end
    end

    create :bulk_create do
      accept [
        :provider,
        :model,
        :prompt_tokens,
        :completion_tokens,
        :total_tokens,
        :cost,
        :currency,
        :user_id,
        :project_id,
        :team_id,
        :feature,
        :request_id,
        :metadata
      ]
      
      # Allow bulk operations
      transaction? true
      upsert? true
      upsert_identity :unique_request_id
    end

    read :by_user do
      argument :user_id, :uuid, allow_nil?: false
      
      filter expr(user_id == ^arg(:user_id))
    end

    read :by_project do
      argument :project_id, :uuid, allow_nil?: false
      
      filter expr(project_id == ^arg(:project_id))
    end

    read :by_date_range do
      argument :start_date, :datetime, allow_nil?: false
      argument :end_date, :datetime, allow_nil?: false
      
      filter expr(inserted_at >= ^arg(:start_date) and inserted_at <= ^arg(:end_date))
    end

    # Aggregate actions
    read :sum_tokens_by_user do
      argument :user_id, :uuid, allow_nil?: false
      argument :start_date, :datetime, allow_nil?: true
      argument :end_date, :datetime, allow_nil?: true
      
      prepare fn query, _context ->
        query
        |> Ash.Query.filter(user_id == ^query.arguments.user_id)
        |> then(fn q ->
          if query.arguments.start_date && query.arguments.end_date do
            Ash.Query.filter(q, 
              inserted_at >= ^query.arguments.start_date and 
              inserted_at <= ^query.arguments.end_date
            )
          else
            q
          end
        end)
        |> Ash.Query.aggregate(:total_tokens, :sum, :total_tokens)
        |> Ash.Query.aggregate(:total_cost, :sum, :cost)
        |> Ash.Query.aggregate(:request_count, :count, :id)
      end
    end

    read :sum_cost_by_project do
      argument :project_id, :uuid, allow_nil?: false
      argument :start_date, :datetime, allow_nil?: true
      argument :end_date, :datetime, allow_nil?: true
      
      prepare fn query, _context ->
        query
        |> Ash.Query.filter(project_id == ^query.arguments.project_id)
        |> then(fn q ->
          if query.arguments.start_date && query.arguments.end_date do
            Ash.Query.filter(q, 
              inserted_at >= ^query.arguments.start_date and 
              inserted_at <= ^query.arguments.end_date
            )
          else
            q
          end
        end)
        |> Ash.Query.aggregate(:total_cost, :sum, :cost)
        |> Ash.Query.aggregate(:total_tokens, :sum, :total_tokens)
        |> Ash.Query.aggregate(:request_count, :count, :id)
        |> Ash.Query.group_by([:provider, :model])
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :string do
      allow_nil? false
      description "LLM provider (e.g., 'openai', 'anthropic', 'local')"
    end

    attribute :model, :string do
      allow_nil? false
      description "Model identifier (e.g., 'gpt-4', 'claude-3-opus')"
    end

    attribute :prompt_tokens, :integer do
      allow_nil? false
      constraints min: 0
      description "Number of tokens in the prompt"
    end

    attribute :completion_tokens, :integer do
      allow_nil? false
      constraints min: 0
      description "Number of tokens in the completion"
    end

    attribute :total_tokens, :integer do
      allow_nil? false
      constraints min: 0
      description "Total tokens (prompt + completion)"
    end

    attribute :cost, :decimal do
      allow_nil? false
      constraints min: 0
      description "Cost in the specified currency"
    end

    attribute :currency, :string do
      allow_nil? false
      default "USD"
      constraints max_length: 3
      description "Currency code (ISO 4217)"
    end

    attribute :user_id, :uuid do
      allow_nil? false
      description "User who made the request"
    end

    attribute :project_id, :uuid do
      allow_nil? true
      description "Project associated with the request"
    end

    attribute :team_id, :uuid do
      allow_nil? true
      description "Team associated with the request"
    end

    attribute :feature, :string do
      allow_nil? true
      description "Feature or component that made the request"
    end

    attribute :request_id, :string do
      allow_nil? false
      description "Unique identifier for the request"
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      description "Additional metadata about the request"
    end

    timestamps()
  end

  relationships do
    belongs_to :user, RubberDuck.Accounts.User do
      attribute_type :uuid
      source_attribute :user_id
      destination_attribute :id
    end

    # Note: Add project and team relationships when those resources exist
  end

  identities do
    identity :unique_request_id, [:request_id]
  end

  postgres do
    table "token_usages"
    repo RubberDuck.Repo

    references do
      reference :user, on_delete: :restrict
    end
  end

  code_interface do
    define :record_usage, action: :create
    define :bulk_record_usage, action: :bulk_create
  end
end