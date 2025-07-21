defmodule RubberDuck.Prompts.Prompt do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Prompts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "prompts"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:title, :description, :content, :template_variables, :is_active, :metadata]
      
      argument :category_ids, {:array, :uuid}, allow_nil?: true
      argument :tag_ids, {:array, :uuid}, allow_nil?: true

      change set_attribute(:user_id, actor(:id))
      change manage_relationship(:category_ids, :categories, type: :append)
      change manage_relationship(:tag_ids, :tags, type: :append)
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:title, :description, :content, :template_variables, :is_active, :metadata]
      
      argument :category_ids, {:array, :uuid}, allow_nil?: true
      argument :tag_ids, {:array, :uuid}, allow_nil?: true

      # Create version before update
      change {RubberDuck.Prompts.Changes.CreateVersion, []}
      
      change manage_relationship(:category_ids, :categories, type: :direct_control)
      change manage_relationship(:tag_ids, :tags, type: :direct_control)
    end

    read :search do
      argument :query, :string, allow_nil?: false
      
      filter expr(
        contains(title, ^arg(:query)) or
        contains(description, ^arg(:query)) or
        contains(content, ^arg(:query))
      )
    end

  end

  policies do
    # For creates, check actor has an id
    policy action_type(:create) do
      authorize_if actor_present()
    end
    
    # For reads, updates, and destroys, users can only access their own prompts
    policy action_type([:read, :update, :destroy]) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    attribute :template_variables, :map do
      default %{}
      public? true
    end

    attribute :is_active, :boolean do
      default true
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, RubberDuck.Accounts.User do
      allow_nil? false
      attribute_writable? false
    end

    has_many :versions, RubberDuck.Prompts.PromptVersion do
      destination_attribute :prompt_id
    end

    many_to_many :categories, RubberDuck.Prompts.Category do
      through RubberDuck.Prompts.PromptCategory
      source_attribute_on_join_resource :prompt_id
      destination_attribute_on_join_resource :category_id
    end

    many_to_many :tags, RubberDuck.Prompts.Tag do
      through RubberDuck.Prompts.PromptTag
      source_attribute_on_join_resource :prompt_id
      destination_attribute_on_join_resource :tag_id
    end
  end

  identities do
    identity :user_title, [:user_id, :title]
  end
end