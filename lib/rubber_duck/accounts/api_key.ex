defmodule RubberDuck.Accounts.ApiKey do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "api_keys"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :expires_at]

      change {AshAuthentication.Strategy.ApiKey.GenerateApiKey, prefix: :rubberduck, hash: :api_key_hash}
    end

    create :create_with_hash do
      accept [:user_id, :expires_at, :api_key_hash]
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:create) do
      description "Users can create API keys when user_id matches actor id"
      authorize_if changing_attributes(user_id: [to: actor(:id)])
    end

    policy action_type([:read, :update, :destroy]) do
      description "Users can only read/update/destroy their own API keys"
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :api_key_hash, :binary do
      allow_nil? false
      sensitive? true
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :user, RubberDuck.Accounts.User
  end

  calculations do
    calculate :valid, :boolean, expr(expires_at > now())
  end

  identities do
    identity :unique_api_key, [:api_key_hash]
  end
end
