defmodule RubberDuck.Projects.FileAudit do
  @moduledoc """
  Audit logging for file operations.
  
  Provides comprehensive audit trail functionality including:
  - Operation logging with user/project context
  - Success/failure tracking
  - Metadata capture
  - Query capabilities
  - Retention policies
  """
  
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Workspace,
    data_layer: AshPostgres.DataLayer
  
  postgres do
    table "file_audits"
    repo RubberDuck.Repo
    
    references do
      reference :project, on_delete: :delete
      reference :user, on_delete: :nilify
    end
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :operation, :atom do
      constraints one_of: [:read, :write, :delete, :create, :rename, :move, :copy, :list]
      allow_nil? false
    end
    
    attribute :file_path, :string do
      allow_nil? false
    end
    
    attribute :status, :atom do
      constraints one_of: [:success, :failure]
      allow_nil? false
    end
    
    attribute :error_reason, :string
    
    attribute :metadata, :map do
      default %{}
    end
    
    attribute :ip_address, :string
    attribute :user_agent, :string
    
    attribute :file_size, :integer
    attribute :file_type, :string
    attribute :content_type, :string
    
    attribute :duration_ms, :integer
    
    create_timestamp :performed_at
  end
  
  relationships do
    belongs_to :project, RubberDuck.Workspace.Project do
      allow_nil? false
    end
    
    belongs_to :user, RubberDuck.Accounts.User do
      allow_nil? true
    end
  end
  
  actions do
    defaults [:read]
    
    create :log_operation do
      accept [
        :operation,
        :file_path,
        :status,
        :error_reason,
        :metadata,
        :ip_address,
        :user_agent,
        :file_size,
        :file_type,
        :content_type,
        :duration_ms
      ]
      
      argument :project_id, :uuid do
        allow_nil? false
      end
      
      argument :user_id, :uuid
      
      change manage_relationship(:project_id, :project, type: :append_and_remove)
      change manage_relationship(:user_id, :user, type: :append_and_remove)
    end
    
    read :by_project do
      argument :project_id, :uuid do
        allow_nil? false
      end
      
      filter expr(project_id == ^arg(:project_id))
    end
    
    read :by_user do
      argument :user_id, :uuid do
        allow_nil? false
      end
      
      filter expr(user_id == ^arg(:user_id))
    end
    
    read :recent_failures do
      filter expr(status == :failure)
      prepare build(sort: [performed_at: :desc])
    end
    
    read :security_events do
      filter expr(
        operation in [:write, :delete, :move] and
        (error_reason != nil or metadata[:security_alert] == true)
      )
      prepare build(sort: [performed_at: :desc])
    end
    
    destroy :cleanup_old_records do
      filter expr(performed_at < ago(90, :day))
    end
  end
  
  calculations do
    calculate :operation_count, :integer do
      calculation fn records, _ ->
        Enum.count(records)
      end
    end
    
    calculate :average_duration, :float do
      calculation fn records, _ ->
        durations = records
        |> Enum.map(& &1.duration_ms)
        |> Enum.reject(&is_nil/1)
        
        if Enum.empty?(durations) do
          0.0
        else
          Enum.sum(durations) / length(durations)
        end
      end
    end
  end
  
  code_interface do
    define :log_operation, action: :log_operation
    define :list_by_project, action: :by_project
    define :list_by_user, action: :by_user
    define :list_recent_failures, action: :recent_failures
    define :list_security_events, action: :security_events
  end
end