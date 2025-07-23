defmodule RubberDuck.Workspace.Project do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Workspace,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "projects"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :name,
        :description,
        :configuration,
        :root_path,
        :file_access_enabled,
        :max_file_size,
        :allowed_extensions,
        :sandbox_config
      ]

      primary? true

      # Automatically set the owner to the current actor
      change fn changeset, context ->
        case context.actor do
          nil -> changeset
          actor -> Ash.Changeset.force_change_attribute(changeset, :owner_id, actor.id)
        end
      end
    end

    update :update do
      accept [
        :name,
        :description,
        :configuration,
        :root_path,
        :file_access_enabled,
        :max_file_size,
        :allowed_extensions,
        :sandbox_config
      ]

      require_atomic? false
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if always()
      description "Any authenticated user can create a project"
    end

    policy action_type(:read) do
      authorize_if expr(owner_id == ^actor(:id))
      authorize_if relates_to_actor_via([:collaborators, :user])
      description "Owners and collaborators can read projects"
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(owner_id == ^actor(:id))
      description "Only owners can update or delete projects"
    end
  end

  validations do
    validate fn changeset, _context ->
      if Ash.Changeset.get_attribute(changeset, :file_access_enabled) == true do
        case Ash.Changeset.get_attribute(changeset, :root_path) do
          nil ->
            {:error, field: :root_path, message: "is required when file access is enabled"}

          path ->
            if String.trim(path) == "" do
              {:error, field: :root_path, message: "cannot be empty when file access is enabled"}
            else
              :ok
            end
        end
      else
        :ok
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? true
      public? true
    end

    attribute :configuration, :map do
      allow_nil? true
      default %{}
      public? true
    end

    # File sandbox attributes
    attribute :root_path, :string do
      allow_nil? true
      public? true
      description "The root directory path for this project's file sandbox"
    end

    attribute :file_access_enabled, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether file access is enabled for this project"
    end

    attribute :max_file_size, :integer do
      allow_nil? true
      # 10MB
      default 10_485_760
      public? true
      description "Maximum file size in bytes allowed for this project"
    end

    attribute :allowed_extensions, {:array, :string} do
      allow_nil? true
      default []
      public? true
      description "List of allowed file extensions (empty means all allowed)"
    end

    attribute :sandbox_config, :map do
      allow_nil? true
      default %{}
      public? true
      description "Additional sandbox configuration options"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :code_files, RubberDuck.Workspace.CodeFile

    belongs_to :owner, RubberDuck.Accounts.User do
      allow_nil? false
      attribute_writable? true
    end

    has_many :collaborators, RubberDuck.Workspace.ProjectCollaborator
  end
end
