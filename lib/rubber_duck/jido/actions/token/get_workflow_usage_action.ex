defmodule RubberDuck.Jido.Actions.Token.GetWorkflowUsageAction do
  @moduledoc """
  Action for retrieving token usage data aggregated by workflow.
  
  This action provides comprehensive usage analytics for a specific
  workflow, including task breakdowns, cost analysis, and usage patterns.
  """
  
  use Jido.Action,
    name: "get_workflow_usage",
    description: "Retrieves token usage data for a specific workflow",
    schema: [
      workflow_id: [type: :string, required: true]
    ]

  alias RubberDuck.Agents.TokenManager.{TokenUsage, TokenProvenance}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, workflow_provenance} <- find_workflow_provenance(agent, params.workflow_id),
         {:ok, workflow_usage} <- find_workflow_usage(agent, workflow_provenance),
         {:ok, analysis} <- analyze_workflow_usage(workflow_usage, workflow_provenance),
         {:ok, result} <- build_workflow_result(params.workflow_id, analysis, workflow_usage) do
      {:ok, result, %{agent: agent}}
    end
  end

  # Private functions

  defp find_workflow_provenance(agent, workflow_id) do
    workflow_provenance = agent.state.provenance_buffer
    |> Enum.filter(&(&1.workflow_id == workflow_id))
    
    {:ok, workflow_provenance}
  end

  defp find_workflow_usage(agent, workflow_provenance) do
    request_ids = Enum.map(workflow_provenance, & &1.request_id)
    
    workflow_usage = agent.state.usage_buffer
    |> Enum.filter(&(&1.request_id in request_ids))
    
    {:ok, workflow_usage}
  end

  defp analyze_workflow_usage(workflow_usage, workflow_provenance) do
    # Calculate totals
    total_tokens = TokenUsage.total_tokens(workflow_usage)
    total_cost = TokenUsage.total_cost(workflow_usage)
    
    # Group by task type
    by_task = workflow_provenance
    |> TokenProvenance.group_by(:task_type)
    |> Enum.map(fn {task_type, provs} ->
      task_request_ids = Enum.map(provs, & &1.request_id)
      task_usage = Enum.filter(workflow_usage, &(&1.request_id in task_request_ids))
      
      {task_type, %{
        count: length(provs),
        tokens: TokenUsage.total_tokens(task_usage),
        cost: TokenUsage.total_cost(task_usage)
      }}
    end)
    |> Map.new()
    
    analysis = %{
      total_tokens: total_tokens,
      total_cost: total_cost,
      by_task: by_task,
      request_count: length(workflow_usage)
    }
    
    {:ok, analysis}
  end

  defp build_workflow_result(workflow_id, analysis, workflow_usage) do
    request_ids = Enum.map(workflow_usage, & &1.request_id)
    
    result = %{
      "workflow_id" => workflow_id,
      "total_requests" => analysis.request_count,
      "total_tokens" => analysis.total_tokens,
      "total_cost" => Decimal.to_string(analysis.total_cost),
      "by_task_type" => analysis.by_task,
      "request_ids" => request_ids,
      "metadata" => %{
        "retrieved_at" => DateTime.utc_now(),
        "task_types_count" => map_size(analysis.by_task)
      }
    }
    
    {:ok, result}
  end
end