defmodule RubberDuck.Agents.TokenManager.UsageReport do
  @moduledoc """
  Usage report generation for token consumption analytics.
  
  Provides comprehensive reporting on token usage patterns, costs,
  trends, and optimization recommendations.
  """

  @type t :: %__MODULE__{
    id: String.t(),
    period_start: DateTime.t(),
    period_end: DateTime.t(),
    total_tokens: non_neg_integer(),
    total_cost: Decimal.t(),
    currency: String.t(),
    provider_breakdown: map(),
    model_breakdown: map(),
    user_breakdown: map(),
    project_breakdown: map(),
    team_breakdown: map(),
    feature_breakdown: map(),
    trends: map(),
    recommendations: [map()],
    anomalies: [map()],
    generated_at: DateTime.t(),
    metadata: map()
  }

  defstruct [
    :id,
    :period_start,
    :period_end,
    :total_tokens,
    :total_cost,
    :currency,
    :provider_breakdown,
    :model_breakdown,
    :user_breakdown,
    :project_breakdown,
    :team_breakdown,
    :feature_breakdown,
    :trends,
    :recommendations,
    :anomalies,
    :generated_at,
    :metadata
  ]

  alias RubberDuck.Agents.TokenManager.TokenUsage

  @doc """
  Creates a new UsageReport.
  
  ## Parameters
  
  - `attrs` - Map containing report attributes
  
  ## Examples
  
      iex> UsageReport.new(%{
      ...>   period_start: start_date,
      ...>   period_end: end_date,
      ...>   total_tokens: 50000,
      ...>   total_cost: Decimal.new(25.50)
      ...> })
      %UsageReport{...}
  """
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: Map.get(attrs, :id, generate_id()),
      period_start: Map.fetch!(attrs, :period_start),
      period_end: Map.fetch!(attrs, :period_end),
      total_tokens: Map.get(attrs, :total_tokens, 0),
      total_cost: Map.get(attrs, :total_cost, Decimal.new(0)),
      currency: Map.get(attrs, :currency, "USD"),
      provider_breakdown: Map.get(attrs, :provider_breakdown, %{}),
      model_breakdown: Map.get(attrs, :model_breakdown, %{}),
      user_breakdown: Map.get(attrs, :user_breakdown, %{}),
      project_breakdown: Map.get(attrs, :project_breakdown, %{}),
      team_breakdown: Map.get(attrs, :team_breakdown, %{}),
      feature_breakdown: Map.get(attrs, :feature_breakdown, %{}),
      trends: Map.get(attrs, :trends, %{}),
      recommendations: Map.get(attrs, :recommendations, []),
      anomalies: Map.get(attrs, :anomalies, []),
      generated_at: Map.get(attrs, :generated_at, DateTime.utc_now()),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @doc """
  Generates a usage report from a list of TokenUsage records.
  """
  def generate_from_usage(usage_list, period_start, period_end) when is_list(usage_list) do
    filtered_usage = TokenUsage.filter_by_date(usage_list, period_start, period_end)
    
    report = new(%{
      period_start: period_start,
      period_end: period_end,
      total_tokens: TokenUsage.total_tokens(filtered_usage),
      total_cost: TokenUsage.total_cost(filtered_usage)
    })
    
    report
    |> add_breakdowns(filtered_usage)
    |> calculate_trends(filtered_usage)
    |> generate_recommendations(filtered_usage)
    |> detect_anomalies(filtered_usage)
  end

  @doc """
  Adds breakdown analytics to the report.
  """
  def add_breakdowns(%__MODULE__{} = report, usage_list) do
    %{report |
      provider_breakdown: calculate_breakdown(usage_list, :provider),
      model_breakdown: calculate_breakdown(usage_list, :model),
      user_breakdown: calculate_breakdown(usage_list, :user_id),
      project_breakdown: calculate_breakdown(usage_list, :project_id),
      team_breakdown: calculate_breakdown(usage_list, :team_id),
      feature_breakdown: calculate_breakdown(usage_list, :feature)
    }
  end

  @doc """
  Calculates usage trends.
  """
  def calculate_trends(%__MODULE__{} = report, usage_list) do
    trends = %{
      hourly_distribution: calculate_hourly_distribution(usage_list),
      daily_average: calculate_daily_average(usage_list, report),
      growth_rate: calculate_growth_rate(usage_list),
      peak_usage_times: find_peak_usage_times(usage_list),
      cost_per_token_trend: calculate_cost_per_token_trend(usage_list)
    }
    
    %{report | trends: trends}
  end

  @doc """
  Generates optimization recommendations based on usage patterns.
  """
  def generate_recommendations(%__MODULE__{} = report, usage_list) do
    recommendations = []
    
    # Model optimization
    recommendations = recommendations ++ model_optimization_recommendations(report)
    
    # Cost optimization
    recommendations = recommendations ++ cost_optimization_recommendations(report)
    
    # Usage pattern optimization
    recommendations = recommendations ++ usage_pattern_recommendations(report, usage_list)
    
    # Efficiency recommendations
    recommendations = recommendations ++ efficiency_recommendations(report, usage_list)
    
    %{report | recommendations: recommendations}
  end

  @doc """
  Detects anomalies in usage patterns.
  """
  def detect_anomalies(%__MODULE__{} = report, usage_list) do
    anomalies = []
    
    # Detect usage spikes
    anomalies = anomalies ++ detect_usage_spikes(usage_list)
    
    # Detect unusual costs
    anomalies = anomalies ++ detect_cost_anomalies(usage_list)
    
    # Detect pattern deviations
    anomalies = anomalies ++ detect_pattern_deviations(usage_list)
    
    %{report | anomalies: anomalies}
  end

  @doc """
  Exports the report to various formats.
  """
  def export(%__MODULE__{} = report, format \\ :json) do
    case format do
      :json -> export_json(report)
      :csv -> export_csv(report)
      :markdown -> export_markdown(report)
      _ -> {:error, :unsupported_format}
    end
  end

  @doc """
  Generates a summary of the report.
  """
  def summary(%__MODULE__{} = report) do
    %{
      period: "#{report.period_start} to #{report.period_end}",
      total_tokens: report.total_tokens,
      total_cost: Decimal.to_string(report.total_cost),
      currency: report.currency,
      top_provider: top_by_tokens(report.provider_breakdown),
      top_model: top_by_tokens(report.model_breakdown),
      top_user: top_by_tokens(report.user_breakdown),
      top_project: top_by_tokens(report.project_breakdown),
      recommendations_count: length(report.recommendations),
      anomalies_count: length(report.anomalies),
      cost_per_thousand_tokens: calculate_cost_per_thousand_tokens(report)
    }
  end

  ## Private Functions

  defp calculate_breakdown(usage_list, field) do
    usage_list
    |> TokenUsage.group_by(field)
    |> Enum.map(fn {key, usages} ->
      {key || "unspecified", %{
        count: length(usages),
        total_tokens: TokenUsage.total_tokens(usages),
        total_cost: TokenUsage.total_cost(usages),
        average_tokens: div(TokenUsage.total_tokens(usages), max(length(usages), 1)),
        percentage: calculate_percentage(TokenUsage.total_tokens(usages), TokenUsage.total_tokens(usage_list))
      }}
    end)
    |> Map.new()
  end

  defp calculate_percentage(part, whole) when whole > 0 do
    Float.round(part / whole * 100, 2)
  end
  defp calculate_percentage(_, _), do: 0.0

  defp calculate_hourly_distribution(usage_list) do
    usage_list
    |> Enum.group_by(fn usage -> usage.timestamp.hour end)
    |> Enum.map(fn {hour, usages} ->
      {hour, length(usages)}
    end)
    |> Map.new()
  end

  defp calculate_daily_average(usage_list, report) do
    days = DateTime.diff(report.period_end, report.period_start, :day) |> max(1)
    
    %{
      tokens: div(report.total_tokens, days),
      cost: Decimal.div(report.total_cost, Decimal.new(days)),
      requests: div(length(usage_list), days)
    }
  end

  defp calculate_growth_rate(_usage_list) do
    # Simplified - in production would calculate actual growth rate
    0.0
  end

  defp find_peak_usage_times(usage_list) do
    usage_list
    |> Enum.group_by(fn usage -> {usage.timestamp.hour, div(usage.timestamp.minute, 15) * 15} end)
    |> Enum.map(fn {{hour, minute}, usages} ->
      {%{hour: hour, minute: minute}, TokenUsage.total_tokens(usages)}
    end)
    |> Enum.sort_by(fn {_time, tokens} -> -tokens end)
    |> Enum.take(5)
    |> Enum.map(fn {time, tokens} -> Map.put(time, :tokens, tokens) end)
  end

  defp calculate_cost_per_token_trend(usage_list) do
    # Group by day and calculate average cost per token
    usage_list
    |> Enum.group_by(fn usage -> DateTime.to_date(usage.timestamp) end)
    |> Enum.map(fn {date, usages} ->
      total_cost = TokenUsage.total_cost(usages)
      total_tokens = TokenUsage.total_tokens(usages)
      
      avg_cost = if total_tokens > 0 do
        Decimal.div(total_cost, Decimal.new(total_tokens))
      else
        Decimal.new(0)
      end
      
      {date, Decimal.to_float(avg_cost)}
    end)
    |> Map.new()
  end

  defp model_optimization_recommendations(report) do
    recommendations = []
    
    # Check for expensive model overuse
    expensive_models = ["gpt-4", "claude-3-opus"]
    
    expensive_usage = report.model_breakdown
    |> Enum.filter(fn {model, _stats} -> model in expensive_models end)
    |> Enum.map(fn {_model, stats} -> stats.percentage end)
    |> Enum.sum()
    
    if expensive_usage > 50 do
      recommendations ++ [%{
        type: "model_optimization",
        priority: "high",
        title: "High expensive model usage",
        description: "#{expensive_usage}% of tokens are from expensive models. Consider using cheaper models for simpler tasks.",
        potential_savings: "30-50%",
        action: "Review tasks and identify opportunities for model downgrading"
      }]
    else
      recommendations
    end
  end

  defp cost_optimization_recommendations(report) do
    cost_per_thousand = calculate_cost_per_thousand_tokens(report)
    
    if Decimal.gt?(cost_per_thousand, Decimal.new("0.05")) do
      [%{
        type: "cost_optimization",
        priority: "medium",
        title: "High cost per token",
        description: "Average cost is #{Decimal.to_string(cost_per_thousand)} per 1000 tokens",
        potential_savings: "20-40%",
        action: "Enable caching and optimize prompts"
      }]
    else
      []
    end
  end

  defp usage_pattern_recommendations(_report, _usage_list) do
    # Check for repeated similar requests
    # In production, would analyze actual request content
    []
  end

  defp efficiency_recommendations(report, _usage_list) do
    recommendations = []
    
    # Check token efficiency by provider
    report.provider_breakdown
    |> Enum.each(fn {provider, stats} ->
      if stats.average_tokens > 2000 do
        recommendations ++ [%{
          type: "efficiency",
          priority: "medium",
          title: "High average tokens for #{provider}",
          description: "Average request uses #{stats.average_tokens} tokens",
          potential_savings: "15-25%",
          action: "Optimize prompts and implement response streaming"
        }]
      end
    end)
    
    recommendations
  end

  defp detect_usage_spikes(_usage_list) do
    # Simplified spike detection
    []
  end

  defp detect_cost_anomalies(usage_list) do
    # Detect unusually expensive requests
    avg_cost = case TokenUsage.total_cost(usage_list) do
      cost when is_struct(cost, Decimal) ->
        if length(usage_list) > 0 do
          Decimal.div(cost, Decimal.new(length(usage_list)))
        else
          Decimal.new(0)
        end
      _ -> Decimal.new(0)
    end
    
    threshold = Decimal.mult(avg_cost, Decimal.new(5)) # 5x average
    
    usage_list
    |> Enum.filter(fn usage -> Decimal.gt?(usage.cost, threshold) end)
    |> Enum.map(fn usage ->
      %{
        type: "cost_anomaly",
        severity: "high",
        description: "Request #{usage.request_id} cost #{Decimal.to_string(usage.cost)} (#{Decimal.to_float(Decimal.div(usage.cost, avg_cost))}x average)",
        timestamp: usage.timestamp,
        details: %{
          provider: usage.provider,
          model: usage.model,
          tokens: usage.total_tokens
        }
      }
    end)
  end

  defp detect_pattern_deviations(_usage_list) do
    # Would detect unusual usage patterns
    []
  end

  defp export_json(report) do
    {:ok, Jason.encode!(report)}
  end

  defp export_csv(report) do
    # Simplified CSV export
    headers = "Period,Total Tokens,Total Cost,Top Provider,Top Model\n"
    data = "#{report.period_start},#{report.total_tokens},#{report.total_cost}," <>
           "#{top_by_tokens(report.provider_breakdown)},#{top_by_tokens(report.model_breakdown)}"
    
    {:ok, headers <> data}
  end

  defp export_markdown(report) do
    summary_data = summary(report)
    
    markdown = """
    # Token Usage Report
    
    **Period**: #{summary_data.period}
    
    ## Summary
    - **Total Tokens**: #{summary_data.total_tokens}
    - **Total Cost**: #{summary_data.total_cost} #{summary_data.currency}
    - **Cost per 1000 tokens**: #{summary_data.cost_per_thousand_tokens}
    
    ## Top Usage
    - **Provider**: #{summary_data.top_provider}
    - **Model**: #{summary_data.top_model}
    - **User**: #{summary_data.top_user}
    - **Project**: #{summary_data.top_project}
    
    ## Insights
    - **Recommendations**: #{summary_data.recommendations_count}
    - **Anomalies**: #{summary_data.anomalies_count}
    """
    
    {:ok, markdown}
  end

  defp top_by_tokens(breakdown) when breakdown == %{}, do: "N/A"
  defp top_by_tokens(breakdown) do
    {name, _stats} = breakdown
    |> Enum.max_by(fn {_key, stats} -> stats.total_tokens end, fn -> {"N/A", %{}} end)
    
    name
  end

  defp calculate_cost_per_thousand_tokens(%{total_tokens: 0}), do: "0.00"
  defp calculate_cost_per_thousand_tokens(report) do
    Decimal.div(
      Decimal.mult(report.total_cost, Decimal.new(1000)),
      Decimal.new(report.total_tokens)
    ) |> Decimal.round(4) |> Decimal.to_string()
  end

  defp generate_id do
    "report_#{System.unique_integer([:positive, :monotonic])}"
  end
end