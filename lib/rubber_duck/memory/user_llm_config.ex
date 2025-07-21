defmodule RubberDuck.Memory.UserLLMConfig do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Memory,
    data_layer: AshPostgres.DataLayer

  @moduledoc """
  Detailed LLM configuration records for users.

  This resource stores individual LLM configuration entries for users,
  allowing for detailed tracking of model preferences, usage statistics,
  and configuration metadata.
  """

  postgres do
    table "user_llm_configs"
    repo RubberDuck.Repo

    custom_indexes do
      index [:user_id]
      index [:provider]
      index [:is_default]
      index [:user_id, :provider]
      index [:user_id, :is_default]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :provider, :model, :is_default, :metadata]
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:model, :is_default, :metadata]
    end

    update :increment_usage do
      require_atomic? false

      change fn changeset, _context ->
        current_count = Ash.Changeset.get_attribute(changeset, :usage_count) || 0
        updated_metadata = Ash.Changeset.get_attribute(changeset, :metadata) || %{}

        updated_metadata =
          Map.merge(updated_metadata, %{
            "last_used" => DateTime.utc_now(),
            "usage_count" => current_count + 1
          })

        changeset
        |> Ash.Changeset.change_attribute(:usage_count, current_count + 1)
        |> Ash.Changeset.change_attribute(:metadata, updated_metadata)
      end
    end

    read :get_by_user do
      argument :user_id, :string, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
    end

    read :get_user_default do
      argument :user_id, :string, allow_nil?: false

      get? true
      filter expr(user_id == ^arg(:user_id) and is_default == true)
    end

    read :get_by_user_and_provider do
      argument :user_id, :string, allow_nil?: false
      argument :provider, :atom, allow_nil?: false

      filter expr(user_id == ^arg(:user_id) and provider == ^arg(:provider))
    end

    read :get_user_provider_default do
      argument :user_id, :string, allow_nil?: false
      argument :provider, :atom, allow_nil?: false

      get? true
      filter expr(user_id == ^arg(:user_id) and provider == ^arg(:provider))
    end

    action :set_user_default do
      argument :user_id, :string, allow_nil?: false
      argument :provider, :atom, allow_nil?: false
      argument :model, :string, allow_nil?: false

      run fn input, _context ->
        user_id = input.arguments.user_id
        provider = input.arguments.provider
        model = input.arguments.model

        # Use the identity to find existing config
        case RubberDuck.Memory.UserLLMConfig
             |> Ash.Query.for_read(:get_by_user_and_provider, %{user_id: user_id, provider: provider})
             |> Ash.read_one() do
          {:ok, nil} ->
            # Create new config
            RubberDuck.Memory.UserLLMConfig
            |> Ash.Changeset.for_create(:create, %{
              user_id: user_id,
              provider: provider,
              model: model,
              is_default: true
            })
            |> Ash.create()

          {:ok, config} ->
            # Update existing config
            config
            |> Ash.Changeset.for_update(:update, %{
              model: model,
              is_default: true
            })
            |> Ash.update()

          error ->
            error
        end
      end
    end
  end

  validations do
    validate fn changeset, _context ->
      # Validate that model is appropriate for provider
      provider = Ash.Changeset.get_attribute(changeset, :provider)
      model = Ash.Changeset.get_attribute(changeset, :model)

      case validate_provider_model(provider, model) do
        :ok ->
          :ok

        {:error, message} ->
          {:error, field: :model, message: message}
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :string do
      allow_nil? false
      public? true
      description "User identifier"
    end

    attribute :provider, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:openai, :anthropic, :ollama, :tgi]
      description "LLM provider name"
    end

    attribute :model, :string do
      allow_nil? false
      public? true
      description "Model name for the provider"
    end

    attribute :is_default, :boolean do
      allow_nil? false
      public? true
      default false
      description "Whether this is the user's default configuration"
    end

    attribute :usage_count, :integer do
      allow_nil? false
      public? true
      default 0
      description "Number of times this configuration has been used"
    end

    attribute :metadata, :map do
      allow_nil? true
      public? true
      default %{}
      description "Additional configuration metadata"
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user_profile, RubberDuck.Memory.UserProfile do
      source_attribute :user_id
      destination_attribute :user_id
      attribute_writable? false
    end
  end

  calculations do
    calculate :is_recently_used, :boolean do
      calculation fn records, _opts ->
        one_week_ago = DateTime.add(DateTime.utc_now(), -7, :day)

        Enum.map(records, fn record ->
          case record.metadata["last_used"] do
            nil ->
              false

            last_used_string ->
              case DateTime.from_iso8601(last_used_string) do
                {:ok, last_used, _} -> DateTime.after?(last_used, one_week_ago)
                _ -> false
              end
          end
        end)
      end
    end

    calculate :provider_string, :string do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          to_string(record.provider)
        end)
      end
    end
  end

  identities do
    identity :unique_user_provider, [:user_id, :provider]
  end

  # Private helper function for validation
  defp validate_provider_model(provider, model) do
    # This could be enhanced to check against actual provider configurations
    case provider do
      :openai when is_binary(model) and model != "" -> :ok
      :anthropic when is_binary(model) and model != "" -> :ok
      :ollama when is_binary(model) and model != "" -> :ok
      :tgi when is_binary(model) and model != "" -> :ok
      _ -> {:error, "Invalid model for provider #{provider}"}
    end
  end
end
