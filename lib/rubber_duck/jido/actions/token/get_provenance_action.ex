defmodule RubberDuck.Jido.Actions.Token.GetProvenanceAction do
  @moduledoc """
  Action for retrieving provenance information for a specific request.
  
  This action looks up provenance data and relationships for a given
  request ID, providing detailed tracking information about the request's
  origin, context, and descendants.
  """
  
  use Jido.Action,
    name: "get_provenance",
    description: "Retrieves provenance information for a specific request",
    schema: [
      request_id: [type: :string, required: true]
    ]

  alias RubberDuck.Agents.TokenManager.{TokenProvenance, ProvenanceRelationship}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    case find_provenance_by_request(agent.state.provenance_buffer, params.request_id) do
      nil ->
        {:error, "Provenance not found for request #{params.request_id}"}
        
      provenance ->
        with {:ok, relationships} <- find_provenance_relationships(agent, params.request_id),
             {:ok, result} <- build_provenance_result(provenance, relationships) do
          {:ok, result, %{agent: agent}}
        end
    end
  end

  # Private functions

  defp find_provenance_by_request(provenance_buffer, request_id) do
    Enum.find(provenance_buffer, fn prov -> 
      prov.request_id == request_id 
    end)
  end

  defp find_provenance_relationships(agent, request_id) do
    relationships = ProvenanceRelationship.find_descendants(
      agent.state.provenance_graph, 
      request_id
    )
    
    {:ok, relationships}
  end

  defp build_provenance_result(provenance, relationships) do
    result = %{
      "provenance" => provenance,
      "relationships" => relationships,
      "lineage_depth" => provenance.depth,
      "is_root" => TokenProvenance.root?(provenance),
      "metadata" => %{
        "retrieved_at" => DateTime.utc_now(),
        "relationship_count" => length(relationships)
      }
    }
    
    {:ok, result}
  end
end