defmodule RubberDuck.Jido.Actions.Token.GenerateReportAction do
  @moduledoc """
  Action for generating various types of token usage reports.
  
  This action creates comprehensive reports including usage analysis,
  cost breakdowns, and optimization recommendations based on the 
  agent's historical data.
  """
  
  use Jido.Action,
    name: "generate_report",
    description: "Generates token usage and cost reports",
    schema: [
      type: [type: :string, default: "usage", values: ["usage", "cost", "optimization"]],
      period: [type: :string, default: nil],
      filters: [type: :map, default: %{}]
    ]

  alias RubberDuck.Agents.TokenManager.UsageReport
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, period} <- parse_period(params.period),
         {:ok, report} <- generate_report(agent, params.type, period, params.filters),
         {:ok, _} <- emit_report_signal(agent, report, params.type) do
      {:ok, report, %{agent: agent}}
    end
  end

  # Private functions

  defp generate_report(agent, "usage", period, filters) do
    generate_usage_report(agent, period, filters)
  end

  defp generate_report(agent, "cost", period, filters) do
    generate_cost_report(agent, period, filters)
  end

  defp generate_report(agent, "optimization", period, filters) do
    generate_optimization_report(agent, period, filters)
  end

  defp generate_report(_agent, unknown_type, _period, _filters) do
    {:error, "Unknown report type: #{unknown_type}"}
  end

  defp generate_usage_report(agent, period, _filters) do
    report = UsageReport.new(%{
      period_start: period.start,
      period_end: period.end_date,
      total_tokens: agent.state.metrics.total_tokens,
      total_cost: agent.state.metrics.total_cost,
      provider_breakdown: calculate_provider_breakdown(agent),
      model_breakdown: calculate_model_breakdown(agent),
      user_breakdown: calculate_user_breakdown(agent),
      project_breakdown: calculate_project_breakdown(agent),
      trends: calculate_usage_trends(agent),
      recommendations: generate_report_recommendations(agent)
    })
    
    {:ok, report}
  end

  defp generate_cost_report(agent, period, _filters) do
    report = %{
      period: period,
      total_cost: agent.state.metrics.total_cost,
      cost_by_provider: %{},
      cost_by_project: %{},
      projections: calculate_cost_projections(agent)
    }
    
    {:ok, report}
  end

  defp generate_optimization_report(agent, period, _filters) do
    report = %{
      period: period,
      opportunities: find_optimization_opportunities(agent),
      recommendations: generate_optimization_recommendations(agent, %{}),
      potential_savings: calculate_potential_savings(agent)
    }
    
    {:ok, report}
  end

  defp emit_report_signal(agent, report, report_type) do
    signal_params = %{
      signal_type: "token.report.generated",
      data: %{
        report_id: report.id || "generated_#{System.unique_integer()}",
        report_type: report_type,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp calculate_provider_breakdown(agent) do
    group_by_field(agent.state.usage_buffer, :provider)
  end

  defp calculate_model_breakdown(agent) do
    group_by_field(agent.state.usage_buffer, :model)
  end

  defp calculate_user_breakdown(agent) do
    group_by_field(agent.state.usage_buffer, :user_id)
  end

  defp calculate_project_breakdown(agent) do
    group_by_field(agent.state.usage_buffer, :project_id)
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

  defp calculate_usage_trends(_agent) do
    %{
      hourly_average: 0,
      daily_average: 0,
      growth_rate: 0.0
    }
  end

  defp generate_report_recommendations(_agent) do
    ["Enable budget alerts", "Review high-usage projects", "Optimize model selection"]
  end

  defp calculate_cost_projections(_agent) do
    %{
      next_day: Decimal.new(0),
      next_week: Decimal.new(0),
      next_month: Decimal.new(0)
    }
  end

  defp find_optimization_opportunities(_agent) do
    []
  end

  defp generate_optimization_recommendations(agent, context) do
    recommendations = []
    
    # Check for model optimization opportunities
    recommendations = recommendations ++ check_model_optimization(agent, context)
    
    # Check for caching opportunities
    recommendations = recommendations ++ check_caching_opportunities(agent, context)
    
    # Check for prompt optimization
    recommendations = recommendations ++ check_prompt_optimization(agent, context)
    
    recommendations
  end

  defp check_model_optimization(agent, _context) do
    high_volume_simple_tasks = detect_high_volume_simple_tasks(agent.state.usage_buffer)
    
    if high_volume_simple_tasks > 0.3 do
      [%{
        type: "model_optimization",
        priority: "high",
        description: "Consider using smaller models for simple tasks",
        potential_savings: "30-50%",
        affected_requests: "#{round(high_volume_simple_tasks * 100)}%"
      }]
    else
      []
    end
  end

  defp check_caching_opportunities(_agent, _context) do
    [%{
      type: "caching",
      priority: "medium",
      description: "Enable response caching for repeated queries",
      potential_savings: "20-40%",
      implementation: "Use ResponseProcessorAgent caching"
    }]
  end

  defp check_prompt_optimization(_agent, _context) do
    [%{
      type: "prompt_optimization",
      priority: "medium",
      description: "Optimize prompt templates to reduce token usage",
      potential_savings: "10-20%",
      implementation: "Review and compress prompt templates"
    }]
  end

  defp detect_high_volume_simple_tasks(usage_buffer) do
    simple_threshold = 100 # tokens
    
    simple_count = Enum.count(usage_buffer, fn usage ->
      usage.total_tokens < simple_threshold
    end)
    
    if length(usage_buffer) > 0 do
      simple_count / length(usage_buffer)
    else
      0.0
    end
  end

  defp calculate_potential_savings(_agent) do
    Decimal.new(0)
  end

  defp parse_period(nil), do: {:ok, default_period()}
  defp parse_period(period) when is_binary(period) do
    result = case period do
      "today" -> today_period()
      "yesterday" -> yesterday_period()
      "last_7_days" -> last_n_days_period(7)
      "last_30_days" -> last_n_days_period(30)
      "this_month" -> this_month_period()
      "last_month" -> last_month_period()
      _ -> default_period()
    end
    {:ok, result}
  end

  defp default_period do
    %{
      start: DateTime.add(DateTime.utc_now(), -7, :day),
      end_date: DateTime.utc_now()
    }
  end

  defp today_period do
    now = DateTime.utc_now()
    start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")
    %{start: start, end_date: now}
  end

  defp yesterday_period do
    today = Date.utc_today()
    yesterday = Date.add(today, -1)
    start = DateTime.new!(yesterday, ~T[00:00:00], "Etc/UTC")
    end_date = DateTime.new!(yesterday, ~T[23:59:59], "Etc/UTC")
    %{start: start, end_date: end_date}
  end

  defp last_n_days_period(n) do
    %{
      start: DateTime.add(DateTime.utc_now(), -n, :day),
      end_date: DateTime.utc_now()
    }
  end

  defp this_month_period do
    today = Date.utc_today()
    start = Date.beginning_of_month(today)
    %{
      start: DateTime.new!(start, ~T[00:00:00], "Etc/UTC"),
      end_date: DateTime.utc_now()
    }
  end

  defp last_month_period do
    today = Date.utc_today()
    first_of_month = Date.beginning_of_month(today)
    last_month = Date.add(first_of_month, -1)
    start = Date.beginning_of_month(last_month)
    end_date = Date.end_of_month(last_month)
    %{
      start: DateTime.new!(start, ~T[00:00:00], "Etc/UTC"),
      end_date: DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")
    }
  end
end