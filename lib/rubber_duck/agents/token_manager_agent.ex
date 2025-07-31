defmodule RubberDuck.Agents.TokenManagerAgent do
  @moduledoc """
  Token Manager Agent for centralized token usage tracking and budget management.
  
  This agent provides comprehensive token usage monitoring, budget enforcement,
  cost tracking, and optimization recommendations across all LLM providers.
  
  ## Responsibilities
  
  - Real-time token usage tracking
  - Budget creation and enforcement
  - Cost calculation and allocation
  - Usage analytics and reporting
  - Optimization recommendations
  
  ## Persistence Integration
  
  This agent integrates with the persistence layer through signals:
  - Emits "token_usage_flush" signals for TokenPersistenceAgent
  - Emits "budget_check" signals for BudgetEnforcementAgent
  - Emits "analytics_request" signals for TokenAnalyticsAgent
  
  ## State Structure
  
  ```elixir
  %{
    budgets: %{budget_id => Budget.t()},
    active_requests: %{request_id => request_data},
    usage_buffer: [TokenUsage.t()],
    pricing_models: %{provider => pricing_data},
    metrics: %{
      total_tokens: integer,
      total_cost: Decimal.t(),
      requests_tracked: integer,
      budget_violations: integer
    },
    config: %{
      buffer_size: integer,
      flush_interval: integer,
      retention_days: integer,
      alert_channels: [String.t()]
    }
  }
  ```
  """

  use RubberDuck.Agents.BaseAgent,
    name: "token_manager",
    description: "Manages token usage tracking, budgets, and optimization",
    category: "infrastructure"

  alias RubberDuck.Agents.TokenManager.{
    TokenUsage, 
    Budget, 
    UsageReport,
    TokenProvenance,
    ProvenanceRelationship
  }
  require Logger

  @default_config %{
    buffer_size: 100,
    flush_interval: 5_000,
    retention_days: 90,
    alert_channels: ["email", "slack"],
    budget_check_mode: :async,
    optimization_enabled: true
  }

  @pricing_models %{
    "openai" => %{
      "gpt-4" => %{prompt: 0.03, completion: 0.06, unit: 1000},
      "gpt-3.5-turbo" => %{prompt: 0.0015, completion: 0.002, unit: 1000},
      "gpt-4-32k" => %{prompt: 0.06, completion: 0.12, unit: 1000}
    },
    "anthropic" => %{
      "claude-3-opus" => %{prompt: 0.015, completion: 0.075, unit: 1000},
      "claude-3-sonnet" => %{prompt: 0.003, completion: 0.015, unit: 1000},
      "claude-3-haiku" => %{prompt: 0.00025, completion: 0.00125, unit: 1000}
    },
    "local" => %{
      "llama-2-70b" => %{prompt: 0.0, completion: 0.0, unit: 1000},
      "mistral-7b" => %{prompt: 0.0, completion: 0.0, unit: 1000}
    }
  }

  ## Initialization

  @impl true
  def init(_args) do
    state = %{
      budgets: %{},
      active_requests: %{},
      usage_buffer: [],
      provenance_buffer: [],
      provenance_graph: [],  # List of ProvenanceRelationship
      pricing_models: @pricing_models,
      metrics: %{
        total_tokens: 0,
        total_cost: Decimal.new(0),
        requests_tracked: 0,
        budget_violations: 0,
        last_flush: DateTime.utc_now()
      },
      config: @default_config
    }
    
    # Schedule periodic tasks
    schedule_buffer_flush()
    schedule_metrics_update()
    schedule_cleanup()
    
    {:ok, state}
  end

  ## Signal Handlers

  def handle_signal("track_usage", data, agent) do
    %{
      "request_id" => request_id,
      "provider" => provider,
      "model" => model,
      "prompt_tokens" => prompt_tokens,
      "completion_tokens" => completion_tokens,
      "user_id" => user_id,
      "project_id" => project_id,
      "metadata" => metadata,
      "provenance" => provenance_data
    } = data
    
    usage = TokenUsage.new(%{
      request_id: request_id,
      provider: provider,
      model: model,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens,
      user_id: user_id,
      project_id: project_id,
      team_id: Map.get(metadata, "team_id"),
      feature: Map.get(metadata, "feature"),
      metadata: metadata
    })
    
    # Calculate cost
    cost = calculate_token_cost(usage, agent.pricing_models)
    usage = %{usage | cost: cost.amount, currency: cost.currency}
    
    # Create provenance record
    provenance = TokenProvenance.new(Map.merge(provenance_data, %{
      usage_id: usage.id,
      request_id: request_id,
      root_request_id: Map.get(provenance_data, :root_request_id, 
        get_root_request_id(agent, provenance_data[:parent_request_id], request_id)),
      depth: calculate_request_depth(agent, provenance_data[:parent_request_id])
    }))
    
    # Create relationship if this has a parent
    agent = if provenance.parent_request_id do
      relationship = ProvenanceRelationship.new(
        provenance.parent_request_id,
        request_id,
        :triggered_by,
        %{signal_type: provenance.signal_type}
      )
      update_in(agent.provenance_graph, &[relationship | &1])
    else
      agent
    end
    
    # Update state with both usage and provenance
    agent = agent
    |> update_usage_buffer(usage)
    |> update_provenance_buffer(provenance)
    |> update_metrics(usage)
    |> update_all_applicable_budgets(usage)
    
    # Check if buffer needs flushing
    agent = maybe_flush_buffer(agent)
    
    signal = Jido.Signal.new!(%{
      type: "token.usage.tracked",
      source: "agent:#{agent.id}",
      data: %{
        request_id: request_id,
        total_tokens: usage.total_tokens,
        cost: usage.cost,
        currency: usage.currency,
        lineage: %{
          parent: provenance.parent_request_id,
          root: provenance.root_request_id,
          depth: provenance.depth
        },
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    {:ok, %{"tracked" => true, "usage" => usage, "provenance" => provenance}, agent}
  end

  def handle_signal("check_budget", data, agent) do
    %{
      "user_id" => user_id,
      "project_id" => project_id,
      "estimated_tokens" => estimated_tokens,
      "request_id" => request_id
    } = data
    
    # Find applicable budgets
    budgets = find_applicable_budgets(agent.budgets, user_id, project_id)
    
    # Check each budget
    {allowed, violations} = check_budgets(budgets, estimated_tokens, agent)
    
    if allowed do
      # Track active request
      agent = track_active_request(agent, request_id, budgets)
      
      signal = Jido.Signal.new!(%{
        type: "token.budget.approved",
        source: "agent:#{agent.id}",
        data: %{
          request_id: request_id,
          budgets_checked: length(budgets),
          timestamp: DateTime.utc_now()
        }
      })
      emit_signal(agent, signal)
      
      {:ok, %{"allowed" => true}, agent}
    else
      # Record violation
      agent = record_budget_violation(agent, violations)
      
      signal = Jido.Signal.new!(%{
        type: "token.budget.denied",
        source: "agent:#{agent.id}",
        data: %{
          request_id: request_id,
          violations: violations,
          timestamp: DateTime.utc_now()
        }
      })
      emit_signal(agent, signal)
      
      {:ok, %{"allowed" => false, "violations" => violations}, agent}
    end
  end

  def handle_signal("create_budget", data, agent) do
    budget_attrs = %{
      name: data["name"],
      type: String.to_atom(data["type"]),
      entity_id: data["entity_id"],
      period: String.to_atom(data["period"]),
      limit: Decimal.new(data["limit"]),
      currency: data["currency"] || "USD",
      alert_thresholds: data["alert_thresholds"] || [50, 80, 90],
      override_policy: data["override_policy"] || %{},
      active: Map.get(data, "active", true)
    }
    
    budget = Budget.new(budget_attrs)
    agent = put_in(agent.budgets[budget.id], budget)
    
    signal = Jido.Signal.new!(%{
      type: "token.budget.created",
      source: "agent:#{agent.id}",
      data: %{
        budget_id: budget.id,
        name: budget.name,
        budget_type: budget.type,
        limit: budget.limit,
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    {:ok, %{"budget_id" => budget.id, "budget" => budget}, agent}
  end

  def handle_signal("update_budget", data, agent) do
    %{"budget_id" => budget_id, "updates" => updates} = data
    
    case Map.get(agent.budgets, budget_id) do
      nil ->
        {:error, "Budget not found", agent}
        
      budget ->
        updated_budget = Budget.update(budget, updates)
        agent = put_in(agent.budgets[budget_id], updated_budget)
        
        signal = Jido.Signal.new!(%{
          type: "token.budget.updated",
          source: "agent:#{agent.id}",
          data: %{
            budget_id: budget_id,
            updates: updates,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
        
        {:ok, %{"budget" => updated_budget}, agent}
    end
  end

  def handle_signal("get_usage", data, agent) do
    filters = %{
      user_id: data["user_id"],
      project_id: data["project_id"],
      provider: data["provider"],
      date_range: parse_date_range(data["date_range"]),
      limit: Map.get(data, "limit", 100)
    }
    
    # In production, this would query from persistent storage
    # For now, return aggregated metrics from memory
    usage_summary = %{
      total_tokens: agent.metrics.total_tokens,
      total_cost: agent.metrics.total_cost,
      requests: agent.metrics.requests_tracked,
      period: "current_session",
      breakdown: calculate_usage_breakdown(agent.usage_buffer, filters)
    }
    
    {:ok, usage_summary, agent}
  end

  def handle_signal("generate_report", data, agent) do
    report_type = data["type"] || "usage"
    period = parse_period(data["period"])
    filters = Map.get(data, "filters", %{})
    
    report = case report_type do
      "usage" -> generate_usage_report(agent, period, filters)
      "cost" -> generate_cost_report(agent, period, filters)
      "optimization" -> generate_optimization_report(agent, period, filters)
      _ -> {:error, "Unknown report type"}
    end
    
    case report do
      {:ok, report_data} ->
        signal = Jido.Signal.new!(%{
          type: "token.report.generated",
          source: "agent:#{agent.id}",
          data: %{
            report_id: report_data.id,
            report_type: report_type,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
        {:ok, report_data, agent}
        
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  def handle_signal("get_recommendations", data, agent) do
    context = %{
      user_id: data["user_id"],
      project_id: data["project_id"],
      timeframe: Map.get(data, "timeframe", "last_7_days")
    }
    
    recommendations = generate_optimization_recommendations(agent, context)
    
    {:ok, %{"recommendations" => recommendations}, agent}
  end

  def handle_signal("update_pricing", data, agent) do
    %{"provider" => provider, "model" => model, "pricing" => pricing} = data
    
    agent = put_in(
      agent.pricing_models[provider][model],
      %{
        prompt: pricing["prompt"],
        completion: pricing["completion"],
        unit: pricing["unit"] || 1000
      }
    )
    
    signal = Jido.Signal.new!(%{
      type: "token.pricing.updated",
      source: "agent:#{agent.id}",
      data: %{
        provider: provider,
        model: model,
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    {:ok, %{"updated" => true}, agent}
  end

  def handle_signal("configure_manager", data, agent) do
    config_updates = Map.take(data, ["buffer_size", "flush_interval", "retention_days", "alert_channels"])
    agent = update_in(agent.config, &Map.merge(&1, config_updates))
    
    {:ok, %{"config" => agent.config}, agent}
  end

  def handle_signal("get_status", _data, agent) do
    status = %{
      "healthy" => true,
      "budgets_active" => map_size(agent.budgets),
      "active_requests" => map_size(agent.active_requests),
      "buffer_size" => length(agent.usage_buffer),
      "provenance_buffer_size" => length(agent.provenance_buffer),
      "relationships_tracked" => length(agent.provenance_graph),
      "total_tracked" => agent.metrics.requests_tracked,
      "total_tokens" => agent.metrics.total_tokens,
      "total_cost" => Decimal.to_string(agent.metrics.total_cost),
      "last_flush" => agent.metrics.last_flush
    }
    
    {:ok, status, agent}
  end

  def handle_signal("get_provenance", %{"request_id" => request_id}, agent) do
    provenance = find_provenance_by_request(agent.provenance_buffer, request_id)
    
    case provenance do
      nil ->
        {:error, "Provenance not found for request #{request_id}", agent}
        
      prov ->
        relationships = ProvenanceRelationship.find_descendants(
          agent.provenance_graph, 
          request_id
        )
        
        result = %{
          "provenance" => prov,
          "relationships" => relationships,
          "lineage_depth" => prov.depth,
          "is_root" => TokenProvenance.root?(prov)
        }
        
        {:ok, result, agent}
    end
  end

  def handle_signal("get_lineage", %{"request_id" => request_id}, agent) do
    lineage_tree = ProvenanceRelationship.build_lineage_tree(
      agent.provenance_graph,
      request_id
    )
    
    # Get provenance for all requests in lineage
    all_request_ids = extract_all_request_ids(lineage_tree)
    provenances = Enum.map(all_request_ids, fn id ->
      find_provenance_by_request(agent.provenance_buffer, id)
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn prov -> {prov.request_id, prov} end)
    
    result = %{
      "lineage_tree" => lineage_tree,
      "provenances" => provenances,
      "root_requests" => ProvenanceRelationship.find_roots(agent.provenance_graph, request_id),
      "total_descendants" => count_descendants(lineage_tree)
    }
    
    {:ok, result, agent}
  end

  def handle_signal("get_workflow_usage", %{"workflow_id" => workflow_id}, agent) do
    # Find all provenance records for this workflow
    workflow_provenance = agent.provenance_buffer
    |> Enum.filter(&(&1.workflow_id == workflow_id))
    
    # Get corresponding usage records
    request_ids = Enum.map(workflow_provenance, & &1.request_id)
    workflow_usage = agent.usage_buffer
    |> Enum.filter(&(&1.request_id in request_ids))
    
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
    
    result = %{
      "workflow_id" => workflow_id,
      "total_requests" => length(workflow_usage),
      "total_tokens" => total_tokens,
      "total_cost" => Decimal.to_string(total_cost),
      "by_task_type" => by_task,
      "request_ids" => request_ids
    }
    
    {:ok, result, agent}
  end

  def handle_signal("analyze_task_costs", %{"task_type" => task_type}, agent) do
    # Find all provenance for this task type
    task_provenance = agent.provenance_buffer
    |> TokenProvenance.filter_by_task_type(task_type)
    
    # Get usage for these requests
    request_ids = Enum.map(task_provenance, & &1.request_id)
    task_usage = agent.usage_buffer
    |> Enum.filter(&(&1.request_id in request_ids))
    
    # Analyze patterns
    analysis = %{
      "task_type" => task_type,
      "total_requests" => length(task_usage),
      "total_tokens" => TokenUsage.total_tokens(task_usage),
      "total_cost" => TokenUsage.total_cost(task_usage),
      "avg_tokens_per_request" => avg_tokens_per_request(task_usage),
      "avg_cost_per_request" => avg_cost_per_request(task_usage),
      "by_model" => analyze_by_model(task_usage),
      "by_intent" => analyze_by_intent(task_provenance, task_usage),
      "duplicate_patterns" => find_duplicate_patterns(task_provenance)
    }
    
    {:ok, analysis, agent}
  end

  ## Private Functions

  defp calculate_token_cost(usage, pricing_models) do
    case get_in(pricing_models, [usage.provider, usage.model]) do
      nil ->
        Logger.warning("No pricing model found for #{usage.provider}/#{usage.model}")
        %{amount: Decimal.new(0), currency: "USD"}
        
      pricing ->
        prompt_cost = Decimal.mult(
          Decimal.new(usage.prompt_tokens),
          Decimal.div(Decimal.new(pricing.prompt), Decimal.new(pricing.unit))
        )
        
        completion_cost = Decimal.mult(
          Decimal.new(usage.completion_tokens),
          Decimal.div(Decimal.new(pricing.completion), Decimal.new(pricing.unit))
        )
        
        total_cost = Decimal.add(prompt_cost, completion_cost)
        %{amount: total_cost, currency: "USD"}
    end
  end

  defp update_usage_buffer(agent, usage) do
    buffer = [usage | agent.usage_buffer]
    
    # Trim buffer if too large
    buffer = if length(buffer) > agent.config.buffer_size do
      Enum.take(buffer, agent.config.buffer_size)
    else
      buffer
    end
    
    put_in(agent.usage_buffer, buffer)
  end

  defp update_metrics(agent, usage) do
    update_in(agent.metrics, fn metrics ->
      %{metrics |
        total_tokens: metrics.total_tokens + usage.total_tokens,
        total_cost: Decimal.add(metrics.total_cost, usage.cost),
        requests_tracked: metrics.requests_tracked + 1
      }
    end)
  end

  defp maybe_flush_buffer(agent) do
    if length(agent.usage_buffer) >= agent.config.buffer_size do
      flush_usage_buffer(agent)
    else
      agent
    end
  end

  defp flush_usage_buffer(agent) do
    if agent.usage_buffer != [] do
      # Emit signal for persistence agent to handle
      Logger.info("Flushing #{length(agent.usage_buffer)} usage records")
      
      signal = Jido.Signal.new!(%{
        type: "token.usage.flush",
        source: "agent:#{agent.id}",
        data: %{
          usage_records: agent.usage_buffer,
          count: length(agent.usage_buffer),
          timestamp: DateTime.utc_now()
        }
      })
      emit_signal(agent, signal)
      
      %{agent | 
        usage_buffer: [],
        metrics: Map.put(agent.metrics, :last_flush, DateTime.utc_now())
      }
    else
      agent
    end
  end

  defp find_applicable_budgets(budgets, user_id, project_id) do
    budgets
    |> Map.values()
    |> Enum.filter(fn budget ->
      budget.active and budget_applies?(budget, user_id, project_id)
    end)
  end

  defp budget_applies?(budget, user_id, project_id) do
    case budget.type do
      :global -> true
      :user -> budget.entity_id == user_id
      :project -> budget.entity_id == project_id
      _ -> false
    end
  end

  defp check_budgets(budgets, estimated_tokens, agent) do
    violations = Enum.reduce(budgets, [], fn budget, acc ->
      estimated_cost = estimate_cost_for_tokens(estimated_tokens, agent.pricing_models)
      
      if Budget.would_exceed?(budget, estimated_cost) do
        [{budget.id, budget.name, budget.remaining} | acc]
      else
        acc
      end
    end)
    
    {violations == [], violations}
  end

  defp estimate_cost_for_tokens(tokens, pricing_models) do
    # Use average pricing across models for estimation
    # In production, would use the specific model being requested
    avg_price = calculate_average_price(pricing_models)
    Decimal.mult(Decimal.new(tokens), avg_price)
  end

  defp calculate_average_price(pricing_models) do
    all_prices = for {_provider, models} <- pricing_models,
                    {_model, pricing} <- models do
      Decimal.add(
        Decimal.new(pricing.prompt),
        Decimal.new(pricing.completion)
      ) |> Decimal.div(Decimal.new(2))
    end
    
    if all_prices == [] do
      Decimal.new(0)
    else
      sum = Enum.reduce(all_prices, Decimal.new(0), &Decimal.add/2)
      Decimal.div(sum, Decimal.new(length(all_prices)))
    end
  end

  defp track_active_request(agent, request_id, budgets) do
    put_in(agent.active_requests[request_id], %{
      timestamp: DateTime.utc_now(),
      budget_ids: Enum.map(budgets, & &1.id)
    })
  end

  defp record_budget_violation(agent, _violations) do
    update_in(agent.metrics.budget_violations, &(&1 + 1))
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
        case key do
          :user_id -> usage.user_id == value
          :project_id -> usage.project_id == value
          :provider -> usage.provider == value
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

  defp generate_usage_report(agent, period, _filters) do
    report = UsageReport.new(%{
      period_start: period.start,
      period_end: period.end_date,
      total_tokens: agent.metrics.total_tokens,
      total_cost: agent.metrics.total_cost,
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
    # Simplified cost report
    {:ok, %{
      period: period,
      total_cost: agent.metrics.total_cost,
      cost_by_provider: %{},
      cost_by_project: %{},
      projections: calculate_cost_projections(agent)
    }}
  end

  defp generate_optimization_report(agent, period, _filters) do
    {:ok, %{
      period: period,
      opportunities: find_optimization_opportunities(agent),
      recommendations: generate_optimization_recommendations(agent, %{}),
      potential_savings: calculate_potential_savings(agent)
    }}
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
    # Analyze usage patterns to recommend model changes
    high_volume_simple_tasks = detect_high_volume_simple_tasks(agent.usage_buffer)
    
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
    # Simplified detection - in production would analyze actual content
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

  defp calculate_provider_breakdown(agent) do
    group_by_field(agent.usage_buffer, :provider)
  end

  defp calculate_model_breakdown(agent) do
    group_by_field(agent.usage_buffer, :model)
  end

  defp calculate_user_breakdown(agent) do
    group_by_field(agent.usage_buffer, :user_id)
  end

  defp calculate_project_breakdown(agent) do
    group_by_field(agent.usage_buffer, :project_id)
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

  defp calculate_potential_savings(_agent) do
    Decimal.new(0)
  end

  ## Provenance Helper Functions

  defp update_provenance_buffer(agent, provenance) do
    buffer = [provenance | agent.provenance_buffer]
    
    # Trim buffer if too large
    buffer = if length(buffer) > agent.config.buffer_size do
      Enum.take(buffer, agent.config.buffer_size)
    else
      buffer
    end
    
    put_in(agent.provenance_buffer, buffer)
  end

  defp update_all_applicable_budgets(agent, usage) do
    # Find all budgets that apply to this usage
    applicable_budgets = find_all_applicable_budgets(agent.budgets, usage)
    
    # Update each budget with the usage
    updated_budgets = Enum.reduce(applicable_budgets, agent.budgets, fn budget, acc ->
      updated_budget = Budget.add_usage(budget, usage.cost)
      Map.put(acc, budget.id, updated_budget)
    end)
    
    %{agent | budgets: updated_budgets}
  end

  defp find_all_applicable_budgets(budgets, usage) do
    budgets
    |> Map.values()
    |> Enum.filter(fn budget ->
      budget.active and budget_applies_to_usage?(budget, usage)
    end)
  end

  defp budget_applies_to_usage?(budget, usage) do
    case budget.type do
      :global -> true
      :user -> budget.entity_id == usage.user_id
      :project -> budget.entity_id == usage.project_id
      :team -> budget.entity_id == usage.team_id
      _ -> false
    end
  end

  defp get_root_request_id(_agent, nil, request_id), do: request_id
  defp get_root_request_id(agent, parent_request_id, _request_id) do
    # Find parent's provenance to get its root
    case find_provenance_by_request(agent.provenance_buffer, parent_request_id) do
      nil -> parent_request_id  # Parent not found, use parent as root
      parent_prov -> parent_prov.root_request_id
    end
  end

  defp calculate_request_depth(_agent, nil), do: 0
  defp calculate_request_depth(agent, parent_request_id) do
    # Find parent's provenance to get its depth
    case find_provenance_by_request(agent.provenance_buffer, parent_request_id) do
      nil -> 1  # Parent not found, assume depth 1
      parent_prov -> parent_prov.depth + 1
    end
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
        last_seen: Enum.max_by(provs, & &1.timestamp).timestamp
      }
    end)
  end

  defp parse_date_range(nil), do: nil
  defp parse_date_range(range) when is_map(range) do
    %{
      start: parse_datetime(range["start"]),
      end_date: parse_datetime(range["end"])
    }
  end

  defp parse_period(nil), do: default_period()
  defp parse_period(period) when is_binary(period) do
    case period do
      "today" -> today_period()
      "yesterday" -> yesterday_period()
      "last_7_days" -> last_n_days_period(7)
      "last_30_days" -> last_n_days_period(30)
      "this_month" -> this_month_period()
      "last_month" -> last_month_period()
      _ -> default_period()
    end
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
    # Go back to first day of current month, then subtract one day to get last month
    first_of_month = Date.beginning_of_month(today)
    last_month = Date.add(first_of_month, -1)
    start = Date.beginning_of_month(last_month)
    end_date = Date.end_of_month(last_month)
    %{
      start: DateTime.new!(start, ~T[00:00:00], "Etc/UTC"),
      end_date: DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")
    }
  end

  defp parse_datetime(nil), do: DateTime.utc_now()
  defp parse_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  ## Scheduled Tasks

  defp schedule_buffer_flush do
    Process.send_after(self(), :flush_buffer, 5_000)
  end

  defp schedule_metrics_update do
    Process.send_after(self(), :update_metrics, 60_000)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_old_data, 3_600_000) # hourly
  end

  @impl true
  def handle_info(:flush_buffer, agent) do
    agent = flush_usage_buffer(agent)
    schedule_buffer_flush()
    {:noreply, agent}
  end

  @impl true
  def handle_info(:update_metrics, agent) do
    # Update derived metrics
    signal = Jido.Signal.new!(%{
      type: "token.metrics.updated",
      source: "agent:#{agent.id}",
      data: %{
        total_tokens: agent.metrics.total_tokens,
        total_cost: Decimal.to_string(agent.metrics.total_cost),
        requests: agent.metrics.requests_tracked,
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    schedule_metrics_update()
    {:noreply, agent}
  end

  @impl true
  def handle_info(:cleanup_old_data, agent) do
    # Clean up old active requests
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second) # 1 hour old
    
    agent = update_in(agent.active_requests, fn requests ->
      Enum.reject(requests, fn {_id, data} ->
        DateTime.compare(data.timestamp, cutoff) == :lt
      end)
      |> Map.new()
    end)
    
    schedule_cleanup()
    {:noreply, agent}
  end
end