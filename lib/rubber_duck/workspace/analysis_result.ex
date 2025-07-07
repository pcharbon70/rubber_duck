defmodule RubberDuck.Workspace.AnalysisResult do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Workspace,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "analysis_results"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:analysis_type, :results, :severity, :code_file_id]
    end

    update :update do
      accept [:analysis_type, :results, :severity]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :analysis_type, :string do
      allow_nil? false
      public? true
    end

    # Results stored as JSONB
    attribute :results, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :severity, :atom do
      allow_nil? true
      constraints one_of: [:low, :medium, :high, :critical]
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :code_file, RubberDuck.Workspace.CodeFile do
      allow_nil? false
      attribute_type :uuid
      attribute_writable? true
    end
  end
end
