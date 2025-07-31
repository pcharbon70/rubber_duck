defmodule RubberDuck.Agents.TokenManager.CostCalculator do
  @moduledoc """
  Cost calculation utilities for token usage.
  
  Handles provider-specific pricing models, currency conversion,
  and cost optimization calculations.
  """

  @type pricing_model :: %{
    prompt: float(),
    completion: float(),
    unit: integer()
  }

  @doc """
  Calculates the cost for a given token usage.
  
  ## Parameters
  
  - `prompt_tokens` - Number of prompt tokens
  - `completion_tokens` - Number of completion tokens
  - `pricing` - Pricing model with prompt/completion rates
  - `currency` - Target currency (default: "USD")
  
  ## Examples
  
      iex> CostCalculator.calculate(100, 50, %{prompt: 0.03, completion: 0.06, unit: 1000})
      {:ok, Decimal.new("0.006")}
  """
  def calculate(prompt_tokens, completion_tokens, pricing, currency \\ "USD") do
    prompt_cost = calculate_token_cost(prompt_tokens, pricing.prompt, pricing.unit)
    completion_cost = calculate_token_cost(completion_tokens, pricing.completion, pricing.unit)
    
    total_cost = Decimal.add(prompt_cost, completion_cost)
    
    # In production, would handle currency conversion
    converted_cost = if currency != "USD" do
      convert_currency(total_cost, "USD", currency)
    else
      total_cost
    end
    
    {:ok, converted_cost}
  end

  @doc """
  Estimates cost for a message based on character count.
  
  Uses rough approximation of 4 characters per token.
  """
  def estimate_from_text(text, pricing, role \\ :completion) when is_binary(text) do
    estimated_tokens = estimate_tokens(text)
    
    rate = case role do
      :prompt -> pricing.prompt
      :completion -> pricing.completion
    end
    
    cost = calculate_token_cost(estimated_tokens, rate, pricing.unit)
    {:ok, cost, estimated_tokens}
  end

  @doc """
  Calculates cost savings between two models.
  """
  def calculate_savings(tokens, expensive_pricing, cheaper_pricing) do
    {:ok, expensive_cost} = calculate(tokens, 0, expensive_pricing)
    {:ok, cheaper_cost} = calculate(tokens, 0, cheaper_pricing)
    
    savings = Decimal.sub(expensive_cost, cheaper_cost)
    savings_percentage = if Decimal.gt?(expensive_cost, 0) do
      Decimal.mult(
        Decimal.div(savings, expensive_cost),
        Decimal.new(100)
      ) |> Decimal.round(2)
    else
      Decimal.new(0)
    end
    
    %{
      amount: savings,
      percentage: savings_percentage,
      expensive_cost: expensive_cost,
      cheaper_cost: cheaper_cost
    }
  end

  @doc """
  Compares costs across multiple providers/models.
  """
  def compare_costs(tokens, pricing_models) when is_map(pricing_models) do
    comparisons = pricing_models
    |> Enum.map(fn {name, pricing} ->
      {:ok, cost} = calculate(tokens, 0, pricing)
      {name, cost}
    end)
    |> Enum.sort_by(fn {_name, cost} -> cost end)
    
    cheapest = List.first(comparisons)
    most_expensive = List.last(comparisons)
    
    %{
      comparisons: comparisons,
      cheapest: cheapest,
      most_expensive: most_expensive,
      potential_savings: calculate_max_savings(cheapest, most_expensive)
    }
  end

  @doc """
  Projects future costs based on usage trends.
  """
  def project_costs(daily_tokens, pricing, days \\ 30) do
    daily_cost = calculate_token_cost(daily_tokens, 
      (pricing.prompt + pricing.completion) / 2, pricing.unit)
    
    %{
      daily: daily_cost,
      weekly: Decimal.mult(daily_cost, Decimal.new(7)),
      monthly: Decimal.mult(daily_cost, Decimal.new(days)),
      yearly: Decimal.mult(daily_cost, Decimal.new(365))
    }
  end

  @doc """
  Calculates ROI for optimization strategies.
  """
  def calculate_optimization_roi(current_cost, optimization_options) do
    optimization_options
    |> Enum.map(fn opt ->
      savings = Decimal.mult(current_cost, 
        Decimal.div(Decimal.new(opt.savings_percentage), Decimal.new(100)))
      
      roi = if opt.implementation_cost > 0 do
        Decimal.div(savings, Decimal.new(opt.implementation_cost))
      else
        Decimal.new("999") # Very high ROI if no implementation cost
      end
      
      payback_days = if Decimal.gt?(savings, 0) do
        Decimal.div(Decimal.new(opt.implementation_cost), 
          Decimal.div(savings, Decimal.new(30))) |> Decimal.round(0)
      else
        Decimal.new("999")
      end
      
      Map.merge(opt, %{
        monthly_savings: savings,
        roi: roi,
        payback_days: payback_days
      })
    end)
    |> Enum.sort_by(& &1.roi, :desc)
  end

  @doc """
  Estimates tokens from text length.
  """
  def estimate_tokens(text) when is_binary(text) do
    # Rough approximation: ~4 characters per token for English
    # More sophisticated tokenization would use actual tokenizer
    words = String.split(text, ~r/\s+/)
    word_count = length(words)
    
    # Average English word is ~5 characters + space = 6 characters
    # Average token is ~4 characters
    # So roughly 1.5 tokens per word
    round(word_count * 1.5)
  end

  @doc """
  Provides cost optimization recommendations.
  """
  def optimization_recommendations(usage_summary, pricing_models) do
    recommendations = []
    
    # Model switching recommendations
    if usage_summary.simple_task_percentage > 50 do
      current_model = usage_summary.primary_model
      cheaper_alternatives = find_cheaper_alternatives(current_model, pricing_models)
      
      recommendations ++ Enum.map(cheaper_alternatives, fn {model, pricing} ->
        savings = calculate_savings(
          usage_summary.average_tokens,
          pricing_models[current_model],
          pricing
        )
        
        %{
          type: "model_switch",
          description: "Switch from #{current_model} to #{model} for simple tasks",
          savings_percentage: Decimal.to_float(savings.percentage),
          monthly_savings: Decimal.mult(savings.amount, Decimal.new(usage_summary.monthly_requests))
        }
      end)
    end
    
    # Caching recommendations
    if usage_summary.duplicate_percentage > 20 do
      cache_savings = Decimal.mult(
        usage_summary.average_cost,
        Decimal.new(usage_summary.duplicate_percentage / 100)
      )
      
      recommendations ++ [%{
        type: "caching",
        description: "Implement response caching for duplicate requests",
        savings_percentage: usage_summary.duplicate_percentage,
        monthly_savings: Decimal.mult(cache_savings, Decimal.new(usage_summary.monthly_requests))
      }]
    end
    
    # Prompt optimization
    if usage_summary.average_prompt_tokens > 500 do
      potential_reduction = 0.2 # 20% reduction possible
      prompt_savings = calculate_prompt_optimization_savings(
        usage_summary,
        pricing_models[usage_summary.primary_model],
        potential_reduction
      )
      
      recommendations ++ [%{
        type: "prompt_optimization",
        description: "Optimize prompts to reduce token usage",
        savings_percentage: potential_reduction * 100,
        monthly_savings: prompt_savings
      }]
    end
    
    recommendations
  end

  ## Private Functions

  defp calculate_token_cost(tokens, rate, unit) do
    Decimal.mult(
      Decimal.new(tokens),
      Decimal.div(Decimal.new(rate), Decimal.new(unit))
    )
  end

  defp convert_currency(amount, from_currency, to_currency) do
    # Simplified - in production would use actual exchange rates
    exchange_rates = %{
      "USD" => %{"EUR" => 0.85, "GBP" => 0.73, "JPY" => 110.0},
      "EUR" => %{"USD" => 1.18, "GBP" => 0.86, "JPY" => 129.0},
      "GBP" => %{"USD" => 1.37, "EUR" => 1.16, "JPY" => 150.0}
    }
    
    rate = get_in(exchange_rates, [from_currency, to_currency]) || 1.0
    Decimal.mult(amount, Decimal.new(rate))
  end

  defp calculate_max_savings({_cheap_name, cheap_cost}, {_exp_name, exp_cost}) do
    if Decimal.gt?(exp_cost, cheap_cost) do
      savings = Decimal.sub(exp_cost, cheap_cost)
      percentage = Decimal.mult(
        Decimal.div(savings, exp_cost),
        Decimal.new(100)
      ) |> Decimal.round(2)
      
      %{
        amount: savings,
        percentage: percentage
      }
    else
      %{amount: Decimal.new(0), percentage: Decimal.new(0)}
    end
  end

  defp find_cheaper_alternatives(current_model, pricing_models) do
    current_price = average_price(pricing_models[current_model])
    
    pricing_models
    |> Enum.filter(fn {model, pricing} ->
      model != current_model and average_price(pricing) < current_price
    end)
    |> Enum.sort_by(fn {_model, pricing} -> average_price(pricing) end)
    |> Enum.take(3)
  end

  defp average_price(pricing) do
    (pricing.prompt + pricing.completion) / 2
  end

  defp calculate_prompt_optimization_savings(usage_summary, pricing, reduction_factor) do
    reduced_tokens = usage_summary.average_prompt_tokens * reduction_factor
    
    cost_per_request = calculate_token_cost(
      reduced_tokens,
      pricing.prompt,
      pricing.unit
    )
    
    Decimal.mult(cost_per_request, Decimal.new(usage_summary.monthly_requests))
  end
end