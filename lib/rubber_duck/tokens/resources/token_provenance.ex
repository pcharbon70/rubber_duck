defmodule RubberDuck.Tokens.Resources.TokenProvenance do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Tokens,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  @moduledoc """
  Tracks the provenance and lineage of token usage.
  
  Records detailed information about how tokens were consumed,
  including the workflow, task type, input/output data, and
  relationships to other token usage for lineage tracking.
  """

  postgres do
    table "token_provenances"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [
        :request_id,
        :workflow_id,
        :task_type,
        :task_name,
        :agent_type,
        :agent_id,
        :input_hash,
        :input_size,
        :output_hash,
        :output_size,
        :processing_time_ms,
        :error_code,
        :error_message,
        :metadata,
        :cached,
        :cache_hit_id
      ]
    end

    create :bulk_create do
      accept [
        :request_id,
        :workflow_id,
        :task_type,
        :task_name,
        :agent_type,
        :agent_id,
        :input_hash,
        :input_size,
        :output_hash,
        :output_size,
        :processing_time_ms,
        :error_code,
        :error_message,
        :metadata,
        :cached,
        :cache_hit_id
      ]
      
      transaction? true
      upsert? true
      upsert_identity :unique_request_id
    end

    read :by_request_id do
      argument :request_id, :string, allow_nil?: false
      
      filter expr(request_id == ^arg(:request_id))
    end

    read :by_workflow do
      argument :workflow_id, :string, allow_nil?: false
      
      filter expr(workflow_id == ^arg(:workflow_id))
    end

    read :by_task_type do
      argument :task_type, :string, allow_nil?: false
      
      filter expr(task_type == ^arg(:task_type))
    end

    read :find_duplicates do
      argument :input_hash, :string, allow_nil?: false
      
      prepare fn query, _context ->
        query
        |> Ash.Query.filter(input_hash == ^query.arguments.input_hash)
        |> Ash.Query.filter(error_code == nil)
        |> Ash.Query.sort(inserted_at: :desc)
      end
    end

    read :get_lineage do
      argument :request_id, :string, allow_nil?: false
      
      # This is a placeholder - actual lineage building would happen
      # in the agent using the ProvenanceRelationship resource
      filter expr(request_id == ^arg(:request_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :request_id, :string do
      allow_nil? false
      description "Unique identifier for the request"
    end

    attribute :workflow_id, :string do
      allow_nil? true
      description "ID of the workflow this request is part of"
    end

    attribute :task_type, :string do
      allow_nil? false
      description "Type of task (e.g., 'code_generation', 'analysis', 'chat')"
    end

    attribute :task_name, :string do
      allow_nil? true
      description "Human-readable name of the specific task"
    end

    attribute :agent_type, :string do
      allow_nil? true
      description "Type of agent that processed this request"
    end

    attribute :agent_id, :string do
      allow_nil? true
      description "ID of the specific agent instance"
    end

    attribute :input_hash, :string do
      allow_nil? false
      description "Hash of the input data for deduplication"
    end

    attribute :input_size, :integer do
      allow_nil? false
      constraints min: 0
      description "Size of input in bytes"
    end

    attribute :output_hash, :string do
      allow_nil? true
      description "Hash of the output data"
    end

    attribute :output_size, :integer do
      allow_nil? true
      constraints min: 0
      description "Size of output in bytes"
    end

    attribute :processing_time_ms, :integer do
      allow_nil? true
      constraints min: 0
      description "Time taken to process in milliseconds"
    end

    attribute :error_code, :string do
      allow_nil? true
      description "Error code if the request failed"
    end

    attribute :error_message, :string do
      allow_nil? true
      description "Error message if the request failed"
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      description "Additional provenance metadata"
    end

    attribute :cached, :boolean do
      allow_nil? false
      default false
      description "Whether this was served from cache"
    end

    attribute :cache_hit_id, :uuid do
      allow_nil? true
      description "ID of the original request if this was a cache hit"
    end

    timestamps()
  end

  relationships do
    # Self-referential relationship for cache hits
    belongs_to :cache_source, __MODULE__ do
      attribute_type :uuid
      source_attribute :cache_hit_id
      destination_attribute :id
    end

    has_one :token_usage, RubberDuck.Tokens.Resources.TokenUsage do
      destination_attribute :request_id
      source_attribute :request_id
    end

    # Many-to-many relationships through ProvenanceRelationship
    many_to_many :ancestors, __MODULE__ do
      through RubberDuck.Tokens.Resources.ProvenanceRelationship
      source_attribute_on_join_resource :child_request_id
      destination_attribute_on_join_resource :parent_request_id
      join_relationship :parent_relationships
    end

    many_to_many :descendants, __MODULE__ do
      through RubberDuck.Tokens.Resources.ProvenanceRelationship
      source_attribute_on_join_resource :parent_request_id
      destination_attribute_on_join_resource :child_request_id
      join_relationship :child_relationships
    end
  end

  calculations do
    calculate :is_success, :boolean, expr(is_nil(error_code))
    
    calculate :has_output, :boolean, expr(not is_nil(output_hash))
    
    calculate :efficiency_ratio, :decimal, expr(
      if input_size > 0 and output_size > 0 do
        output_size / input_size
      else
        0
      end
    )
  end

  identities do
    identity :unique_request_id, [:request_id]
  end

  postgres do
    table "token_provenances"
    repo RubberDuck.Repo

    references do
      reference :cache_source, on_delete: :nilify
    end
  end

  code_interface do
    define :record_provenance, action: :create
    define :bulk_record_provenance, action: :bulk_create
  end
end