defmodule RubberDuck.Workflows.Version do
  @moduledoc """
  Simplified version resource for workflow versions.
  """
  
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Workflows,
    data_layer: AshPostgres.DataLayer
  
  postgres do
    table "workflow_versions"
    repo RubberDuck.Repo
    
    custom_indexes do
      index [:module]
      index [:version]
      index [:module, :version], unique: true
      index [:registered_at]
    end
  end
  
  actions do
    defaults [:read, :update, :destroy]
    
    create :create do
      primary? true
      accept [:module, :version, :definition, :compatibility, :is_current, :metadata]
    end
    
    read :get_current do
      argument :module, :atom do
        allow_nil? false
      end
      
      filter expr(module == ^arg(:module) and is_current == true)
      get? true
    end
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :module, :atom do
      allow_nil? false
      public? true
    end
    
    attribute :version, :string do
      allow_nil? false
      public? true
    end
    
    attribute :compatibility, :string do
      allow_nil? false
      public? true
      default "*"
    end
    
    attribute :is_current, :boolean do
      allow_nil? false
      public? true
      default false
    end
    
    attribute :definition, :map do
      allow_nil? false
      public? true
      default %{}
    end
    
    attribute :migrations, :map do
      allow_nil? false
      public? true
      default %{}
    end
    
    attribute :metadata, :map do
      allow_nil? false
      public? true
      default %{}
    end
    
    create_timestamp :registered_at
  end
end