defmodule RubberDuck.Projects.SecurityAudit do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Workspace,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  @moduledoc """
  Tracks security-related events for project file access.
  
  Records all file access attempts, permission checks, and security violations
  for audit trail and security monitoring.
  """

  postgres do
    table "project_security_audits"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read]
    
    create :log_access do
      accept [:action, :path, :status, :details]
      
      argument :project_id, :uuid do
        allow_nil? false
      end
      
      argument :user_id, :uuid do
        allow_nil? false
      end
      
      change set_attribute(:project_id, arg(:project_id))
      change set_attribute(:user_id, arg(:user_id))
    end
    
    read :by_project do
      argument :project_id, :uuid do
        allow_nil? false
      end
      
      filter expr(project_id == ^arg(:project_id))
    end
    
    read :security_violations do
      filter expr(status == :denied or status == :violation)
    end
    
    read :recent_activity do
      argument :hours, :integer do
        allow_nil? false
        default 24
      end
      
      filter expr(inserted_at > ago(^arg(:hours), :hour))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  policies do
    policy action_type(:create) do
      # System-level logging, always allowed for authenticated users
      authorize_if always()
      description "Security audit logging is always allowed"
    end

    policy action_type(:read) do
      # Only project owners can read security audits
      authorize_if expr(project.owner_id == ^actor(:id))
      description "Only project owners can view security audit logs"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :action, :atom do
      constraints one_of: [:read, :write, :list, :delete, :access_check, :permission_check]
      allow_nil? false
      public? true
      description "The type of action attempted"
    end

    attribute :path, :string do
      allow_nil? false
      public? true
      description "The file path that was accessed or attempted"
    end

    attribute :status, :atom do
      constraints one_of: [:allowed, :denied, :violation, :error]
      allow_nil? false
      public? true
      description "The result of the security check"
    end

    attribute :details, :map do
      allow_nil? true
      default %{}
      public? true
      description "Additional details about the security event"
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :project, RubberDuck.Workspace.Project do
      allow_nil? false
      attribute_writable? true
    end
    
    belongs_to :user, RubberDuck.Accounts.User do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_audit_entry, [:project_id, :user_id, :path, :action, :inserted_at]
  end

  # Custom query functions
  
  def violations_in_last_hour(project_id) do
    __MODULE__
    |> Ash.Query.filter(project_id: project_id)
    |> Ash.Query.filter(status: [:denied, :violation])
    |> Ash.read!()
  end

  def user_activity_summary(user_id, hours \\ 24) do
    # Since Ash doesn't support group_by in queries, we'll fetch and group in Elixir
    cutoff_time = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)
    
    __MODULE__
    |> Ash.Query.filter(user_id: user_id)
    |> Ash.Query.filter(occurred_at > ^cutoff_time)
    |> Ash.read!()
    |> Enum.group_by(&{&1.action, &1.status})
    |> Enum.map(fn {{action, status}, records} ->
      %{
        action: action,
        status: status,
        count: length(records)
      }
    end)
  end
end