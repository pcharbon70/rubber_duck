defmodule RubberDuck.Prompts.PromptVersion do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Prompts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "prompt_versions"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:prompt_id, :version_number, :content, :variables_schema, :change_description]
      argument :created_by_id, :uuid, allow_nil?: false
      
      change set_attribute(:created_by_id, arg(:created_by_id))
    end
  end

  policies do
    # For creates, check actor has an id (version creation is managed internally)
    policy action_type(:create) do
      authorize_if actor_present()
    end
    
    # For reads, users can only access versions of their own prompts
    policy action_type(:read) do
      authorize_if expr(prompt.user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :version_number, :integer do
      allow_nil? false
      public? true
    end

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    attribute :variables_schema, :map do
      public? true
    end

    attribute :change_description, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :prompt, RubberDuck.Prompts.Prompt do
      allow_nil? false
    end

    belongs_to :created_by, RubberDuck.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :prompt_version, [:prompt_id, :version_number]
  end
end