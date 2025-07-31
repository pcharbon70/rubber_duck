defmodule RubberDuck.Agents.TokenManager.ProvenanceRelationship do
  @moduledoc """
  Manages relationships between token usage requests, enabling graph-like
  querying and lineage tracking across the system.
  """

  @type relationship_type :: 
    :triggered_by |      # Direct causation
    :part_of |          # Belongs to larger workflow
    :derived_from |     # Based on or inspired by
    :retry_of |         # Retry attempt
    :fallback_for |     # Fallback after failure
    :enhancement_of |   # Enhancement/refinement
    :validation_of |    # Validation check
    :continuation_of    # Multi-turn continuation

  @type t :: %__MODULE__{
    id: String.t(),
    source_request_id: String.t(),
    target_request_id: String.t(),
    relationship_type: relationship_type(),
    created_at: DateTime.t(),
    metadata: map()
  }

  defstruct [
    :id,
    :source_request_id,
    :target_request_id,
    :relationship_type,
    :created_at,
    :metadata
  ]

  @doc """
  Creates a new relationship between requests.
  
  ## Parameters
  
  - `source_request_id` - The originating request
  - `target_request_id` - The resulting request
  - `relationship_type` - Type of relationship
  - `metadata` - Additional context (optional)
  
  ## Examples
  
      iex> ProvenanceRelationship.new("req_123", "req_124", :triggered_by)
      %ProvenanceRelationship{...}
  """
  def new(source_request_id, target_request_id, relationship_type, metadata \\ %{}) do
    %__MODULE__{
      id: generate_id(),
      source_request_id: source_request_id,
      target_request_id: target_request_id,
      relationship_type: relationship_type,
      created_at: DateTime.utc_now(),
      metadata: metadata
    }
  end

  @doc """
  Validates a relationship.
  """
  def validate(%__MODULE__{} = relationship) do
    errors = []
    
    errors = if relationship.source_request_id == relationship.target_request_id,
      do: ["source and target cannot be the same" | errors], else: errors
    
    errors = if relationship.relationship_type not in valid_relationship_types(),
      do: ["invalid relationship type" | errors], else: errors
    
    if errors == [] do
      {:ok, relationship}
    else
      {:error, errors}
    end
  end

  @doc """
  Returns all valid relationship types.
  """
  def valid_relationship_types do
    [:triggered_by, :part_of, :derived_from, :retry_of, :fallback_for,
     :enhancement_of, :validation_of, :continuation_of]
  end

  @doc """
  Checks if a relationship creates a cycle in the given graph.
  """
  def would_create_cycle?(graph, source_id, target_id) do
    # Check if adding this edge would create a cycle
    has_path?(graph, target_id, source_id)
  end

  @doc """
  Finds all ancestors of a request (requests that led to this one).
  """
  def find_ancestors(relationships, request_id, max_depth \\ nil) do
    find_related(relationships, request_id, :incoming, max_depth)
  end

  @doc """
  Finds all descendants of a request (requests triggered by this one).
  """
  def find_descendants(relationships, request_id, max_depth \\ nil) do
    find_related(relationships, request_id, :outgoing, max_depth)
  end

  @doc """
  Finds the root request(s) in a lineage.
  """
  def find_roots(relationships, request_id) do
    ancestors = find_ancestors(relationships, request_id)
    
    if ancestors == [] do
      [request_id]
    else
      ancestors
      |> Enum.flat_map(&find_roots(relationships, &1))
      |> Enum.uniq()
    end
  end

  @doc """
  Builds a complete lineage tree for a request.
  """
  def build_lineage_tree(relationships, request_id) do
    %{
      id: request_id,
      ancestors: build_ancestor_tree(relationships, request_id),
      descendants: build_descendant_tree(relationships, request_id)
    }
  end

  @doc """
  Filters relationships by type.
  """
  def filter_by_type(relationships, type) when is_atom(type) do
    Enum.filter(relationships, &(&1.relationship_type == type))
  end

  @doc """
  Groups relationships by their type.
  """
  def group_by_type(relationships) do
    Enum.group_by(relationships, & &1.relationship_type)
  end

  @doc """
  Finds all requests in the same workflow.
  """
  def find_workflow_members(relationships, request_id) do
    _workflow_relationships = filter_by_type(relationships, :part_of)
    
    # Find the workflow root
    workflow_roots = find_by_relationship_type(relationships, request_id, :part_of, :incoming)
    
    case workflow_roots do
      [workflow_id | _] ->
        # Find all members of this workflow
        find_by_relationship_type(relationships, workflow_id, :part_of, :outgoing)
      _ ->
        []
    end
  end

  @doc """
  Calculates the depth of a request in its lineage.
  """
  def calculate_depth(relationships, request_id) do
    ancestors = find_ancestors(relationships, request_id)
    
    if ancestors == [] do
      0
    else
      ancestors
      |> Enum.map(&calculate_depth(relationships, &1))
      |> Enum.max()
      |> Kernel.+(1)
    end
  end

  @doc """
  Creates a DOT graph representation for visualization.
  """
  def to_dot_graph(relationships, _options \\ %{}) do
    nodes = extract_all_nodes(relationships)
    
    dot_lines = [
      "digraph Provenance {",
      "  rankdir=LR;",
      "  node [shape=box, style=rounded];",
      ""
    ]
    
    # Add nodes
    node_lines = Enum.map(nodes, fn node ->
      "  \"#{node}\";"
    end)
    
    # Add edges with labels
    edge_lines = Enum.map(relationships, fn rel ->
      label = relationship_label(rel.relationship_type)
      "  \"#{rel.source_request_id}\" -> \"#{rel.target_request_id}\" [label=\"#{label}\"];"
    end)
    
    (dot_lines ++ node_lines ++ [""] ++ edge_lines ++ ["}"])
    |> Enum.join("\n")
  end

  ## Private Functions

  defp find_related(relationships, request_id, direction, max_depth, current_depth \\ 0) do
    if max_depth && current_depth >= max_depth do
      []
    else
      direct_related = case direction do
        :incoming -> 
          relationships
          |> Enum.filter(&(&1.target_request_id == request_id))
          |> Enum.map(& &1.source_request_id)
        :outgoing ->
          relationships
          |> Enum.filter(&(&1.source_request_id == request_id))
          |> Enum.map(& &1.target_request_id)
      end
      
      indirect_related = direct_related
      |> Enum.flat_map(&find_related(relationships, &1, direction, max_depth, current_depth + 1))
      
      (direct_related ++ indirect_related) |> Enum.uniq()
    end
  end

  defp find_by_relationship_type(relationships, request_id, type, direction) do
    relationships
    |> filter_by_type(type)
    |> Enum.filter(fn rel ->
      case direction do
        :incoming -> rel.target_request_id == request_id
        :outgoing -> rel.source_request_id == request_id
      end
    end)
    |> Enum.map(fn rel ->
      case direction do
        :incoming -> rel.source_request_id
        :outgoing -> rel.target_request_id
      end
    end)
  end

  defp build_ancestor_tree(relationships, request_id) do
    relationships
    |> Enum.filter(&(&1.target_request_id == request_id))
    |> Enum.map(fn rel ->
      %{
        id: rel.source_request_id,
        relationship: rel.relationship_type,
        ancestors: build_ancestor_tree(relationships, rel.source_request_id)
      }
    end)
  end

  defp build_descendant_tree(relationships, request_id) do
    relationships
    |> Enum.filter(&(&1.source_request_id == request_id))
    |> Enum.map(fn rel ->
      %{
        id: rel.target_request_id,
        relationship: rel.relationship_type,
        descendants: build_descendant_tree(relationships, rel.target_request_id)
      }
    end)
  end

  defp has_path?(relationships, from_id, to_id) do
    to_id in find_descendants(relationships, from_id)
  end

  defp extract_all_nodes(relationships) do
    source_nodes = Enum.map(relationships, & &1.source_request_id)
    target_nodes = Enum.map(relationships, & &1.target_request_id)
    (source_nodes ++ target_nodes) |> Enum.uniq()
  end

  defp relationship_label(type) do
    case type do
      :triggered_by -> "triggered"
      :part_of -> "part of"
      :derived_from -> "derived"
      :retry_of -> "retry"
      :fallback_for -> "fallback"
      :enhancement_of -> "enhanced"
      :validation_of -> "validates"
      :continuation_of -> "continues"
      _ -> to_string(type)
    end
  end

  defp generate_id do
    "rel_#{System.unique_integer([:positive, :monotonic])}"
  end
end