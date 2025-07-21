defmodule RubberDuck.Prompts.Category do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Prompts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "prompt_categories"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:name, :description, :parent_id]
      
      change set_attribute(:user_id, actor(:id))
    end
  end

  policies do
    # For creates, check actor has an id
    policy action_type(:create) do
      authorize_if actor_present()
    end
    
    # For reads, updates, and destroys, users can only access their own categories
    policy action_type([:read, :update, :destroy]) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, RubberDuck.Accounts.User do
      allow_nil? false
      attribute_writable? false
    end

    belongs_to :parent, __MODULE__ do
      public? true
    end

    has_many :children, __MODULE__ do
      destination_attribute :parent_id
    end

    many_to_many :prompts, RubberDuck.Prompts.Prompt do
      through RubberDuck.Prompts.PromptCategory
      source_attribute_on_join_resource :category_id
      destination_attribute_on_join_resource :prompt_id
    end
  end

  identities do
    identity :user_name, [:user_id, :name]
  end
end