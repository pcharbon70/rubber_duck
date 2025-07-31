defmodule RubberDuck.Jido.Actions.Token.AnalyzeTaskCostsAction do
  @moduledoc """
  Action for analyzing token usage and costs by task type.
  
  This action provides detailed cost analysis for specific task types,
  including usage patterns, model distribution, intent analysis, and 
  optimization opportunities.
  """
  
  use Jido.Action,
    name: "analyze_task_costs",
    description: "Analyzes token usage and costs for a specific task type",
    schema: [
      task_type: [type: :string, required: true]
    ]

  alias RubberDuck.Agents.TokenManager.{TokenUsage, TokenProvenance}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, task_provenance} <- find_task_provenance(agent, params.task_type),
         {:ok, task_usage} <- find_task_usage(agent, task_provenance),
         {:ok, analysis} <- perform_task_analysis(params.task_type, task_provenance, task_usage) do
      {:ok, analysis, %{agent: agent}}
    end
  end

  # Private functions

  defp find_task_provenance(agent, task_type) do
    task_provenance = agent.state.provenance_buffer
    |> TokenProvenance.filter_by_task_type(task_type)
    
    {:ok, task_provenance}
  end

  defp find_task_usage(agent, task_provenance) do
    request_ids = Enum.map(task_provenance, & &1.request_id)
    
    task_usage = agent.state.usage_buffer
    |> Enum.filter(&(&1.request_id in request_ids))
    
    {:ok, task_usage}
  end

  defp perform_task_analysis(task_type, task_provenance, task_usage) do
    # Basic metrics
    total_tokens = TokenUsage.total_tokens(task_usage)
    total_cost = TokenUsage.total_cost(task_usage)
    request_count = length(task_usage)
    
    # Calculate averages
    avg_tokens = avg_tokens_per_request(task_usage)
    avg_cost = avg_cost_per_request(task_usage)
    
    # Analyze by model
    by_model = analyze_by_model(task_usage)
    
    # Analyze by intent
    by_intent = analyze_by_intent(task_provenance, task_usage)
    
    # Find duplicate patterns
    duplicate_patterns = find_duplicate_patterns(task_provenance)
    
    analysis = %{
      "task_type" => task_type,
      "total_requests" => request_count,
      "total_tokens" => total_tokens,
      "total_cost" => total_cost,
      "avg_tokens_per_request" => avg_tokens,
      "avg_cost_per_request" => avg_cost,
      "by_model" => by_model,
      "by_intent" => by_intent,
      "duplicate_patterns" => duplicate_patterns,
      "metadata" => %{
        "analyzed_at" => DateTime.utc_now(),
        "provenance_records" => length(task_provenance),
        "usage_records" => length(task_usage)
      }
    }
    
    {:ok, analysis}
  end

  defp avg_tokens_per_request([]), do: 0
  defp avg_tokens_per_request(usage_list) do
    total = TokenUsage.total_tokens(usage_list)
    count = length(usage_list)
    div(total, count)
  end

  defp avg_cost_per_request([]), do: Decimal.new(0)
  defp avg_cost_per_request(usage_list) do
    total = TokenUsage.total_cost(usage_list)
    count = length(usage_list)
    Decimal.div(total, Decimal.new(count))
  end

  defp analyze_by_model(usage_list) do
    usage_list
    |> TokenUsage.group_by(:model)
    |> Enum.map(fn {model, usages} ->
      {model, %{
        count: length(usages),
        total_tokens: TokenUsage.total_tokens(usages),
        total_cost: TokenUsage.total_cost(usages),
        avg_tokens: avg_tokens_per_request(usages),
        avg_cost: avg_cost_per_request(usages)
      }}
    end)
    |> Map.new()
  end

  defp analyze_by_intent(provenance_list, usage_list) do
    # Group provenance by intent
    provenance_by_intent = TokenProvenance.group_by(provenance_list, :intent)
    
    # Build usage map for quick lookup
    usage_map = Map.new(usage_list, fn u -> {u.request_id, u} end)
    
    # Analyze each intent group
    Enum.map(provenance_by_intent, fn {intent, provs} ->
      # Get usage for these provenances
      intent_usage = provs
      |> Enum.map(& &1.request_id)
      |> Enum.map(&Map.get(usage_map, &1))
      |> Enum.reject(&is_nil/1)
      
      {intent, %{
        count: length(provs),
        total_tokens: TokenUsage.total_tokens(intent_usage),
        total_cost: TokenUsage.total_cost(intent_usage),
        avg_tokens: avg_tokens_per_request(intent_usage),
        avg_cost: avg_cost_per_request(intent_usage)
      }}
    end)
    |> Map.new()
  end

  defp find_duplicate_patterns(provenance_list) do
    # Group by content hash to find duplicates
    by_input_hash = provenance_list
    |> Enum.reject(&is_nil(&1.input_hash))
    |> Enum.group_by(& &1.input_hash)
    |> Enum.filter(fn {_hash, provs} -> length(provs) > 1 end)
    
    # Create duplicate pattern summary
    Enum.map(by_input_hash, fn {hash, provs} ->
      %{
        input_hash: hash,
        duplicate_count: length(provs),
        request_ids: Enum.map(provs, & &1.request_id),
        agents: Enum.map(provs, & &1.agent_type) |> Enum.uniq(),
        first_seen: Enum.min_by(provs, & &1.timestamp).timestamp,
        last_seen: Enum.max_by(provs, & &1.timestamp).timestamp,
        potential_savings: %{
          description: "#{length(provs) - 1} duplicate requests could be cached",
          impact: "medium"
        }
      }
    end)
  end
end