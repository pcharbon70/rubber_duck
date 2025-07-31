defmodule RubberDuck.Tokens.Resources.ProvenanceRelationship do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Tokens,
    data_layer: AshPostgres.DataLayer

  @moduledoc """
  Tracks parent-child relationships between token provenance records.
  
  Enables building lineage trees showing how token usage flows through
  workflows, with support for multiple relationship types and metadata.
  """

  postgres do
    table "provenance_relationships"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [
        :parent_request_id,
        :child_request_id,
        :relationship_type,
        :sequence_number,
        :metadata
      ]
    end

    create :bulk_create do
      accept [
        :parent_request_id,
        :child_request_id,
        :relationship_type,
        :sequence_number,
        :metadata
      ]
      
      transaction? true
      upsert? true
      upsert_identity :unique_parent_child
    end

    read :find_ancestors do
      argument :request_id, :string, allow_nil?: false
      
      filter expr(child_request_id == ^arg(:request_id))
    end

    read :find_descendants do
      argument :request_id, :string, allow_nil?: false
      
      filter expr(parent_request_id == ^arg(:request_id))
    end

    read :find_roots do
      argument :request_id, :string, allow_nil?: false
      
      # This would need a recursive CTE in practice
      # For now, filter relationships where parent has no ancestors
      prepare fn query, _context ->
        # Placeholder - actual implementation would use recursive query
        query
      end
    end

    read :build_lineage_tree do
      argument :request_id, :string, allow_nil?: false
      
      # This would build the full tree structure
      # Implementation would happen in the agent
      prepare fn query, _context ->
        query
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :parent_request_id, :string do
      allow_nil? false
      description "Request ID of the parent provenance record"
    end

    attribute :child_request_id, :string do
      allow_nil? false
      description "Request ID of the child provenance record"
    end

    attribute :relationship_type, :string do
      allow_nil? false
      default "derived_from"
      description "Type of relationship between provenance records"
    end

    attribute :sequence_number, :integer do
      allow_nil? true
      constraints min: 0
      description "Order in sequence for ordered relationships"
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      description "Additional relationship metadata"
    end

    timestamps()
  end

  validations do
    validate one_of(:relationship_type, [
      "derived_from",
      "triggered_by",
      "composed_from",
      "refined_from",
      "validated_by",
      "cached_from"
    ])
  end

  relationships do
    belongs_to :parent_provenance, RubberDuck.Tokens.Resources.TokenProvenance do
      attribute_type :string
      source_attribute :parent_request_id
      destination_attribute :request_id
    end

    belongs_to :child_provenance, RubberDuck.Tokens.Resources.TokenProvenance do
      attribute_type :string
      source_attribute :child_request_id
      destination_attribute :request_id
    end
  end

  identities do
    identity :unique_parent_child, [:parent_request_id, :child_request_id]
  end

  postgres do
    table "provenance_relationships"
    repo RubberDuck.Repo

    references do
      # Note: These would reference the token_provenances table
      # but we're using string IDs for request_id
    end
  end

  code_interface do
    define :create_relationship, action: :create
    define :bulk_create_relationships, action: :bulk_create
  end
end