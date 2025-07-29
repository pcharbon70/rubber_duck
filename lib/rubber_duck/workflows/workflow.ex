defmodule RubberDuck.Workflows.Workflow do
  @moduledoc """
  Represents a workflow instance with its execution state.
  
  Workflows are persisted Reactor executions that can be resumed, monitored,
  and recovered. They store the complete reactor state and execution context.
  """
  
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Workflows,
    data_layer: AshPostgres.DataLayer
  
  postgres do
    table "workflows"
    repo RubberDuck.Repo
    
    custom_indexes do
      index [:status]
      index [:module]
      index [:created_at]
      index [:updated_at]
      index [:workflow_id], unique: true
    end
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :create do
      primary? true
      accept [:workflow_id, :module, :reactor_state, :context, :metadata, :status]
      
      change set_attribute(:created_at, &DateTime.utc_now/0)
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end
    
    update :update do
      primary? true
      accept [:reactor_state, :context, :metadata, :status]
      
      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end
    
    update :update_status do
      accept []
      require_atomic? false
      
      argument :status, :atom do
        allow_nil? false
        constraints one_of: [:running, :completed, :failed, :halted]
      end
      
      argument :error, :map do
        allow_nil? true
      end
      
      change set_attribute(:status, arg(:status))
      change set_attribute(:error, arg(:error))
      change set_attribute(:updated_at, &DateTime.utc_now/0)
      
      change fn changeset, _ ->
        if changeset.arguments.status == :completed do
          Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())
        else
          changeset
        end
      end
    end
    
    read :get_by_workflow_id do
      get? true
      
      argument :workflow_id, :string do
        allow_nil? false
      end
      
      filter expr(workflow_id == ^arg(:workflow_id))
    end
    
    read :list_by_status do
      argument :status, :atom do
        allow_nil? false
        constraints one_of: [:running, :completed, :failed, :halted]
      end
      
      filter expr(status == ^arg(:status))
    end
    
    read :list_by_module do
      argument :module, :atom do
        allow_nil? false
      end
      
      filter expr(module == ^arg(:module))
    end
    
    read :list_halted do
      filter expr(status == :halted)
    end
    
    destroy :cleanup_old do
      argument :days_old, :integer do
        allow_nil? false
        default 30
      end
      
      filter expr(created_at < ago(^arg(:days_old), :day))
    end
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :workflow_id, :string do
      allow_nil? false
      public? true
      description "Unique identifier for the workflow instance"
    end
    
    attribute :module, :atom do
      allow_nil? false
      public? true
      description "The Reactor workflow module"
    end
    
    attribute :status, :atom do
      allow_nil? false
      public? true
      default :running
      constraints one_of: [:running, :completed, :failed, :halted]
      description "Current status of the workflow"
    end
    
    attribute :reactor_state, :map do
      allow_nil? false
      public? true
      default %{}
      description "Serialized Reactor execution state"
    end
    
    attribute :context, :map do
      allow_nil? false
      public? true
      default %{}
      description "Workflow execution context"
    end
    
    attribute :metadata, :map do
      allow_nil? false
      public? true
      default %{}
      description "Additional workflow metadata"
    end
    
    attribute :error, :map do
      allow_nil? true
      public? true
      description "Error information if workflow failed"
    end
    
    attribute :completed_at, :utc_datetime do
      allow_nil? true
      public? true
      description "When the workflow completed"
    end
    
    create_timestamp :created_at
    update_timestamp :updated_at
  end
  
  # Removed relationships for now due to type mismatch
  # TODO: Fix checkpoint relationship type compatibility
  
  calculations do
    calculate :duration, :integer do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case {record.created_at, record.completed_at} do
            {created, completed} when not is_nil(completed) ->
              DateTime.diff(completed, created, :second)
            _ ->
              nil
          end
        end)
      end
    end
    
    calculate :checkpoint_count, :integer do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          case record.checkpoints do
            %Ash.NotLoaded{} -> 0
            checkpoints -> length(checkpoints)
          end
        end)
      end
    end
    
    calculate :is_resumable, :boolean do
      calculation fn records, _opts ->
        Enum.map(records, fn record ->
          record.status == :halted and not is_nil(record.reactor_state)
        end)
      end
    end
  end
end