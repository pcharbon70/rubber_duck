defmodule RubberDuck.Jido.Actions.Token.GetLineageAction do
  @moduledoc """
  Action for retrieving complete lineage information for a request.
  
  This action builds a comprehensive lineage tree showing all ancestors
  and descendants of a request, providing full traceability of request
  relationships and provenance data.
  """
  
  use Jido.Action,
    name: "get_lineage",
    description: "Retrieves complete lineage tree for a request",
    schema: [
      request_id: [type: :string, required: true]
    ]

  alias RubberDuck.Agents.TokenManager.ProvenanceRelationship
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, lineage_tree} <- build_lineage_tree(agent, params.request_id),
         {:ok, provenance_data} <- gather_provenance_data(agent, lineage_tree),
         {:ok, result} <- build_lineage_result(lineage_tree, provenance_data, agent, params.request_id) do
      {:ok, result, %{agent: agent}}
    end
  end

  # Private functions

  defp build_lineage_tree(agent, request_id) do
    lineage_tree = ProvenanceRelationship.build_lineage_tree(
      agent.state.provenance_graph,
      request_id
    )
    
    {:ok, lineage_tree}
  end

  defp gather_provenance_data(agent, lineage_tree) do
    # Extract all request IDs from the lineage tree
    all_request_ids = extract_all_request_ids(lineage_tree)
    
    # Find provenance for all requests in lineage
    provenances = all_request_ids
    |> Enum.map(fn id ->
      find_provenance_by_request(agent.state.provenance_buffer, id)
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn prov -> {prov.request_id, prov} end)
    
    {:ok, provenances}
  end

  defp build_lineage_result(lineage_tree, provenances, agent, request_id) do
    root_requests = ProvenanceRelationship.find_roots(agent.state.provenance_graph, request_id)
    descendant_count = count_descendants(lineage_tree)
    
    result = %{
      "lineage_tree" => lineage_tree,
      "provenances" => provenances,
      "root_requests" => root_requests,
      "total_descendants" => descendant_count,
      "metadata" => %{
        "request_id" => request_id,
        "total_requests_in_lineage" => map_size(provenances),
        "root_count" => length(root_requests),
        "retrieved_at" => DateTime.utc_now()
      }
    }
    
    {:ok, result}
  end

  defp find_provenance_by_request(provenance_buffer, request_id) do
    Enum.find(provenance_buffer, fn prov -> 
      prov.request_id == request_id 
    end)
  end

  defp extract_all_request_ids(lineage_tree) do
    extract_request_ids_recursive(lineage_tree, [])
  end

  defp extract_request_ids_recursive(nil, acc), do: acc
  defp extract_request_ids_recursive(%{id: id} = node, acc) do
    acc = [id | acc]
    
    # Extract from ancestors
    acc = case Map.get(node, :ancestors, []) do
      ancestors when is_list(ancestors) ->
        Enum.reduce(ancestors, acc, &extract_request_ids_recursive/2)
      _ -> acc
    end
    
    # Extract from descendants
    case Map.get(node, :descendants, []) do
      descendants when is_list(descendants) ->
        Enum.reduce(descendants, acc, &extract_request_ids_recursive/2)
      _ -> acc
    end
  end
  defp extract_request_ids_recursive(_, acc), do: acc

  defp count_descendants(lineage_tree) do
    count_descendants_recursive(Map.get(lineage_tree, :descendants, []))
  end

  defp count_descendants_recursive([]), do: 0
  defp count_descendants_recursive(descendants) when is_list(descendants) do
    Enum.reduce(descendants, 0, fn desc, acc ->
      acc + 1 + count_descendants_recursive(Map.get(desc, :descendants, []))
    end)
  end
end