defmodule RubberDuck.Memory.Summary do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Memory,
    data_layer: Ash.DataLayer.Ets
  
  require Ash.Query

  @moduledoc """
  Mid-term memory storage for topic summaries and patterns.
  Uses ETS for fast access with heat score-based retention (max 100 patterns).
  """

  ets do
    table :memory_summaries
    private? false
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :string do
      allow_nil? false
      public? true
    end

    attribute :topic, :string do
      allow_nil? false
      public? true
    end

    attribute :summary, :string do
      allow_nil? false
      public? true
    end

    attribute :pattern_type, :atom do
      allow_nil? false
      constraints one_of: [:code_pattern, :error_pattern, :usage_pattern, :conversation_pattern]
      public? true
    end

    attribute :frequency, :integer do
      allow_nil? false
      default 1
      public? true
    end

    attribute :heat_score, :float do
      allow_nil? false
      default 1.0
      public? true
    end

    attribute :metadata, :map do
      allow_nil? true
      default %{}
      public? true
    end

    attribute :source_interactions, {:array, :uuid} do
      allow_nil? true
      default []
      public? true
    end

    create_timestamp :created_at
    update_timestamp :last_accessed_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :topic, :summary, :pattern_type, :frequency, :metadata, :source_interactions]
      
      # Implement heat score-based eviction
      change fn changeset, _context ->
        user_id = Ash.Changeset.get_attribute(changeset, :user_id)
        
        # Count existing summaries for this user
        case count_user_summaries(user_id) do
          {:ok, count} when count >= 100 ->
            # Remove coldest summary
            remove_coldest_summary(user_id)
            changeset
            
          _ ->
            changeset
        end
      end
    end

    update :update do
      primary? true
      accept [:heat_score, :frequency, :metadata]
      
      # Update heat score and last accessed
      change set_attribute(:last_accessed_at, &DateTime.utc_now/0)
    end

    update :increment_frequency do
      accept []
      
      change increment(:frequency)
      change set_attribute(:last_accessed_at, &DateTime.utc_now/0)
      change fn changeset, _context ->
        # Recalculate heat score
        frequency = Ash.Changeset.get_attribute(changeset, :frequency)
        created_at = Ash.Changeset.get_data(changeset, :created_at)
        heat_score = calculate_heat_score(frequency, created_at)
        
        Ash.Changeset.change_attribute(changeset, :heat_score, heat_score)
      end
    end

    read :by_user do
      argument :user_id, :string, allow_nil?: false
      
      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [heat_score: :desc])
    end

    read :by_topic do
      argument :user_id, :string, allow_nil?: false
      argument :topic, :string, allow_nil?: false
      
      filter expr(user_id == ^arg(:user_id) and topic == ^arg(:topic))
    end

    read :search do
      argument :user_id, :string, allow_nil?: false
      argument :query, :string, allow_nil?: false
      argument :limit, :integer, default: 10
      
      filter expr(user_id == ^arg(:user_id))
      
      prepare fn query, context ->
        # Simple keyword matching for now
        # TODO: Implement more sophisticated search
        search_term = String.downcase(context.arguments.query)
        pattern = "%#{search_term}%"
        
        query
        |> Ash.Query.filter(expr(
          fragment("LOWER(?) LIKE ?", topic, ^pattern) or
          fragment("LOWER(?) LIKE ?", summary, ^pattern)
        ))
        |> Ash.Query.sort(heat_score: :desc)
        |> Ash.Query.limit(context.arguments.limit)
      end
    end
  end

  # Private helper functions
  defp count_user_summaries(user_id) do
    __MODULE__
    |> Ash.Query.for_read(:by_user, %{user_id: user_id})
    |> Ash.count(authorize?: false)
  end

  defp remove_coldest_summary(user_id) do
    __MODULE__
    |> Ash.Query.for_read(:by_user, %{user_id: user_id})
    |> Ash.Query.sort(heat_score: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> case do
      [coldest | _] -> Ash.destroy!(coldest, authorize?: false)
      _ -> :ok
    end
  end

  defp calculate_heat_score(frequency, created_at) do
    # Heat score calculation based on frequency and recency
    # Score = frequency * recency_factor
    
    days_old = DateTime.diff(DateTime.utc_now(), created_at, :day)
    recency_factor = :math.exp(-days_old / 30)  # Decay over 30 days
    
    frequency * recency_factor
  end
end