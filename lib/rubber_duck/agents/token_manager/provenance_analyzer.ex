defmodule RubberDuck.Agents.TokenManager.ProvenanceAnalyzer do
  @moduledoc """
  Advanced analytics and insights from token usage provenance data.
  
  Provides capabilities for:
  - Pattern detection (duplicate requests, inefficient chains)
  - Cost attribution analysis
  - Workflow optimization recommendations
  - Agent performance analysis
  - Lineage visualization
  """

  alias RubberDuck.Agents.TokenManager.{
    TokenProvenance,
    ProvenanceRelationship,
    TokenUsage
  }

  @doc """
  Analyzes provenance patterns to detect inefficiencies.
  
  Returns a list of detected patterns with recommendations.
  """
  def detect_inefficiency_patterns(provenance_list, relationships, usage_map) do
    patterns = []
    
    # Detect duplicate requests
    patterns = patterns ++ detect_duplicate_requests(provenance_list, usage_map)
    
    # Detect retry storms
    patterns = patterns ++ detect_retry_storms(provenance_list, relationships)
    
    # Detect deep request chains
    patterns = patterns ++ detect_deep_chains(provenance_list, relationships)
    
    # Detect circular dependencies
    patterns = patterns ++ detect_circular_patterns(relationships)
    
    # Detect expensive task patterns
    patterns = patterns ++ detect_expensive_patterns(provenance_list, usage_map)
    
    patterns
  end

  @doc """
  Performs complete cost attribution analysis.
  
  Breaks down costs by various dimensions and identifies cost drivers.
  """
  def analyze_cost_attribution(provenance_list, usage_map) do
    %{
      by_workflow: attribute_costs_by_workflow(provenance_list, usage_map),
      by_agent_type: attribute_costs_by_agent_type(provenance_list, usage_map),
      by_task_type: attribute_costs_by_task_type(provenance_list, usage_map),
      by_intent: attribute_costs_by_intent(provenance_list, usage_map),
      by_depth: attribute_costs_by_depth(provenance_list, usage_map),
      top_cost_drivers: identify_top_cost_drivers(provenance_list, usage_map),
      cost_trends: analyze_cost_trends(provenance_list, usage_map)
    }
  end

  @doc """
  Generates optimization recommendations based on provenance analysis.
  """
  def generate_optimization_recommendations(provenance_list, relationships, usage_map) do
    recommendations = []
    
    # Check for cacheable patterns
    recommendations = recommendations ++ recommend_caching(provenance_list, usage_map)
    
    # Check for model optimization
    recommendations = recommendations ++ recommend_model_changes(provenance_list, usage_map)
    
    # Check for workflow optimization
    recommendations = recommendations ++ recommend_workflow_changes(provenance_list, relationships)
    
    # Check for prompt optimization
    recommendations = recommendations ++ recommend_prompt_optimization(provenance_list, usage_map)
    
    # Sort by potential impact
    Enum.sort_by(recommendations, & &1.potential_savings, :desc)
  end

  @doc """
  Analyzes agent performance metrics from provenance data.
  """
  def analyze_agent_performance(provenance_list, usage_map) do
    provenance_list
    |> TokenProvenance.group_by(:agent_type)
    |> Enum.map(fn {agent_type, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      
      {agent_type, %{
        request_count: length(provs),
        total_tokens: TokenUsage.total_tokens(usage_list),
        total_cost: TokenUsage.total_cost(usage_list),
        avg_tokens_per_request: avg_tokens(usage_list),
        avg_cost_per_request: avg_cost(usage_list),
        task_distribution: task_distribution(provs),
        error_rate: calculate_error_rate(provs),
        efficiency_score: calculate_efficiency_score(provs, usage_list)
      }}
    end)
    |> Map.new()
  end

  @doc """
  Builds a comprehensive workflow analysis.
  """
  def analyze_workflows(provenance_list, relationships, usage_map) do
    provenance_list
    |> TokenProvenance.group_by(:workflow_id)
    |> Enum.reject(fn {workflow_id, _} -> is_nil(workflow_id) end)
    |> Enum.map(fn {workflow_id, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      
      {workflow_id, %{
        total_requests: length(provs),
        total_tokens: TokenUsage.total_tokens(usage_list),
        total_cost: TokenUsage.total_cost(usage_list),
        duration: calculate_workflow_duration(provs),
        depth_stats: calculate_depth_statistics(provs),
        agent_distribution: agent_distribution(provs),
        task_flow: build_task_flow(provs, relationships),
        bottlenecks: identify_bottlenecks(provs, relationships, usage_map),
        optimization_potential: calculate_optimization_potential(provs, usage_map)
      }}
    end)
    |> Map.new()
  end

  @doc """
  Creates a visualization-ready lineage graph.
  """
  def build_lineage_graph(request_id, provenance_list, relationships, usage_map) do
    # Build the basic lineage tree
    lineage_tree = ProvenanceRelationship.build_lineage_tree(relationships, request_id)
    
    # Enrich with provenance and usage data
    enrich_lineage_node(lineage_tree, provenance_list, usage_map)
  end

  ## Private Functions - Pattern Detection

  defp detect_duplicate_requests(provenance_list, usage_map) do
    provenance_list
    |> Enum.reject(&is_nil(&1.input_hash))
    |> Enum.group_by(& &1.input_hash)
    |> Enum.filter(fn {_hash, provs} -> length(provs) > 1 end)
    |> Enum.map(fn {hash, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      total_cost = TokenUsage.total_cost(usage_list)
      
      %{
        type: :duplicate_requests,
        severity: :high,
        description: "Found #{length(provs)} duplicate requests with same input",
        affected_requests: Enum.map(provs, & &1.request_id),
        wasted_cost: Decimal.mult(total_cost, Decimal.div(Decimal.new(length(provs) - 1), Decimal.new(length(provs)))),
        recommendation: "Implement request caching for this pattern",
        pattern_details: %{
          input_hash: hash,
          agents: Enum.map(provs, & &1.agent_type) |> Enum.uniq(),
          task_types: Enum.map(provs, & &1.task_type) |> Enum.uniq()
        }
      }
    end)
  end

  defp detect_retry_storms(provenance_list, relationships) do
    retry_relationships = ProvenanceRelationship.filter_by_type(relationships, :retry_of)
    
    retry_chains = retry_relationships
    |> Enum.group_by(& &1.source_request_id)
    |> Enum.map(fn {original, _retries} ->
      {original, find_all_retries(original, retry_relationships)}
    end)
    |> Enum.filter(fn {_original, retries} -> length(retries) > 2 end)
    
    Enum.map(retry_chains, fn {original, retries} ->
      %{
        type: :retry_storm,
        severity: :high,
        description: "Request #{original} has #{length(retries)} retries",
        affected_requests: [original | retries],
        recommendation: "Investigate root cause of failures and implement circuit breaker",
        pattern_details: %{
          original_request: original,
          retry_count: length(retries),
          retry_pattern: analyze_retry_pattern(original, retries, provenance_list)
        }
      }
    end)
  end

  defp detect_deep_chains(provenance_list, _relationships) do
    # Find requests with depth > threshold
    deep_requests = provenance_list
    |> Enum.filter(&(&1.depth > 5))
    |> Enum.group_by(& &1.root_request_id)
    
    Enum.map(deep_requests, fn {root_id, deep_provs} ->
      max_depth = Enum.max_by(deep_provs, & &1.depth).depth
      
      %{
        type: :deep_request_chain,
        severity: :medium,
        description: "Request chain from #{root_id} reaches depth #{max_depth}",
        affected_requests: Enum.map(deep_provs, & &1.request_id),
        recommendation: "Consider flattening request chain or implementing batch processing",
        pattern_details: %{
          root_request: root_id,
          max_depth: max_depth,
          depth_distribution: depth_distribution(deep_provs)
        }
      }
    end)
  end

  defp detect_circular_patterns(relationships) do
    # Find potential cycles in the relationship graph
    all_nodes = extract_all_nodes(relationships)
    
    cycles = Enum.flat_map(all_nodes, fn node ->
      if ProvenanceRelationship.would_create_cycle?(relationships, node, node) do
        [{node, find_cycle_path(relationships, node)}]
      else
        []
      end
    end)
    
    Enum.map(cycles, fn {node, path} ->
      %{
        type: :circular_dependency,
        severity: :critical,
        description: "Circular dependency detected starting from #{node}",
        affected_requests: path,
        recommendation: "Break circular dependency to prevent infinite loops",
        pattern_details: %{
          cycle_start: node,
          cycle_path: path
        }
      }
    end)
  end

  defp detect_expensive_patterns(provenance_list, usage_map) do
    # Group by task type and find expensive patterns
    task_costs = provenance_list
    |> TokenProvenance.group_by(:task_type)
    |> Enum.map(fn {task_type, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      avg_cost = avg_cost(usage_list)
      {task_type, avg_cost, provs}
    end)
    |> Enum.filter(fn {_task, avg_cost, _provs} -> 
      Decimal.gt?(avg_cost, Decimal.new("1.0"))  # $1 threshold
    end)
    
    Enum.map(task_costs, fn {task_type, avg_cost, provs} ->
      %{
        type: :expensive_task_pattern,
        severity: :medium,
        description: "Task type '#{task_type}' has high average cost: $#{Decimal.to_string(avg_cost)}",
        affected_requests: Enum.map(provs, & &1.request_id),
        recommendation: "Review if cheaper models can handle this task type",
        pattern_details: %{
          task_type: task_type,
          avg_cost: avg_cost,
          request_count: length(provs),
          models_used: Enum.map(provs, & &1.metadata["model"]) |> Enum.uniq()
        }
      }
    end)
  end

  ## Private Functions - Cost Attribution

  defp attribute_costs_by_workflow(provenance_list, usage_map) do
    provenance_list
    |> TokenProvenance.group_by(:workflow_id)
    |> Enum.reject(fn {workflow_id, _} -> is_nil(workflow_id) end)
    |> Enum.map(fn {workflow_id, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      
      {workflow_id, %{
        total_cost: TokenUsage.total_cost(usage_list),
        request_count: length(provs),
        avg_cost_per_request: avg_cost(usage_list)
      }}
    end)
    |> Map.new()
  end

  defp attribute_costs_by_agent_type(provenance_list, usage_map) do
    provenance_list
    |> TokenProvenance.group_by(:agent_type)
    |> Enum.map(fn {agent_type, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      
      {agent_type, %{
        total_cost: TokenUsage.total_cost(usage_list),
        total_tokens: TokenUsage.total_tokens(usage_list),
        request_count: length(provs)
      }}
    end)
    |> Map.new()
  end

  defp attribute_costs_by_task_type(provenance_list, usage_map) do
    provenance_list
    |> TokenProvenance.group_by(:task_type)
    |> Enum.map(fn {task_type, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      
      {task_type, %{
        total_cost: TokenUsage.total_cost(usage_list),
        total_tokens: TokenUsage.total_tokens(usage_list),
        request_count: length(provs),
        avg_cost: avg_cost(usage_list)
      }}
    end)
    |> Map.new()
  end

  defp attribute_costs_by_intent(provenance_list, usage_map) do
    provenance_list
    |> TokenProvenance.group_by(:intent)
    |> Enum.map(fn {intent, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      
      {intent, %{
        total_cost: TokenUsage.total_cost(usage_list),
        request_count: length(provs),
        avg_cost: avg_cost(usage_list)
      }}
    end)
    |> Map.new()
  end

  defp attribute_costs_by_depth(provenance_list, usage_map) do
    provenance_list
    |> Enum.group_by(& &1.depth)
    |> Enum.map(fn {depth, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      
      {depth, %{
        total_cost: TokenUsage.total_cost(usage_list),
        request_count: length(provs),
        avg_cost: avg_cost(usage_list)
      }}
    end)
    |> Map.new()
  end

  defp identify_top_cost_drivers(provenance_list, usage_map) do
    # Map each provenance to its cost
    cost_entries = provenance_list
    |> Enum.map(fn prov ->
      usage = Map.get(usage_map, prov.request_id)
      cost = if usage, do: usage.cost, else: Decimal.new(0)
      {prov, cost}
    end)
    |> Enum.sort_by(fn {_prov, cost} -> cost end, :desc)
    |> Enum.take(10)
    
    Enum.map(cost_entries, fn {prov, cost} ->
      %{
        request_id: prov.request_id,
        cost: cost,
        agent_type: prov.agent_type,
        task_type: prov.task_type,
        intent: prov.intent,
        workflow_id: prov.workflow_id,
        depth: prov.depth
      }
    end)
  end

  defp analyze_cost_trends(provenance_list, usage_map) do
    # Group by hour and calculate costs
    hourly_costs = provenance_list
    |> Enum.map(fn prov ->
      usage = Map.get(usage_map, prov.request_id)
      cost = if usage, do: usage.cost, else: Decimal.new(0)
      hour = DateTime.truncate(prov.timestamp, :hour)
      {hour, cost}
    end)
    |> Enum.group_by(fn {hour, _cost} -> hour end, fn {_hour, cost} -> cost end)
    |> Enum.map(fn {hour, costs} ->
      {hour, Enum.reduce(costs, Decimal.new(0), &Decimal.add/2)}
    end)
    |> Enum.sort_by(fn {hour, _cost} -> hour end)
    
    %{
      hourly: hourly_costs,
      trend: calculate_trend(hourly_costs),
      peak_hour: find_peak_hour(hourly_costs),
      average_hourly_cost: calculate_average_hourly_cost(hourly_costs)
    }
  end

  ## Private Functions - Recommendations

  defp recommend_caching(provenance_list, usage_map) do
    # Find duplicate patterns
    duplicates = provenance_list
    |> Enum.reject(&is_nil(&1.input_hash))
    |> Enum.group_by(& &1.input_hash)
    |> Enum.filter(fn {_hash, provs} -> length(provs) > 2 end)
    
    Enum.map(duplicates, fn {hash, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      total_cost = TokenUsage.total_cost(usage_list)
      potential_savings = Decimal.mult(total_cost, Decimal.div(Decimal.new(length(provs) - 1), Decimal.new(length(provs))))
      
      %{
        type: :implement_caching,
        priority: :high,
        description: "Cache responses for input pattern #{String.slice(hash, 0..7)}",
        potential_savings: potential_savings,
        implementation: "Use ResponseProcessorAgent caching with TTL based on content type",
        affected_patterns: %{
          input_hash: hash,
          occurrence_count: length(provs),
          task_types: Enum.map(provs, & &1.task_type) |> Enum.uniq()
        }
      }
    end)
  end

  defp recommend_model_changes(provenance_list, usage_map) do
    # Analyze by task type and model usage
    task_model_analysis = provenance_list
    |> Enum.group_by(& &1.task_type)
    |> Enum.map(fn {task_type, provs} ->
      models_used = Enum.map(provs, & &1.metadata["model"]) |> Enum.frequencies()
      usage_list = get_usage_for_provenances(provs, usage_map)
      avg_tokens = avg_tokens(usage_list)
      
      {task_type, %{
        models: models_used,
        avg_tokens: avg_tokens,
        total_cost: TokenUsage.total_cost(usage_list)
      }}
    end)
    
    # Generate recommendations for tasks using expensive models for simple work
    task_model_analysis
    |> Enum.filter(fn {_task, data} -> data.avg_tokens < 500 end)
    |> Enum.filter(fn {_task, data} -> 
      expensive_model_used?(Map.keys(data.models))
    end)
    |> Enum.map(fn {task_type, data} ->
      %{
        type: :optimize_model_selection,
        priority: :medium,
        description: "Use smaller model for task type '#{task_type}'",
        potential_savings: Decimal.mult(data.total_cost, Decimal.new("0.7")),
        implementation: "Switch to GPT-3.5-turbo or Claude Haiku for simple tasks",
        affected_patterns: %{
          task_type: task_type,
          current_models: data.models,
          avg_tokens: data.avg_tokens
        }
      }
    end)
  end

  defp recommend_workflow_changes(provenance_list, _relationships) do
    # Find inefficient workflow patterns
    workflow_groups = provenance_list
    |> Enum.reject(&is_nil(&1.workflow_id))
    |> TokenProvenance.group_by(:workflow_id)
    
    workflow_groups
    |> Enum.map(fn {workflow_id, provs} ->
      depth_stats = calculate_depth_statistics(provs)
      
      if depth_stats.max > 5 do
        %{
          type: :flatten_workflow,
          priority: :medium,
          description: "Workflow #{workflow_id} has excessive depth (max: #{depth_stats.max})",
          potential_savings: Decimal.new("0.2"),  # Estimated 20% savings
          implementation: "Batch operations and reduce sequential dependencies",
          affected_patterns: %{
            workflow_id: workflow_id,
            current_depth: depth_stats,
            request_count: length(provs)
          }
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp recommend_prompt_optimization(provenance_list, usage_map) do
    # Find prompts with high token usage
    prompt_analysis = provenance_list
    |> Enum.reject(&is_nil(&1.prompt_template_id))
    |> Enum.group_by(& &1.prompt_template_id)
    |> Enum.map(fn {template_id, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      avg_tokens = avg_tokens(usage_list)
      
      {template_id, %{
        avg_tokens: avg_tokens,
        usage_count: length(provs),
        total_cost: TokenUsage.total_cost(usage_list)
      }}
    end)
    |> Enum.filter(fn {_template, data} -> data.avg_tokens > 1000 end)
    
    Enum.map(prompt_analysis, fn {template_id, data} ->
      %{
        type: :optimize_prompt_template,
        priority: :low,
        description: "Optimize prompt template #{template_id} to reduce tokens",
        potential_savings: Decimal.mult(data.total_cost, Decimal.new("0.3")),
        implementation: "Review and compress prompt while maintaining effectiveness",
        affected_patterns: %{
          template_id: template_id,
          current_avg_tokens: data.avg_tokens,
          usage_count: data.usage_count
        }
      }
    end)
  end

  ## Private Functions - Helpers

  defp get_usage_for_provenances(provenance_list, usage_map) do
    provenance_list
    |> Enum.map(& &1.request_id)
    |> Enum.map(&Map.get(usage_map, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp avg_tokens([]), do: 0
  defp avg_tokens(usage_list) do
    total = TokenUsage.total_tokens(usage_list)
    div(total, length(usage_list))
  end

  defp avg_cost([]), do: Decimal.new(0)
  defp avg_cost(usage_list) do
    total = TokenUsage.total_cost(usage_list)
    Decimal.div(total, Decimal.new(length(usage_list)))
  end

  defp task_distribution(provenance_list) do
    provenance_list
    |> Enum.map(& &1.task_type)
    |> Enum.frequencies()
  end

  defp calculate_error_rate(provenance_list) do
    error_count = Enum.count(provenance_list, fn prov ->
      Map.get(prov.metadata, "error", false)
    end)
    
    if length(provenance_list) > 0 do
      error_count / length(provenance_list)
    else
      0.0
    end
  end

  defp calculate_efficiency_score(provenance_list, usage_list) do
    # Simple efficiency score based on tokens per task
    if length(provenance_list) > 0 and length(usage_list) > 0 do
      avg_tokens_val = avg_tokens(usage_list)
      task_complexity = estimate_task_complexity(provenance_list)
      
      # Lower tokens for task complexity = higher efficiency
      min(100, round(1000 / (avg_tokens_val / task_complexity)))
    else
      0
    end
  end

  defp estimate_task_complexity(provenance_list) do
    # Estimate based on task types
    task_weights = %{
      "simple_query" => 1,
      "code_generation" => 3,
      "analysis" => 2,
      "complex_reasoning" => 4
    }
    
    weights = provenance_list
    |> Enum.map(& Map.get(task_weights, &1.task_type, 2))
    
    if length(weights) > 0 do
      Enum.sum(weights) / length(weights)
    else
      1
    end
  end

  defp calculate_workflow_duration(provenance_list) do
    if length(provenance_list) > 0 do
      min_time = Enum.min_by(provenance_list, & &1.timestamp).timestamp
      max_time = Enum.max_by(provenance_list, & &1.timestamp).timestamp
      DateTime.diff(max_time, min_time, :second)
    else
      0
    end
  end

  defp calculate_depth_statistics(provenance_list) do
    depths = Enum.map(provenance_list, & &1.depth)
    
    %{
      min: Enum.min(depths, fn -> 0 end),
      max: Enum.max(depths, fn -> 0 end),
      avg: if(length(depths) > 0, do: Enum.sum(depths) / length(depths), else: 0),
      distribution: Enum.frequencies(depths)
    }
  end

  defp agent_distribution(provenance_list) do
    provenance_list
    |> Enum.map(& &1.agent_type)
    |> Enum.frequencies()
  end

  defp build_task_flow(provenance_list, relationships) do
    # Build a simplified task flow representation
    provenance_list
    |> Enum.sort_by(& &1.timestamp)
    |> Enum.map(fn prov ->
      %{
        request_id: prov.request_id,
        task_type: prov.task_type,
        agent_type: prov.agent_type,
        timestamp: prov.timestamp,
        relationships: find_relationships_for_request(prov.request_id, relationships)
      }
    end)
  end

  defp find_relationships_for_request(request_id, relationships) do
    relationships
    |> Enum.filter(fn rel ->
      rel.source_request_id == request_id or rel.target_request_id == request_id
    end)
    |> Enum.map(fn rel ->
      %{
        type: rel.relationship_type,
        other_request: if(rel.source_request_id == request_id, 
          do: rel.target_request_id, 
          else: rel.source_request_id)
      }
    end)
  end

  defp identify_bottlenecks(provenance_list, relationships, usage_map) do
    # Find requests that block many others
    _blocking_requests = relationships
    |> Enum.group_by(& &1.source_request_id)
    |> Enum.map(fn {source, rels} ->
      {source, length(rels)}
    end)
    |> Enum.filter(fn {_source, count} -> count > 3 end)
    |> Enum.map(fn {source, blocked_count} ->
      prov = Enum.find(provenance_list, &(&1.request_id == source))
      usage = Map.get(usage_map, source)
      
      %{
        request_id: source,
        blocked_requests: blocked_count,
        task_type: prov && prov.task_type,
        cost: usage && usage.cost,
        tokens: usage && usage.total_tokens
      }
    end)
  end

  defp calculate_optimization_potential(provenance_list, usage_map) do
    # Estimate potential for optimization
    duplicate_potential = calculate_duplicate_savings(provenance_list, usage_map)
    model_potential = calculate_model_optimization_potential(provenance_list, usage_map)
    
    %{
      duplicate_savings: duplicate_potential,
      model_savings: model_potential,
      total_potential: Decimal.add(duplicate_potential, model_potential)
    }
  end

  defp calculate_duplicate_savings(provenance_list, usage_map) do
    provenance_list
    |> Enum.reject(&is_nil(&1.input_hash))
    |> Enum.group_by(& &1.input_hash)
    |> Enum.filter(fn {_hash, provs} -> length(provs) > 1 end)
    |> Enum.map(fn {_hash, provs} ->
      usage_list = get_usage_for_provenances(provs, usage_map)
      total_cost = TokenUsage.total_cost(usage_list)
      Decimal.mult(total_cost, Decimal.div(Decimal.new(length(provs) - 1), Decimal.new(length(provs))))
    end)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  defp calculate_model_optimization_potential(provenance_list, usage_map) do
    # Estimate savings from using cheaper models for simple tasks
    provenance_list
    |> Enum.map(fn prov ->
      usage = Map.get(usage_map, prov.request_id)
      if usage && usage.total_tokens < 500 && expensive_model?(prov.metadata["model"]) do
        Decimal.mult(usage.cost, Decimal.new("0.7"))
      else
        Decimal.new(0)
      end
    end)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  defp expensive_model?(nil), do: false
  defp expensive_model?(model) do
    model in ["gpt-4", "gpt-4-32k", "claude-3-opus"]
  end

  defp expensive_model_used?(models) do
    Enum.any?(models, &expensive_model?/1)
  end

  defp enrich_lineage_node(node, provenance_list, usage_map) do
    node_id = Map.get(node, :id)
    provenance = Enum.find(provenance_list, &(&1.request_id == node_id))
    usage = Map.get(usage_map, node_id)
    
    enriched = Map.merge(node, %{
      provenance: provenance,
      usage: usage,
      cost: usage && usage.cost,
      tokens: usage && usage.total_tokens
    })
    
    # Recursively enrich ancestors and descendants
    enriched
    |> Map.update(:ancestors, [], fn ancestors ->
      Enum.map(ancestors, &enrich_lineage_node(&1, provenance_list, usage_map))
    end)
    |> Map.update(:descendants, [], fn descendants ->
      Enum.map(descendants, &enrich_lineage_node(&1, provenance_list, usage_map))
    end)
  end

  defp find_all_retries(request_id, retry_relationships) do
    direct_retries = retry_relationships
    |> Enum.filter(&(&1.source_request_id == request_id))
    |> Enum.map(& &1.target_request_id)
    
    # Recursively find retries of retries
    all_retries = direct_retries ++ Enum.flat_map(direct_retries, fn retry_id ->
      find_all_retries(retry_id, retry_relationships)
    end)
    
    Enum.uniq(all_retries)
  end

  defp analyze_retry_pattern(_original, retries, provenance_list) do
    retry_provs = provenance_list
    |> Enum.filter(&(&1.request_id in retries))
    
    %{
      intervals: calculate_retry_intervals(retry_provs),
      agents_involved: Enum.map(retry_provs, & &1.agent_type) |> Enum.uniq(),
      error_types: extract_error_types(retry_provs)
    }
  end

  defp calculate_retry_intervals(retry_provs) do
    retry_provs
    |> Enum.sort_by(& &1.timestamp)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [p1, p2] ->
      DateTime.diff(p2.timestamp, p1.timestamp, :second)
    end)
  end

  defp extract_error_types(provenance_list) do
    provenance_list
    |> Enum.map(& Map.get(&1.metadata, "error_type"))
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  defp depth_distribution(provenance_list) do
    provenance_list
    |> Enum.map(& &1.depth)
    |> Enum.frequencies()
  end

  defp find_cycle_path(relationships, start_node) do
    # Simplified cycle detection - would need more sophisticated algorithm in production
    visited = find_all_descendants(relationships, start_node, [start_node])
    
    if start_node in visited do
      [start_node | Enum.take_while(visited, &(&1 != start_node))] ++ [start_node]
    else
      []
    end
  end

  defp find_all_descendants(relationships, node, visited) do
    direct_descendants = relationships
    |> Enum.filter(&(&1.source_request_id == node))
    |> Enum.map(& &1.target_request_id)
    |> Enum.reject(&(&1 in visited))
    
    if direct_descendants == [] do
      visited
    else
      Enum.reduce(direct_descendants, visited ++ direct_descendants, fn desc, acc ->
        find_all_descendants(relationships, desc, acc)
      end)
    end
  end

  defp extract_all_nodes(relationships) do
    source_nodes = Enum.map(relationships, & &1.source_request_id)
    target_nodes = Enum.map(relationships, & &1.target_request_id)
    (source_nodes ++ target_nodes) |> Enum.uniq()
  end

  defp calculate_trend(hourly_costs) do
    if length(hourly_costs) < 2 do
      :stable
    else
      # Simple trend calculation
      first_half = Enum.take(hourly_costs, div(length(hourly_costs), 2))
      second_half = Enum.drop(hourly_costs, div(length(hourly_costs), 2))
      
      first_avg = average_cost(first_half)
      second_avg = average_cost(second_half)
      
      cond do
        Decimal.gt?(second_avg, Decimal.mult(first_avg, Decimal.new("1.2"))) -> :increasing
        Decimal.lt?(second_avg, Decimal.mult(first_avg, Decimal.new("0.8"))) -> :decreasing
        true -> :stable
      end
    end
  end

  defp average_cost(cost_list) do
    if length(cost_list) == 0 do
      Decimal.new(0)
    else
      total = cost_list
      |> Enum.map(fn {_time, cost} -> cost end)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
      
      Decimal.div(total, Decimal.new(length(cost_list)))
    end
  end

  defp find_peak_hour(hourly_costs) do
    if length(hourly_costs) > 0 do
      {hour, _cost} = Enum.max_by(hourly_costs, fn {_hour, cost} -> cost end)
      hour
    else
      nil
    end
  end

  defp calculate_average_hourly_cost(hourly_costs) do
    average_cost(hourly_costs)
  end
end