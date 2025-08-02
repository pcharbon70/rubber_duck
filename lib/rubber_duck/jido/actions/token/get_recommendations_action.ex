defmodule RubberDuck.Jido.Actions.Token.GetRecommendationsAction do
  @moduledoc """
  Action for generating optimization recommendations based on token usage patterns.
  
  This action analyzes current usage patterns and provides actionable
  recommendations for optimizing token usage and reducing costs.
  """
  
  use Jido.Action,
    name: "get_recommendations",
    description: "Generates optimization recommendations for token usage",
    schema: [
      user_id: [type: :string, default: nil],
      project_id: [type: :string, default: nil],
      timeframe: [type: :string, default: "last_7_days"]
    ]

  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, analysis_context} <- build_analysis_context(params),
         {:ok, recommendations} <- generate_optimization_recommendations(agent, analysis_context) do
      {:ok, %{"recommendations" => recommendations}, %{agent: agent}}
    end
  end

  # Private functions

  defp build_analysis_context(params) do
    context = %{
      user_id: params.user_id,
      project_id: params.project_id,
      timeframe: params.timeframe
    }
    
    {:ok, context}
  end

  defp generate_optimization_recommendations(agent, context) do
    recommendations = []
    
    # Check for model optimization opportunities
    recommendations = recommendations ++ check_model_optimization(agent, context)
    
    # Check for caching opportunities
    recommendations = recommendations ++ check_caching_opportunities(agent, context)
    
    # Check for prompt optimization
    recommendations = recommendations ++ check_prompt_optimization(agent, context)
    
    # Check for usage patterns
    recommendations = recommendations ++ check_usage_patterns(agent, context)
    
    # Check for budget optimization
    recommendations = recommendations ++ check_budget_optimization(agent, context)
    
    {:ok, recommendations}
  end

  defp check_model_optimization(agent, context) do
    # Filter usage buffer by context if needed
    usage_data = filter_usage_by_context(agent.state.usage_buffer, context)
    
    high_volume_simple_tasks = detect_high_volume_simple_tasks(usage_data)
    
    recommendations = []
    
    # Check for overuse of expensive models for simple tasks
    if high_volume_simple_tasks > 0.3 do
      _ = [%{
        type: "model_optimization",
        priority: "high",
        category: "cost_reduction",
        title: "Switch to smaller models for simple tasks",
        description: "#{round(high_volume_simple_tasks * 100)}% of your requests use expensive models for simple tasks that could be handled by smaller, cheaper models",
        potential_savings: "30-50% cost reduction",
        impact: "high",
        effort: "medium",
        actions: [
          "Review tasks with < 100 tokens",
          "Consider using gpt-3.5-turbo instead of gpt-4 for simple tasks",
          "Implement model selection based on task complexity"
        ]
      } | recommendations]
    end
    
    recommendations
  end

  defp check_caching_opportunities(agent, context) do
    usage_data = filter_usage_by_context(agent.state.usage_buffer, context)
    
    # Analyze for repeated patterns (simplified)
    duplicate_potential = analyze_duplicate_potential(usage_data)
    
    if duplicate_potential > 0.2 do
      [%{
        type: "caching",
        priority: "medium",
        category: "efficiency",
        title: "Enable response caching",
        description: "Approximately #{round(duplicate_potential * 100)}% of requests could benefit from caching",
        potential_savings: "20-40% token reduction",
        impact: "medium",
        effort: "low",
        actions: [
          "Enable ResponseProcessorAgent caching",
          "Implement semantic caching for similar queries",
          "Set appropriate cache TTL based on content type"
        ]
      }]
    else
      []
    end
  end

  defp check_prompt_optimization(agent, context) do
    usage_data = filter_usage_by_context(agent.state.usage_buffer, context)
    
    avg_prompt_tokens = calculate_avg_prompt_tokens(usage_data)
    
    recommendations = []
    
    # Check for overly long prompts
    if avg_prompt_tokens > 1000 do
      _ = [%{
        type: "prompt_optimization",
        priority: "medium",
        category: "efficiency",
        title: "Optimize prompt templates",
        description: "Average prompt length is #{avg_prompt_tokens} tokens, indicating room for optimization",
        potential_savings: "10-20% token reduction",
        impact: "medium",
        effort: "medium",
        actions: [
          "Review and compress prompt templates",
          "Remove redundant instructions",
          "Use more concise language",
          "Implement dynamic prompts based on context"
        ]
      } | recommendations]
    end
    
    recommendations
  end

  defp check_usage_patterns(agent, context) do
    usage_data = filter_usage_by_context(agent.state.usage_buffer, context)
    
    recommendations = []
    
    # Check for peak usage times
    peak_usage = analyze_peak_usage(usage_data)
    if peak_usage[:variation] > 0.5 do
      _ = [%{
        type: "usage_optimization",
        priority: "low",
        category: "efficiency",
        title: "Optimize usage timing",
        description: "Usage varies significantly throughout the day",
        potential_savings: "5-15% cost reduction through timing optimization",
        impact: "low",
        effort: "high",
        actions: [
          "Schedule non-urgent tasks during off-peak hours",
          "Implement usage quotas per time period",
          "Consider batch processing strategies"
        ]
      } | recommendations]
    end
    
    recommendations
  end

  defp check_budget_optimization(agent, context) do
    # Check if user/project has budgets
    applicable_budgets = find_applicable_budgets(agent.state.budgets, context)
    
    if length(applicable_budgets) == 0 do
      [%{
        type: "budget_management",
        priority: "medium",
        category: "governance",
        title: "Set up budget controls",
        description: "No budgets are currently configured for this scope",
        potential_savings: "Prevent overspend through proactive controls",
        impact: "high",
        effort: "low",
        actions: [
          "Create monthly budget limits",
          "Set up alert thresholds at 50%, 80%, and 90%",
          "Configure automatic notifications",
          "Review budget performance regularly"
        ]
      }]
    else
      # Check for budget utilization patterns
      over_budget_count = Enum.count(applicable_budgets, &budget_over_threshold(&1, 0.8))
      
      if over_budget_count > 0 do
        [%{
          type: "budget_management",
          priority: "high",
          category: "governance",
          title: "Review budget allocations",
          description: "#{over_budget_count} budgets are near or over their limits",
          potential_savings: "Better resource allocation",
          impact: "high",
          effort: "low",
          actions: [
            "Review current budget limits",
            "Analyze spending patterns",
            "Consider increasing limits or optimizing usage",
            "Implement stricter controls for high-usage periods"
          ]
        }]
      else
        []
      end
    end
  end

  # Helper functions

  defp filter_usage_by_context(usage_buffer, context) do
    usage_buffer
    |> Enum.filter(fn usage ->
      matches_context_filter?(usage, context)
    end)
  end

  defp matches_context_filter?(usage, context) do
    user_match = context.user_id == nil or usage.user_id == context.user_id
    project_match = context.project_id == nil or usage.project_id == context.project_id
    
    user_match and project_match
  end

  defp detect_high_volume_simple_tasks(usage_data) do
    simple_threshold = 100 # tokens
    
    simple_count = Enum.count(usage_data, fn usage ->
      usage.total_tokens < simple_threshold
    end)
    
    if length(usage_data) > 0 do
      simple_count / length(usage_data)
    else
      0.0
    end
  end

  defp analyze_duplicate_potential(usage_data) do
    # Simplified duplicate analysis - in reality would analyze actual content
    if length(usage_data) > 10 do
      0.25 # Assume 25% potential for caching
    else
      0.1
    end
  end

  defp calculate_avg_prompt_tokens(usage_data) do
    if length(usage_data) > 0 do
      total_prompt_tokens = Enum.sum(Enum.map(usage_data, & &1.prompt_tokens))
      div(total_prompt_tokens, length(usage_data))
    else
      0
    end
  end

  defp analyze_peak_usage(usage_data) do
    # Simplified peak usage analysis
    if length(usage_data) > 5 do
      %{variation: 0.6} # Assume high variation
    else
      %{variation: 0.2} # Low variation
    end
  end

  defp find_applicable_budgets(budgets, context) do
    budgets
    |> Map.values()
    |> Enum.filter(fn budget ->
      budget.active and budget_applies_to_context?(budget, context)
    end)
  end

  defp budget_applies_to_context?(budget, context) do
    case budget.type do
      :global -> true
      :user -> budget.entity_id == context.user_id
      :project -> budget.entity_id == context.project_id
      _ -> false
    end
  end

  defp budget_over_threshold(budget, threshold) do
    usage_percentage = if Decimal.positive?(budget.limit) do
      Decimal.div(budget.used, budget.limit)
      |> Decimal.to_float()
    else
      0.0
    end
    
    usage_percentage > threshold
  end
end