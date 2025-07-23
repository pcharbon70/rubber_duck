defmodule RubberDuck.Workspace.ProjectCollaborator do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Workspace,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "project_collaborators"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:permission]
      primary? true

      argument :project_id, :uuid do
        allow_nil? false
      end

      argument :user_id, :uuid do
        allow_nil? false
      end

      change set_attribute(:project_id, arg(:project_id))
      change set_attribute(:user_id, arg(:user_id))
    end

    update :update do
      accept [:permission]
    end
  end

  policies do
    policy action_type(:create) do
      # Only project owners can add collaborators
      # This is enforced via the domain function
      authorize_if always()
      description "Authorization handled by domain function"
    end

    policy action_type(:read) do
      authorize_if expr(project.owner_id == ^actor(:id))
      authorize_if expr(user_id == ^actor(:id))
      description "Project owners and the collaborator themselves can read"
    end

    policy action_type(:update) do
      authorize_if expr(project.owner_id == ^actor(:id))
      description "Only project owners can update collaborator permissions"
    end

    policy action_type(:destroy) do
      authorize_if expr(project.owner_id == ^actor(:id))
      authorize_if expr(user_id == ^actor(:id))
      description "Project owners can remove collaborators, collaborators can remove themselves"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :permission, :atom do
      constraints one_of: [:read, :write]
      allow_nil? false
      default :read
      public? true
      description "Permission level for the collaborator"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, RubberDuck.Workspace.Project do
      allow_nil? false
      attribute_writable? true
      primary_key? true
    end

    belongs_to :user, RubberDuck.Accounts.User do
      allow_nil? false
      attribute_writable? true
      primary_key? true
    end
  end

  identities do
    identity :unique_collaborator, [:project_id, :user_id]
  end
end
