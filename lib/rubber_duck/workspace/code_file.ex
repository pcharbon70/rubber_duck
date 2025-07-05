defmodule RubberDuck.Workspace.CodeFile do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Workspace,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "code_files"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :file_path, :string do
      allow_nil? false
      public? true
    end

    attribute :content, :string do
      allow_nil? true
      public? true
    end

    attribute :language, :string do
      allow_nil? true
      public? true
    end

    # AST cache stored as JSONB
    attribute :ast_cache, :map do
      allow_nil? true
      default %{}
      public? true
    end

    # Embeddings stored as vector array
    attribute :embeddings, {:array, :float} do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, RubberDuck.Workspace.Project do
      allow_nil? false
      attribute_type :uuid
      attribute_writable? true
    end

    has_many :analysis_results, RubberDuck.Workspace.AnalysisResult
  end

  actions do
    defaults [:read, :destroy]
    
    create :create do
      accept [:file_path, :content, :language, :ast_cache, :embeddings, :project_id]
    end
    
    update :update do
      accept [:file_path, :content, :language, :ast_cache, :embeddings]
    end

    # Custom semantic search action
    read :semantic_search do
      argument :embedding, {:array, :float} do
        allow_nil? false
      end

      argument :limit, :integer do
        allow_nil? true
        default 10
      end

      # This will need to be implemented with a preparation
      # that uses pgvector for similarity search
      prepare fn query, _context ->
        # TODO: Implement pgvector similarity search
        query
      end
    end
  end
end