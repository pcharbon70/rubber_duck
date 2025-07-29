defmodule RubberDuck.Workflows.Checkpoint do
  @moduledoc """
  Represents a checkpoint in a workflow execution.
  
  Checkpoints allow workflows to be resumed from specific points
  and provide recovery mechanisms for long-running workflows.
  """
  
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Workflows,
    data_layer: AshPostgres.DataLayer
  
  postgres do
    table "workflow_checkpoints"
    repo RubberDuck.Repo
    
    custom_indexes do
      index [:workflow_id]
      index [:created_at]
      index [:checkpoint_id], unique: true
      index [:workflow_id, :created_at]
    end
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :create do
      primary? true
      accept [:workflow_id, :checkpoint_id, :step_name, :state, :metadata]
      
      change set_attribute(:created_at, &DateTime.utc_now/0)
    end
    
    read :get_by_checkpoint_id do
      get? true
      
      argument :checkpoint_id, :string do
        allow_nil? false
      end
      
      filter expr(checkpoint_id == ^arg(:checkpoint_id))
    end
    
    read :get_latest do
      get? true
      
      argument :workflow_id, :string do
        allow_nil? false
      end
      
      filter expr(workflow_id == ^arg(:workflow_id))
      prepare fn query, _ ->
        Ash.Query.sort(query, [created_at: :desc])
      end
    end
    
    read :list_by_workflow do
      argument :workflow_id, :string do
        allow_nil? false
      end
      
      filter expr(workflow_id == ^arg(:workflow_id))
      prepare fn query, _ ->
        Ash.Query.sort(query, [created_at: :desc])
      end
    end
    
    destroy :cleanup_by_workflow do
      argument :workflow_id, :string do
        allow_nil? false
      end
      
      filter expr(workflow_id == ^arg(:workflow_id))
    end
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :checkpoint_id, :string do
      allow_nil? false
      public? true
      description "Unique identifier for the checkpoint"
    end
    
    attribute :workflow_id, :string do
      allow_nil? false
      public? true
      description "ID of the workflow this checkpoint belongs to"
    end
    
    attribute :step_name, :string do
      allow_nil? false
      public? true
      description "Name of the step where checkpoint was created"
    end
    
    attribute :state, :map do
      allow_nil? false
      public? true
      default %{}
      description "Intermediate state at this checkpoint"
    end
    
    attribute :metadata, :map do
      allow_nil? false
      public? true
      default %{}
      description "Additional checkpoint metadata"
    end
    
    create_timestamp :created_at
  end
  
  # Simplified - no relationships for now
  
  calculations do
    calculate :age_in_seconds, :integer do
      calculation fn records, _opts ->
        now = DateTime.utc_now()
        Enum.map(records, fn record ->
          DateTime.diff(now, record.created_at, :second)
        end)
      end
    end
  end
end