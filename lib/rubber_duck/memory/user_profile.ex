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

  postgres do
    custom_indexes do
      index [:user_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :preferred_language, :coding_style, :experience_level, :preferences, :llm_preferences]
      upsert? true
      upsert_identity :unique_user
    end

    update :update do
      primary? true
      accept [:preferred_language, :coding_style, :experience_level, :preferences, :llm_preferences]
    end

    update :add_learned_pattern do
      require_atomic? false
      
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

    update :set_llm_preference do
      require_atomic? false
      
      argument :provider, :atom, allow_nil?: false
      argument :model, :string, allow_nil?: false
      argument :is_default, :boolean, default: false

      change fn changeset, context ->
        provider = context.arguments.provider
        model = context.arguments.model
        is_default = context.arguments.is_default

        current_prefs = Ash.Changeset.get_attribute(changeset, :llm_preferences) || %{}

        # Update provider preferences
        provider_prefs = Map.get(current_prefs, "provider_preferences", %{})
        updated_provider_prefs = Map.put(provider_prefs, to_string(provider), %{
          "models" => [model],
          "default" => model
        })

        # Update overall preferences
        updated_prefs = Map.merge(current_prefs, %{
          "provider_preferences" => updated_provider_prefs
        })

        # Set as default if requested
        if is_default do
          updated_prefs = Map.merge(updated_prefs, %{
            "default_provider" => to_string(provider),
            "default_model" => model
          })
        end

        Ash.Changeset.change_attribute(changeset, :llm_preferences, updated_prefs)
      end
    end

    update :add_llm_model do
      require_atomic? false
      
      argument :provider, :atom, allow_nil?: false
      argument :model, :string, allow_nil?: false

      change fn changeset, context ->
        provider = context.arguments.provider
        model = context.arguments.model

        current_prefs = Ash.Changeset.get_attribute(changeset, :llm_preferences) || %{}
        provider_prefs = Map.get(current_prefs, "provider_preferences", %{})
        
        provider_config = Map.get(provider_prefs, to_string(provider), %{"models" => [], "default" => nil})
        current_models = provider_config["models"] || []
        
        # Add model if not already present
        updated_models = if model in current_models do
          current_models
        else
          [model | current_models]
        end

        # Set as default if no default exists
        updated_default = provider_config["default"] || model

        updated_provider_config = Map.merge(provider_config, %{
          "models" => updated_models,
          "default" => updated_default
        })

        updated_provider_prefs = Map.put(provider_prefs, to_string(provider), updated_provider_config)
        updated_prefs = Map.put(current_prefs, "provider_preferences", updated_provider_prefs)

        Ash.Changeset.change_attribute(changeset, :llm_preferences, updated_prefs)
      end
    end

    update :clear_llm_preferences do
      require_atomic? false
      
      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :llm_preferences, %{})
      end
    end
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

    attribute :llm_preferences, :map do
      allow_nil? true
      default %{}
      public? true
      description "User's preferred LLM providers and models"
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_user, [:user_id]
  end
end
