defmodule RubberDuck.Memory.UserProfile do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Memory,
    data_layer: AshPostgres.DataLayer

  @moduledoc """
  Long-term memory storage for user profiles and preferences.
  Uses PostgreSQL for persistence across sessions.
  """

  postgres do
    table "memory_user_profiles"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :string do
      allow_nil? false
      public? true
    end

    attribute :preferred_language, :string do
      allow_nil? true
      public? true
    end

    attribute :coding_style, :atom do
      allow_nil? true
      constraints one_of: [:functional, :object_oriented, :procedural, :mixed]
      public? true
    end

    attribute :experience_level, :atom do
      allow_nil? true
      constraints one_of: [:beginner, :intermediate, :advanced, :expert]
      public? true
    end

    attribute :preferences, :map do
      allow_nil? true
      default %{}
      public? true
    end

    attribute :learned_patterns, :map do
      allow_nil? true
      default %{}
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_user, [:user_id]
  end

  postgres do
    custom_indexes do
      index [:user_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :preferred_language, :coding_style, :experience_level, :preferences]
      upsert? true
      upsert_identity :unique_user
    end

    update :update do
      primary? true
      accept [:preferred_language, :coding_style, :experience_level, :preferences]
    end

    update :add_learned_pattern do
      argument :pattern_key, :string, allow_nil?: false
      argument :pattern_data, :map, allow_nil?: false
      
      change fn changeset, context ->
        key = context.arguments.pattern_key
        data = context.arguments.pattern_data
        current_patterns = Ash.Changeset.get_attribute(changeset, :learned_patterns) || %{}
        
        updated_patterns = Map.put(current_patterns, key, data)
        Ash.Changeset.change_attribute(changeset, :learned_patterns, updated_patterns)
      end
    end

    read :get_by_user do
      argument :user_id, :string, allow_nil?: false
      
      get? true
      filter expr(user_id == ^arg(:user_id))
    end
  end
end