defmodule RubberDuck.Jido.Actions.Token.GetUsageAction do
  @moduledoc """
  Action for retrieving token usage data and statistics.
  
  This action processes usage queries with filtering and provides
  aggregated statistics from the agent's usage buffer and metrics.
  """
  
  use Jido.Action,
    name: "get_usage",
    description: "Retrieves token usage data with filtering",
    schema: [
      user_id: [type: :string, default: nil],
      project_id: [type: :string, default: nil],
      provider: [type: :string, default: nil],
      date_range: [type: :map, default: nil],
      limit: [type: :integer, default: 100]
    ]

  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, filters} <- build_filters(params),
         {:ok, usage_summary} <- generate_usage_summary(agent, filters) do
      {:ok, usage_summary, %{agent: agent}}
    end
  end

  # Private functions

  defp build_filters(params) do
    filters = %{
      user_id: params.user_id,
      project_id: params.project_id,
      provider: params.provider,
      date_range: parse_date_range(params.date_range),
      limit: params.limit
    }
    
    {:ok, filters}
  end

  defp generate_usage_summary(agent, filters) do
    # In production, this would query from persistent storage
    # For now, return aggregated metrics from memory
    usage_summary = %{
      total_tokens: agent.state.metrics.total_tokens,
      total_cost: agent.state.metrics.total_cost,
      requests: agent.state.metrics.requests_tracked,
      period: "current_session",
      breakdown: calculate_usage_breakdown(agent.state.usage_buffer, filters)
    }
    
    {:ok, usage_summary}
  end

  defp calculate_usage_breakdown(usage_buffer, filters) do
    filtered = apply_usage_filters(usage_buffer, filters)
    
    %{
      by_provider: group_by_field(filtered, :provider),
      by_model: group_by_field(filtered, :model),
      by_user: group_by_field(filtered, :user_id),
      by_project: group_by_field(filtered, :project_id)
    }
  end

  defp apply_usage_filters(usage_buffer, filters) do
    usage_buffer
    |> Enum.filter(fn usage ->
      Enum.all?(filters, fn {key, value} ->
        case {key, value} do
          {:user_id, nil} -> true
          {:user_id, val} -> usage.user_id == val
          {:project_id, nil} -> true
          {:project_id, val} -> usage.project_id == val
          {:provider, nil} -> true
          {:provider, val} -> usage.provider == val
          _ -> true
        end
      end)
    end)
  end

  defp group_by_field(usage_list, field) do
    usage_list
    |> Enum.group_by(&Map.get(&1, field))
    |> Enum.map(fn {key, usages} ->
      {key, %{
        count: length(usages),
        total_tokens: Enum.sum(Enum.map(usages, & &1.total_tokens)),
        total_cost: Enum.reduce(usages, Decimal.new(0), fn u, acc -> 
          Decimal.add(acc, u.cost)
        end)
      }}
    end)
    |> Map.new()
  end

  defp parse_date_range(nil), do: nil
  defp parse_date_range(range) when is_map(range) do
    %{
      start: parse_datetime(range["start"]),
      end_date: parse_datetime(range["end"])
    }
  end

  defp parse_datetime(nil), do: DateTime.utc_now()
  defp parse_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
end